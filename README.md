# Infrastructure

This repository manages the infrastructure for multiple hosts using Ansible and Docker Compose.

## Architecture

The project follows a host-based isolation strategy where each top-level directory corresponds to a specific host (e.g., `mx1`, `web1`).

Each host directory contains:
- `ansible/`: Playbooks and roles for system configuration.
- `containers/`: Docker Compose definitions for services running on that host.

### Deployment Pattern

1.  **Ansible**: Configures the host system (OS hardening, users, firewall, etc.).
2.  **Containers**: The `system/containers` role copies the local `containers/` directory to `/opt/containers/` on the remote host.
3.  **Services**: Services are deployed via `docker compose` by iterating over the defined compose files.
4.  **Network**: All containers typically attach to an external Docker network named `app-infra`.

## Hosts

The repository currently manages the following hosts:
- `mx1`
- `web1`
- `web2`
- `web3`
- `web8`

## Usage

### Prerequisites

- **Ansible**: Must be installed on the machine running the playbooks.
- **SSH Access**: You need SSH access to the target hosts.

### Running Playbooks

Navigate to the host's ansible directory and run the playbook:

```bash
cd <host>/ansible
ansible-playbook playbook.yml
```

### Environment Variables & Secrets

Secrets are injected via environment variables using `lookup('env', 'VAR_NAME')`. Ensure these are set in your environment before running playbooks.

Common required variables include:
- `BORG_PASSPHRASE`
- `BORG_REPOSITORY`
- `MYSQL_PASSWORD`
- `BORG_HEARTBEAT_URL`

### Scheduled vs. Quick Runs

The `scheduled_run` variable (controlled by the `SCHEDULED_RUN` environment variable) determines the scope of the execution:

- `SCHEDULED_RUN=true`: Runs "heavy" tasks like OS hardening, APT updates, and Docker installation. This is typically used for maintenance runs.
- `SCHEDULED_RUN=false` (default): Skips heavy tasks for quick app deployments.

## Migrations

This infrastructure uses a migration system similar to Laravel's database migrations, but for system configuration. Migrations are one-time Ansible tasks that run only once per host.

### Migration Features
- **One-time execution**: Each migration runs only once, tracked in `/opt/ansible/migrations.db`
- **Per-host state**: Each host maintains its own migration history
- **Error handling**: Playbook execution stops if a migration fails
- **Versioned**: Migrations use timestamped filenames (e.g., `20240121_0001_setup_database.yml`)

### Creating Migrations
1. Create a new `.yml` file in `<host>/ansible/migrations/`
2. Use timestamp format: `YYYYMMDD_NNNN_description.yml`
3. Write standard Ansible tasks in the file

### Example Migration
```yaml
---
# Migration: 20240121_0001_create_app_user
- name: Create application user
  user:
    name: myapp
    system: yes
    shell: /bin/bash

- name: Create application directory
  file:
    path: /opt/myapp
    state: directory
    owner: myapp
    group: myapp
    mode: '0755'
```

### Migration Execution
Migrations run automatically as part of the playbook execution via the `system/migrations` role. They execute before container deployment to ensure system prerequisites are met.

If a migration fails, the entire playbook stops to prevent inconsistent states.

## Dependency Management

This repository uses Renovate to keep dependencies up-to-date:

- **Docker Images**: Updates Docker images in `docker-compose.yml` files across all host `containers/` directories.
- **Ansible Requirements**: Manages Ansible collections and roles in `requirements.yml` files for each host.

To enable Renovate:
- Install the [Renovate GitHub app](https://github.com/apps/renovate) on the repository.

For private registries, configure `hostRules` in `renovate.json` with appropriate credentials.

## Development

### Adding a Service

1.  Create a new directory in `<host>/containers/<service_name>/`.
2.  Add a `docker-compose.yml` file.
    -   Ensure it uses the `app-infra` network:
        ```yaml
        networks:
          app-infra:
            external: true
        ```
    -   **Note**: Do not include the top-level `version` property in `docker-compose.yml` files.
3.  Add the service name to the `compose_files` list in the host's Ansible variables (usually in `defaults/main.yml`) if it is not dynamically discovered.

## Role Responsibilities

- **`system/containers`**: Core deployment role. Copies `containers/` to `/opt/containers/` and runs `docker compose up`.
- **`system/config`**: System-level config including UFW rules and `systemd-resolved`.
- **`system/backup`**: Configures Borgmatic backups.
- **`system/apt`**: Handles package updates and installation (usually conditional on `scheduled_run`).
