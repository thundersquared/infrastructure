# Infrastructure Repository Instructions

This repository manages infrastructure for multiple hosts (`mx1`, `web1`, `web2`, etc.) using Ansible and Docker Compose.

## Architecture & Structure

- **Host-Based Isolation**: Each top-level directory corresponds to a specific host (e.g., `mx1/`, `web1/`).
- **Ansible & Containers**: Each host directory contains:
  - `ansible/`: Playbooks and roles for system configuration.
  - `containers/`: Docker Compose definitions for services running on that host.
- **Deployment Pattern**:
  - The `system/containers` role copies the *entire* local `containers/` directory to `/opt/containers/` on the remote host.
  - Services are deployed via `community.docker.docker_compose_v2` by iterating over the `compose_files` list (defined in vars or defaults).
  - **Shared Network**: All containers typically attach to an external Docker network named `app-infra`.

## Key Workflows

- **Ansible Execution**:
  - Run playbooks from the host's `ansible/` directory.
  - **Conditional Execution**: The `scheduled_run` variable (env var `SCHEDULED_RUN`) controls "heavy" tasks like OS hardening, APT updates, and Docker installation. Set to `true` for maintenance runs, `false` for quick app deployments.
  - **Secrets**: Secrets are injected via environment variables using `lookup('env', 'VAR_NAME')`. Ensure these are set in your environment before running playbooks.
    - **Backup Secrets**: `BORG_PASSPHRASE`, `BORG_REPOSITORY`, `MYSQL_PASSWORD`, `BORG_HEARTBEAT_URL` are required for the `system/backup` role.

## Role Responsibilities

- **`system/containers`**: Core deployment role. Copies `containers/` to `/opt/containers/` and runs `docker compose up`.
- **`system/config`**: System-level config including UFW rules and `systemd-resolved` (DNS over TLS with Cloudflare/Quad9).
- **`system/backup`**: Configures Borgmatic backups using `borgbase.ansible_role_borgbackup`.
- **`system/apt`**: Handles package updates and installation (usually conditional on `scheduled_run`).

## Conventions

- **Role Structure**: Roles are often nested under `roles/system/` (e.g., `roles/system/containers`, `roles/system/config`).
- **Service Location**: Docker Compose projects live in `/opt/containers/<service_name>`.
- **Network**: Use `networks: { app-infra: { external: true } }` in `docker-compose.yml`.
- **Compose Version**: Do not include the `version` top-level element in `docker-compose.yml` files, as it is deprecated in Compose V2.
- **Hardening**: The project uses `devsec.hardening` roles. Be mindful of strict permissions and SSH configurations (e.g., `ssh_permit_root_login: "without-password"`).
- **Variables**: Check `defaults/main.yml` in each host's ansible directory for global settings like `sysctl` overrides and SSH policies.

## Development Tips

- **Adding a Service**:
  1. Create `containers/<service>/docker-compose.yml`.
  2. Ensure it uses the `app-infra` network.
  3. Add the service name to the `compose_files` list in the appropriate Ansible vars/defaults if it's not dynamically discovered (currently defaults to `['watchtower']`).
- **Debugging**:
  - If a deploy fails, check the `system/containers` role tasks.
  - Verify environment variables for secrets are present.
