# shellcheck shell=bash
# Tests for the governance and release files (R14, R16, R17): .github/ruleset.json,
# release-please, Dependabot. JSON is read with jq, YAML with the awk helpers in lib/assert.sh.

RULESET=$HARNESS_ROOT/.github/ruleset.json
CI=$HARNESS_ROOT/.github/workflows/ci.yml

# ruleset_rule TYPE: the ruleset rule of this type, or nothing.
ruleset_rule() { jq -c --arg t "$1" '.rules[] | select(.type == $t)' "$RULESET"; }

# required_ci_jobs: the ci.yml job ids that can block a merge (no continue-on-error), sorted.
required_ci_jobs() {
  local j
  while IFS= read -r j; do
    job_block "$CI" "$j" | grep -qE '^    continue-on-error: true$' || printf '%s\n' "$j"
  done < <(job_names "$CI") | sort
}

test_ruleset_required_checks_are_ci_jobs() {
  # R14: the required status checks are exactly the blocking ci.yml jobs (R12 "Required? Yes").
  assert_file "$RULESET"
  local checks
  checks=$(ruleset_rule required_status_checks | jq -r '.parameters.required_status_checks[].context' | sort)
  assert_eq "$(xargs <<< "$checks")" "$(required_ci_jobs | xargs)" 'ruleset checks vs ci.yml jobs'
  assert_not_contains "$checks" ste-lint
}

test_ruleset_protects_main() {
  # R14: PR with zero approvals, thread resolution, squash only, strict checks, linear history,
  # no force-push or deletion, empty bypass list, no signed-commit rule.
  assert_eq "$(jq -c '[.target, .enforcement, .conditions.ref_name.include]' "$RULESET")" '["branch","active",["~DEFAULT_BRANCH"]]'
  assert_eq "$(jq -c '.bypass_actors' "$RULESET")" '[]' 'bypass list'
  assert_eq "$(ruleset_rule pull_request | jq -c '.parameters | [.required_approving_review_count, .required_review_thread_resolution, .allowed_merge_methods]')" \
    '[0,true,["squash"]]' 'pull_request rule'
  assert_eq "$(ruleset_rule required_status_checks | jq -c '.parameters.strict_required_status_checks_policy')" 'true' 'strict checks'
  local t
  for t in required_linear_history non_fast_forward deletion; do
    [[ -n $(ruleset_rule "$t") ]] || fail "missing rule $t"
  done
  [[ -z $(ruleset_rule required_signatures) ]] || fail 'signed commits are not required in v1'
}

test_release_please_simple_from_0_1_0() {
  # R16: release-type simple, version.txt and the manifest start at 0.1.0.
  local cfg=$HARNESS_ROOT/release-please-config.json
  assert_eq "$(jq -r '.packages["."]["release-type"]' "$cfg")" simple
  assert_eq "$(jq -c . "$HARNESS_ROOT/.release-please-manifest.json")" '{".":"0.1.0"}'
  assert_eq "$(cat "$HARNESS_ROOT/version.txt")" 0.1.0
  assert_file "$HARNESS_ROOT/CHANGELOG.md"
}

test_release_please_pr_passes_docs_gate() {
  # R16: the owner merges the release PR, so its body has the R13 fields that docs-gate needs.
  init_repo
  jq -r '.["pull-request-footer"]' "$HARNESS_ROOT/release-please-config.json" > body.md
  numstat 12 0 CHANGELOG.md 1 1 version.txt 1 1 .release-please-manifest.json
  assert_status 0 "$HARNESS_ROOT/.harness/ci/docs-gate.sh" changes body.md
}

test_release_please_workflow() {
  # R16: runs on push to main; an optional RELEASE_PLEASE_TOKEN lets CI run on the release PR.
  local f=$HARNESS_ROOT/.github/workflows/release-please.yml on
  assert_file "$f"
  on=$(top_block "$f" on)
  assert_contains "$on" '  push:'
  assert_contains "$on" 'branches: [main]'
  grep -q 'uses: *googleapis/release-please-action@' "$f" || fail 'does not use release-please-action'
  # shellcheck disable=SC2016 # a literal workflow expression, not shell
  grep -qF 'token: ${{ secrets.RELEASE_PLEASE_TOKEN || github.token }}' "$f" || fail 'token does not fall back from RELEASE_PLEASE_TOKEN'
}

test_dependabot_github_actions_weekly() {
  # R17: github-actions only, weekly, 3-day cooldown, minor and patch updates in one group,
  # Conventional Commit titles so pr-title passes.
  local f=$HARNESS_ROOT/.github/dependabot.yml
  assert_file "$f"
  assert_eq "$(grep -E '^ *- package-ecosystem:' "$f" | sed 's/.*: *//' | xargs)" github-actions 'ecosystems'
  grep -qE '^ +interval: weekly$' "$f" || fail 'interval is not weekly'
  grep -qE '^ +default-days: 3$' "$f" || fail 'cooldown is not 3 days'
  grep -qE '^ +update-types: \[minor, patch\]$' "$f" || fail 'minor and patch are not grouped'
  grep -qE '^ +prefix: chore$' "$f" || fail 'commit prefix is not chore'
  grep -qE '^ +include: scope$' "$f" || fail 'commit message does not include the deps scope'
}
