# Infrastructure Repository Instructions

This repository manages infrastructure for multiple hosts (`mx1`, `web1`, `web2`, etc.) using Ansible and Docker Compose.

## Architecture & Structure

- **Host-Based Isolation**: Each top-level directory corresponds to a specific host (e.g., `mx1/`, `web1/`).
- **Ansible & Containers**: Each host directory contains:
  - `ansible/`: Playbooks and roles for system configuration.
  - `containers/`: Docker Compose definitions for services running on that host.
- **Deployment Pattern**:
  - The `system/containers` role copies the *entire* local `containers/` directory to `/opt/containers/` on the remote host.
  - Services are deployed via `community.docker.docker_compose_v2` by iterating over the `docker_stacks` map (defined in `defaults/main.yml`).
  - For each stack, an included task file checks for `.env` file existence and deploys conditionally.
  - Deployment conditions: A stack is deployed if `env_file: false` or (`env_file: true` and the `.env` file exists in the stack folder).
  - State is set directly from the `state` value in the map (`present` or `restarted`).
  - **Shared Network**: All containers typically attach to an external Docker network named `app-infra`.

## Key Workflows

- **Ansible Execution**:
  - Run playbooks from the host's `ansible/` directory.
  - **Conditional Execution**: The `scheduled_run` variable (env var `SCHEDULED_RUN`) controls "heavy" tasks like OS hardening, APT updates, and Docker installation. Set to `true` for maintenance runs, `false` for quick app deployments.
  - **Secrets**: Secrets are injected via environment variables using `lookup('env', 'VAR_NAME')`. Ensure these are set in your environment before running playbooks.
    - **Backup Secrets**: `BORG_PASSPHRASE`, `BORG_REPOSITORY`, `MYSQL_PASSWORD`, `BORG_HEARTBEAT_URL` are required for the `system/backup` role.

## Role Responsibilities

- **`system/containers`**: Core deployment role. Copies `containers/` to `/opt/containers/` and deploys Docker Compose stacks based on the `docker_stacks` configuration, with conditional deployment based on environment file requirements.
- **`system/config`**: System-level config including UFW rules and `systemd-resolved` DNS configuration. Configures conntrack tuning to prevent connection tracking table exhaustion in nftables environments.
- **`system/backup`**: Configures Borgmatic backups using `borgbase.ansible_role_borgbackup`.
- **`system/apt`**: Handles package updates and installation (usually conditional on `scheduled_run`).
- **`system/crowdsec`**: Deploys CrowdSec and its bouncers (nftables and nginx). Ensures bouncer mode is set to `nftables` when using nftables firewall.

## Migrations

The infrastructure includes a migration system for one-time system configuration tasks:

- **Location**: `ansible/migrations/` directory per host
- **State Storage**: `/opt/ansible/migrations.db` (SQLite database)
- **Execution**: Via `system/migrations` role, runs **first** after apt (before config, crowdsec, containers, etc.) to apply patches before other roles run as a sanity check
- **Error Handling**: Playbook stops on migration failure
- **Tracking**: Each migration recorded with timestamp

When adding migrations, ensure they are idempotent and handle errors appropriately. Use timestamped filenames like `20240121_0001_description.yml`.

## Conventions

- **Role Structure**: Roles are often nested under `roles/system/` (e.g., `roles/system/containers`, `roles/system/config`).
- **Service Location**: Docker Compose projects live in `/opt/containers/<service_name>`.
- **Network**: Use `networks: { app-infra: { external: true } }` in `docker-compose.yml`.
- **Compose Version**: Do not include the `version` top-level element in `docker-compose.yml` files, as it is deprecated in Compose V2.
- **Environment Variables**: Prefer `.env` files over explicit `environment:` definitions in `docker-compose.yml`. Use `env_file: - .env` to load all required environment variables from a single source of truth.
- **Container Versions**: Use fixed version tags instead of `latest` for improved accountability and reproducible deployments. For PostgreSQL, use `postgres:18-alpine` in new stacks.
- **Port Assignment**: New stacks should use incremental ports (e.g., 3001, 3002, 3003) based on the highest port number used by existing stacks. Always bind to localhost (127.0.0.1) unless otherwise stated.
- **Hardening**: The project uses `devsec.hardening` roles. Be mindful of strict permissions and SSH configurations (e.g., `ssh_permit_root_login: "without-password"`).
- **Variables**: Check `defaults/main.yml` in each host's ansible directory for global settings like `sysctl` overrides, SSH policies, and the `docker_stacks` map defining which containers to deploy and their configuration.

## nftables & Docker Compatibility

When using nftables as the firewall backend with Docker containers and CrowdSec:

1. **CrowdSec Bouncer Configuration**: Ensure `mode: nftables` is set in `/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml`. If the bouncer uses iptables mode while nftables is the system firewall, it will cause container outbound traffic to be blocked. Migration `20260204_0003_fix_crowdsec_nftables_priority` applies this fix to existing hosts.

2. **Connection Tracking Tuning**: Add the following sysctl settings in `defaults/main.yml` under `sysctl_overwrite` to prevent conntrack table exhaustion with many containers:
   ```yaml
   net.netfilter.nf_conntrack_max: 262144
   net.netfilter.nf_conntrack_tcp_timeout_established: 86400
   net.netfilter.nf_conntrack_tcp_timeout_time_wait: 30
   ```

3. **CrowdSec nftables Priority**: The bouncer configuration should include:
   ```yaml
   nftables:
     ipv4:
       enabled: true
       set-only: false
       table: crowdsec
       chain: crowdsec-chain
       priority: -10
     ipv6:
       enabled: true
       set-only: false
       table: crowdsec6
       chain: crowdsec6-chain
       priority: -10
   ```
   This ensures CrowdSec rules are evaluated before Docker's NAT rules (priority 0), maintaining proper chain processing order.

## DNS Configuration

**systemd-resolved** settings in `system/config`:

- **Servers**: Primary DNS resolvers (Google, Quad9)
- **Fallback DNS**: Secondary resolvers (ControlD, Cloudflare) for redundancy
- **Cache**: Use `Cache=yes` (default) in production for optimal performance. Caches both positive and negative responses, reducing DNS query load. Avoid `Cache=no-negative` as it causes repeated queries for failed lookups.
- **DNSOverTLS**: Set to `no` for compatibility with common network environments
- **Search Domain**: Can be configured via `Domain=` setting (e.g., `Domain=eu.sqrd-dns.com`) to append domain to single-label hostname lookups

## Development Tips

- **Adding a Service**:
  1. Create `containers/<service>/docker-compose.yml`.
  2. Ensure it uses the `app-infra` network.
  3. Add an entry to the `docker_stacks` map in `roles/system/containers/defaults/main.yml` with `env_file` and `state` settings. Set `env_file: true` if the compose file uses `env_file: - .env`, otherwise `false`. Set `state: restarted` for services that should be restarted on deployment (e.g., watchtower), otherwise `present`.
- **Debugging**:
  - If a deploy fails, check the `system/containers` role tasks.
  - Verify environment variables for secrets are present.

## Dependency Management

- **Renovate**: Handles updates for Docker images in `docker-compose.yml` files and Ansible requirements in `requirements.yml` files across all hosts. Requires the Renovate GitHub app to be installed on the repository.
