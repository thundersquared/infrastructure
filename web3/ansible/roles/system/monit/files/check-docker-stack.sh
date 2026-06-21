#!/bin/sh
# Monit program check: verify all containers in a Docker Compose stack are running.
# Managed by Ansible (system/monit role).
#
# Usage: check-docker-stack.sh <stack-directory>
# Exit 0 = all stack containers running (or no containers expected yet).
# Exit 1 = one or more containers are stopped/exited/dead/paused.
#
# Monit runs this at each cycle. A non-zero exit for N consecutive cycles
# triggers the configured alert and exec action.

set -eu

STACK_DIR="${1:-}"
if [ -z "$STACK_DIR" ]; then
  echo "usage: check-docker-stack.sh <stack-directory>" >&2
  exit 2
fi

if [ ! -d "$STACK_DIR" ]; then
  echo "stack directory not found: $STACK_DIR" >&2
  exit 2
fi

cd "$STACK_DIR"

if [ ! -f "docker-compose.yml" ] && [ ! -f "docker-compose.yaml" ] && [ ! -f "compose.yml" ]; then
  echo "no compose file in: $STACK_DIR" >&2
  exit 2
fi

# Containers in a non-running state (exited, dead, paused, restarting).
STOPPED=$(/usr/bin/docker compose ps \
  --format '{{.Name}}' \
  --status exited \
  --status dead \
  --status paused \
  --status restarting \
  2>/dev/null || true)

if [ -n "$STOPPED" ]; then
  # Print stopped container names for monit's program output / alerts.
  echo "stopped containers in $STACK_DIR: $STOPPED"
  exit 1
fi

# Also verify at least one container is running (catches the case where the
# stack was never started at all, which would show zero exited containers).
RUNNING=$(/usr/bin/docker compose ps \
  --format '{{.Name}}' \
  --status running \
  2>/dev/null || true)

TOTAL=$(/usr/bin/docker compose ps \
  --format '{{.Name}}' \
  --all \
  2>/dev/null | wc -l || echo 0)

TOTAL=$(echo "$TOTAL" | tr -d '[:space:]')

if [ "$TOTAL" -gt 0 ] && [ -z "$RUNNING" ]; then
  echo "no running containers in $STACK_DIR (total expected: $TOTAL)"
  exit 1
fi

exit 0
