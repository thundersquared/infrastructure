# hypebun-web

Hypebun Bio (AltumCode) served by **FrankenPHP** (Caddy + PHP in one process) with a
single **MariaDB** instance. Replaces the legacy split stack (Caddy + devilbox
php-fpm + 3-node DB cluster + MaxScale/ProxySQL).

## Architecture

| Service      | Image                              | Role                                                        |
|--------------|------------------------------------|-------------------------------------------------------------|
| `frankenphp` | `dunglas/frankenphp:1.12.4-php8.5` | Caddy + PHP in-process; serves prod, test and user domains. |
| `db`         | `mariadb:12.3.2`                   | Single MySQL-compatible database.                           |

Both join the external `app-infra` network. PHP runs in **classic** (per-request)
mode — see [Worker mode](#worker-mode-future) before changing that.

### Environments (shared ports)

One FrankenPHP process owns `:80` / `:443`. The `Caddyfile` has named site blocks:

- `bio.hypebun.com`       -> `/app/prod/current`
- `bio-test.hypebun.com`  -> `/app/test/current`
- catch-all `https://`    -> `/app/prod/current` (self-served user domains)

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

## Host filesystem layout

App code is **not** part of this repo and is **not** deployed by Ansible. It lives on
the host under `/opt/hypebun/<env>` in a Capistrano-style release tree:

```
/opt/hypebun/prod/
├── releases/<timestamp>/   immutable code for one deploy (mounted read-only)
├── shared/
│   ├── uploads/            persisted user media     -> Docker volume uploads_prod
│   ├── cache/              ephemeral render cache    -> tmpfs
│   └── config.php          per-env app config (secrets; never committed)
└── current -> releases/<timestamp>   atomic symlink the web server serves
```

Each release's `uploads/`, `uploads/cache/` and `config.php` are symlinked into
`shared/` by `deploy.sh`, so mutable state and secrets survive deploys and are kept
out of the code tree.

The container mounts the **whole** `/opt/hypebun/<env>` dir at `/app/<env>`
**read-only** (so a `current` symlink swap is visible inside the container), with the
writable Docker volume / tmpfs overlaid on the stable `shared/uploads` and
`shared/cache` paths.

> **Read-only code:** the app must not mutate its own code. The only runtime writes
> outside `uploads/` are AltumCode's plugin enable/disable (writes
> `plugins/<name>/config.json`). Treat plugin state as **deploy-time** config: enable
> the plugins you want in the source before deploying. Toggling plugins via the admin
> UI at runtime will fail under the read-only mount — re-deploy instead.

## Zero-downtime deploys

`deploy.sh` implements atomic releases:

```bash
# Deploy a new release of an environment from a prepared source dir:
./deploy.sh prod /path/to/hypebun-bio
./deploy.sh test /path/to/hypebun-bio

# Roll back to the previous release:
./deploy.sh prod --rollback
```

How it stays zero-downtime:

- The new code is staged at a fresh `releases/<timestamp>/` path, then `current` is
  flipped with an atomic `rename(2)`. In-flight requests finish on the old release;
  new requests hit the new one.
- Because each release has a **unique realpath**, OPcache treats the new files as new
  — no stale cache, no restart needed. `deploy.sh` also issues a best-effort
  `opcache_reset()` as a safety net.
- No container restart, no port rebind, the `caddy_data` cert store is untouched.

Tunables (env vars): `HYPEBUN_BASE` (default `/opt/hypebun`), `KEEP_RELEASES`
(default `5`), `COMPOSE_SERVICE` (default `hypebun-web`).

> Wire CI to call `deploy.sh` after syncing the source to the host. Database schema
> changes should use **expand/contract** migrations (add columns/tables first, deploy
> code, drop later) so old and new releases stay compatible during the swap.

## Required host-side `config.php` (per environment)

`shared/config.php` (git-ignored in the app repo) must use the socket connection:

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
4. Create `shared/config.php` for each env (see above), then deploy the first
   release: `./deploy.sh prod /path/to/hypebun-bio`.
5. Deploy the stack via the Ansible `system/containers` role (`hypebun-web` is
   registered in `docker_stacks`).

## Worker mode (future)

FrankenPHP worker mode keeps the app booted in long-lived processes for a big perf
win, but AltumCode Bio is **not worker-safe as-is**: it uses static singletons that
would leak state across requests, and calls `die()`/`exit()` mid-request (which would
kill a worker, not just the request). Enabling it requires app patches (replace
`die()`/`exit()` with exceptions, reset static state each loop). Until then we run
classic per-request mode — still far faster than the old php-fpm + FastCGI stack
because PHP is in-process. The zero-downtime deploy flow above does not depend on
worker mode.

## Notes

- No `version:` key (Compose V2).
- `db` (data store) is intentionally exempt from `cap_drop: [ALL]` /
  `no-new-privileges` — its entrypoint runs as root and uses `gosu`.
- `frankenphp` keeps `cap_drop: [ALL]` + `cap_add: [NET_BIND_SERVICE]` +
  `no-new-privileges:true`. If it fails to bind `:80`/`:443` (some kernels strip the
  binary's ambient file capability under `no-new-privileges`), drop only
  `no-new-privileges` for this service and keep `cap_drop: [ALL]` +
  `NET_BIND_SERVICE`.
