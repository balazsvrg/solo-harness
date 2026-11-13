#!/usr/bin/env bash
# Hook adapter for Codex, Copilot and Antigravity (R6, R7). See adapter.py.
# Usage: adapter.sh AGENT EVENT < hook-input.json
set -uo pipefail
exec python3 "$(dirname "$0")/adapter.py" "$@"
