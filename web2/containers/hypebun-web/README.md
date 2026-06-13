# hypebun-web

Hypebun Bio (AltumCode) served by **FrankenPHP** (Caddy + PHP in one process) with a
single **MariaDB** instance. Replaces the legacy split stack (Caddy + devilbox
php-fpm + 3-node DB cluster + MaxScale/ProxySQL).

## Architecture

| Service      | Image                              | Role                                                        |
|--------------|------------------------------------|-------------------------------------------------------------|
| `frankenphp` | `dunglas/frankenphp:1.12.4-php8.5` | Caddy + PHP in-process; serves prod, test and user domains. |
| `db`         | `mariadb:12.3.2`                   | Single MySQL-compatible database.                           |

Both join the external `app-infra` network.

### Environments (shared ports)

One FrankenPHP process owns `:80` / `:443`. The `Caddyfile` has named site blocks:

- `bio.hypebun.com`       -> `/apps/hypebun/bio-prod`
- `bio-test.hypebun.com`  -> `/apps/hypebun/bio-test`
- catch-all `https://`    -> `/apps/hypebun/bio-prod` (self-served user domains)

### Self-served domains (on-demand TLS)

Users point their own domain at this server. Any hostname not matched by the named
blocks falls into the catch-all block, which uses Caddy **on-demand TLS** to obtain a
Let's Encrypt certificate. Issuance is gated by the `ask` endpoint:

```
https://licensing-v1.sqrd-prod.com/hypebun/can-generate-https.php
```

Caddy queries it with `?domain=<host>`; an HTTP 200 allows the certificate.

### TLS certificate persistence

Issued certificates and the ACME account key live in Caddy's data dir
(`/data/caddy/certificates/`), backed by the **`caddy_data` named volume**. This
volume MUST be preserved so certificates survive container restarts/recreations —
**do not** prune it. Re-issuing on every restart would quickly hit Let's Encrypt
rate limits.

### App <-> DB over UNIX socket (zero-TCP)

MariaDB writes its socket to `/run/mysqld/mysqld.sock` (see `my.cnf`), shared to
FrankenPHP through the `db_socket` volume mounted at `/sockets`. PHP connects through
it via `mysqli.default_socket` / `pdo_mysql.default_socket` (see
`php-conf.d/zz-hypebun.ini`).

The DB is also published on `127.0.0.1:3306` for DBA access / imports only.

## Required host-side `config.php` (per environment)

App code is pre-placed on the host at `/apps/hypebun/bio-prod` and
`/apps/hypebun/bio-test` (out of scope for this stack). Each docroot's `config.php`
(git-ignored in the app repo) must use the socket connection:

```php
define('DATABASE_SERVER',   'localhost'); // 'localhost' => mysqli uses the socket
define('DATABASE_PORT',      null);        // null => fall back to mysqli.default_socket
define('DATABASE_USERNAME', '<MYSQL_USER or root>');
define('DATABASE_PASSWORD', '<MYSQL_PASSWORD>');
```

Per-environment differences:

| Setting          | prod                          | test                              |
|------------------|-------------------------------|-----------------------------------|
| `DATABASE_NAME`  | `hypebun_bio_prod`            | `hypebun_bio_test`                |
| `SITE_URL`       | `https://bio.hypebun.com/`    | `https://bio-test.hypebun.com/`   |
| `CDN_URL`        | `https://bio.hypebun.com/`    | `https://bio-test.hypebun.com/`   |

> `mysqli` treats `DATABASE_SERVER='localhost'` as a socket connection and reads the
> path from `mysqli.default_socket`. No core file edit is required for the socket.

## Setup

1. `cp .env.example .env` and fill `MYSQL_ROOT_PASSWORD`, `MYSQL_USER`,
   `MYSQL_PASSWORD`. `MYSQL_DATABASE=hypebun_bio_prod` is created on first boot.
2. Create the test database and grant the app user (the entrypoint only creates the
   single `MYSQL_DATABASE`):
   ```sql
   CREATE DATABASE hypebun_bio_test
     CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   GRANT ALL PRIVILEGES ON hypebun_bio_test.* TO '<MYSQL_USER>'@'%';
   FLUSH PRIVILEGES;
   ```
3. Import data dumps into `hypebun_bio_prod` / `hypebun_bio_test` (manual; out of
   scope for this stack).
4. Ensure app code exists in `/apps/hypebun/bio-prod` and `/apps/hypebun/bio-test`
   with the `config.php` shown above.
5. Deploy via the Ansible `system/containers` role (`hypebun-web` is registered in
   `docker_stacks`).

## Notes

- No `version:` key (Compose V2).
- `db` (data store) is intentionally exempt from `cap_drop: [ALL]` /
  `no-new-privileges` — its entrypoint runs as root and uses `gosu`.
- `frankenphp` keeps `cap_drop: [ALL]` + `cap_add: [NET_BIND_SERVICE]` +
  `no-new-privileges:true`. If it fails to bind `:80`/`:443` (some kernels strip the
  binary's ambient file capability under `no-new-privileges`), drop only
  `no-new-privileges` for this service and keep `cap_drop: [ALL]` +
  `NET_BIND_SERVICE`.
