# OpenCloud on Storage Box

OpenCloud runs under `opencloud.service`. Docker Compose stays in the foreground
for systemd lifecycle control. User data uses OpenCloud DecomposedS3 with the
private Garage S3 service. Garage metadata is stored in local named Docker
volume `garage_meta`; Garage object blocks use Storage Box CIFS at
`/mnt/opencloud/garage`. OpenCloud configuration and system state use local
named volumes `opencloud_config` and `opencloud_data`.

## Compatibility status

Hetzner Storage Box CIFS rejects OpenCloud PosixFS grant xattr names such as
`user.oc.grant.u:<UUID>` with `EINVAL`. Do not use `STORAGE_USERS_DRIVER=posix`
on this mount. Garage isolates OpenCloud from these xattrs: its metadata and
object index stay local while Storage Box receives only Garage data blocks.

`opencloud-storagebox.service` mounts the Storage Box. Every OpenCloud start
checks the exact mountpoint plus Garage data-directory write, sync, read, and
rename behavior. Initial provisioning flushes a renamed block, remounts once,
and verifies its content persists. Failed checks block OpenCloud; no
local-storage fallback exists.

## Initial setup

1. Create dedicated Hetzner Storage Box subaccount. Enable SMB.
2. Run `ansible-playbook web1/ansible/playbook.yml` once. It installs tools,
   services, local directories, and host-only placeholder files. OpenCloud
   remains stopped until configuration exists.
3. On web1, create `/opt/containers/opencloud/.env` and `garage.env` from
   their `.example` files. Set real HTTPS `OC_URL`,
   `IDM_ADMIN_PASSWORD`, `IDP_DOMAIN`, `OC_OIDC_ISSUER`, all
   `STORAGE_USERS_DECOMPOSEDS3_*` values, and all `GARAGE_*` values in
   `garage.env`. Garage access key, secret key, and bucket values must exactly
   match their `STORAGE_USERS_DECOMPOSEDS3_*` counterparts. Generate
   `GARAGE_RPC_SECRET` as 64 random hexadecimal characters.
4. Fill `/etc/opencloud-storagebox.env` with the dedicated share:
   ```env
   OPENCLOUD_STORAGEBOX_REMOTE=//uXXXXX-subN.your-storagebox.de/uXXXXX-subN
   ```
5. Fill `/etc/opencloud-storagebox.credentials`, then keep mode `0600`:
   ```ini
   username=uXXXXX-subN
   password=CHANGE_ME
   ```
6. Run the playbook again. It mounts the share, creates `/mnt/opencloud/garage`,
   runs the persistence gate, bootstraps single-node Garage and its bucket,
   enables OpenCloud, then waits for `http://127.0.0.1:3006/`.

Ansible never reads configuration or credential contents. Manual `.env` edits
need `systemctl restart opencloud.service`.

Before storing production data, upload a file larger than 4 KiB through
OpenCloud, stop `opencloud.service`, remount Storage Box, restart OpenCloud,
then download and checksum the file. Simulate a temporary CIFS outage and
confirm Garage and OpenCloud recover after remount.

## Authentik

OpenCloud uses Authentik as external OIDC provider. Built-in OpenCloud `idp` is
disabled; built-in IDM LDAP remains local and autoprovisions users using
Authentik `preferred_username` claims. Authentik usernames must be unique and
immutable after first OpenCloud login.

Create an Authentik OAuth2/OIDC provider and application:

1. Client type: `Public`; client ID: `web`; scopes: `openid`, `profile`,
   `email`, `offline_access`. Enable the Refresh Token grant and
   `offline_access` scope mapping. Set Access token validity to `hours=8` or
   policy-approved equivalent; Authentik defaults to one hour.
2. Add Strict Authorization redirects:
   `https://<OC_URL host>/oidc-callback.html`,
   `https://<OC_URL host>/oidc-silent-redirect.html`, and
   `https://<OC_URL host>/`.
3. Set Back-channel logout URI to
   `https://<OC_URL host>/backchannel_logout`.
4. Set `IDP_DOMAIN` without protocol. Set `OC_OIDC_ISSUER` to
   `https://<authentik host>/application/o/<application slug>/`.
5. Ensure the Authentik `profile` scope mapping emits the `groups` claim.
   Create `opencloudAdmin` and `opencloudUser` groups. Add initial operator to
   both groups; add every standard user to `opencloudUser`. OpenCloud also
   recognizes `opencloudSpaceAdmin` and `opencloudGuest`.

OpenCloud maps those group values to roles on every login. An `opencloudAdmin`
member signs in at the OpenCloud URL, then opens user menu and selects
**Administration**. Users without a mapped group cannot sign in.

This config supports browser login only. Desktop, Android, and iOS clients need
their own Authentik public clients and matching `WEBFINGER_*` OIDC values.

## Reverse proxy and operations

Proxy dedicated OpenCloud HTTPS hostname rooted at `/` to
`http://127.0.0.1:3006`. Preserve `Host`, `X-Real-IP`, `X-Forwarded-For`,
`X-Forwarded-Proto=https`, WebSocket upgrade headers, streaming responses, and
large resumable uploads. Disable request buffering or use equivalent streaming
behavior.

Check state with `systemctl status opencloud-storagebox.service opencloud.service`
and `docker compose exec garage /garage status`.
Before changing Storage Box endpoint, stop `opencloud.service`, stop the mount
service, update host configuration, start the mount service, verify its probes,
then start OpenCloud. Never remount while OpenCloud runs.

Single-node Garage has no redundancy. Back up named volumes
`opencloud_config`, `opencloud_data`, and `garage_meta` with Storage Box Garage
data blocks together. Stop OpenCloud and Garage before coordinated restore or
backup.
