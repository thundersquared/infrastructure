#!/usr/bin/env bash
# Fail unless n8n and its external task runners are pinned to the same
# version. The runners must run n8n's own version. Renovate updates only the
# n8n image, and .github/workflows/n8n-sync-runners.yml then pins the runners
# to match, so this check fails a pull request until that has happened.
#
# It also fails unless the n8n sandbox service API, runner and sandbox images
# are on the same release: they are only supported together, and Renovate can
# open (and automerge) a group PR before all three have been published.
#
# Usage: ci/n8n-versions-check.sh [COMPOSE_FILE...]

set -euo pipefail

if [ "$#" -eq 0 ]; then
  set -- web3/containers/n8n/docker-compose.yml
fi

# tag FILE IMAGE: the tags of IMAGE pinned in FILE, without the digest, one
# per distinct tag. The sandbox image is set through an environment variable.
tag() {
  sed -nE "s#^[[:space:]]*(image|SANDBOX_RUNNER_DOCKER_SANDBOX_IMAGE):[[:space:]]*$2:([^@[:space:]]+).*#\2#p" "$1" | sort -u
}

status=0
for compose in "$@"; do
  n8n=$(tag "$compose" 'ghcr\.io/thundersquared/n8n')
  runners=$(tag "$compose" 'n8nio/runners')
  if [ -z "$n8n" ] || [ -z "$runners" ]; then
    echo "$compose: could not find both the n8n and the n8nio/runners image" >&2
    status=1
  elif [ "$n8n" != "$runners" ]; then
    echo "$compose: n8n is $n8n but its task runners are $runners; run ci/n8n-sync-runners.sh" >&2
    status=1
  else
    echo "$compose: n8n and task runners both at $n8n"
  fi

  api=$(tag "$compose" 'ghcr\.io/n8n-io/n8n-sandbox-service-api')
  runner=$(tag "$compose" 'ghcr\.io/n8n-io/n8n-sandbox-service-runner-dind')
  sandbox=$(tag "$compose" 'ghcr\.io/n8n-io/n8n-sandbox-service-sandbox')
  if [ -z "$api" ] || [ -z "$runner" ] || [ -z "$sandbox" ]; then
    echo "$compose: could not find the sandbox service API, runner and sandbox images" >&2
    status=1
  elif [ "$api" != "$runner" ] || [ "$api" != "$sandbox" ]; then
    echo "$compose: sandbox service images differ: API ${api//$'\n'/ and }, runner $runner, sandbox $sandbox" >&2
    status=1
  else
    echo "$compose: sandbox service API, runner and sandbox all at $api"
  fi
done
exit "$status"
