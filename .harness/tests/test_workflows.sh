# shellcheck shell=bash
# Tests for .github/workflows (R12, R22). The files are read with awk, so they keep
# the layout actionlint accepts: two-space indent, one job per `  name:` line.

WF=$HARNESS_ROOT/.github/workflows
CI_JOBS='check deps pr-size pr-title secrets ste-lint test-oracle zizmor'

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
workflows() { local f; for f in "$WF"/*.yml; do [[ -e $f ]] && printf '%s\n' "$f"; done; }

test_workflows_pin_actions_to_full_sha() {
  # R12: every remote action is pinned to a 40-character commit SHA with the tag in a comment.
  local f line n=0
  while IFS= read -r f; do
    while IFS= read -r line; do
      n=$((n + 1))
      [[ $line =~ uses:\ *\./ ]] && continue
      [[ $line =~ uses:\ *[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}\ +#\ *v[0-9] ]] ||
        fail "${f##*/}: not pinned to a SHA with a version comment: $line"
    done < <(grep -E '^\s*-?\s*uses:' "$f")
  done < <(workflows)
  ((n > 0)) || fail 'no uses: lines found'
}

test_workflows_least_privilege_permissions() {
  # R12: an empty workflow-level permissions block, and a permissions block on every job.
  local f j
  while IFS= read -r f; do
    grep -qx 'permissions: {}' "$f" || fail "${f##*/}: workflow-level permissions is not {}"
    while IFS= read -r j; do
      job_block "$f" "$j" | grep -qE '^    permissions:' || fail "${f##*/}: job $j has no permissions"
      job_block "$f" "$j" | grep -qE 'write-all|read-all' && fail "${f##*/}: job $j uses a broad permission"
    done < <(job_names "$f")
  done < <(workflows)
  return 0
}

test_workflows_no_pull_request_target() {
  # R12
  local f
  while IFS= read -r f; do
    grep -q 'pull_request_target' "$f" && fail "${f##*/} uses pull_request_target"
  done < <(workflows)
  return 0
}

test_workflows_checkout_without_credentials() {
  # R12: checkout does not leave the token in .git/config.
  local f n
  while IFS= read -r f; do
    n=$(grep -c 'uses: *actions/checkout@' "$f" || true)
    assert_eq "$(grep -c 'persist-credentials: false' "$f" || true)" "$n" "${f##*/}: persist-credentials: false per checkout"
  done < <(workflows)
}

test_ci_has_r12_jobs() {
  # R12: the job ids are the required check names that T9 puts in the ruleset.
  assert_eq "$(job_names "$WF/ci.yml" | sort | xargs)" "$CI_JOBS"
}

test_ci_check_job_runs_make_check() {
  # AC-1-17
  job_block "$WF/ci.yml" check | grep -qE '^ +(- )?run: make check$' || fail 'job check does not run make check'
  job_block "$WF/ci.yml" check | grep -q 'check-harness' && fail 'job check must not branch to check-harness'
  return 0
}

test_ci_ste_lint_is_not_blocking() {
  # AC-1-11
  job_block "$WF/ci.yml" ste-lint | grep -qE '^    continue-on-error: true$' || fail 'ste-lint must set continue-on-error: true'
  job_block "$WF/ci.yml" ste-lint | grep -q 'ste-lint.py' || fail 'ste-lint does not run ste-lint.py'
}

test_ci_gate_jobs_call_harness_scripts() {
  # R12: pr-size and test-oracle run the tested scripts, not inline logic.
  job_block "$WF/ci.yml" pr-size | grep -q '.harness/ci/pr-size.sh' || fail 'pr-size job does not call .harness/ci/pr-size.sh'
  job_block "$WF/ci.yml" test-oracle | grep -q '.harness/ci/test-oracle.sh' || fail 'test-oracle job does not call .harness/ci/test-oracle.sh'
}

test_ci_deps_switches_on_visibility() {
  # R12 deps: dependency-review on public repos, osv-scanner on private repos.
  local b; b=$(job_block "$WF/ci.yml" deps)
  assert_contains "$b" 'actions/dependency-review-action@'
  assert_contains "$b" 'osv-scanner'
  assert_contains "$b" 'github.event.repository.private'
}

test_tools_outdated_is_report_only() {
  # AC-1-39
  local f=$WF/tools-outdated.yml perms
  assert_file "$f"
  assert_eq "$(top_block "$f" on | awk '/^  [a-z_]+:/ {sub(/:.*/, ""); sub(/^ +/, ""); print}' | sort | xargs)" 'schedule workflow_dispatch'
  perms=$(grep -E '^ +(actions|attestations|checks|contents|deployments|discussions|id-token|issues|packages|pages|pull-requests|security-events|statuses): ' "$f" | sed 's/^ *//' | sort -u | xargs)
  assert_eq "$perms" 'contents: read issues: write'
  grep -qE 'git push|gh pr |create-pull-request|git commit' "$f" && fail 'tools-outdated must not push or open a PR'
  return 0
}
