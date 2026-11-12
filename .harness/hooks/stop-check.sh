#!/usr/bin/env bash
# Stop hook: runs `make check` when the working tree has changes (R7).
# Clean tree: exits 0 and does nothing. Red check: prints the last 40 lines on
# stderr and exits 2, so the agent cannot stop. Silent on success.
set -uo pipefail
root=${CLAUDE_PROJECT_DIR:-$(pwd)}
active=$(python3 -c 'import json,sys; print(bool(json.load(sys.stdin).get("stop_hook_active")))' 2>/dev/null || echo False)
# A second stop after a block must not loop forever.
[[ $active == True ]] && exit 0
[[ -n $(git -C "$root" status --porcelain 2>/dev/null) ]] || exit 0
if ! out=$(make -s -C "$root" check 2>&1); then
  { printf 'make check failed. Fix it before you stop. Last lines:\n'; tail -n 39 <<<"$out"; } >&2
  exit 2
fi
exit 0
