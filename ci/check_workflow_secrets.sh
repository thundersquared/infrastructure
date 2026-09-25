#!/usr/bin/env bash
# Assert that the pull_request validation workflow holds no credentials.
#
# Secret availability on pull_request runs is a property of the platform, not
# of this repository. The property asserted here is self-contained instead: the
# validation workflow declares no credentials at all, so its behaviour does not
# depend on who opened the pull request.
#
# This script enforces that by construction, so a later edit that adds a
# credential reference fails CI rather than passing unnoticed.
#
# Usage: ci/check_workflow_secrets.sh <workflow.yml> [more.yml ...]

set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <workflow.yml> [...]" >&2
  exit 2
fi

status=0

for workflow in "$@"; do
  if [ ! -f "$workflow" ]; then
    echo "$workflow: not found" >&2
    status=1
    continue
  fi

  # Strip comments before scanning. This file documents the forbidden patterns
  # in prose; matching the documentation would make the check unpassable.
  stripped=$(sed -E 's/[[:space:]]*#.*$//' "$workflow")

  findings=0

  # 1. No secrets context. GITHUB_TOKEN is the sole exception: it is
  #    automatically scoped read-only for PRs and is not a repository secret.
  if printf '%s\n' "$stripped" | grep -nE '\$\{\{[[:space:]]*secrets\.' >/dev/null; then
    echo "$workflow: references the secrets context. A pull_request validation" >&2
    echo "  workflow should declare no credentials — see the header comment in" >&2
    echo "  .github/workflows/validate.yml for where that belongs." >&2
    findings=$((findings + 1))
  fi

  # 2. No environment: key. Environments gate access to environment-scoped
  #    secrets, so naming one is an implicit secret grant.
  if printf '%s\n' "$stripped" | grep -nE '^[[:space:]]*environment:[[:space:]]*[^[:space:]]' >/dev/null; then
    echo "$workflow: sets an 'environment:' — environments can gate secret access" >&2
    findings=$((findings + 1))
  fi

  # 3. Triggers that run with elevated privileges on someone else's behalf are
  #    out of scope for a static-check workflow. Matched as a bare word so both
  #    the nested and the compact inline spelling are caught.
  if printf '%s\n' "$stripped" | grep -qw 'pull_request_target'; then
    echo "$workflow: uses pull_request_target, which runs with base-repo" >&2
    echo "  credentials and a write-scoped token" >&2
    findings=$((findings + 1))
  fi

  # 4. Likewise for a workflow chained off another workflow's run, which
  #    executes with full repository secrets. Flag it for review.
  if printf '%s\n' "$stripped" | grep -qw 'workflow_run'; then
    echo "$workflow: uses workflow_run, which executes with repository secrets" >&2
    findings=$((findings + 1))
  fi

  # 5. Write scopes would let PR code push to the repo or read actions/cache
  #    with write access. contents: read is the only permission allowed.
  if printf '%s\n' "$stripped" | grep -nE '^[[:space:]]*(contents|actions|packages|id-token|deployments):[[:space:]]*write' >/dev/null; then
    echo "$workflow: grants a write permission — pull_request workflows must be" >&2
    echo "  read-only" >&2
    findings=$((findings + 1))
  fi

  # 6. checkout must not persist the token into .git/config, where any later
  #    step (including repo-controlled code) could read it off disk.
  if printf '%s\n' "$stripped" | grep -q 'actions/checkout' \
     && ! printf '%s\n' "$stripped" | grep -q 'persist-credentials:[[:space:]]*false'; then
    echo "$workflow: uses actions/checkout without 'persist-credentials: false'," >&2
    echo "  leaving GITHUB_TOKEN in .git/config for later steps to read" >&2
    findings=$((findings + 1))
  fi

  if [ "$findings" -eq 0 ]; then
    echo "$workflow: OK — no secret access path"
  else
    status=1
  fi
done

exit "$status"
