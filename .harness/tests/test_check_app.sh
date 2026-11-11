# shellcheck shell=bash
# Tests for make check and the check-app placeholder (R10).

test_check_passes_without_app_source() {
  # AC-1-15
  local r; r=$(copy_repo)
  assert_status 0 env HARNESS_NESTED=1 make -s -C "$r" check
  assert_contains "$OUT" 'no app checks configured'
}

test_check_fails_with_app_source() {
  # AC-1-16
  local r; r=$(copy_repo)
  mkdir -p "$r/src" && echo 'print(1)' > "$r/src/main.py"
  assert_status 2 env HARNESS_NESTED=1 make -s -C "$r" check
  assert_contains "$OUT" 'no app checks configured'
  assert_contains "$OUT" 'src/main.py'
  rm -r "$r/src"
  mkdir -p "$r/tests" && echo 'def test(): pass' > "$r/tests/test_api.py"
  assert_status 2 env HARNESS_NESTED=1 make -s -C "$r" check-app
  assert_contains "$OUT" 'tests/test_api.py'
}

test_check_app_placeholder_marker() {
  # AC-1-16: the marker is how bootstrap and check-app detect the placeholder.
  grep -q '^# solo-harness:check-app-placeholder$' "$HARNESS_ROOT/Makefile" || fail 'marker missing'
}
