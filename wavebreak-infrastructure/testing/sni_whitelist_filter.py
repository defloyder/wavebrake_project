"""
SNI whitelist firewall simulator for testing "bypass allowlist" VPN transports.

Purpose: simulate a restrictive network (school/office/some-ISP) that only
allows outbound TLS connections to a specific whitelist of SNI hostnames
(everything else is dropped), so we can test whether WaveBreak's
REALITY-based transport (which presents a genuine, whitelisted-looking SNI
like www.cloudflare.com) can still get through while normal apps
(Telegram, Instagram, ...) cannot, unless their own domains are whitelisted.

How it works: intercepts outbound TCP packets on the shared/hotspot network
interface via WinDivert, inspects the TLS ClientHello of the first packet of
each new TCP flow for its SNI extension, and only allows the flow to
continue if that SNI is in WHITELIST (or if the destination IP is in
ALWAYS_ALLOW_IPS, for things like DNS/gateway traffic that isn't itself
TLS). Everything else is silently dropped (no RST, so blocked apps see a
timeout — closer to real restrictive-network behavior than an instant
connection-refused).

Requirements (on the laptop acting as the hotspot):
    pip install pydivert
    (pydivert bundles the WinDivert driver; first run needs Administrator)

Usage:
    1. Turn on Windows Mobile Hotspot on the laptop, sharing its normal
       internet connection.
    2. Run this script AS ADMINISTRATOR on the laptop, before/while the
       phone is connected to that hotspot:
           python sni_whitelist_filter.py
    3. On the phone, browse normally — only sites in WHITELIST below should
       load. Then turn on WaveBreak's "whitelist bypass" (REALITY) location
       and confirm Telegram/Instagram/etc. now work through the tunnel.
    4. Ctrl+C to stop filtering and restore normal traffic.

Tune WHITELIST to whatever the target scenario actually allows — a school
network might allow *.edu domains plus a handful of vendor sites; a
corporate network might allow only specific SaaS tools. Edit the list below
to match whatever you're trying to simulate.
"""

import re
import socket
import struct
import sys

try:
    import pydivert
except ImportError:
    print("Missing dependency. Run: pip install pydivert")
    sys.exit(1)

# --- Configuration ------------------------------------------------------

# SNI hostnames allowed through untouched. Exact match on the ClientHello's
# server_name extension. Add whatever the simulated network is supposed to
# permit (a handful of common/trusted sites is realistic for most
# allowlist-style networks; keep this deliberately narrow to make the test
# meaningful).
WHITELIST = {
    "www.google.com",
    "www.microsoft.com",
    "www.cloudflare.com",  # WaveBreak's REALITY SNI — should get through
                              # via legitimate-looking TLS regardless of what
                              # else is blocked; this line documents that
                              # intent, not a special-case in the code below.
}

# Destination IPs always allowed regardless of SNI (or for non-TLS traffic
# like DNS) — the local gateway/DNS resolver, and anything else the test
# network itself needs to function. 8.8.8.8/1.1.1.1 are included so DNS
# resolution keeps working for the client (blocking DNS entirely would make
# it impossible to even attempt a connection to a blocked site, which is a
# less realistic simulation than "DNS resolves, but the TLS connection to
# the resulting IP gets dropped").
ALWAYS_ALLOW_IPS = {"8.8.8.8", "1.1.1.1", "8.8.4.4"}

# Also always allow WaveBreak's own server IP by destination IP, in
# addition to it being allowed via the www.cloudflare.com SNI match above —
# belt and suspenders in case a client ever reconnects with a slightly
# different SNI/config than expected. Comment this out if you specifically
# want to test whether the SNI match ALONE is what lets it through (the
# more realistic test — a real allowlist box doesn't know our server's IP
# in advance).
# ALWAYS_ALLOW_IPS.add("45.15.41.3")

# --------------------------------------------------------------------- --


def extract_sni(tcp_payload: bytes) -> str | None:
    """Pull the SNI hostname out of a TLS ClientHello, or None if this
    doesn't look like one (payload too short, wrong record type, no SNI
    extension present, etc.) — callers must treat None as "no SNI to
    check," not as "definitely not TLS."""
    try:
        if len(tcp_payload) < 6 or tcp_payload[0] != 0x16:  # handshake record
            return None
        if tcp_payload[5] != 0x01:  # ClientHello
            return None
        pos = 43  # skip record header(5) + handshake header(4) + version(2)
                  # + random(32)
        session_id_len = tcp_payload[pos]
        pos += 1 + session_id_len
        cipher_suites_len = struct.unpack(">H", tcp_payload[pos:pos + 2])[0]
        pos += 2 + cipher_suites_len
        compression_len = tcp_payload[pos]
        pos += 1 + compression_len
        if pos + 2 > len(tcp_payload):
            return None
        extensions_len = struct.unpack(">H", tcp_payload[pos:pos + 2])[0]
        pos += 2
        extensions_end = pos + extensions_len
        while pos < extensions_end and pos + 4 <= len(tcp_payload):
            ext_type = struct.unpack(">H", tcp_payload[pos:pos + 2])[0]
            ext_len = struct.unpack(">H", tcp_payload[pos + 2:pos + 4])[0]
            ext_data_start = pos + 4
            if ext_type == 0x0000:  # server_name
                # server_name_list length(2) + type(1) + hostname length(2)
                name_len = struct.unpack(
                    ">H", tcp_payload[ext_data_start + 3:ext_data_start + 5]
                )[0]
                name_start = ext_data_start + 5
                return tcp_payload[name_start:name_start + name_len].decode(
                    "ascii", errors="ignore"
                )
            pos = ext_data_start + ext_len
    except (struct.error, IndexError):
        return None
    return None


def main() -> None:
    print("SNI whitelist filter starting.")
    print(f"Whitelisted SNIs: {sorted(WHITELIST)}")
    print(f"Always-allowed IPs: {sorted(ALWAYS_ALLOW_IPS)}")
    print("Press Ctrl+C to stop.\n")

    # Only look at outbound TCP packets carrying a payload (skip bare
    # ACKs/handshake packets with no data) heading somewhere other than a
    # private/local address — this is intentionally broad (checks every
    # such packet, not just the first of a flow) since ClientHello can
    # occasionally span more than one packet's worth of buffering on the
    # capture side; checking every data-bearing packet is simpler and
    # cheap enough for a manual test rig.
    packet_filter = (
        "outbound and tcp and tcp.PayloadLength > 0 "
        "and !ip.DstAddr.InRange(10.0.0.0, 10.255.255.255) "
        "and !ip.DstAddr.InRange(172.16.0.0, 172.31.255.255) "
        "and !ip.DstAddr.InRange(192.168.0.0, 192.168.255.255)"
    )

    # decided[(src_ip, src_port, dst_ip, dst_port)] -> bool, so once a flow
    # is allowed/blocked we don't re-parse every subsequent packet in it —
    # only the first data packet (the ClientHello, for a TLS flow) actually
    # carries the SNI we need to decide on.
    decided: dict[tuple, bool] = {}

    with pydivert.WinDivert(packet_filter) as w:
        for packet in w:
            flow_key = (
                packet.src_addr,
                packet.src_port,
                packet.dst_addr,
                packet.dst_port,
            )

            if flow_key in decided:
                if decided[flow_key]:
                    w.send(packet)
                # else: drop (don't re-send) — silently continues dropping
                # every packet in an already-blocked flow.
                continue

            if packet.dst_addr in ALWAYS_ALLOW_IPS:
                decided[flow_key] = True
                w.send(packet)
                continue

            sni = extract_sni(bytes(packet.payload))
            if sni is None:
                # Not a recognizable ClientHello on this packet — allow it
                # through rather than guessing wrong on non-TLS traffic
                # (e.g. plain HTTP, or a TLS flow whose ClientHello was
                # already handled/decided on the packet before this one).
                w.send(packet)
                continue

            allowed = sni in WHITELIST
            decided[flow_key] = allowed
            verdict = "ALLOW" if allowed else "BLOCK"
            print(f"{verdict}  sni={sni}  -> {packet.dst_addr}:{packet.dst_port}")
            if allowed:
                w.send(packet)
            # else: drop this packet (the ClientHello itself), which kills
            # the handshake before it can proceed — the client will see a
            # timeout, not an immediate reset.


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nStopped.")
