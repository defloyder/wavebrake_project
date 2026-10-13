#!/bin/bash
# WaveBreak RU entry node — deploys a whitelist-friendly entry point that
# chains everything to an existing foreign WaveBreak node (default:
# Istanbul) for real internet egress. Self-contained: installs nothing but
# Docker, touches no other service on the box.
#
# Gives the client THREE independent "looks" on the same public IP, so a
# carrier blocking one transport/fingerprint doesn't take down the others:
#   1. VLESS + REALITY + XTLS Vision, masquerading as a real RU site
#      (default ya.ru) — the primary, most resistant to active/behavioral
#      DPI since Vision randomizes packet shape and REALITY steals a real
#      site's TLS handshake for any unauthenticated probe.
#   2. VLESS + gRPC + TLS — HTTP/2-framed, looks like ordinary API traffic,
#      no REALITY camouflage (just a real cert on OWN_DOMAIN).
#   3. VLESS + WebSocket + TLS — the most compatible fallback, looks like a
#      plain website visit (HTTP Upgrade), also on OWN_DOMAIN.
# All three are reachable only via port 443 (nginx stream + ssl_preread,
# SNI-routed) — non-standard ports have repeatedly proven unreliable
# against upstream/carrier filtering in this project, so nothing is
# exposed on any other port.
#
# Usage:
#   ./deploy.sh <PUBLIC_IP> <OWN_DOMAIN> [REALITY_SNI] [CHAIN_IP] [CHAIN_PORT] [CHAIN_SNI] [HOP_ID]
#
# <PUBLIC_IP>   This box's own public IPv4 (used only to label output).
# <OWN_DOMAIN>  A domain you control, already DNS-A'd to PUBLIC_IP, with a
#               Let's Encrypt cert obtainable (used for gRPC/WS's real TLS
#               cert — these two are NOT camouflaged, so this domain name
#               will be visible in their SNI).
# [REALITY_SNI] Real external site to masquerade as for transport #1.
#               Default: ya.ru (confirmed TLS1.3, widely reachable).
# [CHAIN_IP]/[CHAIN_PORT]/[CHAIN_SNI]
#               Where to forward all accepted traffic for real egress.
#               Defaults match the existing Istanbul landing
#               (45.15.41.3:443, SNI hop.wavebreak.com.tr) — change only if
#               deploying a new landing elsewhere.
# [HOP_ID]      VLESS UUID the landing side already trusts. Defaults to the
#               existing Istanbul hop's ID; only override if you set up a
#               fresh landing with its own ID.
#
# Run as root on a fresh Debian/Ubuntu box with a public IP. Safe to re-run
# (idempotent): regenerates config and restarts the containers in place.
set -euo pipefail

PUBLIC_IP="${1:?Usage: deploy.sh <PUBLIC_IP> <OWN_DOMAIN> [REALITY_SNI] [CHAIN_IP] [CHAIN_PORT] [CHAIN_SNI] [HOP_ID]}"
OWN_DOMAIN="${2:?OWN_DOMAIN is required — a domain already pointed at PUBLIC_IP}"
REALITY_SNI="${3:-ya.ru}"
CHAIN_IP="${4:-45.15.41.3}"
CHAIN_PORT="${5:-443}"
CHAIN_SNI="${6:-hop.wavebreak.com.tr}"
HOP_ID="${7:-6d76c86d-1f23-42d9-b4f6-a3c94822642b}"

# REALITY accepts a LIST of client-facing SNI values, not just one — the
# server only ever makes its own real probe connection to REALITY_SNI
# ("dest", to borrow that one site's handshake), but any SNI in this list
# is accepted from a client. REALITY never actually presents a certificate
# to the client (that's the whole trick — no per-SNI cert is needed), so
# these don't need to share hosting with REALITY_SNI; they just need to be
# real, reachable, TLS1.3 sites so the choice itself doesn't look odd.
# REALITY_SNI is always included (as "dest") even if not repeated here.
REALITY_SERVER_NAMES=("$REALITY_SNI" "yandex.ru" "mail.ru" "vk.com")

echo "==> Deploying WaveBreak RU entry on $PUBLIC_IP (domain: $OWN_DOMAIN, REALITY SNI: $REALITY_SNI, serverNames: ${REALITY_SERVER_NAMES[*]})"
echo "==> Chaining to $CHAIN_IP:$CHAIN_PORT (SNI $CHAIN_SNI)"

if ! command -v docker >/dev/null 2>&1; then
  echo "==> Installing Docker..."
  curl -fsSL https://get.docker.com | sh
fi

if ! command -v certbot >/dev/null 2>&1; then
  echo "==> Installing certbot..."
  apt-get update -qq && apt-get install -y -qq certbot
fi

CERT_DIR="/etc/letsencrypt/live/$OWN_DOMAIN"
if [ ! -f "$CERT_DIR/fullchain.pem" ]; then
  echo "==> Issuing a Let's Encrypt cert for $OWN_DOMAIN via standalone HTTP-01."
  echo "    (Port 80 must be free and DNS for $OWN_DOMAIN must already point here.)"
  certbot certonly --standalone --non-interactive --agree-tos \
    --register-unsafely-without-email -d "$OWN_DOMAIN"
fi

echo "==> Generating a fresh REALITY keypair for this node."
KEYS=$(docker run --rm teddysun/xray:latest xray x25519)
REALITY_PRIV=$(echo "$KEYS" | grep -i PrivateKey | awk '{print $NF}')
REALITY_PUB=$(echo "$KEYS" | grep -i 'Password\|PublicKey' | awk '{print $NF}')
SHORT_ID=$(openssl rand -hex 8)
echo "    private key: $REALITY_PRIV"
echo "    public key:  $REALITY_PUB"
echo "    short id:    $SHORT_ID"

# The 14 grant UUIDs already live on every other WaveBreak node — reused
# here so the same subscription works across nodes without Core changes.
CLIENTS_JSON='[
  {"id":"57afe491-b30b-498f-a8f9-4422d6de1231"},
  {"id":"7a83b697-52dd-4de2-a4a0-6def16966260"},
  {"id":"44f8635a-8e4f-4bed-958f-3c90a0fe4e12"},
  {"id":"ace3ccc2-8921-4719-87b4-20b18fd3bff9"},
  {"id":"4fe6b104-0cf9-4c93-8a7e-1e299b2ebe1e"},
  {"id":"7926bc13-8655-473b-9083-67adff27d7fa"},
  {"id":"e80e62dc-118c-4a69-af1f-8aa95880c84b"},
  {"id":"b4226b48-410a-454b-8f93-5b507047710d"},
  {"id":"6de98486-291d-4874-8a2a-8c1f20a99b0f"},
  {"id":"3eb47ef0-93c8-4cbe-9d35-cc0df9ce5526"},
  {"id":"51548156-9c04-4cdd-bc72-af1fb4f35d20"},
  {"id":"d762d06b-85a1-461e-9da5-def23abb4ce9"},
  {"id":"5f81f3f7-5d71-41f5-8190-6600d67c1d51"},
  {"id":"1f2c54bf-ef87-42e1-93bf-2c9193c23108"}
]'
CLIENTS_VISION=$(echo "$CLIENTS_JSON" | jq -c '[.[] | . + {flow:"xtls-rprx-vision"}]')
REALITY_SERVER_NAMES_JSON=$(printf '%s\n' "${REALITY_SERVER_NAMES[@]}" | jq -R . | jq -sc .)

mkdir -p /opt/wavebreak-ru-entry /opt/wavebreak-stream-nginx

jq -n \
  --argjson clientsVision "$CLIENTS_VISION" \
  --argjson clientsPlain "$CLIENTS_JSON" \
  --arg realitySni "$REALITY_SNI" \
  --argjson realityServerNames "$REALITY_SERVER_NAMES_JSON" \
  --arg realityPriv "$REALITY_PRIV" \
  --arg shortId "$SHORT_ID" \
  --arg ownDomain "$OWN_DOMAIN" \
  --arg chainIp "$CHAIN_IP" \
  --argjson chainPort "$CHAIN_PORT" \
  --arg chainSni "$CHAIN_SNI" \
  --arg hopId "$HOP_ID" \
  '{
    log: { loglevel: "warning" },
    inbounds: [
      {
        listen: "127.0.0.1", port: 18501, protocol: "vless", tag: "entry-reality",
        settings: { decryption: "none", clients: $clientsVision },
        streamSettings: {
          network: "tcp", security: "reality",
          sockopt: { acceptProxyProtocol: true },
          realitySettings: {
            show: false, dest: ($realitySni + ":443"),
            serverNames: $realityServerNames, privateKey: $realityPriv, shortIds: [$shortId]
          }
        },
        sniffing: { enabled: true, destOverride: ["http","tls","quic"] }
      },
      {
        listen: "127.0.0.1", port: 18502, protocol: "vless", tag: "entry-grpc",
        settings: { decryption: "none", clients: $clientsPlain },
        streamSettings: {
          network: "grpc", security: "tls",
          tlsSettings: { certificates: [{ certificateFile: ("/etc/letsencrypt/live/" + $ownDomain + "/fullchain.pem"), keyFile: ("/etc/letsencrypt/live/" + $ownDomain + "/privkey.pem") }] },
          grpcSettings: { serviceName: "wvb.entry.v1.AccountService" }
        },
        sniffing: { enabled: true, destOverride: ["http","tls","quic"] }
      },
      {
        listen: "127.0.0.1", port: 18503, protocol: "vless", tag: "entry-ws",
        settings: { decryption: "none", clients: $clientsPlain },
        streamSettings: {
          network: "ws", security: "tls",
          tlsSettings: { alpn: ["http/1.1"], certificates: [{ certificateFile: ("/etc/letsencrypt/live/" + $ownDomain + "/fullchain.pem"), keyFile: ("/etc/letsencrypt/live/" + $ownDomain + "/privkey.pem") }] },
          wsSettings: { path: "/api/ws", heartbeatPeriod: 15 }
        },
        sniffing: { enabled: true, destOverride: ["http","tls","quic"] }
      }
    ],
    outbounds: [
      {
        tag: "to-chain", protocol: "vless",
        settings: { vnext: [{ address: $chainIp, port: $chainPort, users: [{ id: $hopId, encryption: "none" }] }] },
        streamSettings: { network: "tcp", security: "tls", tlsSettings: { serverName: $chainSni } }
      }
    ],
    routing: {
      rules: [
        { type: "field", inboundTag: ["entry-reality","entry-grpc","entry-ws"], outboundTag: "to-chain" }
      ]
    }
  }' > /opt/wavebreak-ru-entry/config.json

REALITY_NGINX_MAP_LINES=""
for sni in "${REALITY_SERVER_NAMES[@]}"; do
  REALITY_NGINX_MAP_LINES="${REALITY_NGINX_MAP_LINES}    ${sni} 127.0.0.1:18501;
"
done

cat > /opt/wavebreak-stream-nginx/nginx.conf <<NGINXEOF
events {}
stream {
  map \$ssl_preread_server_name \$tls_backend {
$REALITY_NGINX_MAP_LINES    $OWN_DOMAIN  127.0.0.1:18502;
    default      127.0.0.1:18503;
  }
  server {
    listen 443 reuseport;
    listen [::]:443 reuseport;
    proxy_pass \$tls_backend;
    proxy_protocol on;
    ssl_preread on;
    proxy_connect_timeout 5s;
    proxy_timeout 1h;
  }
}
NGINXEOF

echo "==> Starting containers..."
docker rm -f wavebreak-ru-entry wavebreak-stream-nginx >/dev/null 2>&1 || true

docker run -d --name wavebreak-ru-entry --restart unless-stopped --network host \
  -v /opt/wavebreak-ru-entry:/c \
  -v /etc/letsencrypt:/etc/letsencrypt:ro \
  teddysun/xray:latest xray run -config /c/config.json

docker run -d --name wavebreak-stream-nginx --restart unless-stopped --network host \
  -v /opt/wavebreak-stream-nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
  nginx:1.27-alpine

sleep 2
echo "==> Status:"
docker ps --format '{{.Names}} {{.Status}}' | grep -E 'wavebreak-ru-entry|wavebreak-stream-nginx'

REALITY_ALT_SNI_LINKS=""
for sni in "${REALITY_SERVER_NAMES[@]:1}"; do
  REALITY_ALT_SNI_LINKS="${REALITY_ALT_SNI_LINKS}
# REALITY + Vision, same server, masquerades as ${sni} instead (try if the
# primary SNI gets blocked on a given network — same key/shortId, only the
# SNI differs):
vless://57afe491-b30b-498f-a8f9-4422d6de1231@$PUBLIC_IP:443?security=reality&sni=${sni}&fp=chrome&pbk=$REALITY_PUB&sid=$SHORT_ID&flow=xtls-rprx-vision&type=tcp#WaveBreak-RU-REALITY-${sni}
"
done

cat > /opt/wavebreak-ru-entry/client-links.txt <<LINKSEOF
# REALITY + Vision (primary, masquerades as $REALITY_SNI):
vless://57afe491-b30b-498f-a8f9-4422d6de1231@$PUBLIC_IP:443?security=reality&sni=$REALITY_SNI&fp=chrome&pbk=$REALITY_PUB&sid=$SHORT_ID&flow=xtls-rprx-vision&type=tcp#WaveBreak-RU-REALITY
$REALITY_ALT_SNI_LINKS
# gRPC fallback (own cert on $OWN_DOMAIN):
vless://57afe491-b30b-498f-a8f9-4422d6de1231@$PUBLIC_IP:443?security=tls&sni=$OWN_DOMAIN&fp=chrome&type=grpc&serviceName=wvb.entry.v1.AccountService&mode=gun#WaveBreak-RU-gRPC

# WebSocket fallback (own cert on $OWN_DOMAIN):
vless://57afe491-b30b-498f-a8f9-4422d6de1231@$PUBLIC_IP:443?type=ws&path=/api/ws&security=tls&sni=$OWN_DOMAIN&fp=chrome&alpn=http/1.1#WaveBreak-RU-WS
LINKSEOF

echo "==> Done. Client links saved to /opt/wavebreak-ru-entry/client-links.txt:"
cat /opt/wavebreak-ru-entry/client-links.txt
