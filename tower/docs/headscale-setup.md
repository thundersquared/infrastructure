# Headscale Setup Guide

## Overview

Tower runs [Headscale](https://github.com/juanfont/headscale), a self-hosted implementation of the Tailscale control
server, with the embedded DERP relay enabled. Nodes run the standard Tailscale client pointed at
`https://<tower-hostname>`. Node addresses come from `100.64.0.0/10` and `fd7a:115c:a1e0::/48`.

This repository is public, so tower's hostname is not in its files. It lives in one GitHub environment secret,
`TOWER_HOSTNAME` (environment `tower`, see [setup.md](setup.md#environment-secrets-tower)), as a bare FQDN with no scheme.
OpenTofu uses it as the DNS record name. Ansible writes it into the stack's `.env` as `HEADSCALE_SERVER_URL` and
`HEADSCALE_TLS_LETSENCRYPT_HOSTNAME`, which Headscale reads in place of the matching config keys. Docs and examples
write it as `<tower-hostname>`. This keeps the name out of the current tree, not secret. Let's Encrypt publishes it in
Certificate Transparency logs, and any name that was ever committed stays in public git history. To keep the host hard
to find, pick a name that has never been in the repository, before registering clients.

Who manages what:

| Piece | Where | Managed by |
|---|---|---|
| VM, security list (`443/tcp`, `3478/udp`), DNS record | `tower/terraform/` | OpenTofu |
| Compose stack | `tower/containers/headscale/docker-compose.yml` | Ansible (`system/containers`) |
| Server config and access policy | `tower/containers/headscale/config/` | Git → Ansible, checked by CI |
| Hostname, ACME email, MagicDNS domains (`/opt/containers/headscale/.env`) | `TOWER_HOSTNAME`, `TOWER_ACME_EMAIL`, `TAILNET_*` secrets | Ansible (`system/headscale`) |
| Pre-deploy snapshots, data dir permissions | `tower/ansible/roles/system/headscale/` | Ansible |
| Keys, SQLite DB, ACME cache | `/opt/containers/headscale/data/` on tower | Headscale (never in git) |
| Users, nodes, pre-auth keys | Headscale's database | CLI on tower (see [below](#why-headscale-objects-are-not-in-opentofu)) |

Nothing in `config/` is secret. The server's private keys are generated into the data directory on first start.

If `TOWER_HOSTNAME` is unset and no `.env` exists yet, the deploy skips the Headscale stack (the role logs why) and
leaves any running container alone. Without the two variables Headscale refuses to start (`server_url must start with
https://`).

---

## Before promoting to production

1. Add the `TOWER_HOSTNAME` environment secret **before merging**. Without it the OpenTofu apply stops at
   variable validation (an unset secret arrives as an empty string), and the Headscale stack is skipped.
2. Run these on tower, since the stack's live state was never checked:

   ```bash
   cd /opt/containers/headscale
   docker compose ps                    # want: Up. "Restarting" = crash loop
   docker compose logs --tail 50
   ls -la config.yaml data/             # config.yaml should be a file, not a directory
   grep server_url config.yaml          # must be https://<tower-hostname>, the TOWER_HOSTNAME value
   ```

- If clients were registered against a different `server_url`, set `TOWER_HOSTNAME` to that host instead. Clients store
  the login server URL, so changing it orphans every registered node. Changing `TOWER_HOSTNAME` also renames the
  OpenTofu-managed DNS record in place. If a record for the new name already exists, delete it or `tofu import` it first,
  or the apply fails.
- If `data/db.sqlite` exists and nodes are registered, the deploy snapshots it before switching to the committed config
  (see [Backup and restore](#backup-and-restore)).
- Once the stack runs on the new compose (so nothing mounts it any more), the deploy renames the hand-written
  `config.yaml` to `config.yaml.pre-git`, so it can't be mistaken for the live file. Diff it against
  `config/config.yaml`, then delete it.

After the deploy, verify from **outside** tower:

```bash
curl -fsS https://<tower-hostname>/health     # {"status":"pass"}; also proves the Let's Encrypt cert is valid
```

From a node: `tailscale netcheck` must report `UDP: true` and `IPv4: yes, <address>`. The mapped address comes from
tower's STUN server, which proves `3478/udp` is reachable. A `tower` region latency on its own does not: netcheck
measures it over HTTPS when STUN fails. If either check fails while the container is healthy, check the host firewall: OCI's Ubuntu images can ship
iptables rules that reject inbound traffic other than SSH, on top of the security list.

---

## First start

DNS must already resolve to tower: Headscale fetches its certificate via ACME (TLS-ALPN-01, on port 443) the first time
a client connects. The record is `cloudflare_dns_record.tower` in `tower/terraform/dns.tf`.

Nothing has to be created on tower by hand. With `TOWER_HOSTNAME` set, Ansible deploys the config, writes `.env`,
creates `/opt/containers/headscale/data` (mode `0700`) and starts the container. Then, from `/opt/containers/headscale/`:

### 1. Create a user

A user owns nodes, roughly a Tailscale account.

```bash
docker compose exec headscale headscale users create <user>
docker compose exec headscale headscale users list            # note the ID
```

### 2. Create a pre-auth key per node

`--user` takes the numeric **ID** from `users list`, not the name. Prefer one single-use, short-lived key per node over a
reusable key:

```bash
docker compose exec headscale headscale preauthkeys create --user <ID> --expiration 1h
```

Use it within the hour on the node ([headscale-nodes.md](headscale-nodes.md)). A used or expired key cannot register
anything; already-registered nodes are unaffected by key expiry.

---

## Changing the config or the policy

Edit `config/config.yaml` or `config/policy.hujson` in a pull request. The **Headscale config** CI job runs the pinned
image's `headscale configtest` and `headscale policy check` against them. A bad policy also stops Headscale from
starting, so a red check here means "this would have taken the tailnet down".

On merge, the deploy copies the files and recreates the container, which reloads both. A fingerprint of `config/` is
written into `.env` (`CONFIG_SHA256`), so a retry after an interrupted deploy still recreates it, even when the files on
tower are already up to date.

`policy.hujson` is currently allow-all, which is exactly what Headscale does with no policy at all. The file explains how
to restrict it; any `"grants"` key switches the tailnet to deny-by-default.

---

## MagicDNS

MagicDNS is off until the `TAILNET_BASE_DOMAIN` secret is set. With it, the role switches it on through `.env`, and every
node becomes `<node>.<base domain>`. Each `TAILNET_SEARCH_DOMAINS` entry is pushed to nodes as a search domain, with
1.1.1.1, 9.9.9.9 and their IPv6 addresses as its split nameservers (`headscale_dns_split_nameservers` in the role
defaults). The role refuses a base domain that is tower's hostname or a parent of it: Headscale would refuse to start.

`override_local_dns` stays `false`. Nodes keep their own resolvers for everything outside the tailnet, and no global
nameservers are pushed (with this setting the client would use them only while an exit node is in use).

**Per node it is on by default.** Whether a node uses Tailscale's DNS is the client's `--accept-dns` setting, which
defaults to on. To opt a node out, run `tailscale set --accept-dns=false`. To make it opt-in, register nodes with
`tailscale up --accept-dns=false` and turn it on where wanted. In the macOS and iOS apps it is the "Use Tailscale DNS
settings" toggle. `tailscale dns status --all` shows what a node received.

What a node with it on does, per the Tailscale client source:

- **Linux without systemd-resolved** (plain `/etc/resolv.conf`): tailscaled takes the file over. It moves the original
  to `/etc/resolv.pre-tailscale-backup.conf` and writes `nameserver 100.100.100.100`, the search domains and the
  original's search domains. `options` and `domain` lines are dropped while it owns the file. Names outside the tailnet
  are forwarded to the original nameservers. A clean stop or `--accept-dns=false` restores the file. After a crash it
  stays pointed at 100.100.100.100 until tailscaled starts again (or `tailscaled --cleanup` runs), so lookups fail in
  between.
- **Linux with systemd-resolved:** split DNS. Only the tailnet domain and the search domains go to Tailscale; the
  search domains resolve through the split nameservers.
- **macOS app:** takes over all DNS and forwards names outside the tailnet to the Mac's own resolvers.
- **iOS:** because the search domains have split nameservers, it also takes over all DNS and forwards everything else
  to the phone's resolvers.

Short names try the tailnet first: a node named `web1` wins over `web1.<search domain>`. MagicDNS answers A records
only; to get AAAA records for dual-stack nodes, grant the `magicdns-aaaa` attribute in `policy.hujson` (`nodeAttrs`).

---

## Upgrading

Headscale ≥ 0.29 **refuses to start** if a minor version is skipped (0.28 → 0.30) or downgraded. It migrates the database
on start. Renovate raises one PR per minor version (`renovate.json`), and each PR body carries this checklist:

1. Merge minor versions **one at a time, oldest first**. Patch releases within a minor are always safe.
2. Read the release notes for removed config keys and the minimum Tailscale client version (0.29: **v1.80.0**). Update
   the clients first if needed.
3. Diff `config/config.yaml` against that release's `config-example.yaml`. The CI check fails only on keys Headscale
   lists as removed (it refuses to start on those). Any other renamed or dropped key is **silently ignored**, and new
   options don't show up at all, so this diff is the only way to catch either.
4. Merge. The deploy snapshots the database, then recreates the container on the new image.
5. Check `docker compose ps` (healthy) and `docker compose logs`, then run `tailscale status` on a node.

To roll back a minor upgrade, the previous image and the pre-upgrade database must go back together. The order
matters:

1. Merge a revert of the upgrade PR. The deploy recreates the container on the previous image, which refuses to open the
   migrated database and crash-loops. That is expected and changes nothing.
2. On tower, restore the snapshot **the upgrade deploy itself took**, following the steps in
   [Backup and restore](#backup-and-restore). The deploy takes its snapshot before it switches the image, so that one is
   the newest copy from before the migration. Every later snapshot holds the migrated database, including the one the
   revert deploy just took. The deploy log shows which run was the upgrade.

Doing it the other way round (restore first, revert later) leaves a window where the newer image starts on the restored
database, for example on the next scheduled deploy, and migrates it again.

---

## Backup and restore

Before every deploy, `system/headscale` writes a snapshot to `/opt/containers/headscale/backups/<UTC timestamp>/`. It
is built under a hidden `.<timestamp>.partial` name and renamed only once complete, so an interrupted attempt never takes
one of the kept slots. The next run removes leftover partial directories. Each snapshot holds:

- `db.sqlite`: an online copy taken with SQLite's backup API (consistent while Headscale runs), checked with
  `PRAGMA quick_check`. A failing check fails the deploy before the image is changed.
- `noise_private.key`, `derp_server_private.key`. The Noise key identifies the server to every client. Without it,
  every node has to be registered again.

The newest 14 are kept (`headscale_backup_keep`), about a week at two deploys a day. These snapshots live on the same
boot volume: they protect against a bad upgrade, **not** against losing the VM.

To restore:

```bash
cd /opt/containers/headscale
docker compose stop
cp backups/<timestamp>/db.sqlite data/db.sqlite
rm -f data/db.sqlite-wal data/db.sqlite-shm      # stale WAL from the newer database
cp backups/<timestamp>/*.key data/               # only if the keys were lost
docker compose up -d
```

`up -d` (not `start`) makes sure the container runs the image `docker-compose.yml` currently pins. `start` would reuse
the existing container, whatever image it was created from.

Removing the stale `-wal`/`-shm` files matters. SQLite would replay them onto the older `db.sqlite` and corrupt it.

---

## Key commands

Run from `/opt/containers/headscale/` on tower. Node and key commands take numeric IDs from the `list` output.

| Action | Command |
|---|---|
| Health | `docker compose exec headscale headscale health` |
| Create a user | `docker compose exec headscale headscale users create <name>` |
| List users (shows IDs) | `docker compose exec headscale headscale users list` |
| Create a single-use pre-auth key | `docker compose exec headscale headscale preauthkeys create --user <user-id> --expiration 1h` |
| List pre-auth keys | `docker compose exec headscale headscale preauthkeys list` |
| Expire a pre-auth key | `docker compose exec headscale headscale preauthkeys expire --id <key-id>` |
| List nodes | `docker compose exec headscale headscale nodes list` |
| Rename a node | `docker compose exec headscale headscale nodes rename --identifier <node-id> <new-name>` |
| Expire a node (forces re-login) | `docker compose exec headscale headscale nodes expire --identifier <node-id>` |
| Delete a node | `docker compose exec headscale headscale nodes delete --identifier <node-id>` |
| Show / approve advertised routes | `docker compose exec headscale headscale nodes list-routes` / `nodes approve-routes --identifier <node-id> --routes <cidr,…>` |
| Show the policy file as mounted (not necessarily the loaded one until the next restart) | `docker compose exec headscale headscale policy get` |

---

## Why Headscale objects are not in OpenTofu

OpenTofu already manages everything below Headscale: the VM, the security-list rules for `443/tcp` and `3478/udp`, and
the DNS record the server URL depends on. Headscale's **static** configuration, the server config and the access policy,
is declarative in git, deployed by Ansible and checked in CI against the real binary. What remains is runtime state: a
few users and nodes, and short-lived pre-auth keys. Moving that into OpenTofu was evaluated and rejected for now.

**The official `tailscale/tailscale` provider can't be used.** Headscale reimplements the protocol the Tailscale
*client* uses to reach its control server, not Tailscale's admin API. The provider's client builds every request as
`/api/v2/tailnet/{tailnet}/…` (`/acl`, `/keys`, `/devices`, `/dns/…`). Headscale serves a different API at `/api/v1/…`
(`/policy`, `/preauthkey`, `/node/{id}/tags`, `/user`) and has no `/api/v2` routes. Setting the provider's `base_url` to
tower gets 404s.

**The community `awlsring/headscale` provider doesn't support this version.** It covers users, pre-auth keys, API keys,
node tags, subnet routes and the policy (the policy only with `policy.mode: database`). Its newest line, 0.5.x, last
released 2026-03-19, supports Headscale **0.28.x**. Tower runs 0.29.4, whose API added the `auth` routes and changed the
register endpoint. Headscale also won't downgrade to 0.28 to match it. Every Headscale minor bump would wait on a
third-party provider release.

**It would cost more than it saves, even if it were compatible:**

- **A standing admin credential in CI.** OpenTofu needs a Headscale API key, created by hand on the server first, that
  expires after 90 days by default. As a GitHub secret it can mint pre-auth keys, which means it can join a machine to
  the tailnet next to every node. Today no such credential exists outside tower.
- **Join credentials in state.** Pre-auth keys created by OpenTofu are stored in the S3 state file.
- **Nodes register themselves.** OpenTofu can only adopt a node after `tailscale up`, by its server-assigned ID, for tags
  and routes. Every node join becomes two steps.
- **Coupling to the VM's apply.** `tower-tofu-apply.yml` runs daily with `-auto-approve` and discards its output, and the
  Ansible deploy (which starts Headscale) runs after it. A Headscale provider in the same root module would make the VM
  and DNS apply depend on the app being up and on API compatibility after every Renovate bump. On a rebuilt VM it could
  not apply at all until Ansible had run. Avoiding that means a separate root module, state and workflow.
- **The policy already gets the benefit.** In file mode, `policy.hujson` is reviewed in a PR, checked by
  `headscale policy check`, and deployed like any other file.

**When to revisit:** the provider ships and keeps up with Headscale 0.29+ releases, *and* the tailnet grows to the point
where users, tags or routes change often (several operators, OIDC, ACL tags per service). Then it belongs in its own
root module (for example `tower/headscale/`) with its own state and workflow, chained after the Ansible deploy, never in
`tower/terraform/`.

OpenTofu changes worth making for Headscale, none applied here:

- **Off-host backups.** An `oci_core_volume_backup_policy` assigned to the boot volume would protect the data directory
  against losing the VM. The free tier includes five volume backups.
- **No `AAAA` record yet.** The instance has IPv6, but the `app-infra` network on tower is IPv4-only. Docker's userland
  proxy would make STUN report the wrong address to IPv6 clients. Enable IPv6 on that network (or use host networking for
  this container) before publishing an `AAAA` record.
