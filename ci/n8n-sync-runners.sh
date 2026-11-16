#!/usr/bin/env bash
# Pin n8nio/runners to the version of the n8n image, with the digest Docker Hub
# serves for that tag. Renovate updates only the n8n image; this is run on its
# branch by .github/workflows/n8n-sync-runners.yml, and by hand after editing
# the n8n tag. Fails without changing anything when the runners tag does not
# exist yet.
#
# Usage: ci/n8n-sync-runners.sh [COMPOSE_FILE]

set -euo pipefail

compose="${1:-web3/containers/n8n/docker-compose.yml}"

version=$(sed -nE 's#^[[:space:]]*image:[[:space:]]*ghcr\.io/thundersquared/n8n:([^@[:space:]]+).*#\1#p' "$compose")
if [ -z "$version" ]; then
  echo "$compose: no ghcr.io/thundersquared/n8n image found" >&2
  exit 1
fi

token=$(curl -fsS "https://auth.docker.io/token?service=registry.docker.io&scope=repository:n8nio/runners:pull" | jq -r .token)
headers=$(curl -fsSI \
  -H "Authorization: Bearer $token" \
  -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
  "https://registry-1.docker.io/v2/n8nio/runners/manifests/$version") || headers=
digest=$(printf '%s\n' "$headers" | tr -d '\r' |
  sed -nE 's#^docker-content-digest:[[:space:]]*(sha256:[0-9a-f]{64})$#\1#Ip')
if [ -z "$digest" ]; then
  echo "n8nio/runners:$version not found on Docker Hub" >&2
  exit 1
fi

sed -i -E "s#^([[:space:]]*image:[[:space:]]*n8nio/runners:)[^[:space:]]+#\1$version@$digest#" "$compose"
echo "n8nio/runners pinned to $version@$digest"
