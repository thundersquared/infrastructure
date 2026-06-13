#!/usr/bin/env bash
#
# Zero-downtime deploy for a Hypebun environment (Capistrano-style).
#
# Layout on the host (HYPEBUN_BASE/<env>):
#   releases/<timestamp>/   immutable code for one deploy
#   shared/uploads/         persisted user media (Docker volume)
#   shared/cache/           ephemeral render cache (tmpfs)
#   shared/config.php       per-env app config (secrets; never in releases)
#   current -> releases/<timestamp>   atomic symlink the web server serves
#
# A release's uploads/, uploads/cache/ and config.php are symlinked into the
# shared dirs so they survive deploys. Swapping "current" is an atomic rename(2):
# in-flight requests finish on the old release, new requests hit the new one.
# Because each release lives at a new path, OPcache never serves stale files.
#
# Usage:
#   ./deploy.sh <env> <source_dir>     deploy source_dir as a new release
#   ./deploy.sh <env> --rollback       switch back to the previous release
#
# Env vars:
#   HYPEBUN_BASE   base dir on host           (default: /opt/hypebun)
#   KEEP_RELEASES  releases to retain          (default: 5)
#   COMPOSE_SERVICE  frankenphp service name   (default: hypebun-web)

set -euo pipefail

HYPEBUN_BASE="${HYPEBUN_BASE:-/opt/hypebun}"
KEEP_RELEASES="${KEEP_RELEASES:-5}"
COMPOSE_SERVICE="${COMPOSE_SERVICE:-hypebun-web}"

err() { echo "deploy: $*" >&2; exit 1; }
log() { echo "deploy: $*"; }

[ $# -ge 2 ] || err "usage: $0 <env> <source_dir|--rollback>"

ENV="$1"
case "$ENV" in
	prod|test) ;;
	*) err "env must be 'prod' or 'test' (got '$ENV')" ;;
esac

ENV_DIR="$HYPEBUN_BASE/$ENV"
RELEASES_DIR="$ENV_DIR/releases"
SHARED_DIR="$ENV_DIR/shared"
CURRENT_LINK="$ENV_DIR/current"

reload_opcache() {
	# Each release has a unique realpath, so OPcache auto-loads fresh files; this
	# is a best-effort belt-and-braces reset. Ignore failures (e.g. no CLI).
	if docker ps --format '{{.Names}}' | grep -qx "$COMPOSE_SERVICE"; then
		docker exec "$COMPOSE_SERVICE" \
			php -r 'function_exists("opcache_reset") && opcache_reset();' \
			>/dev/null 2>&1 || true
	fi
}

prune_releases() {
	local count
	count=$(find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
	if [ "$count" -gt "$KEEP_RELEASES" ]; then
		find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d | sort \
			| head -n "$((count - KEEP_RELEASES))" \
			| while read -r old; do log "pruning old release $(basename "$old")"; rm -rf "$old"; done
	fi
}

if [ "$2" = "--rollback" ]; then
	[ -L "$CURRENT_LINK" ] || err "no current release to roll back from"
	current_target=$(basename "$(readlink "$CURRENT_LINK")")
	previous=$(find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d | sort \
		| grep -v -- "$current_target" | tail -n 1 || true)
	[ -n "$previous" ] || err "no previous release to roll back to"
	ln -sfn "$previous" "$CURRENT_LINK"
	reload_opcache
	log "rolled back $ENV to $(basename "$previous")"
	exit 0
fi

SOURCE_DIR="$2"
[ -d "$SOURCE_DIR" ] || err "source dir '$SOURCE_DIR' does not exist"
[ -f "$SOURCE_DIR/index.php" ] || err "source dir has no index.php (wrong path?)"

# Ensure shared structure exists (uploads + cache are backed by Docker volumes,
# config.php is supplied out of band).
mkdir -p "$RELEASES_DIR" "$SHARED_DIR/uploads" "$SHARED_DIR/cache"
[ -f "$SHARED_DIR/config.php" ] \
	|| err "missing $SHARED_DIR/config.php (create it before first deploy; see README)"

RELEASE="$RELEASES_DIR/$(date -u +%Y%m%d%H%M%S)"
log "creating release $(basename "$RELEASE")"
mkdir -p "$RELEASE"

# Copy code (exclude state that belongs to shared/). Use rsync if available.
if command -v rsync >/dev/null 2>&1; then
	rsync -a --delete \
		--exclude '/uploads' --exclude '/config.php' --exclude '/.git' \
		"$SOURCE_DIR"/ "$RELEASE"/
else
	cp -a "$SOURCE_DIR"/. "$RELEASE"/
	rm -rf "$RELEASE/uploads" "$RELEASE/config.php" "$RELEASE/.git"
fi

# Wire shared state into the release: config.php and uploads/ are symlinks into
# shared/, so they persist across deploys. uploads/cache points at the tmpfs.
ln -sfn "$SHARED_DIR/config.php" "$RELEASE/config.php"
ln -sfn "$SHARED_DIR/uploads"    "$RELEASE/uploads"
ln -sfn "$SHARED_DIR/cache"      "$SHARED_DIR/uploads/cache"

# Atomic swap.
ln -sfn "$RELEASE" "$CURRENT_LINK"
log "switched $ENV current -> $(basename "$RELEASE")"

reload_opcache
prune_releases
log "done."
