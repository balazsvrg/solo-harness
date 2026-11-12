# shellcheck shell=bash
# Shared helpers for harness scripts. Source it; do not run it.

repo_root() { git rev-parse --show-toplevel 2>/dev/null || pwd; }

HARNESS_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../config
source "$HARNESS_LIB_DIR/../config"

log()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
err()  { printf 'error: %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

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

# has_label NAME: true if PR_LABELS contains NAME exactly.
has_label() { [[ ",${PR_LABELS:-}," == *",$1,"* ]]; }
