#!/usr/bin/env bash
# AC-1-2, AC-1-3, AC-1-4, AC-1-41: AGENTS.md length and content; no agent config pins a model.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
root=${1:-$(repo_root)}
f=$root/AGENTS.md
rc=0
bad() { err "$*"; rc=1; }

[[ -f $f ]] || die "AGENTS.md: missing"

lines=$(wc -l < "$f")
(( lines <= AGENTS_MD_MAX_LINES )) || bad "AGENTS.md: $lines lines, limit is $AGENTS_MD_MAX_LINES"

for needle in 'make check' 'S/M/L' '.agents/skills' 'strongest model' 'once at the end of every ticket' 'Never skip it' 'unless the owner asks'; do
  grep -qF -- "$needle" "$f" || bad "AGENTS.md: must mention '$needle'"
done

# No ALL-CAPS emphasis. Inline code and *.md names are ignored; acronyms are allowed.
allowed=' AGENTS CLAUDE README CHANGELOG GLOSSARY LICENSE ADR MIT API CLI CI PR PRS STE ASD TDD JSON YAML TOML URL SHA AC OS UI MCP HTTP ASCII '
# shellcheck disable=SC2016 # backticks are literal
caps=$(sed -E 's/`[^`]*`//g; s/[A-Z_]+\.md//g' "$f" | grep -oE '\b[A-Z]{2,}\b' | sort -u || true)
for w in $caps; do
  [[ $allowed == *" $w "* ]] || bad "AGENTS.md: ALL-CAPS emphasis '$w'"
done

# No agent config pins a model.
shopt -s nullglob
for c in "$root"/.claude/settings*.json; do
  [[ -f $c ]] || continue
  grep -qE '"model"[[:space:]]*:' "$c" && bad "${c#"$root"/}: pins a model"
done
for c in "$root"/.codex/*.toml; do
  grep -qE '^[[:space:]]*model[[:space:]]*=' "$c" && bad "${c#"$root"/}: pins a model"
done
for c in "$root"/.claude/agents/*.md "$root"/.github/agents/*.md; do
  awk 'NR==1 && $0!="---" {exit 1} NR>1 && $0=="---" {exit 1} /^model:/ && $2!="inherit" {found=1; exit 0} END {exit !found}' "$c" \
    && bad "${c#"$root"/}: pins a model"
done
exit $rc
