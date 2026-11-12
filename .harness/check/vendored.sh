#!/usr/bin/env bash
# AC-1-5: .agents/skills/VENDORED.md has a complete row per vendored skill, and
#         every skill folder is either vendored or listed under "Original skills".
# AC-1-6: THIRD_PARTY_LICENSES.md has a full MIT notice per upstream and names
#         every modified skill.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
root=${1:-$(repo_root)}
skills=$root/.agents/skills
vendored=$skills/VENDORED.md
licenses=$root/THIRD_PARTY_LICENSES.md
rc=0
bad() { err "$*"; rc=1; }
trim() { local x=$1; x=${x#"${x%%[![:space:]]*}"}; printf '%s' "${x%"${x##*[![:space:]]}"}"; }

[[ -d $skills ]] || exit 0
[[ -f $vendored ]] || die ".agents/skills/VENDORED.md: missing"

declare -A row=() source_of=()
modified=()
# Rows: | `skill` | owner/repo | path | sha | license | changes |
while IFS='|' read -r _ skill src path sha license changes _; do
  skill=$(trim "${skill//\`/}") src=$(trim "$src") path=$(trim "$path")
  sha=$(trim "$sha") license=$(trim "$license") changes=$(trim "$changes")
  row[$skill]=1 source_of[$skill]=$src
  for v in src path sha license changes; do
    [[ -n ${!v} ]] || bad "VENDORED.md: $skill: empty $v"
  done
  [[ -z $sha || $sha =~ ^[0-9a-f]{40}$ ]] || bad "VENDORED.md: $skill: commit must be a full 40-character SHA"
  [[ -z $src || $src =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || bad "VENDORED.md: $skill: source must be owner/repo"
  [[ -f $skills/$skill/SKILL.md ]] || bad "VENDORED.md: $skill: missing .agents/skills/$skill/SKILL.md"
  [[ -n $changes && $changes != unmodified ]] && modified+=("$skill")
done < <(grep -E '^\|[[:space:]]*`' "$vendored")

# Skills written for this repo are listed as "- `name`" under "## Original skills".
# shellcheck disable=SC2016 # backticks are literal
original=$(awk '/^## /{on = ($0 ~ /^## Original skills/)} on && /^- `/' "$vendored" | grep -oE '`[^`]+`' | tr -d '`' || true)
for d in "$skills"/*/; do
  s=${d%/}; s=${s##*/}
  [[ -f $d/SKILL.md ]] || continue
  [[ -n ${row[$s]:-} ]] || grep -qx -- "$s" <<<"$original" || bad "VENDORED.md: $s: no row (vendored) and not listed under Original skills"
done

# Derived files are listed as "- `path`: ..." under "## Derived files". Each must
# exist and be named in THIRD_PARTY_LICENSES.md.
# shellcheck disable=SC2016 # backticks are literal
derived=$(awk '/^## /{on = ($0 ~ /^## Derived files/)} on && /^- `/' "$vendored" | grep -oE '^- `[^`]+`' | cut -d'`' -f2 || true)
for p in $derived; do
  [[ -e $root/$p ]] || bad "VENDORED.md: derived file $p does not exist"
  grep -qF "\`$p\`" "$licenses" 2>/dev/null || bad "THIRD_PARTY_LICENSES.md: derived file $p not listed"
done

if (( ${#row[@]} )); then
  [[ -f $licenses ]] || die "THIRD_PARTY_LICENSES.md: missing"
  for src in $(printf '%s\n' "${source_of[@]}" | sort -u); do
    # The section for SRC runs from its "## SRC" heading to the next "## " heading.
    section=$(awk -v h="## $src" '/^## /{on = ($0 == h)} on' "$licenses")
    if [[ $section != *'Permission is hereby granted, free of charge'* || $section != *'THE SOFTWARE IS PROVIDED "AS IS"'* ]]; then
      bad "THIRD_PARTY_LICENSES.md: $src: no full MIT notice under a '## $src' heading"
    fi
  done
  for s in ${modified[@]+"${modified[@]}"}; do
    grep -q "\`$s\`" "$licenses" || bad "THIRD_PARTY_LICENSES.md: $s: modified but not listed"
  done
fi
exit $rc
