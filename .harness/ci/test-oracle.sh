#!/usr/bin/env bash
# test-oracle gate (R12): a PR that changes the oracle (tests, snapshots, workflows,
# CI config, gate settings, pinned tools) must also change specs/, so the reason is on record.
# Usage: [PR_AUTHOR=login PR_DIFF=file] test-oracle.sh CHANGES_FILE
# A Dependabot PR that changes only uses: pins passes (dependabot_pin_only in common.sh).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_changes "${1:-}"

if dependabot_pin_only; then
  log 'test-oracle: Dependabot PR that changes only uses: pins; no specs/ change needed'
  exit 0
fi

guarded=() specs=0
for path in "${CHANGE_PATHS[@]}"; do
  [[ $path == specs/* ]] && specs=1
  if is_test_path "$path" || glob_match "$path" "${ORACLE_GLOBS[@]}"; then guarded+=("$path"); fi
done

if ((${#guarded[@]} == 0)); then
  log 'test-oracle: no tests or CI config changed'
elif ((specs)); then
  log "test-oracle: ${#guarded[@]} guarded file(s) changed; specs/ changed too"
else
  err 'test-oracle: these files change what counts as correct, but no file under specs/ changed:'
  printf '  %s\n' "${guarded[@]}" >&2
  err 'Update the spec or change folder that explains why.'
  exit 1
fi
