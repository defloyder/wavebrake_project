#!/bin/sh
set -eu

CONFIG_PATH="${XRAY_CONFIG_PATH:-/etc/xray/config.json}"
LISTEN_PORT="${XRAY_LISTEN_PORT:-8443}"
REALITY_DEST="${XRAY_REALITY_DEST:-www.microsoft.com:443}"
REALITY_SERVER_NAME="${XRAY_REALITY_SERVER_NAME:-www.microsoft.com}"
REALITY_PRIVATE_KEY="${XRAY_REALITY_PRIVATE_KEY:?XRAY_REALITY_PRIVATE_KEY is required}"
REALITY_SHORT_ID="${XRAY_REALITY_SHORT_ID:?XRAY_REALITY_SHORT_ID is required}"

mkdir -p "$(dirname "$CONFIG_PATH")"

if [ ! -s "$CONFIG_PATH" ]; then
  cat > "$CONFIG_PATH" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${LISTEN_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "xver": 0,
          "dest": "${REALITY_DEST}",
          "serverNames": ["${REALITY_SERVER_NAME}"],
          "privateKey": "${REALITY_PRIVATE_KEY}",
          "shortIds": ["${REALITY_SHORT_ID}"]
        },
        "sockopt": {
          "tcpFastOpen": true,
          "tcpFragment": true,
          "tcpMaxSeg": 1350
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "sockopt": {
        "tcpFastOpen": true
      }
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ]
}
EOF
fi

exec xray run -config "$CONFIG_PATH"
