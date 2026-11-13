#!/usr/bin/env bash
# PostToolUse(Edit|Write|MultiEdit) hook: runs `make fmt FILE=<path>` (R7).
# Silent, and never blocks: a formatter failure is caught later by `make check`.
set -uo pipefail
root=${CLAUDE_PROJECT_DIR:-$(pwd)}
file=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["tool_input"]["file_path"])' 2>/dev/null) || exit 0
[[ -n $file ]] || exit 0
make -s -C "$root" fmt FILE="$file" >/dev/null 2>&1 || true
exit 0
