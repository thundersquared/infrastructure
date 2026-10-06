#!/usr/bin/env bash
# Check tower's Headscale config and policy templates with the exact image the
# compose file pins.
#
# Headscale refuses to start on keys its deprecation list marks as removed
# (`dns_config` in 0.23, `randomize_client_port` in 0.29) and on invalid
# values, and `docker compose up -d` still reports success when the container
# then crash-loops, so the deploy cannot catch it. Running the pinned image
# against the rendered templates here can. On a Renovate image bump, this is what
# fails when the new release removed a key the config still uses. Other
# renamed or dropped keys are ignored without a warning (old configs' unread
# `ip_prefixes` left no prefix configured, which only failed indirectly), so
# the upgrade checklist's config-example.yaml diff is still needed.
#
# The repo is public, so the server's hostname is not in the config: on tower
# it arrives through the stack's .env (HEADSCALE_SERVER_URL and
# HEADSCALE_TLS_LETSENCRYPT_HOSTNAME). This check supplies a placeholder the
# same way, and fails if a hostname is committed into the file instead.
#
# The config and policy are templates in the system/headscale role. Their only
# Jinja is the `ansible_managed` header, so this renders them by dropping that
# line, and fails if any other Jinja appears (it would need a real renderer).
#
# Needs docker. The container gets no network and a throwaway data directory.
#
# Usage: ci/headscale-check.sh [ROOT]

set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

stack=tower/containers/headscale
image=$(awk '$1 == "image:" { print $2; exit }' "$stack/docker-compose.yml")
if [ -z "$image" ]; then
  echo "no image: line in $stack/docker-compose.yml" >&2
  exit 1
fi

templates=tower/ansible/roles/system/headscale/templates
rendered=$(mktemp -d)
trap 'rm -rf -- "$rendered"' EXIT
for f in config.yaml policy.hujson; do
  grep -vE '^\{\{ ansible_managed \| comment(\(.*\))? \}\}$' "$templates/$f.j2" > "$rendered/$f"
  if grep -nE '\{\{|\{%|\{#' "$rendered/$f"; then
    echo "$templates/$f.j2 has Jinja beyond the ansible_managed header; render it properly here first" >&2
    exit 1
  fi
done
chmod 0755 "$rendered"
chmod 0644 "$rendered"/*

config="$rendered/config.yaml"
if grep -nE '^[[:space:]]*(server_url|tls_letsencrypt_hostname)[[:space:]]*:' "$config"; then
  echo "$templates/config.yaml.j2 sets the hostname; it must come from the stack's .env (see the file header)" >&2
  exit 1
fi

placeholder=headscale.example.com

# Extra `-e KEY=VALUE` pairs may come first; the rest is headscale's argv.
headscale() {
  local env=()
  while [ "${1:-}" = -e ]; do
    env+=("$1" "$2")
    shift 2
  done
  docker run --rm --network none --read-only \
    --tmpfs /var/run/headscale \
    --tmpfs /var/lib/headscale \
    -e HEADSCALE_SERVER_URL="https://$placeholder" \
    -e HEADSCALE_TLS_LETSENCRYPT_HOSTNAME="$placeholder" \
    "${env[@]}" \
    -v "$rendered:/etc/headscale:ro" \
    "$image" "$@"
}

echo "=== headscale configtest ($image)"
headscale configtest

# MagicDNS and the ACME email are also switched on through .env when their
# secrets are set (tower/ansible/roles/system/headscale). Check that shape
# too, with placeholders.
echo "=== headscale configtest, MagicDNS + ACME email via env"
headscale \
  -e HEADSCALE_ACME_EMAIL=ops@example.com \
  -e HEADSCALE_DNS_MAGIC_DNS=true \
  -e HEADSCALE_DNS_BASE_DOMAIN=tailnet.internal \
  configtest

# The bypass flag opens a fresh SQLite database in the tmpfs instead of
# dialling a running server; --force answers its "is headscale running?"
# prompt.
echo "=== headscale policy check"
headscale policy check --bypass-grpc-and-access-database-directly --force \
  -f /etc/headscale/policy.hujson
