#!/usr/bin/env bash
# Change-folder structure lint: specs/changes/<id>-<slug>/ and
# specs/changes/archive/YYYY-MM-DD-<id>-<slug>/ hold proposal.md and tasks.md,
# plus design.md when the proposal says Size L.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
root=${1:-$(repo_root)}
rc=0
check_dir() {
  local d=$1 name=${1##*/} pattern=$2
  if [[ ! $name =~ $pattern ]]; then err "${d#"$root"/}: name must match $pattern"; rc=1; return; fi
  for need in proposal.md tasks.md; do
    [[ -f $d/$need ]] || { err "${d#"$root"/}: missing $need"; rc=1; }
  done
  if [[ -f $d/proposal.md ]] && grep -qE '^- \*\*Size:\*\* L\b' "$d/proposal.md" && [[ ! -f $d/design.md ]]; then
    err "${d#"$root"/}: Size L needs design.md"; rc=1
  fi
}
shopt -s nullglob
for d in "$root"/specs/changes/*/; do
  d=${d%/}
  [[ ${d##*/} == archive ]] && continue
  check_dir "$d" '^[0-9]+-[a-z0-9-]+$'
done
for d in "$root"/specs/changes/archive/*/; do
  check_dir "${d%/}" '^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]+-[a-z0-9-]+$'
done
exit $rc
