# shellcheck shell=bash
# Tests for the CI gate scripts in .harness/ci/ (R12). Each script reads a
# `git diff --numstat -z` file and the PR labels from PR_LABELS (comma-separated).
# The inputs are small, so each test writes its own with numstat (lib/assert.sh).

pr_size() { "$HARNESS_ROOT/.harness/ci/pr-size.sh" "$@"; }

test_pr_size_passes_at_limit() {
  # R12 pr-size: 400 changed lines is the limit, not over it.
  numstat 300 50 src/a.py 40 10 README.md
  assert_status 0 pr_size changes
}

test_pr_size_fails_over_limit() {
  # R12 pr-size: 401 changed lines fails and names the count.
  numstat 300 51 src/a.py 40 10 README.md
  assert_status 1 pr_size changes
  assert_contains "$OUT" '401'
  assert_contains "$OUT" 'size-exception'
}

test_pr_size_skips_lockfiles_and_archive() {
  # R12 pr-size: lockfiles and specs/changes/archive/ do not count.
  numstat 10 0 src/a.py 5000 0 package-lock.json 900 0 web/yarn.lock \
    700 0 specs/changes/archive/2026-01-01-1-x/proposal.md
  assert_status 0 pr_size changes
}

test_pr_size_counts_binary_as_zero() {
  # R12 pr-size: binary files (numstat "-") add no lines.
  numstat - - img/logo.png 10 0 src/a.py
  assert_status 0 pr_size changes
}

test_pr_size_exception_label_passes() {
  # R12 pr-size: label size-exception lets a large PR pass.
  numstat 1000 0 src/a.py
  PR_LABELS='bug,size-exception' assert_status 0 pr_size changes
  assert_contains "$OUT" 'size-exception'
  PR_LABELS='bug,size-exceptional' assert_status 1 pr_size changes
}

test_pr_size_missing_input_fails() {
  # R12 pr-size: no changes file is a usage error, not a pass.
  assert_status 2 pr_size
  assert_status 2 pr_size does-not-exist
}

oracle() { "$HARNESS_ROOT/.harness/ci/test-oracle.sh" "$@"; }

test_oracle_passes_without_guarded_files() {
  # R12 test-oracle: app and doc changes alone pass.
  numstat 10 0 src/a.py 3 1 README.md
  assert_status 0 oracle changes
}

test_oracle_fails_on_guarded_change_without_specs() {
  # R12 test-oracle: tests, snapshots, workflows, CI config and tools.lock need a specs/ change.
  local p
  for p in tests/test_api.py src/a.test.ts .harness/tests/test_x.sh web/__snapshots__/a.snap \
    src/b.snap .github/workflows/ci.yml .harness/ci/pr-size.sh .harness/tools.lock \
    .harness/config .harness/lib/common.sh; do
    numstat 10 0 src/a.py 1 1 "$p"
    assert_status 1 oracle changes
    assert_contains "$OUT" "$p"
  done
}

test_oracle_passes_when_specs_change() {
  # R12 test-oracle: the same changes pass when the PR also touches specs/.
  numstat 1 1 tests/test_api.py 1 1 .harness/tools.lock 4 0 specs/changes/7-x/tasks.md
  assert_status 0 oracle changes
}

test_oracle_reads_test_globs_from_config() {
  # R12 test-oracle: the test globs come from .harness/config, not a second copy.
  local r; r=$(new_repo)
  cp -a "$HARNESS_ROOT/.harness" "$r/"
  echo "TEST_GLOBS=('checks/**')" >> "$r/.harness/config"
  numstat 1 0 checks/x.py
  assert_status 1 "$r/.harness/ci/test-oracle.sh" changes
  numstat 1 0 tests/test_api.py
  assert_status 0 "$r/.harness/ci/test-oracle.sh" changes
}

test_gates_read_unusual_paths() {
  # R12: a path with spaces or non-ASCII characters is read as one path, not quoted.
  numstat 1 1 'tests/a b.py' 1 1 'specs/é.md'
  assert_status 0 oracle changes
  numstat 401 0 'src/a b é.py'
  assert_status 1 pr_size changes
}

test_oracle_missing_input_fails() {
  # R12 test-oracle: no changes file is a usage error.
  assert_status 2 oracle
}
