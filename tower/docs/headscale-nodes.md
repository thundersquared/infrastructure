# Headscale Nodes

Nodes are machines running the standard Tailscale client against tower's Headscale. Their names, addresses and owners
live in Headscale's database, not in this repository. List them on tower with `headscale nodes list` (see
[headscale-setup.md](headscale-setup.md)).

Headscale assigns each node an address from `100.64.0.0/10` (plus one from `fd7a:115c:a1e0::/48`) at registration.

---

## Registering a Node

A node joins in one of three ways. All of them need the control server URL, `https://<tower-hostname>`, where
`<tower-hostname>` is the value of the `TOWER_HOSTNAME` environment secret. The client stores that URL at first login,
so it must not change later.

| Way | Use it for |
|:----|:-----------|
| [System-level client](#a-system-level-client) | Workstations, laptops, phones, and any host where MagicDNS should work for the host itself |
| [The `tailscale` container stack](#b-the-tailscale-container-stack) | mx1, web1, web2, web3: puts the host on the tailnet without installing packages |
| [A sidecar container](#c-a-sidecar-for-one-service) | Exposing a single service on the tailnet, as its own node |

Headscale 0.29 rejects clients older than **v1.80.0**. Check with `tailscale version`.

### Create a pre-auth key

Every way except an interactive login on macOS or iOS starts with a single-use key, created on tower from
`/opt/containers/headscale/` ([headscale-setup.md](headscale-setup.md#2-create-a-pre-auth-key-per-node)):

```bash
docker compose exec headscale headscale users list                      # note the user's ID
docker compose exec headscale headscale preauthkeys create --user <ID> --expiration 1h
```

Add `--ephemeral` for a node that should be deleted after 30 minutes offline (`node.ephemeral.inactivity_timeout`).
Ephemeral is a property of the key the node registered with: switching a node later means deleting it and registering
it again with the other kind of key.

### A. System-level client

**Linux.** Install the package from <https://tailscale.com/download/linux>, which enables `tailscaled`, then:

```bash
sudo tailscale up --login-server=https://<tower-hostname> --authkey=<preauth-key>
```

The key is only used for this login; `tailscaled` keeps the node's identity in `/var/lib/tailscale` and reconnects on
boot. If MagicDNS is enabled ([headscale-setup.md](headscale-setup.md#magicdns)) the node uses it by default and, with
systemd-resolved, sends only names under the base domain to Tailscale. Add `--accept-dns=false` to leave the node's DNS
untouched; `tailscale set --accept-dns=true` turns it on later.

**macOS.** With the CLI (any variant of the app):

```bash
tailscale login --login-server=https://<tower-hostname> --authkey=<preauth-key>
```

Or in the GUI: Option-click the menu bar icon, open **Debug → Custom Login Server → Add Account…**, and enter the URL.

**iOS.** In the Tailscale app, tap the account icon, then **Log in…**, then the options menu (top right) and **Use custom
coordination server**, and enter the URL.

The GUI logins on macOS and iOS are interactive: the browser shows a `headscale auth register --auth-id <id> --user
<user>` command. Run it on tower from `/opt/containers/headscale/` as `docker compose exec headscale headscale auth
register …` to approve the device.

### B. The `tailscale` container stack

Every Ansible host other than tower (`mx1`, `web1`, `web2`, `web3`) has a `containers/tailscale/` stack. Tower is the
control plane and does not join the tailnet as a node. It is listed in
`docker_stacks` with `env_file: true`, so it is deployed only on hosts where its `.env` exists. It runs
`ghcr.io/tailscale/tailscale` with host networking, so `tailscale0` and the `100.64.x.x` address belong to the host itself.

1. On the host, create the `.env` from the committed example and fill in the key, the login server and optionally a
   node name:

   ```bash
   cd /opt/containers/tailscale
   cp .env.example .env && chmod 600 .env
   $EDITOR .env        # TS_AUTHKEY, TS_EXTRA_ARGS=--login-server=https://<tower-hostname>, TS_HOSTNAME
   ```

2. Start it, or let the next deploy do it:

   ```bash
   docker compose up -d
   docker compose exec tailscale tailscale status
   ```

3. Once the node is listed, delete the `TS_AUTHKEY` line from `.env`. With `TS_AUTH_ONCE=true` the container logs in
   only when `./state` is not logged in yet; later starts reapply the hostname and DNS setting with `tailscale set` and
   never read the key. Without it, every start would log in again with the key, and a used or expired key would fail.

Things to know:

- **`./state` is the node.** Deleting `/opt/containers/tailscale/state` means registering again with a new key.
- **`TS_EXTRA_ARGS` only applies at first login**, because later starts do not run `tailscale up`. To change the login
  server or other `up`-only flags, register again (delete the node on tower, clear `./state`, set a new key).
- **No MagicDNS for the host.** The container cannot reach the host's systemd-resolved, so `TS_ACCEPT_DNS=false`. Use
  full names or `100.x` addresses, or the system-level client if the host needs MagicDNS.
- **Capabilities.** `cap_drop: [ALL]` plus `NET_ADMIN` (the TUN device and routes) and `NET_RAW` (tailscaled's
  firewall rules fail with "Permission denied" without it).
- **Health.** `TS_ENABLE_HEALTH_CHECK` serves `/healthz` on `127.0.0.1:9002`, which the compose healthcheck polls.

### C. A sidecar for one service

To put one service on the tailnet as its own node, without the host, run Tailscale in the service's network namespace.
In that service's stack:

```yaml
services:
  tailscale:
    image: ghcr.io/tailscale/tailscale:v1.102.5   # same pin as containers/tailscale
    hostname: <node-name>
    env_file: .tailscale.env    # TS_AUTHKEY, TS_EXTRA_ARGS, TS_STATE_DIR, TS_AUTH_ONCE=true, TS_USERSPACE=true
    volumes:
      - ./tailscale-state:/var/lib/tailscale
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true

  app:
    image: <app image>
    network_mode: service:tailscale
    depends_on:
      - tailscale
```

With `TS_USERSPACE=true` it needs no TUN device and no capabilities. Other nodes reach the app at
`<node-name>.<base domain>` or its `100.x` address on the port it listens on. The app cannot open connections into the
tailnet unless you also set `TS_SOCKS5_SERVER` or `TS_OUTBOUND_HTTP_PROXY_LISTEN` and point it at that proxy.

### What tailnet nodes can reach

`tailscaled` accepts everything that arrives on `tailscale0` in its own firewall chain, ahead of UFW. A host on the
tailnet therefore exposes every port it listens on outside loopback to every node the policy allows. The committed
policy (`tower/containers/headscale/config/policy.hujson`) lets every user reach their own devices and the nodes of the
`infrastructure` user, so a server is reachable from every user's devices, and the servers from each other. Ports bound
to `127.0.0.1`, as this repo's convention requires, stay unreachable. Change access with grants in the policy rather
than per-host rules.

Register servers under the `infrastructure` user and people's devices under their own user: the policy decides access
by user, so a server registered under a person's user is visible only to that person.

Exit nodes are the exception. Every user may use exit nodes (`autogroup:internet`), so an approved exit node is offered
to every user whoever owns it, including a person's own device. Only approve exit nodes that everyone may use.

### Verify the node is registered

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
