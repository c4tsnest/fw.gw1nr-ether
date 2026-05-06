#!/usr/bin/env python3
"""
pcap2ethercat - Convert tcpdump pcap files to human-readable EtherCAT frame dumps.

Reads a pcap file (magic 0xa1b2c3d4, link-type Ethernet) and prints each
EtherCAT frame (EtherType 0x88A4) with datagram details.

Features:
- Detects frame direction (OUT=master→slave, IN=slave→master) via WKC
- Human-readable AL Control/Status descriptions
- Human-readable EEPROM operation summaries
- Collapses repetitive polling frames
"""

import struct
import sys
from datetime import datetime
from collections import OrderedDict

ECAT_ETYPE = 0x88A4

CMD_NAMES = {
    0x00: "NOP", 0x01: "APRD", 0x02: "APWR", 0x03: "APRW",
    0x04: "FPRD", 0x05: "FPWR", 0x06: "FPRW",
    0x07: "BRD", 0x08: "BWR", 0x09: "BRW",
    0x0D: "LRD", 0x0E: "LWR", 0x0F: "LRW",
}

AL_STATE_NAMES = {
    0x01: "INIT", 0x02: "PREOP", 0x04: "SAFEOP", 0x08: "OP",
}

def al_control_desc(val):
    state = val & 0x0F
    flags = []
    if val & 0x10: flags.append("ErrAck")
    if val & 0x20: flags.append("DevEmul")
    state_name = AL_STATE_NAMES.get(state, f"0x{state:02X}")
    if flags:
        return f"{state_name}+{'+'.join(flags)}"
    return state_name

def al_status_desc(val):
    state = val & 0x0F
    flags = []
    if val & 0x10: flags.append("ErrInd")
    if val & 0x20: flags.append("DevEmul")
    state_name = AL_STATE_NAMES.get(state, f"0x{state:02X}")
    if flags:
        return f"{state_name}+{'+'.join(flags)}"
    return state_name

def eeprom_cmd_desc(data):
    """Decode EEPROM PDI control/status register write."""
    if len(data) < 6:
        return None
    stat = data[0]
    stat_hi = data[1]
    addr = struct.unpack('<I', data[2:6])[0]
    cmd_type = (stat_hi >> 0) & 0x07
    cmd_names = {0: "none", 1: "read", 2: "write", 3: "reload"}
    cmd_name = cmd_names.get(cmd_type, f"cmd{cmd_type}")
    return f"EEPROM {cmd_name} addr=0x{addr:08X}"

def describe_datagram(dg):
    """Return a concise one-line description of a datagram."""
    cmd = dg['cmd']
    ado = dg['ado']
    payload = dg['payload']
    wkc = dg['wkc']
    extra = ""

    if ado == 0x0120 and cmd in ("FPWR", "APWR", "BWR") and len(payload) >= 2:
        val = struct.unpack('<H', payload[:2])[0]
        extra = f" AL-Control={al_control_desc(val)}"
    elif ado == 0x0130 and cmd in ("FPRD", "APRD", "BRD") and len(payload) >= 2:
        val = struct.unpack('<H', payload[:2])[0]
        extra = f" AL-Status={al_status_desc(val)}"
    elif ado == 0x0502 and cmd in ("FPWR", "APWR", "BWR") and len(payload) >= 6:
        desc = eeprom_cmd_desc(payload)
        if desc:
            extra = f" {desc}"
    elif ado == 0x0508 and cmd in ("FPRD", "APRD", "BRD") and len(payload) >= 4:
        val = struct.unpack('<I', payload[:4])[0]
        extra = f" EEPROM-data=0x{val:08X}"
    elif ado == 0x0F00 and cmd in ("FPWR", "FPRD") and len(payload) >= 1:
        val = payload[0]
        extra = f" GPIO=0x{val:02X}"
    elif ado == 0x0000 and cmd in ("FPRD", "BRD", "APRD") and len(payload) >= 2:
        val = struct.unpack('<H', payload[:2])[0]
        extra = f" Type=0x{val:04X}"
    elif ado == 0x0001 and cmd in ("FPRD", "BRD", "APRD") and len(payload) >= 2:
        val = struct.unpack('<H', payload[:2])[0]
        extra = f" Revision=0x{val:04X}"

    dir_mark = "→" if wkc == 0 else "←"
    return f"  {dir_mark} {cmd} ADP=0x{dg['adp']:04X} ADO=0x{ado:04X} len={dg['len']} WKC={wkc}{extra}"

def datagram_key(dg):
    """Return a hashable key for detecting repeated datagrams."""
    return (dg['cmd'], dg['adp'], dg['ado'], dg['len'], dg['payload'][:8].hex(), dg['wkc'])

def read_pcap_global_header(f):
    data = f.read(24)
    magic, v_major, v_minor, thiszone, sigfigs, snaplen, network = struct.unpack('<IHHiIII', data)
    if magic not in (0xa1b2c3d4, 0xd4c3b2a1):
        raise ValueError(f"Unknown pcap magic: {hex(magic)}")
    return snaplen, network

def read_pcap_packet(f):
    hdr = f.read(16)
    if len(hdr) < 16:
        return None
    ts_sec, ts_usec, incl_len, orig_len = struct.unpack('<IIII', hdr)
    data = f.read(incl_len)
    if len(data) < incl_len:
        return None
    return ts_sec * 1_000_000 + ts_usec, data

def parse_ethernet_frame(data):
    if len(data) < 14:
        return None, None, None, None
    dst, src, etype = struct.unpack('>6s6sH', data[:14])
    return src, dst, etype, data[14:]

def parse_ethercat_frame(data):
    if len(data) < 2:
        return []
    length = data[0] | ((data[1] & 0x0F) << 8)
    return parse_datagrams(data[2:], length)

def parse_datagrams(data, expected_len):
    datagrams = []
    pos = 0
    while pos < expected_len and pos + 10 <= len(data):
        cmd_byte = data[pos]
        index = data[pos + 1]
        adp = struct.unpack('<H', data[pos + 2:pos + 4])[0]
        ado = struct.unpack('<H', data[pos + 4:pos + 6])[0]
        len_cfg = struct.unpack('<H', data[pos + 6:pos + 8])[0]
        irq = struct.unpack('<H', data[pos + 8:pos + 10])[0]
        dgram_len = len_cfg & 0x07FF
        pos += 10
        payload = data[pos:pos + dgram_len]
        pos += dgram_len
        wkc = struct.unpack('<H', data[pos:pos + 2])[0] if pos + 2 <= len(data) else 0
        pos += 2
        datagrams.append({
            'cmd': CMD_NAMES.get(cmd_byte, f"CMD_0x{cmd_byte:02X}"),
            'index': index, 'adp': adp, 'ado': ado,
            'len': dgram_len, 'irq': irq,
            'payload': payload, 'wkc': wkc,
        })
    return datagrams

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

        frames = []
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
            dgrams = parse_ethercat_frame(payload)
            if not dgrams:
                continue
            frames.append({
                'num': pkt_num,
                'ts_us': ts_us,
                'src': src_mac,
                'dst': dst_mac,
                'dgrams': dgrams,
            })

        # Collapse repetitive frames
        print(f"# Total EtherCAT frames: {len(frames)}")
        print()

        i = 0
        while i < len(frames):
            fr = frames[i]
            # Build a description key for this frame
            descs = tuple(describe_datagram(dg) for dg in fr['dgrams'])
            direction = "OUT" if all(dg['wkc'] == 0 for dg in fr['dgrams']) else "IN"

            # Count consecutive identical frames
            count = 1
            while i + count < len(frames):
                next_fr = frames[i + count]
                next_descs = tuple(describe_datagram(dg) for dg in next_fr['dgrams'])
                if next_descs == descs:
                    count += 1
                else:
                    break

            ts = datetime.fromtimestamp(fr['ts_us'] // 1_000_000)
            us = fr['ts_us'] % 1_000_000

            if count > 3:
                # Collapse
                last_fr = frames[i + count - 1]
                last_ts = datetime.fromtimestamp(last_fr['ts_us'] // 1_000_000)
                last_us = last_fr['ts_us'] % 1_000_000
                print(f"=== Frame {fr['num']}–{last_fr['num']} [{count}x repeated, {direction}] ===")
                print(f"  [{ts.strftime('%H:%M:%S')}.{us:06d}] → [{last_ts.strftime('%H:%M:%S')}.{last_us:06d}]")
                for desc in descs:
                    print(desc)
                print()
                i += count
            else:
                print(f"=== Frame {fr['num']} [{direction}] ===")
                print(f"  [{ts.strftime('%H:%M:%S')}.{us:06d}]")
                for desc in descs:
                    print(desc)
                print()
                i += 1

if __name__ == '__main__':
    main()