
// mii_mac_and_testbench.v
// Simple MII transmit and receive modules + CRC32 + lightweight PHY model + testbench
// Designed for behavioral simulation and functional verification of MII logic.
// Note: This is a simple educational model and omits many real-world details
// (MDIO register config, full-duplex collision handling, auto-negotiation, flow control, timing corner cases).

`timescale 1ns/1ps

// --------------------------------------------------
// CRC32 (Ethernet) — polynomial 0x04C11DB7
// LFSR that accepts serial input LSB-first per octet (standard implementation for Ethernet FCS)
// We'll implement a parallel byte update to compute CRC over bytes.
// --------------------------------------------------
module crc32_byte(
    input  wire        clk,
    input  wire        rstn,
    input  wire        en,       // pulse per input byte
    input  wire [7:0]  data,     // next byte (MSB-first as appearing on the wire)
    output reg  [31:0] crc_out
);
    reg [31:0] crc;
    integer i;
    wire [7:0] d = data;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            crc <= 32'hFFFFFFFF;
        end else if (en) begin
            // update CRC per byte, bitwise (MSB-first)
            // naive bitwise method — fine for simulation and clarity
            for (i = 0; i < 8; i = i + 1) begin
                if ((crc[31] ^ d[7-i]) == 1'b1) begin
                    crc <= {crc[30:0], 1'b0} ^ 32'h04C11DB7;
                end else begin
                    crc <= {crc[30:0], 1'b0};
                end
            end
        end
    end

    always @(*) crc_out = ~crc; // Ethernet places inverted CRC on wire
endmodule

// --------------------------------------------------
// MII Transmitter (nibbles at TX_CLK)
// Accepts bytes from a simple FIFO-like interface (tx_valid/tx_byte)
// Outputs TXD[3:0], TX_EN, TX_CLK externally provided by PHY in real hardware
// For simulation we assume tx_clk provided
// --------------------------------------------------
module mii_tx(
    input  wire        tx_clk,    // 25 MHz typical (clock domain for nibble output)
    input  wire        rstn,
    // simple byte interface
    input  wire [7:0]  tx_byte,
    input  wire        tx_byte_valid,
    output reg         tx_byte_ready,
    // MII outputs
    output reg  [3:0]  TXD,
    output reg         TX_EN
);
    // state: send preamble (7 bytes of 0x55), SFD 0xD5, then payload bytes L->M, then FCS later
    reg [3:0] nibble_sel; // 0: upper nibble, 1: lower nibble etc. but we'll use toggling scheme
    reg [7:0] active_byte;
    reg       have_byte;
    reg [15:0] preamble_cnt;

    initial begin
        TXD = 4'b0000;
        TX_EN = 1'b0;
        tx_byte_ready = 1'b1;
        nibble_sel = 0;
        have_byte = 0;
        preamble_cnt = 0;
    end

    always @(posedge tx_clk or negedge rstn) begin
        if (!rstn) begin
            TXD <= 4'b0000;
            TX_EN <= 1'b0;
            tx_byte_ready <= 1'b1;
            nibble_sel <= 0;
            have_byte <= 0;
            preamble_cnt <= 0;
        end else begin
            // load byte when available and not holding one
            if (!have_byte && tx_byte_valid) begin
                active_byte <= tx_byte;
                have_byte <= 1;
                tx_byte_ready <= 1'b0; // consuming
            end else if (have_byte && !tx_byte_valid) begin
                tx_byte_ready <= 1'b1;
            end

            // For simplicity: transmit preamble first once, then stream bytes as they arrive
            if (preamble_cnt < 7*2) begin // each byte takes two nibbles cycles
                TX_EN <= 1'b1;
                // send 0x55 pattern MSB-first as two nibbles (upper then lower)
                if (nibble_sel == 0) begin
                    TXD <= 4'h5; // upper nibble (0x5)
                end else begin
                    TXD <= 4'h5; // lower nibble also 0x5
                end
                nibble_sel <= ~nibble_sel;
                if (nibble_sel == 1) preamble_cnt <= preamble_cnt + 1;
            end else if (preamble_cnt == 7*2) begin
                // send SFD 0xD5
                TX_EN <= 1'b1;
                if (nibble_sel == 0) TXD <= 4'hD; else TXD <= 4'h5;
                nibble_sel <= ~nibble_sel;
                if (nibble_sel == 1) preamble_cnt <= preamble_cnt + 1;
            end else begin
                // payload transmission
                if (have_byte) begin
                    TX_EN <= 1'b1;
                    if (nibble_sel == 0) TXD <= active_byte[7:4]; else TXD <= active_byte[3:0];
                    nibble_sel <= ~nibble_sel;
                    if (nibble_sel == 1) begin
                        have_byte <= 0; // byte transmitted
                        tx_byte_ready <= 1'b1;
                    end
                end else begin
                    // idle
                    TX_EN <= 1'b0;
                    TXD <= 4'b0000;
                end
            end
        end
    end
endmodule

// --------------------------------------------------
// MII Receiver (nibbles sampled at RX_CLK)
// Presents bytes on rx_byte + rx_valid
// --------------------------------------------------
module mii_rx(
    input  wire        rx_clk,
    input  wire        rstn,
    input  wire [3:0]  RXD,
    input  wire        RX_DV,
    output reg  [7:0]  rx_byte,
    output reg         rx_valid
);
    reg [3:0] nibble_buf;
    reg       nibble_phase; // 0: expect upper nibble next, 1: lower

    always @(posedge rx_clk or negedge rstn) begin
        if (!rstn) begin
            rx_byte <= 8'h00;
            rx_valid <= 1'b0;
            nibble_buf <= 4'h0;
            nibble_phase <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            if (RX_DV) begin
                if (nibble_phase == 1'b0) begin
                    nibble_buf <= RXD;
                    nibble_phase <= 1'b1;
                end else begin
                    rx_byte <= {nibble_buf, RXD};
                    rx_valid <= 1'b1;
                    nibble_phase <= 1'b0;
                end
            end else begin
                nibble_phase <= 1'b0;
            end
        end
    end
endmodule

// --------------------------------------------------
// Simple behavioral PHY model for simulation
// It loops back TX->RX with a small latency and provides TX_CLK and RX_CLK.
// Useful to validate MII TX/RX logic in simulation.
// --------------------------------------------------
module simple_phy_model(
    input  wire        tx_clk_in, // in real hw PHY provides TX_CLK to MAC; here we accept a clock
    input  wire        rstn,
    input  wire [3:0]  TXD_in,
    input  wire        TX_EN_in,
    output reg  [3:0]  RXD_out,
    output reg         RX_DV_out,
    output reg         tx_clk_out,
    output reg         rx_clk_out
);
    // create local clocks derived from tx_clk_in for simulation ease
    initial begin
        tx_clk_out = 0;
        rx_clk_out = 0;
        RXD_out = 4'h0;
        RX_DV_out = 1'b0;
    end

    always @(posedge tx_clk_in or negedge rstn) begin
        if (!rstn) begin
            RXD_out <= 4'h0;
            RX_DV_out <= 1'b0;
        end else begin
            // simple: echo TXD back after 2 cycles
            RX_DV_out <= TX_EN_in;
            if (TX_EN_in) RXD_out <= TXD_in; else RXD_out <= 4'h0;
        end
    end

    // pass clocks through (for testbench we can tie clocks)
    always @(posedge tx_clk_in or negedge rstn) begin
        if (!rstn) begin
            tx_clk_out <= 1'b0;
            rx_clk_out <= 1'b0;
        end else begin
            tx_clk_out <= ~tx_clk_out;
            rx_clk_out <= ~rx_clk_out;
        end
    end
endmodule

// --------------------------------------------------
// Testbench: instantiate mii_tx, simple_phy_model, mii_rx, drive a small frame
// --------------------------------------------------
module tb_mii;
    reg rstn = 0;
    // generate a 25 MHz clock (40 ns period): but for ease of simulation we'll use 20 ns so 25 MHz=40ns
    reg clk_25 = 0;
    always #20 clk_25 = ~clk_25; // 25 MHz -> period 40ns, half 20ns

    // DUT signals
    wire [3:0] TXD;
    wire       TX_EN;

    // simple byte producer
    reg [7:0] tx_byte;
    reg       tx_byte_valid;
    wire      tx_byte_ready;

    // RX side
    wire [3:0] RXD;
    wire       RX_DV;
    wire [7:0] rx_byte;
    wire       rx_valid;

    // instantiate TX
    mii_tx dut_tx(
        .tx_clk(clk_25),
        .rstn(rstn),
        .tx_byte(tx_byte),
        .tx_byte_valid(tx_byte_valid),
        .tx_byte_ready(tx_byte_ready),
        .TXD(TXD),
        .TX_EN(TX_EN)
    );

    // simple PHY
    simple_phy_model phy(
        .tx_clk_in(clk_25),
        .rstn(rstn),
        .TXD_in(TXD),
        .TX_EN_in(TX_EN),
        .RXD_out(RXD),
        .RX_DV_out(RX_DV),
        .tx_clk_out(),
        .rx_clk_out()
    );

    // RX
    mii_rx dut_rx(
        .rx_clk(clk_25),
        .rstn(rstn),
        .RXD(RXD),
        .RX_DV(RX_DV),
        .rx_byte(rx_byte),
        .rx_valid(rx_valid)
    );

    integer i;

    initial begin
        $dumpfile("tb_mii.vcd");
        $dumpvars(0, tb_mii);
        rstn = 0;
        tx_byte_valid = 0;
        tx_byte = 8'h00;
        #200;
        rstn = 1;

        // wait some cycles for preamble
        #2000;

        // send bytes "Hello" (ASCII)
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk_25);
            //tx_byte <= "Hello"[8*(4-i) : 8]; // crude indexing; but we can set manually
        end

        // simpler: feed bytes manually
        @(posedge clk_25); tx_byte <= 8'h48; tx_byte_valid <= 1; // 'H'
        @(posedge clk_25); tx_byte_valid <= 0;
        wait(tx_byte_ready);
        @(posedge clk_25); tx_byte <= 8'h65; tx_byte_valid <= 1; // 'e'
        @(posedge clk_25); tx_byte_valid <= 0; wait(tx_byte_ready);
        @(posedge clk_25); tx_byte <= 8'h6C; tx_byte_valid <= 1; // 'l'
        @(posedge clk_25); tx_byte_valid <= 0; wait(tx_byte_ready);
        @(posedge clk_25); tx_byte <= 8'h6C; tx_byte_valid <= 1; // 'l'
        @(posedge clk_25); tx_byte_valid <= 0; wait(tx_byte_ready);
        @(posedge clk_25); tx_byte <= 8'h6F; tx_byte_valid <= 1; // 'o'
        @(posedge clk_25); tx_byte_valid <= 0; wait(tx_byte_ready);

        // run a bit
        #2000;

        $finish;
    end

    // monitor received bytes
    always @(posedge clk_25) begin
        if (rx_valid) begin
            $display("%t RX byte: 0x%02x (%c)", $time, rx_byte, rx_byte);
        end
    end
endmodule

