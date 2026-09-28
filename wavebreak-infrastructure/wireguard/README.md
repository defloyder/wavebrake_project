# Ops-only WireGuard access to the admin panel

Restricts `admin.wavebreak.com.tr` to two people (you + one colleague) by
making it reachable only over a small, dedicated WireGuard tunnel — not by
IP-allowlisting in nginx. That distinction matters here specifically
because of how this box's public 443 is architected: traffic hits a single
`stream` listener that dispatches by TLS SNI to internal proxy targets
(`nginx/pilot-public-http.conf`), and by the time a request reaches the
`http` block, its source IP has already become `127.0.0.1` (the stream
proxy's own address), not the real client's. An `allow`/`deny` list in the
`http` block would not have seen the real caller — it would have allowed
everyone or no one. Terminating admin traffic on the WireGuard interface's
own address sidesteps that: only correctly-authenticated tunnel peers can
put a packet on that address in the first place.

## What changed (already applied in git)

- `nginx/pilot-public-http.conf`: `admin.wavebreak.com.tr` removed from
  the public SNI map and its plaintext port-80 vhost deleted. In their
  place, a new server block listens on `10.66.0.1:9443` — the WireGuard
  interface's address — and proxies to the admin container exactly as
  before.
- `docker-compose.pilot.yml`: the admin container's port publish is now
  `127.0.0.1:${WAVEBREAK_ADMIN_PORT}:8000` instead of publishing on every
  interface. This closes a separate, pre-existing gap: the raw port was
  reachable directly from the public internet, bypassing nginx entirely,
  regardless of any SNI or VPN restriction placed in front of it.

Neither change takes effect until deployed and WireGuard is actually
running on the server — see below.

## Setup (run once, on the server)

1. Install WireGuard:
   ```bash
   apt-get update && apt-get install -y wireguard
   ```
2. Generate the server keypair:
   ```bash
   umask 077
   wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
   ```
3. Have each of the two of you generate your own keypair **on your own
   machine** (never generate someone else's private key for them):
   ```bash
   wg genkey | tee privatekey | wg pubkey > publickey
   ```
   Send only the contents of `publickey` to whoever is doing the server
   setup — the private key never leaves your machine.
4. Copy `wg0.conf.example` to `/etc/wireguard/wg0.conf` on the server,
   and fill in:
   - `<SERVER_PRIVATE_KEY>` — from step 2.
   - `<PEER_YOU_PUBLIC_KEY>` / `<PEER_COLLEAGUE_PUBLIC_KEY>` — from step 3.
5. Start it:
   ```bash
   systemctl enable --now wg-quick@wg0
   ```
6. Allow the tunnel's handshake port through whatever firewall the box
   runs (ufw/iptables/etc.) — UDP 51820, inbound, from anywhere. This is
   safe to expose: WireGuard silently drops any packet that isn't
   correctly signed by a configured peer key, so an unauthenticated probe
   gets nothing back, not even an error. Do **not** open TCP 9443
   publicly — it's bound to the WireGuard interface address, not a public
   one, so there's nothing to open.
7. Deploy the nginx and docker-compose changes already committed here, and
   reload:
   ```bash
   docker compose --env-file .env.pilot -p wavebreak_pilot -f docker-compose.pilot.yml up -d --no-deps wavebreak-admin
   nginx -t && systemctl reload nginx
   ```

Each of you then fills in your own `peer-*.conf.example` (your generated
private key, the server's public key from step 2, and the server's public
IP), imports it into your WireGuard client, and connects.

## Using it day-to-day

With the tunnel up, add a hosts-file entry pointing the real hostname at
the tunnel IP, so the TLS certificate (issued for `admin.wavebreak.com.tr`)
still matches what your browser requests:

```
# /etc/hosts (Linux/macOS) or C:\Windows\System32\drivers\etc\hosts (Windows)
10.66.0.1  admin.wavebreak.com.tr
```

Then browse to `https://admin.wavebreak.com.tr:9443/`. Without the tunnel
up, that hostname resolves to nothing reachable — there's no other route
to it left.

## Adding or revoking a peer later

- **Add**: generate a new keypair for them (on their machine), pick the
  next unused `10.66.0.x`, add a `[Peer]` block to `/etc/wireguard/wg0.conf`
  on the server, then `wg syncconf wg0 <(wg-quick strip wg0)` to apply
  without dropping existing connections.
- **Revoke**: delete their `[Peer]` block from `/etc/wireguard/wg0.conf`
  and run the same `wg syncconf` command. Their key stops working
  immediately — no certificate or password rotation needed elsewhere,
  since the admin app's own login is unaffected either way.

## Rollback

If this needs to be backed out, reverting the two commits (nginx config +
docker-compose port binding) and redeploying restores the previous public
reachability. `wg-quick down wg0` (or simply not enabling the service)
removes the tunnel with nothing else affected.
