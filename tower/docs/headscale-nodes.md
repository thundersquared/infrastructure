# Headscale Nodes

## Current Nodes

| Name | Expected VPN IP | Role |
|---|---|---|
| `giraffe` | `100.64.x.x` | Unraid NAS/compute node |
| `cetriolo` | `100.64.x.x` | Unraid NAS/compute node |
| `ostrich` | `100.64.x.x` | Unraid NAS/compute node |

Actual IPs are assigned by Headscale from the `100.64.0.0/10` CGNAT range and can be confirmed with `headscale nodes list` on tower (see [headscale-setup.md](headscale-setup.md)).

---

## Registering an Unraid Node

### 1. Install Tailscale on Unraid

Install the Tailscale plugin via **Unraid Community Apps** (search for "Tailscale"). Alternatively, run the official `tailscale/tailscale` Docker container if you prefer a compose-managed approach. Either method works; the plugin is simpler for Unraid.

### 2. Point Tailscale at the custom control server

Run the following command in the Unraid terminal (or via the plugin's shell):

```bash
tailscale up --login-server=https://<HEADSCALE_SERVER_URL> --authkey=<preauth-key>
```

- Replace `<HEADSCALE_SERVER_URL>` with the value from the GitHub secret (the public hostname of tower).
- Replace `<preauth-key>` with a key generated on tower (see [headscale-setup.md](headscale-setup.md)).

On success, Tailscale will print the assigned VPN IP and the node will appear in `headscale nodes list` on tower.

### 3. Verify the node is registered

On tower:

```bash
docker compose exec headscale headscale nodes list
```

The node should appear with a `100.64.x.x` address and an `Online` status.

---

## Verifying the Mesh

### Check node status and peer list

On any registered node:

```bash
tailscale status
```

This lists all peers, their VPN IPs, and whether they are online.

### Ping a peer

```bash
tailscale ping <peer-name-or-ip>
```

Successful pings confirm the mesh is functional.

### Check relay vs. direct (P2P) connection

To see whether traffic to a peer is going direct (P2P) or through the DERP relay on tower:

```bash
tailscale debug peer-endpoint-changes
```

Or run a general connectivity check (shows DERP latency, STUN results, UDP availability):

```bash
tailscale netcheck
```

Direct connections are preferred. If all traffic routes through DERP, check that UDP port `3478` is reachable from the nodes and that no NAT is blocking peer-to-peer UDP.
