# shellcheck shell=bash
# Shared helpers for harness scripts. Source it; do not run it.

repo_root() { git rev-parse --show-toplevel 2>/dev/null || pwd; }

HARNESS_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../config
source "$HARNESS_LIB_DIR/../config"

log()  { printf '%s\n' "$*"; }
err()  { printf 'error: %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

# trim TEXT: print TEXT without leading and trailing whitespace.
trim() { local x=$1; x=${x#"${x%%[![:space:]]*}"}; printf '%s' "${x%"${x##*[![:space:]]}"}"; }

# vendored_rows FILE: print one line per skill row of a VENDORED.md table, as
# "skill|source|path|commit|license|changes" with each field trimmed.
vendored_rows() {
  local _ skill src path sha license changes
  while IFS='|' read -r _ skill src path sha license changes _; do
    printf '%s|%s|%s|%s|%s|%s\n' "$(trim "${skill//\`/}")" "$(trim "$src")" "$(trim "$path")" \
      "$(trim "$sha")" "$(trim "$license")" "$(trim "$changes")"
  done < <(grep -E '^\|[[:space:]]*`' "$1")
}

# run CMD...: execute, or only print it when DRY_RUN=1.
run() {
  if [[ ${DRY_RUN:-0} == 1 ]]; then
    printf 'dry-run: %s\n' "$*"
  else
    "$@"
  fi
}

# glob_to_regex GLOB: '**/' matches zero or more dirs, '**' anything,
# '*' and '?' never cross '/'.
glob_to_regex() {
  local g=$1 out='' c i
  for ((i = 0; i < ${#g}; i++)); do
    c=${g:i:1}
    if [[ $c == '*' && ${g:i+1:1} == '*' ]]; then
      if [[ ${g:i+2:1} == '/' ]]; then out+='(.*/)?'; ((i += 2)); else out+='.*'; ((i += 1)); fi
    elif [[ $c == '*' ]]; then out+='[^/]*'
    elif [[ $c == '?' ]]; then out+='[^/]'
    else
      case $c in
        [].+^\$\(\)\{\}\|\[\\]) out+="\\$c" ;;
        *) out+=$c ;;
      esac
    fi
  done
  printf '^%s$' "$out"
}

# glob_match PATH GLOB...: true if PATH matches any GLOB.
glob_match() {
  local path=$1 g re; shift
  for g in "$@"; do
    re=$(glob_to_regex "$g")
    [[ $path =~ $re ]] && return 0
  done
  return 1
}

# list_files [ROOT]: tracked and untracked, non-ignored files that exist.
list_files() {
  local root=${1:-.} f
  git -C "$root" ls-files -co --exclude-standard | sort -u | while IFS= read -r f; do
    [[ -e $root/$f || -L $root/$f ]] && printf '%s\n' "$f"
  done
}

is_test_path() { glob_match "$1" "${TEST_GLOBS[@]}"; }

is_harness_path() {
  local p=$1 d
  for d in "${HARNESS_DIRS[@]}"; do
    [[ $p == "$d"/* ]] && return 0
  done
  [[ $p != */* ]] && glob_match "$p" "${HARNESS_ROOT_FILES[@]}"
}

# is_app_source PATH: outside the harness, or a test file outside .harness/.
is_app_source() {
  local p=$1
  is_harness_path "$p" || return 0
  [[ $p != .harness/* ]] && is_test_path "$p"
}

# --- CI gate input (.harness/ci/*.sh) ---------------------------------------
# A changes file is `git diff --numstat -z --no-renames` output: one record
# ADDED<TAB>DELETED<TAB>PATH<NUL> per file. -z keeps paths unquoted. Binary files
# show "-" for both counts. Labels come from PR_LABELS (comma-separated).

# load_changes FILE: fill CHANGE_PATHS and CHANGE_LINES (added + deleted, 0 for
# binary files). Exit 2 with a usage message unless FILE is readable.
load_changes() {
  [[ -n ${1:-} && -r $1 ]] || { err "usage: ${0##*/} CHANGES_FILE (git diff --numstat -z --no-renames output)"; exit 2; }
  CHANGE_PATHS=() CHANGE_LINES=()
  local added deleted path
  while IFS=$'\t' read -r -d '' added deleted path; do
    CHANGE_PATHS+=("$path")
    if [[ $added == - ]]; then CHANGE_LINES+=(0); else CHANGE_LINES+=($((added + deleted))); fi
  done < "$1"
}

# counted_lines GLOB...: print the CHANGE_LINES total, without files that match a GLOB.
counted_lines() {
  local i total=0
  for i in "${!CHANGE_PATHS[@]}"; do
    glob_match "${CHANGE_PATHS[i]}" "$@" || total=$((total + CHANGE_LINES[i]))
  done
  printf '%s' "$total"
}

# has_label NAME: true if PR_LABELS contains NAME exactly.
has_label() { [[ ",${PR_LABELS:-}," == *",$1,"* ]]; }

# dependabot_pin_only: true if the PR is a Dependabot update of action pins only:
# PR_AUTHOR is dependabot[bot], every changed file is in .github/workflows/, and the
# `git diff -U0 --no-renames` file PR_DIFF changes only uses: lines. In each hunk the
# n-th removed line and the n-th added line must be the same up to the "@" (indent,
# step marker and action), and the added ref must be a full commit SHA. Any other
# diff, or no PR_DIFF, is false: the full gate runs. Needs load_changes first.
dependabot_pin_only() {
  [[ ${PR_AUTHOR:-} == 'dependabot[bot]' && -n ${PR_DIFF:-} && -r $PR_DIFF ]] || return 1
  ((${#CHANGE_PATHS[@]})) || return 1
  local p line in_hunk=0 pins=0 old=() new=()
  for p in "${CHANGE_PATHS[@]}"; do [[ $p == .github/workflows/* ]] || return 1; done
  while IFS= read -r line; do
    case $line in
      'diff --git '* | '@@ '*)
        pin_hunk_ok || return 1
        if [[ $line == '@@ '* ]]; then in_hunk=1; else in_hunk=0; fi
        ;;
      *)
        if ((!in_hunk)); then
          # File headers only: a new, deleted or renamed file is not a pin update.
          [[ $line == 'index '* || $line == '--- a/'* || $line == '+++ b/'* ]] || return 1
        elif [[ $line == -* ]]; then old+=("${line:1}")
        elif [[ $line == +* ]]; then new+=("${line:1}"); pins=$((pins + 1))
        fi
        ;;
    esac
  done < "$PR_DIFF"
  pin_hunk_ok && ((pins))
}

# pin_hunk_ok: true if the hunk in `old` and `new` (from dependabot_pin_only) changes
# only the ref of each uses: line, to a full commit SHA. Empties both lists.
pin_hunk_ok() {
  local i re='^([[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*[^@[:space:]]+)@([^[:space:]]+)([[:space:]]+#.*)?$' head
  ((${#old[@]} == ${#new[@]})) || return 1
  for i in "${!old[@]}"; do
    [[ ${old[i]} =~ $re ]] || return 1
    head=${BASH_REMATCH[1]}
    [[ ${new[i]} =~ $re && ${BASH_REMATCH[1]} == "$head" && ${BASH_REMATCH[3]} =~ ^[0-9a-f]{40}$ ]] || return 1
  done
  old=() new=()
}
