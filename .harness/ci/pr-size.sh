#!/usr/bin/env bash
# pr-size gate (R12): fail when a PR changes more than PR_SIZE_MAX_LINES lines.
# Files in SIZE_EXCLUDE_GLOBS do not count. Label size-exception lets the PR pass.
# Usage: PR_LABELS=a,b pr-size.sh CHANGES_FILE
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
load_changes "${1:-}"

total=$(counted_lines "${SIZE_EXCLUDE_GLOBS[@]}")

if ((total <= PR_SIZE_MAX_LINES)); then
  log "pr-size: $total changed lines (limit $PR_SIZE_MAX_LINES)"
elif has_label size-exception; then
  log "pr-size: $total changed lines, over the limit of $PR_SIZE_MAX_LINES; passing because of label size-exception"
else
  err "pr-size: $total changed lines, over the limit of $PR_SIZE_MAX_LINES. Split the PR, or add the label size-exception."
  exit 1
fi
