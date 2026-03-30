module esc_al_fsm (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       req_valid,
    input  logic [3:0] req_state,
    output logic [3:0] al_state,
    output logic [15:0] al_status_code
);

  logic [3:0] next_state;
  logic transition_valid;

  always_comb begin
    next_state = al_state;
    transition_valid = 1'b1;
    case (req_state)
      4'h1: next_state = 4'h1;
      4'h2: begin
        if ((al_state == 4'h1) || (al_state == 4'h4) || (al_state == 4'h8)) next_state = 4'h2;
        else transition_valid = 1'b0;
      end
      4'h4: begin
        if ((al_state == 4'h2) || (al_state == 4'h8)) next_state = 4'h4;
        else transition_valid = 1'b0;
      end
      4'h8: begin
        if (al_state == 4'h4) next_state = 4'h8;
        else transition_valid = 1'b0;
      end
      default: transition_valid = 1'b0;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      al_state <= 4'h1;
      al_status_code <= 16'h0000;
    end else if (req_valid) begin
      if (transition_valid) begin
        al_state <= next_state;
        al_status_code <= 16'h0000;
      end else begin
        al_status_code <= 16'h0011;
      end
    end
  end

endmodule