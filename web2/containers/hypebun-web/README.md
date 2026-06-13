# hypebun-web

Hypebun Bio (AltumCode) served by **FrankenPHP** (Caddy + PHP in one process) with a
single **MariaDB** instance. Replaces the legacy split stack (Caddy + devilbox
php-fpm + 3-node DB cluster + MaxScale/ProxySQL).

## Architecture

| Service      | Image                                    | Role                                                        |
|--------------|------------------------------------------|-------------------------------------------------------------|
| `frankenphp` | built from `Dockerfile` (FrankenPHP 1.12.4 / PHP 8.5) | Caddy + PHP in-process; serves prod, test and user domains. |
| `db`         | `mariadb:12.3.2`                         | Single MySQL-compatible database.                           |

Both join the external `app-infra` network. PHP runs in **classic** (per-request)
mode — see [Worker mode](#worker-mode-future) before changing that.

### Custom PHP image

The base `dunglas/frankenphp` image ships a minimal extension set (PDO + mysqlnd
only). AltumCode requires `mysqli` (its core DB layer) and `gd` (captcha / image
processing), so `frankenphp` is built from the local `Dockerfile`, which adds:
`mysqli`, `pdo_mysql`, `gd`, `intl`, `zip`, `exif`, `bcmath`, `gmp`, `opcache`.
Compose builds it automatically; the resulting image is tagged
`hypebun-frankenphp:1.12.4-php8.5`.

### Environments (shared ports)

One FrankenPHP process owns `:80` / `:443`. The `Caddyfile` has named site blocks:

- `bio.hypebun.com`       -> `/app/prod`
- `bio-test.hypebun.com`  -> `/app/test`
- catch-all `https://`    -> `/app/prod` (self-served user domains)

### Self-served domains (on-demand TLS)

Users point their own domain at this server. Any hostname not matched by the named
blocks falls into the catch-all block, which uses Caddy **on-demand TLS** to obtain a
Let's Encrypt certificate. Issuance is gated by a local **ask** endpoint:

```
http://127.0.0.1:9180/can-generate-https.php
```

This is served by the same FrankenPHP instance via a loopback-only listener
(`:9180` site block in the `Caddyfile`) that runs the prod release's
`tools/can-generate-https.php`. No external licensing service is contacted on the
cert hot path. Caddy queries it with `?domain=<host>`; the endpoint replies `200`
(allow) if the host is one of our first-party hosts **or** exists in the `domains`
table with `is_enabled = 1`, otherwise `403` (deny). It **fails closed** — any error
denies issuance.

The endpoint reads two optional env vars (set on the `frankenphp` service if needed):

- `HYPEBUN_TLS_VERIFY_DNS` — `0` to skip the DNS pre-check (default: on). When on,
  the requested host must resolve (A/AAAA) to one of this server's IPs before a cert
  is issued — extra protection against issuing certs for domains not actually pointed
  here.
- `HYPEBUN_SERVER_IPS` — comma-separated public IP(s) of this host, used by the DNS
  check. If unset it is derived from the hostname; set it explicitly to avoid
  surprises.

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
the host under `/opt/hypebun/<env>` as a plain **git clone**:

```
/opt/hypebun/prod/        git clone of the app (git pull to update)
├── index.php
├── config.php            per-env app config (secrets; git-ignored)
├── uploads/              persisted user media (git-ignored; bind-mounted RW)
│   └── cache/            ephemeral render cache (tmpfs)
└── ...
```

The container mounts `/opt/hypebun/<env>` at `/app/<env>` **read-only** (the app must
not mutate its own code). `uploads/` is git-ignored, so it stays inside the clone and
is bind-mounted back **read-write** so the app can write user media; `uploads/cache/`
is a tmpfs (ephemeral, off-disk, out of backups).

> **Read-only code:** the only runtime writes outside `uploads/` are AltumCode's
> plugin enable/disable (writes `plugins/<name>/config.json`). Under the read-only
> mount, toggling plugins via the admin UI will fail — set plugin state in the repo
> and `git pull` instead.

## Deploying / updating

```bash
# First time: clone the app into the env dir.
git clone <hypebun-bio repo> /opt/hypebun/prod
git clone <hypebun-bio repo> /opt/hypebun/test   # if running test

# Create /opt/hypebun/prod/config.php (see "Required host-side config.php"),
# place any existing uploads under /opt/hypebun/prod/uploads, then start.
cd /opt/containers/hypebun-web
docker compose up -d --build

# To update the code later:
cd /opt/hypebun/prod && git pull
docker exec hypebun-web php -r 'opcache_reset();'   # drop stale opcache
```

> No zero-downtime story for now — a `git pull` updates files in place. OPcache
> picks them up within `opcache.revalidate_freq` (3s) or immediately after the
> `opcache_reset()` above. Database schema changes should still use **expand /
> contract** migrations to stay compatible across an update.

## Required host-side `config.php` (per environment)

`/opt/hypebun/<env>/config.php` (git-ignored in the app repo) must use the socket
connection:

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
4. Clone the app into each env dir and create its `config.php` (see above):
   ```bash
   git clone <hypebun-bio repo> /opt/hypebun/prod
   # edit /opt/hypebun/prod/config.php
   ```
5. Deploy the stack via the Ansible `system/containers` role (`hypebun-web` is
   registered in `docker_stacks`), or `docker compose up -d --build` locally.

## Worker mode (future)

FrankenPHP worker mode keeps the app booted in long-lived processes for a big perf
win, but AltumCode Bio is **not worker-safe as-is**: it uses static singletons that
would leak state across requests, and calls `die()`/`exit()` mid-request (which would
kill a worker, not just the request). Enabling it requires app patches (replace
`die()`/`exit()` with exceptions, reset static state each loop). Until then we run
classic per-request mode — still far faster than the old php-fpm + FastCGI stack
because PHP is in-process.

## Notes

- No `version:` key (Compose V2).
- `db` (data store) is intentionally exempt from `cap_drop: [ALL]` /
  `no-new-privileges` — its entrypoint runs as root and uses `gosu`.
- `frankenphp` keeps `cap_drop: [ALL]` + `cap_add: [NET_BIND_SERVICE]` +
  `no-new-privileges:true`. If it fails to bind `:80`/`:443` (some kernels strip the
  binary's ambient file capability under `no-new-privileges`), drop only
  `no-new-privileges` for this service and keep `cap_drop: [ALL]` +
  `NET_BIND_SERVICE`.
