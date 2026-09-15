# OpenCloud on Storage Box

OpenCloud runs under `opencloud.service`. Docker Compose stays in the foreground
for systemd lifecycle control. User files live only on the CIFS-mounted Storage
Box at `/mnt/opencloud`; OpenCloud configuration and system state stay local in
`/var/lib/opencloud/config` and `/var/lib/opencloud/data`.

`opencloud-storagebox.service` mounts the Storage Box. Every OpenCloud start
checks the exact mountpoint, UID/GID `1000:1000` access, rename, advisory lock,
xattrs, case-distinct names, and SMB-reserved names. Initial provisioning also
remounts once to verify content and xattr persistence. Failed checks block
OpenCloud; no local-storage fallback exists.

## Initial setup

1. Create dedicated Hetzner Storage Box subaccount. Enable SMB.
2. Run `ansible-playbook web1/ansible/playbook.yml` once. It installs tools,
   services, local directories, and host-only placeholder files. OpenCloud
   remains stopped until configuration exists.
3. On web1, create `/opt/containers/opencloud/.env` from
   `/opt/containers/opencloud/.env.example`. Set real HTTPS `OC_URL`,
   `IDM_ADMIN_PASSWORD`, `IDP_DOMAIN`, and `OC_OIDC_ISSUER`.
4. Fill `/etc/opencloud-storagebox.env` with the dedicated share:
   ```env
   OPENCLOUD_STORAGEBOX_REMOTE=//uXXXXX-subN.your-storagebox.de/uXXXXX-subN
   ```
5. Fill `/etc/opencloud-storagebox.credentials`, then keep mode `0600`:
   ```ini
   username=uXXXXX-subN
   password=CHANGE_ME
   ```
6. Run the playbook again. It mounts the share, runs the persistence gate,
   enables both services, then waits for `http://127.0.0.1:3006/`.

Ansible never reads configuration or credential contents. Manual `.env` edits
need `systemctl restart opencloud.service`.

## Authentik

OpenCloud uses Authentik as external OIDC provider. Built-in OpenCloud `idp` is
disabled; built-in IDM LDAP remains local and autoprovisions users using stable
Authentik `sub` claims.

Create an Authentik OAuth2/OIDC provider and application:

1. Client type: `Public`; client ID: `web`; scopes: `openid`, `profile`,
   `email`.
2. Add Strict Authorization redirects:
   `https://<OC_URL host>/oidc-callback.html`,
   `https://<OC_URL host>/oidc-silent-redirect.html`, and
   `https://<OC_URL host>/`.
3. Set Back-channel logout URI to
   `https://<OC_URL host>/backchannel_logout`.
4. Set `IDP_DOMAIN` without protocol. Set `OC_OIDC_ISSUER` to
   `https://<authentik host>/application/o/<application slug>/`.

This config supports browser login only. Desktop, Android, and iOS clients need
their own Authentik public clients and matching `WEBFINGER_*` OIDC values.

## Reverse proxy and operations

Proxy dedicated OpenCloud HTTPS hostname rooted at `/` to
`http://127.0.0.1:3006`. Preserve `Host`, `X-Real-IP`, `X-Forwarded-For`,
`X-Forwarded-Proto=https`, WebSocket upgrade headers, streaming responses, and
large resumable uploads. Disable request buffering or use equivalent streaming
behavior.

Check state with `systemctl status opencloud-storagebox.service opencloud.service`.
Before changing Storage Box endpoint, stop `opencloud.service`, stop the mount
service, update host configuration, start the mount service, verify its probes,
then start OpenCloud. Never remount while OpenCloud runs.

Storage Box snapshots alone are insufficient. Consistent backups include local
`/var/lib/opencloud/config`, local `/var/lib/opencloud/data`, and Storage Box
user data; stop OpenCloud before coordinated restore or backup.
