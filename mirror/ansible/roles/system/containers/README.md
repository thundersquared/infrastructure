# Ansible Role: system/containers

This role copies the `web8/containers/` directory to the remote node at `/opt/containers/` and deploys all docker-compose files from a given list (currently only `watchtower`).

## Tasks
- Copies the local `containers` directory to `/opt/containers/` on the remote node.
- Deploys docker-compose projects listed in the `compose_files` variable (default: `watchtower`).

## Usage
Include this role in your playbook:

```yaml
- hosts: all
  roles:
    - role: system/containers
```

Override `compose_files` if you want to deploy more projects:

```yaml
- hosts: all
  roles:
    - role: system/containers
      vars:
        compose_files:
          - watchtower
          - another_project
```
