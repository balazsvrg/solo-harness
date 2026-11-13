#!/usr/bin/env bash
# AC-1-8: every SKILL.md has YAML frontmatter with non-empty name and description.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
root=${1:-$(repo_root)}
rc=0
while IFS= read -r f; do
  [[ $f == */SKILL.md || $f == SKILL.md ]] || continue
  if [[ $(head -n1 "$root/$f") != '---' ]]; then
    err "$f: missing frontmatter"; rc=1; continue
  fi
  fm=$(awk 'NR>1 && $0=="---" {exit} NR>1 {print}' "$root/$f")
  for key in name description; do
    grep -qE "^$key:[[:space:]]*[^[:space:]]" <<<"$fm" || { err "$f: missing $key"; rc=1; }
  done
done < <(list_files "$root")
exit $rc
