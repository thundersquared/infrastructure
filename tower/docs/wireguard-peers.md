# WireGuard Peer Setup

Tower acts as the hub (`10.253.0.1`). All peers connect to tower and route
`10.253.0.0/24` through it to reach each other.

## Getting tower's public key

SSH into tower and run:

```bash
wg pubkey < /etc/wireguard/private.key
```

## Registering a new peer

Add an entry to `tower/ansible/roles/system/wireguard/defaults/main.yml` and re-run the playbook:

```yaml
wireguard_peers:
  - name: my-peer
    public_key: "<peer public key>"
    allowed_ips: "10.253.0.x/32"
```

---

## Unraid (VPN Manager → Add Tunnel)

### Local (Unraid's WireGuard interface)

| Field | Value |
|---|---|
| **Local name** | `infra-vpn` (or any label) |
| **Local private key** | click **Generate keypair** — Unraid fills this |
| **Local public key** | auto-derived — **copy this** and add it to `wireguard_peers` in the playbook |
| **Local endpoint** | leave blank (Unraid is a spoke, not accepting incoming connections) |

### Peer (tower)

| Field | Value |
|---|---|
| **Peer name** | `tower` |
| **Peer type of access** | `Server hub & spoke access` |
| **Peer private key** | leave blank (tower's private key never leaves tower) |
| **Peer public key** | tower's public key — get it with `wg pubkey < /etc/wireguard/private.key` on tower |
| **Peer preshared key** | leave blank |
| **Peer tunnel address** | `10.253.0.x/24` (Unraid's VPN IP, e.g. `10.253.0.2/24`) |
| **Peer endpoint** | `<tower public IP>:51820` |
| **Peer allowed IPs** | `10.253.0.0/24` |
| **Peer DNS server** | leave blank |
| **Persistent keepalive** | `25` |
