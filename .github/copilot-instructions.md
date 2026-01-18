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
  - For each stack, a stat task checks for `.env` file existence before deployment.
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
- **`system/config`**: System-level config including UFW rules and `systemd-resolved` (DNS over TLS with Cloudflare/Quad9).
- **`system/backup`**: Configures Borgmatic backups using `borgbase.ansible_role_borgbackup`.
- **`system/apt`**: Handles package updates and installation (usually conditional on `scheduled_run`).

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
