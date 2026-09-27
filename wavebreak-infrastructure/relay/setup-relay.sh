#!/usr/bin/env bash
# Turns a fresh Ubuntu 22.04/24.04 VPS into a WAVEBREAK domestic relay:
# TCP :443 is forwarded untouched to the main node, so phones on mobile
# networks with IP/SNI whitelists reach a domestic IP while the VLESS
# XHTTP+REALITY session stays end to end with the main node. The relay
# holds no keys and no user data: if its hoster closes it, provision a new
# VPS with this script and point Core's WAVEBREAK_VLESS_RELAYS at it.
#
# Usage (as root on the relay):
#   UPSTREAM=45.15.41.3:443 bash setup-relay.sh
# Idempotent: safe to run again.
set -euo pipefail

UPSTREAM="${UPSTREAM:-45.15.41.3:443}"
SSH_PORT="${SSH_PORT:-22}"

log() { printf '\n==> %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

log "packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nginx libnginx-mod-stream ufw >/dev/null

log "nginx: TCP 443 -> ${UPSTREAM}"
# IPv6 listener only where the host has IPv6 (nginx fails otherwise).
LISTEN_V6=""
if [ -s /proc/net/if_inet6 ]; then LISTEN_V6="    listen [::]:443 reuseport;"; fi
# No HTTP sites on the relay: only the stream forwarder listens.
rm -f /etc/nginx/sites-enabled/default
mkdir -p /etc/nginx/stream.d
cat > /etc/nginx/stream.d/wavebreak-relay.conf <<EOF
# Managed by wavebreak-infrastructure/relay/setup-relay.sh
server {
    listen 443 reuseport;
${LISTEN_V6}
    proxy_pass ${UPSTREAM};
    proxy_connect_timeout 5s;
    # Long-lived VPN sessions: don't cut idle-but-open tunnels too early.
    proxy_timeout 30m;
    tcp_nodelay on;
}
EOF
if ! grep -q 'stream.d/\*.conf' /etc/nginx/nginx.conf; then
    printf '\nstream {\n    include /etc/nginx/stream.d/*.conf;\n}\n' >> /etc/nginx/nginx.conf
fi
nginx -t
systemctl enable --now nginx >/dev/null
systemctl reload nginx

log "kernel: BBR + fq, larger backlog"
cat > /etc/sysctl.d/90-wavebreak-relay.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.tcp_fin_timeout = 15
EOF
sysctl --system >/dev/null
mkdir -p /etc/systemd/system/nginx.service.d
printf '[Service]\nLimitNOFILE=65535\n' > /etc/systemd/system/nginx.service.d/limits.conf
systemctl daemon-reload
systemctl restart nginx

log "firewall: only ssh and 443/tcp"
ufw --force default deny incoming >/dev/null
ufw --force default allow outgoing >/dev/null
ufw allow "${SSH_PORT}/tcp" >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null

log "ssh: key-only login (only if a key is installed)"
if [ -s /root/.ssh/authorized_keys ]; then
    cat > /etc/ssh/sshd_config.d/90-wavebreak-relay.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
    if sshd -t; then
        systemctl reload ssh 2>/dev/null || systemctl reload sshd
    else
        echo "sshd config check failed: removing the override" >&2
        rm -f /etc/ssh/sshd_config.d/90-wavebreak-relay.conf
    fi
else
    echo "no /root/.ssh/authorized_keys: password login left as is"
fi

log "check: upstream reachable from the relay"
host="${UPSTREAM%:*}"; port="${UPSTREAM##*:}"
if timeout 5 bash -c "exec 3<>/dev/tcp/${host}/${port}" 2>/dev/null; then
    echo "upstream ${UPSTREAM}: OK"
else
    echo "upstream ${UPSTREAM}: NOT reachable" >&2
    exit 2
fi
ss -ltn | grep -q ':443 ' && echo "relay listening on :443"
echo "done"
