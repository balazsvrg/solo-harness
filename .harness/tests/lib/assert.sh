# shellcheck shell=bash
# Assertions for harness tests. Each prints a reason and returns 1 on failure.

fail() { printf '  %s\n' "$*" >&2; return 1; }

assert_eq() { [[ $1 == "$2" ]] || fail "expected '$2', got '$1'${3:+ ($3)}"; }
assert_contains() { [[ $1 == *"$2"* ]] || fail "expected output to contain '$2'; got: ${1:0:500}"; }
assert_not_contains() { [[ $1 != *"$2"* ]] || fail "expected output not to contain '$2'"; }
assert_file() { [[ -e $1 ]] || fail "missing file: $1"; }
assert_no_file() { [[ ! -e $1 ]] || fail "file should not exist: $1"; }

# assert_status CODE CMD...: run CMD, compare its exit code. Output goes to $OUT.
assert_status() {
  local want=$1 got; shift
  OUT=$("$@" 2>&1) && got=0 || got=$?
  [[ $got == "$want" ]] || fail "exit $got, want $want: $* -> ${OUT:0:800}"
}

# new_repo: make an empty git repo in a fresh temp dir and print its path.
new_repo() {
  local d
  d=$(mktemp -d "$TEST_TMP/repo.XXXXXX")
  git -C "$d" init -q
  printf '%s\n' "$d"
}

# copy_repo: copy the working tree under test (with .git) to a temp dir.
copy_repo() {
  local d
  d=$(mktemp -d "$TEST_TMP/copy.XXXXXX")
  cp -a "$HARNESS_ROOT/." "$d/"
  printf '%s\n' "$d"
}

# numstat ADDED DELETED PATH...: write NUL-terminated `git diff --numstat -z` records
# to ./changes, the input of the CI gate scripts.
numstat() {
  : > changes
  while (($#)); do printf '%s\t%s\t%s\0' "$1" "$2" "$3" >> changes; shift 3; done
}

# init_repo: make the current temp dir a repo for the CI gate scripts; their inputs stay untracked.
init_repo() { git init -q .; printf 'changes\nbody.md\n' > .git/info/exclude; }

# YAML readers for workflow files in the layout actionlint accepts (two-space indent).
# top_block FILE KEY: the lines of a top-level KEY, without the KEY line.
top_block() {
  awk -v k="$2" '$0 ~ "^"k":" {on=1; next} on && /^[^ #]/ {on=0} on' "$1"
}
# job_names FILE: one job id per line.
job_names() { top_block "$1" jobs | awk '/^  [A-Za-z0-9_-]+:/ {sub(/:.*/, ""); sub(/^ +/, ""); print}'; }
# job_block FILE JOB: the lines of one job, without the job id line.
job_block() {
  top_block "$1" jobs | awk -v j="$2" '/^  [A-Za-z0-9_-]+:/ {on = ($1 == j":"); next} on'
}

# has_agent NAME: true if the repo under test still has the config of agent NAME
# (claude, codex, copilot, antigravity). Bootstrap deletes the configs of unused
# agents, so tests of one agent's files return early without them. The bootstrap
# tests prove that the template itself has all four.
has_agent() {
  case $1 in
    claude) [[ -e $HARNESS_ROOT/.claude/settings.json ]] ;;
    codex) [[ -e $HARNESS_ROOT/.codex ]] ;;
    copilot) [[ -e $HARNESS_ROOT/.github/copilot-instructions.md ]] ;;
    antigravity) [[ -e $HARNESS_ROOT/.agents/hooks.json ]] ;;
    *) fail "unknown agent: $1" ;;
  esac
}
