````markdown
# Ansible Role: system/containers

This role copies containers from `common/containers/` and optionally from host-specific `containers/` directories to the remote node at `/opt/containers/` and deploys all docker-compose files from a given list.

## Tasks
- Copies the `common/containers` directory to `/opt/containers/` on the remote node (controlled by `common_containers_dir` variable).
- Optionally copies the host-specific `containers` directory to `/opt/containers/` on the remote node (controlled by `host_containers_dir` variable).
- Deploys docker-compose projects listed in the `compose_files` variable (default: `watchtower`).

## Variables
- `common_containers_dir`: Boolean to control if common containers should be copied (default: `true`)
- `host_containers_dir`: Boolean to control if host-specific containers should be copied (default: `false`)
- `compose_files`: List of docker-compose projects to deploy (default: `['watchtower']`)

## Usage
Include this role in your playbook:

```yaml
- hosts: all
  roles:
    - role: system/containers
```

Override variables to control container sources and deployments:

```yaml
- hosts: all
  roles:
    - role: system/containers
      vars:
        common_containers_dir: true
        host_containers_dir: true
        compose_files:
          - watchtower
          - another_project
```

````
