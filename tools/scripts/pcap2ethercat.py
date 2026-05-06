#!/usr/bin/env python3
"""
pcap2ethercat - Convert tcpdump pcap files to human-readable EtherCAT frame dumps.

Reads a pcap file (magic 0xa1b2c3d4, link-type Ethernet) and prints each
EtherCAT frame (EtherType 0x88A4) with datagram details.
"""

import struct
import sys
from datetime import datetime

ECAT_ETYPE = 0x88A4

CMD_NAMES = {
    0x00: "NOP",
    0x01: "APRD",
    0x02: "APWR",
    0x03: "APRW",
    0x04: "FPRD",
    0x05: "FPWR",
    0x06: "FPRW",
    0x07: "BRD",
    0x08: "BWR",
    0x09: "BRW",
    0x0D: "LRD",
    0x0E: "LWR",
    0x0F: "LRW",
}

def read_pcap_global_header(f):
    """Read and parse pcap global header. Returns (snaplen, network)."""
    data = f.read(24)
    magic, v_major, v_minor, thiszone, sigfigs, snaplen, network = struct.unpack('<IHHiIII', data)
    if magic not in (0xa1b2c3d4, 0xd4c3b2a1):
        raise ValueError(f"Unknown pcap magic: {hex(magic)}")
    return snaplen, network

def read_pcap_packet(f):
    """Read next pcap packet record. Returns (timestamp_us, packet_data) or None."""
    hdr = f.read(16)
    if len(hdr) < 16:
        return None
    ts_sec, ts_usec, incl_len, orig_len = struct.unpack('<IIII', hdr)
    data = f.read(incl_len)
    if len(data) < incl_len:
        return None
    return ts_sec * 1_000_000 + ts_usec, data

def parse_ethernet_frame(data):
    """Returns (src_mac, dst_mac, ether_type, payload)."""
    if len(data) < 14:
        return None, None, None, None
    dst, src, etype = struct.unpack('>6s6sH', data[:14])
    return src, dst, etype, data[14:]

def parse_ethercat_frame(data):
    """Parse EtherCAT frame header. Returns list of datagrams."""
    if len(data) < 2:
        return []
    # EtherCAT header: 2 bytes
    # bits 0-10: length
    # bit 11: reserved
    # bits 12-15: type
    length = struct.unpack('<H', data[:2])[0]
    # Actually, let's just parse the length properly
    # The header is: 11-bit length, 1-bit reserved, 4-bit type
    length = data[0] | ((data[1] & 0x0F) << 8)
    type_bits = (data[1] >> 4) & 0x0F
    # Length is the total byte length of all datagrams
    # The frame type is usually 1 (process data) or 2 (mailbox)
    return parse_datagrams(data[2:], length)

def parse_datagrams(data, expected_len):
    """Parse EtherCAT datagrams from frame data."""
    datagrams = []
    pos = 0
    while pos < expected_len and pos + 10 <= len(data):
        cmd_byte = data[pos]
        index = data[pos + 1]
        adp = struct.unpack('<H', data[pos + 2:pos + 4])[0]
        ado = struct.unpack('<H', data[pos + 4:pos + 6])[0]
        len_cfg = struct.unpack('<H', data[pos + 6:pos + 8])[0]
        irq = struct.unpack('<H', data[pos + 8:pos + 10])[0]

        dgram_len = len_cfg & 0x07FF  # lower 11 bits
        reserve = (len_cfg >> 11) & 0x1F
        # bit 15 is R (reserved)
        # bits 11-14 are reserved

        cmd_name = CMD_NAMES.get(cmd_byte, f"CMD_0x{cmd_byte:02X}")

        pos += 10
        payload = data[pos:pos + dgram_len]
        pos += dgram_len

        if pos + 2 <= len(data):
            wkc = struct.unpack('<H', data[pos:pos + 2])[0]
            pos += 2
        else:
            wkc = 0

        datagrams.append({
            'cmd': cmd_name,
            'index': index,
            'adp': adp,
            'ado': ado,
            'len': dgram_len,
            'irq': irq,
            'payload': payload,
            'wkc': wkc,
        })

    return datagrams

def hexdump(data, cols=16):
    """Return hex string dump of data."""
    lines = []
    for i in range(0, len(data), cols):
        chunk = data[i:i+cols]
        hex_part = ' '.join(f'{b:02X}' for b in chunk)
        ascii_part = ''.join(chr(b) if 32 <= b < 127 else '.' for b in chunk)
        lines.append(f"  {i:04X}: {hex_part:<{cols*3}}  {ascii_part}")
    return '\n'.join(lines)

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <input.pcap>")
        sys.exit(1)

    fname = sys.argv[1]
    with open(fname, 'rb') as f:
        snaplen, network = read_pcap_global_header(f)
        print(f"# pcap2ethercat: {fname}")
        print(f"# snaplen={snaplen}, linktype={network}")
        print()

        pkt_num = 0
        while True:
            result = read_pcap_packet(f)
            if result is None:
                break
            ts_us, pkt_data = result
            pkt_num += 1

            src_mac, dst_mac, etype, payload = parse_ethernet_frame(pkt_data)
            if etype != ECAT_ETYPE:
                continue

            dt = datetime.fromtimestamp(ts_us // 1_000_000)
            us = ts_us % 1_000_000
            print(f"=== Frame {pkt_num} [{dt.strftime('%Y-%m-%d %H:%M:%S')}.{us:06d}] ===")
            print(f"  dst={dst_mac.hex(':')}, src={src_mac.hex(':')}, etype=0x{etype:04X}")

            datagrams = parse_ethercat_frame(payload)
            for i, dg in enumerate(datagrams):
                print(f"  Datagram {i+1}: {dg['cmd']}")
                print(f"    index=0x{dg['index']:02X}, adp=0x{dg['adp']:04X}, ado=0x{dg['ado']:04X}")
                print(f"    len={dg['len']}, irq=0x{dg['irq']:04X}")
                if dg['len'] > 0:
                    print(f"    data ({dg['len']} bytes):")
                    print(hexdump(dg['payload']))
                print(f"    wkc=0x{dg['wkc']:04X}")
            print()

if __name__ == '__main__':
    main()