# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repo manages infrastructure for multiple hosts using Ansible + Docker Compose (most hosts) or OpenTofu (tower).

**Ansible hosts** (`mx1`, `web1`, `web2`, `web3`, `web8`): each top-level directory contains `ansible/` (playbooks and roles) and `containers/` (Docker Compose stacks).

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
