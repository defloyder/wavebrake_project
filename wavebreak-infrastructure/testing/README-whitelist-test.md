# Testing the "whitelist bypass" (REALITY) location

Simulates a restrictive network that only allows outbound TLS to a small
domain whitelist, so we can check whether WaveBreak's REALITY transport
actually gets through where normal apps don't.

## Setup (on the laptop that will act as the hotspot)

1. Install Python 3 if not already present, then:
   ```
   pip install pydivert
   ```
2. Turn on Windows Mobile Hotspot (Settings → Network & Internet → Mobile
   hotspot), sharing the laptop's normal internet connection.
3. Open a terminal **as Administrator** and run:
   ```
   python sni_whitelist_filter.py
   ```
   Leave it running — it prints `ALLOW`/`BLOCK` for every new connection it
   sees, live.

## Test procedure

1. Connect the phone to the laptop's hotspot.
2. **Before** turning on WaveBreak: try Telegram, Instagram, a random
   website. They should all fail/hang (blocked — confirms the simulated
   allowlist is actually restrictive).
3. Turn on WaveBreak, pick the **VLESS-REALITY** location (the
   "whitelist bypass" one — SNI `www.cloudflare.com`).
4. Retry Telegram/Instagram/browsing. If REALITY is doing its job, these
   should now work, and the filter script's console should show an
   `ALLOW  sni=www.cloudflare.com` line for WaveBreak's own connection —
   proving it got through specifically because it presented a whitelisted
   SNI, not because the whitelist was too loose.
5. If something doesn't work, use the app's **Export logs** feature
   (Settings → About → Export logs, or wherever it's exposed) and send the
   log file back — that's the fastest way to diagnose it further.

## Editing the whitelist

Open `sni_whitelist_filter.py` and edit the `WHITELIST` set near the top to
match whatever scenario you're simulating (a school network, a specific
company's proxy, etc.) — a handful of real, unrelated-to-us domains is more
realistic than a single-entry whitelist.

## Known limitations of this test rig

- This checks TLS SNI only, not full DPI/IP-reputation cross-checking (a
  more sophisticated real-world filter might also flag "SNI says
  cloudflare.com but the IP isn't actually Cloudflare's" — this script
  does not do that check, so it's testing the *simpler and more common*
  kind of allowlist, not the hardest possible one).
- Blocked connections are dropped silently (client sees a timeout), which
  is realistic for most such networks, but some real deployments send an
  explicit RST or an HTTP redirect to a "blocked" page instead — behavior
  may differ slightly from a specific real network you're trying to match.
