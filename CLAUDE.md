# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repo manages infrastructure for multiple hosts using Ansible + Docker Compose (most hosts) or OpenTofu (tower).

**Ansible hosts** (`mx1`, `web1`, `web2`, `web3`): each top-level directory contains `ansible/` (playbooks and roles) and `containers/` (Docker Compose stacks).

**OpenTofu hosts** (`tower`): each top-level directory contains `terraform/` (`.tf` files) and `docs/` (node-specific setup guide). Run `tofu` commands from the `terraform/` subdirectory. Variables are passed via `TF_VAR_*` env vars; the S3 backend requires `-backend-config` flags at `init` time — see `tower/docs/setup.md`. OpenTofu version: **1.11.x** (pinned in `.github/workflows/tower-tofu-apply.yml`). Note: `error()` in expressions requires ≥ 1.9. When updating providers, regenerate the lock file with `tofu providers lock -platform=linux_amd64` so CI hashes are included.

## Running Playbooks

```bash
cd <host>/ansible
ansible-playbook playbook.yml
```

`SCHEDULED_RUN=true` enables heavy tasks (OS hardening, APT updates, Docker install). Default is `false` for quick deploys.

Required environment variables before running (used by `lookup('env', ...)`): `BORG_PASSPHRASE`, `BORG_REPOSITORY`, `MYSQL_PASSWORD`, `BORG_HEARTBEAT_URL`.

## Architecture

**Deployment flow**: Ansible copies the local `containers/` directory to `/opt/containers/` on the remote host, then deploys each stack via `community.docker.docker_compose_v2`. The `docker_stacks` map in `roles/system/containers/defaults/main.yml` controls which stacks are deployed:

```yaml
docker_stacks:
  <service>:
    env_file: true   # deploy only if .env exists; false = always deploy
    state: present   # or restarted
```

**Shared network**: All containers use an external Docker network `app-infra`. The network is created by the `system/containers` role with optional IPv6 support via `DOCKER_IPV6_SUBNET`.

**Migrations**: One-time Ansible tasks in `ansible/migrations/`, tracked in `/opt/ansible/migrations.db` per host. Run first, before other roles. Use timestamped filenames: `YYYYMMDD_NNNN_description.yml`.

## Conventions

- **No `version:` key** in `docker-compose.yml` (deprecated in Compose V2)
- **Always bind ports to localhost**: `127.0.0.1:<port>:<port>`; use incremental ports (3001, 3002, ...) per host
- **Prefer `.env` files** over inline `environment:` blocks; set `env_file: - .env` in compose
- **Fixed image tags** — no `latest`; prefer `-alpine` variants; use `postgres:18-alpine` for new PostgreSQL stacks
- **Network declaration** in every compose file:
  ```yaml
  networks:
    app-infra:
      external: true
  ```

## Monitoring (monit)

The `system/monit` role (first-party; runs on every deploy) installs and
configures [monit](https://mmonit.com/monit/) on the Ansible hosts (`mx1`,
`web1`, `web2`, `web3`). It monitors filesystem space usage and alerts at two
thresholds (defaults `80%` and `90%`, set in the role's `defaults/main.yml`).

- **Base config**: `/etc/monitrc` (Ansible-managed, overwritten). monit's CLI
  is bound to a **localhost unix socket** (`/run/monit.sock`) — no TCP exposure.
- **Disk checks**: `/etc/monit.d/disk.cfg` (Ansible-managed). Filesystems are
  declared via `monit_disk_filesystems` in the role defaults (default: `/`;
  uncomment the `/var/lib/docker` entry on hosts where it is a separate mount).
- **Both thresholds fire email *and* a chat push.**

Two files are deployed **only if absent** (`force: no`), so hand-edited secrets
survive re-runs — they are intentionally kept out of git and Ansible vars:

- `/etc/monit.d/mail.cfg` — hand-edit SMTP server + `set alert <addr>` for email
  notifications (see the committed `mail.cfg.example`).
- `/etc/monit/notify-chat.env` — hand-fill `TELEGRAM_BOT_TOKEN` /
  `TELEGRAM_CHAT_ID` and/or `SLACK_WEBHOOK_URL` for chat notifications. The
  `/etc/monit/notify-chat.sh` helper curls whichever channel is configured and
  is a silent no-op otherwise.

After editing either file on a node: `monit reload`.

> Role selection note: `pgolm.monit` (MIT, Galaxy) was evaluated as the best
> community option (supports `filesystem` checks + mail templating), but a thin
> first-party role was chosen to avoid a stale dependency and because SMTP/chat
> secrets are hand-edited on the node rather than templated by Ansible.

## Container Security

Every service must have these two options by default:

```yaml
cap_drop:
  - ALL
security_opt:
  - no-new-privileges:true
```

**When to add `cap_add` back** (always pair with `cap_drop: [ALL]`):
- `NET_BIND_SERVICE` — container binds a privileged port (< 1024) directly, e.g. SMTP (25, 465, 587), IMAP (993), HTTPS (443)
- `NET_ADMIN` — VPN/network management (e.g. headscale)
- `SYS_NICE` — real-time scheduling (e.g. MySQL)
- `CHOWN` — init/setup containers that `chown` volume paths on startup

**Stateless containers** (no writable volume mounts) also get `read_only: true` plus `tmpfs` for any paths the runtime needs to write:

```yaml
read_only: true
tmpfs:
  - /tmp        # all runtimes
  - /run        # nginx (PID file)
```

Applied to: cloudflared, webmail, n8n runner.

`calcom` is **not** read-only — its entrypoint installs NPM packages and writes a build cache on startup, which breaks under `read_only: true`. Keep `cap_drop: [ALL]` + `no-new-privileges:true`, omit `read_only`/`tmpfs`.

**Containers exempt from `cap_drop`** (do not add):
- `watchtower` — requires Docker socket management
- `authentik worker` — runs as `root` with Docker socket for blueprint management
- Any init container whose sole job is `chown` (needs `CAP_CHOWN`; dropping all caps breaks it)
- **All data store images** (PostgreSQL, MySQL, Redis, KeyDB, Valkey, OpenSearch, Meilisearch) — their entrypoints start as `root` and use `gosu` to drop to the database user, which requires `CAP_SETUID`/`CAP_SETGID`. Both `cap_drop: [ALL]` and `no-new-privileges:true` break this pattern and prevent the container from starting.
- `roundcube` — Apache+PHP image breaks with `cap_drop: [ALL]`; gets `tmpfs: [/tmp]` only.

## Adding a Service

1. Create `<host>/containers/<service>/docker-compose.yml`
2. Add to `docker_stacks` in `<host>/ansible/roles/system/containers/defaults/main.yml`

## nftables + Docker + CrowdSec

When nftables is the firewall backend, three things must be correct:

1. **CrowdSec bouncer mode**: must be `nftables` (not iptables) in `/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml`
2. **IP forwarding**: both `net.ipv4.ip_forward: 1` and `net.ipv6.conf.all.forwarding: 1` required for containers to reach external services
3. **Conntrack tuning** (in `defaults/main.yml` under `sysctl_overwrite`):
   ```yaml
   net.netfilter.nf_conntrack_max: 262144
   net.netfilter.nf_conntrack_tcp_timeout_established: 86400
   net.netfilter.nf_conntrack_tcp_timeout_time_wait: 30
   ```
