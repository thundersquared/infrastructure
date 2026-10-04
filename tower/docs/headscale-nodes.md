# Headscale Nodes

Nodes are machines running the standard Tailscale client against tower's Headscale. Their names, addresses and owners
live in Headscale's database, not in this repository. List them on tower with `headscale nodes list` (see
[headscale-setup.md](headscale-setup.md)).

Headscale assigns each node an address from `100.64.0.0/10` (plus one from `fd7a:115c:a1e0::/48`) at registration.

---

## Registering a Node

### 1. Install Tailscale

Install the Tailscale client for the node's OS from <https://tailscale.com/download>, or run the official
`tailscale/tailscale` container. Headscale 0.29 rejects clients older than **v1.80.0**. Check with `tailscale version`.

### 2. Point Tailscale at the control server

Create a single-use pre-auth key on tower ([headscale-setup.md](headscale-setup.md)),
then run this on the node:

```bash
tailscale up --login-server=https://<tower-hostname> --authkey=<preauth-key>
```

`<tower-hostname>` is the value of the `TOWER_HOSTNAME` environment secret. The login server URL is stored by the client,
so it must not change later.

### 3. Verify the node is registered

On tower, from `/opt/containers/headscale/`:

```bash
docker compose exec headscale headscale nodes list
```

The node should be listed with a `100.64.x.x` address and show as online.

---

## Verifying the Mesh

### Check node status and peer list

On any registered node:

```bash
tailscale status
```

This lists all peers with their VPN IPs and whether they are online. A peer reached through the relay shows `relay "tower"`.

### Ping a peer

```bash
tailscale ping <peer-name-or-ip>
```

Each reply says how it travelled: `via DERP(tower)` means relayed through tower, `via <ip>:<port>` means a direct
peer-to-peer path.

### Check NAT traversal and DERP reachability

```bash
tailscale netcheck
```

This shows UDP availability, the STUN result and the latency to the `tower` DERP region. Direct connections are
preferred. If everything relays through DERP, check that `3478/udp` on tower is reachable from the node and that the
node's NAT allows peer-to-peer UDP.
