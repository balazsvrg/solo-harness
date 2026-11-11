#!/usr/bin/env bash
# AC-1-1: every symlink in the repo resolves to an existing target.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
root=${1:-$(repo_root)}
rc=0
while IFS= read -r f; do
  if [[ -L $root/$f && ! -e $root/$f ]]; then
    err "$f: broken symlink -> $(readlink "$root/$f")"; rc=1
  fi
done < <(list_files "$root")
exit $rc
