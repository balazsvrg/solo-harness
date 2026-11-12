# shellcheck shell=bash
# Tests for .harness/hooks/stop-check.sh (R7).

# stop_repo RECIPE: a committed repo whose `make check` runs RECIPE and leaves a marker.
stop_repo() {
  local r; r=$(new_repo)
  printf 'check:\n\t@touch ran.marker\n\t@%s\n' "$1" > "$r/Makefile"
  printf 'ran.marker\n' > "$r/.gitignore"
  git -C "$r" add -A
  git -C "$r" -c user.name=t -c user.email=t@t commit -qm init
  printf '%s\n' "$r"
}
stop() { echo "${2:-"{}"}" | CLAUDE_PROJECT_DIR=$1 "$HARNESS_ROOT/.harness/hooks/stop-check.sh"; }

test_stop_hook_clean_tree_noop() {
  # AC-1-13
  local r; r=$(stop_repo 'exit 1')
  assert_status 0 stop "$r"
  assert_eq "$OUT" '' 'silent'
  assert_no_file "$r/ran.marker"
}

test_stop_hook_blocks_on_failing_check() {
  # AC-1-14
  local r
  # shellcheck disable=SC2016 # make expands $$ in the recipe
  r=$(stop_repo 'for i in $$(seq 100); do echo line$$i; done; exit 1')
  echo dirty > "$r/new.txt"
  assert_status 2 stop "$r"
  assert_file "$r/ran.marker"
  (( $(wc -l <<<"$OUT") <= 40 )) || fail "printed $(wc -l <<<"$OUT") lines, limit is 40"
  assert_contains "$OUT" line100
}

test_stop_hook_passes_and_avoids_loops() {
  # AC-1-13 (dirty tree, green check is silent; stop_hook_active never re-runs)
  local r; r=$(stop_repo 'true')
  echo dirty > "$r/new.txt"
  assert_status 0 stop "$r"
  assert_eq "$OUT" '' 'silent on green check'
  r=$(stop_repo 'exit 1')
  echo dirty > "$r/new.txt"
  assert_status 0 stop "$r" '{"stop_hook_active": true}'
  assert_no_file "$r/ran.marker"
}
