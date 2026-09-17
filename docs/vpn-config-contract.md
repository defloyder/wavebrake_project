# WAVEBREAK VPN Config Contract

This document tracks the VPN configuration contract.

Current endpoint:

```http
GET /v1/access/grants/{grantID}/config
```

Live pilot VLESS status:

```json
{
  "config_status": "ready",
  "connection_url": "vless://...#WVB-NL-PILOT-01-..."
}
```

The endpoint validates grant ownership and returns grant, node, optional device context, and a personal VLESS REALITY link for `protocol = vless`. WireGuard remains a future contract.

The response also contains a versioned `routing_policy` for WAVEBREAK clients.
Version 1 uses smart split routing: private networks, Russian domain groups and
Russian destination IP ranges are direct; unmatched traffic and all fallback
cases use the protected route. DNS follows the selected route to prevent leaks.
Plain third-party subscription links do not carry this policy.

## VLESS REALITY Pilot Shape

```json
{
  "config_status": "ready",
  "config_version": 3,
  "connection_url": "vless://grant-uuid@91.149.241.52:18443?...#WVB-NL-PILOT-01-XXXXXXXX",
  "share_url": "vless://grant-uuid@91.149.241.52:18443?...#WVB-NL-PILOT-01-XXXXXXXX",
  "vless": {
    "client_id": "grant-uuid",
    "label": "WVB-NL-PILOT-01-XXXXXXXX",
    "protocol": "vless",
    "security": "reality",
    "network": "tcp",
    "flow": "xtls-rprx-vision",
    "server": "91.149.241.52",
    "port": 18443,
    "sni": "www.microsoft.com",
    "fingerprint": "chrome"
  }
}
```

`pending_node_ack` means Core created the grant but node-agent has not acknowledged the desired-state revision yet. The app should retry config polling.

## WireGuard Target Shape

Core should eventually return:

```json
{
  "config_status": "ready",
  "config_version": 7,
  "wireguard": {
    "interface": {
      "private_key": "client_generated_or_core_wrapped",
      "address": "10.77.0.12/32",
      "dns": ["1.1.1.1", "1.0.0.1"],
      "mtu": 1420
    },
    "peer": {
      "public_key": "server-public-key",
      "preshared_key": "optional-psk",
      "endpoint": "tr-ist-01.example.com:51820",
      "allowed_ips": ["0.0.0.0/0", "::/0"],
      "persistent_keepalive": 25
    }
  },
  "raw_config": "[Interface]\n..."
}
```

## Suggested Backend Work

1. Add node network profile fields:
   - public endpoint host
   - WireGuard port
   - server public key
   - DNS profile
   - routed CIDR pool
2. Add grant/client peer material:
   - client public key
   - optional encrypted private key if Core generates keys
   - assigned tunnel address
   - config revision
3. Add a secure key flow:
   - preferred: client generates private key locally and sends public key to Core
   - fallback: Core generates private key and returns it once, encrypted at rest
4. Update node desired-state:
   - include active peer public keys and assigned addresses
   - keep revoked/expired grants out of active peer state
5. Update node runtime adapter:
   - render WireGuard config
   - apply config atomically
   - ACK applied revision
   - fail revision with error details
6. Change `/v1/access/grants/{grantID}/config`:
   - return `config_status = ready` only after Core has all peer/server material
   - return `pending_node_ack` when config exists but node has not ACKed the desired revision
   - return `revoked` for revoked grants

## Mobile/Desktop Responsibility

The app should:

- generate client private/public key locally when the final key-registration endpoint exists
- store private key in OS secure storage
- never send private key to Core in the preferred flow
- poll grant config until `config_status = ready`
- hand the final config to the native VPN adapter
- stop tunnel and delete local config when grant/device is revoked

The app should not:

- report traffic usage directly
- talk to nodes directly
- call Laravel Web/Admin
- mutate subscription or grant state outside Core API
