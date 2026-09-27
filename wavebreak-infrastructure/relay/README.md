# Domestic relay

A relay is a small VPS in the users' country that forwards TCP :443 to the
main node untouched. Phones on mobile networks with IP/SNI whitelists reach
a domestic IP; the VLESS XHTTP+REALITY session stays end to end with the
main node. The relay has no keys and no user data, so it is disposable.

## Provision a relay (≈3 minutes)

1. Fresh Ubuntu 22.04/24.04, public IPv4, root SSH by key.
2. Check the IP against the mobile whitelist before investing time
   (hxehex/russia-mobile-internet-whitelist `cidrwhitelist.txt`). Selectel
   Moscow gave ~13% whitelisted addresses in 2026-09; re-roll the IP if not.
3. `scp setup-relay.sh root@RELAY:` then on the relay:
   `UPSTREAM=45.15.41.3:443 bash setup-relay.sh`
4. On the main node add it to `.env.pilot`:
   `WAVEBREAK_VLESS_RELAYS=Moscow=RELAY_IP` (comma-separate several) and
   recreate `wavebreak-api`. Apps pick up the new "Russia, Moscow → Istanbul
   (XHTTP)" location on their next refresh.

## When a hoster closes a relay

Core TCP-checks every relay each minute and stops handing out one that
failed twice, so apps stop offering it within ~2 minutes; the direct
transports (Hysteria2, REALITY, Direct-TLS) remain. Provision a new VPS with
the steps above and replace the address in `WAVEBREAK_VLESS_RELAYS`.
Keep two relays at different hosters to have no gap at all.
