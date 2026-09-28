#!/usr/bin/env bash
# Run every check that .github/workflows/validate.yml runs, locally.
#
# CI is the source of truth for what gates a PR; this script exists so the same
# failures show up before pushing rather than after. Keep the two in sync.
#
# Requirements:
#   ansible-lint, yamllint, zizmor   (pip, or via the repo venv)
#   opentofu >= 1.12                 (tofu)
#
# Usage: ci/validate.sh [ROOT]

set -uo pipefail

ROOT="${1:-.}"
cd "$ROOT" || exit 2

status=0
run() {
  local label="$1"
  shift
  printf '\n=== %s ===\n' "$label"
  if "$@"; then
    printf 'PASS: %s\n' "$label"
  else
    printf 'FAIL: %s\n' "$label"
    status=1
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# 1. YAML style and correctness.
if have yamllint; then
  run "yamllint" yamllint --strict --config-file .yamllint .
else
  printf '\nSKIP: yamllint (not installed)\n'
  status=1
fi

# 2. Ansible correctness: syntax-check, FQCN, idempotency, risky permissions.
if have ansible-lint; then
  run "ansible-lint" ansible-lint --offline
else
  printf '\nSKIP: ansible-lint (not installed)\n'
  status=1
fi

# 3. OpenTofu for the tower host. -backend=false means no OCI credentials and
#    no state access are needed, matching CI.
if have tofu; then
  run "tofu validate" env -C tower/terraform tofu init -backend=false -input=false -no-color
  run "tofu fmt" tofu -chdir=tower/terraform fmt -check -recursive
else
  printf '\nSKIP: tofu (not installed)\n'
  status=1
fi

# 4. Audit this workflow for Actions-level privilege footguns.
if have zizmor; then
  run "zizmor" zizmor --persona=pedantic --min-severity=low .github/workflows/validate.yml
else
  printf '\nSKIP: zizmor (not installed)\n'
  status=1
fi

printf '\n'
if [ "$status" -eq 0 ]; then
  echo "all checks passed"
else
  echo "one or more checks failed"
fi
exit "$status"
