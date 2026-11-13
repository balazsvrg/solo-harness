#!/usr/bin/env bash
# Lint: shellcheck on every shell script, actionlint on workflows. Uses the pinned tools in .harness/bin.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
root=${1:-$(repo_root)}
cd "$root"
scripts=()
while IFS= read -r f; do
  [[ -f $f && ! -L $f ]] || continue
  if [[ $f == *.sh ]] || head -n1 "$f" | grep -qE '^#!.*\b(ba)?sh\b'; then scripts+=("$f"); fi
done < <(list_files .)
rc=0
if (( ${#scripts[@]} )); then
  shellcheck -x -P SCRIPTDIR "${scripts[@]}" || rc=1
fi
shopt -s nullglob
workflows=(.github/workflows/*.yml .github/workflows/*.yaml)
if (( ${#workflows[@]} )); then
  actionlint "${workflows[@]}" || rc=1
fi
exit $rc
