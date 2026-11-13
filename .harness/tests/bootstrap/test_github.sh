# shellcheck shell=bash
# shellcheck disable=SC2016 # backticks and $REPO_API placeholders are literal text
# Tests for the GitHub steps of scripts/bootstrap (R15, R18 steps 4-6 and 9). gh_api is
# replaced by .harness/tests/lib/fake_gh.sh, so no test reaches the network.

# gh_reply METHOD PATH BODY [STATUS]: what the fake GitHub answers to METHOD PATH.
gh_reply() {
  local f="$GH_STATE/$1 ${2//\//_}"
  printf '%s' "$3" > "$f"
  if [[ -n ${4:-} ]]; then printf '%s' "$4" > "$f.status"; fi
}

REPO_API='repos/{owner}/{repo}'

# fake_github VISIBILITY: a new GitHub repo with default settings, no labels and no ruleset.
fake_github() {
  export GH_STATE=$TEST_TMP/gh
  rm -rf "$GH_STATE"; mkdir -p "$GH_STATE"
  : > "$GH_STATE/calls"
  gh_reply GET "$REPO_API" "$(printf '{"full_name": "acme/demo", "html_url": "https://github.com/acme/demo", "visibility": "%s",
    "allow_squash_merge": true, "allow_merge_commit": true, "allow_rebase_merge": true, "delete_branch_on_merge": false,
    "squash_merge_commit_title": "COMMIT_OR_PR_TITLE", "squash_merge_commit_message": "COMMIT_MESSAGES",
    "security_and_analysis": {"secret_scanning": {"status": "disabled"}, "secret_scanning_push_protection": {"status": "disabled"}}}' "$1")"
  gh_reply GET "$REPO_API/labels" '[{"id": 1, "name": "bug"}]'
  gh_reply GET "$REPO_API/rulesets" '[]'
  gh_reply GET "$REPO_API/code-scanning/default-setup" '{"state": "not-configured"}'
}

# configured_github: the fake repo after a full bootstrap run (public, strict mode).
configured_github() {
  fake_github public
  gh_reply GET "$REPO_API" '{"full_name": "acme/demo", "html_url": "https://github.com/acme/demo", "visibility": "public",
    "allow_squash_merge": true, "allow_merge_commit": false, "allow_rebase_merge": false, "delete_branch_on_merge": true,
    "squash_merge_commit_title": "PR_TITLE", "squash_merge_commit_message": "COMMIT_MESSAGES",
    "security_and_analysis": {"secret_scanning": {"status": "enabled"}, "secret_scanning_push_protection": {"status": "enabled"}}}'
  gh_reply GET "$REPO_API/labels" '[{"name": "Size/S"}, {"name": "size/M"}, {"name": "size/L"}, {"name": "size-exception"}, {"name": "agent"}, {"name": "dependencies"}]'
  gh_reply GET "$REPO_API/rulesets" '[{"id": 7, "name": "main", "source": "acme/demo", "enforcement": "active"}]'
  # GitHub adds fields and reorders the rules; neither is a difference.
  gh_reply GET "$REPO_API/rulesets/7" "$(python3 -c 'import json,sys
d = json.load(open(sys.argv[1]))
d.update(id=7, source="acme/demo", node_id="x", current_user_can_bypass="never")
d["rules"].reverse()
d["rules"][0]["parameters"]["do_not_enforce_on_create"] = False
print(json.dumps(d))' "$HARNESS_ROOT/.github/ruleset.json")"
  gh_reply GET "$REPO_API/code-scanning/default-setup" '{"state": "configured"}'
  gh_reply GET "$REPO_API/vulnerability-alerts" ''
}

# gh_bs DIR ANSWERS ARGS...: run bootstrap in DIR against the fake GitHub.
gh_bs() {
  local d=$1 a=$2; shift 2
  mkdir -p "$TEST_TMP/home"
  (cd "$d" && BOOTSTRAP_ANSWERS=$a HOME=$TEST_TMP/home bash -c \
    'set -euo pipefail; source "$1"; source "$2"; shift 2; main "$@"' _ \
    scripts/bootstrap "$HARNESS_ROOT/.harness/tests/lib/fake_gh.sh" "$@")
}

# writes: the write calls the fake GitHub received.
writes() { grep -v '^GET ' "$GH_STATE/calls" || true; }

test_dry_run_prints_every_github_call_and_writes_nothing() {
  # AC-1-29
  local d args; d=$(copy_repo)
  for args in '--template --dry-run' '--dry-run'; do
    fake_github public
    # shellcheck disable=SC2086 # two flags
    assert_status 0 gh_bs "$d" 'name=demo agents=claude' $args
    assert_eq "$(writes)" '' 'no network write'
    assert_contains "$OUT" "dry-run: gh api -X PATCH $REPO_API -F allow_merge_commit=false"
    assert_contains "$OUT" 'delete_branch_on_merge=true'
    assert_contains "$OUT" "-f 'description=Small change: no new or changed requirement'"
    assert_contains "$OUT" 'squash_merge_commit_title=PR_TITLE'
    assert_contains "$OUT" 'squash_merge_commit_message=COMMIT_MESSAGES'
    local l
    for l in size/S size/M size/L size-exception agent dependencies; do
      assert_contains "$OUT" "dry-run: gh api -X POST $REPO_API/labels -f name=$l -f color="
    done
    assert_contains "$OUT" "dry-run: gh api -X POST $REPO_API/rulesets --input .github/ruleset.json"
    assert_contains "$OUT" "dry-run: gh api -X PATCH $REPO_API/code-scanning/default-setup -f state=configured"
    assert_contains "$OUT" "dry-run: gh api -X PATCH $REPO_API -f security_and_analysis[secret_scanning][status]=enabled"
    assert_contains "$OUT" 'security_and_analysis[secret_scanning_push_protection][status]=enabled'
    assert_contains "$OUT" "dry-run: gh api -X PUT $REPO_API/vulnerability-alerts"
  done
}

test_configured_repo_gets_no_write() {
  # R18: each GitHub step checks the state first. R15: strict mode.
  local d; d=$(copy_repo)
  configured_github
  assert_status 0 gh_bs "$d" '' --template
  assert_eq "$(writes)" '' 'no write'
  assert_contains "$OUT" 'ok: repo options'
  assert_contains "$OUT" 'ok: labels'
  assert_contains "$OUT" 'ok: ruleset'
  assert_contains "$OUT" 'ok: security features'
  assert_contains "$OUT" 'done: 0 change(s)'
  assert_contains "$OUT" 'GitHub: strict mode'
}

test_ruleset_updated_by_name_when_it_differs() {
  # R18: step 6, create-or-update by name.
  local d; d=$(copy_repo)
  configured_github
  gh_reply GET "$REPO_API/rulesets/7" '{"id": 7, "name": "main", "target": "branch", "enforcement": "evaluate", "rules": []}'
  assert_status 0 gh_bs "$d" '' --template
  assert_eq "$(writes)" "PUT $REPO_API/rulesets/7"
  assert_contains "$OUT" 'changed: ruleset main updated'
}

test_ruleset_403_means_honor_mode() {
  # R15
  local d; d=$(copy_repo)
  fake_github private
  gh_reply POST "$REPO_API/rulesets" '' 403
  assert_status 0 gh_bs "$d" '' --template
  assert_contains "$OUT" 'honor mode'
  assert_contains "$OUT" 'merging is your decision'
  assert_not_contains "$OUT" 'GitHub: strict mode'
  fake_github private
  gh_reply GET "$REPO_API/rulesets" '' 403
  assert_status 0 gh_bs "$d" '' --template
  assert_contains "$OUT" 'honor mode'
  assert_not_contains "$(writes)" rulesets
}

test_private_repo_skips_codeql_and_push_protection() {
  # R18: step 6, public repos only.
  local d; d=$(copy_repo)
  fake_github private
  assert_status 0 gh_bs "$d" '' --template
  assert_not_contains "$(cat "$GH_STATE/calls")" code-scanning
  assert_not_contains "$(cat "$GH_STATE/calls")" vulnerability-alerts
  [[ $(writes | grep -c "^PATCH $REPO_API\$") == 1 ]] || fail "one repo PATCH (options only): $(writes)"
  assert_contains "$OUT" 'need a public repo'
}

test_template_mode_changes_no_file() {
  # R18: template mode runs the GitHub steps only and never deletes or renames.
  local d before; d=$(copy_repo)
  fake_github public
  before=$(git -C "$d" status --porcelain --untracked-files=all)
  assert_status 0 gh_bs "$d" 'name=x agents=claude attribution=remove' --template
  assert_eq "$(git -C "$d" status --porcelain --untracked-files=all)" "$before"
  assert_contains "$(writes)" "POST $REPO_API/rulesets"
  assert_not_contains "$OUT" 'configure `check-app`'
}

test_human_steps_listed() {
  # R18: step 9.
  local d; d=$(copy_repo)
  fake_github public
  assert_status 0 gh_bs "$d" 'name=demo agents=claude,codex,antigravity'
  assert_contains "$OUT" 'Steps only you can do'
  assert_contains "$OUT" '[1/4]'
  assert_contains "$OUT" 'https://github.com/acme/demo/settings/secrets/actions'
  assert_contains "$OUT" 'RELEASE_PLEASE_TOKEN'
  assert_contains "$OUT" '/hooks'
  assert_contains "$OUT" 'trustedWorkspaces'
  assert_not_contains "$OUT" 'Template repository'
  d=$(copy_repo)
  assert_status 0 gh_bs "$d" 'name=demo agents=copilot' --local
  assert_contains "$OUT" 'RELEASE_PLEASE_TOKEN'
  assert_not_contains "$OUT" 'settings/secrets'
  fake_github public
  assert_status 0 gh_bs "$(copy_repo)" '' --template
  assert_contains "$OUT" 'Template repository'
  assert_contains "$OUT" 'https://github.com/acme/demo/settings'
  assert_not_contains "$OUT" '/hooks'
}

test_unreadable_repo_stops_with_a_hint() {
  # R18: GitHub steps need gh, a login and a GitHub remote.
  fake_github public
  rm "$GH_STATE/GET ${REPO_API//\//_}"
  assert_status 1 gh_bs "$(copy_repo)" '' --template
  assert_contains "$OUT" 'gh auth login'
  assert_contains "$OUT" '--local'
}

test_refused_or_failed_writes_are_reported() {
  # R18: steps 5 and 6. A refused write stops with a reason; CodeQL only adds a note.
  local d; d=$(copy_repo)
  fake_github public
  gh_reply POST "$REPO_API/labels" '' 403
  assert_status 1 gh_bs "$d" '' --template
  assert_contains "$OUT" 'HTTP 403'
  assert_contains "$OUT" 'admin'
  fake_github public
  gh_reply PATCH "$REPO_API/code-scanning/default-setup" '' 422
  assert_status 0 gh_bs "$d" '' --template
  assert_contains "$OUT" 'GitHub refused CodeQL default setup'
  fake_github public
  gh_reply PUT "$REPO_API/vulnerability-alerts" '' 422
  assert_status 0 gh_bs "$d" '' --template
  assert_contains "$OUT" 'GitHub refused the dependency graph'
}

test_public_repo_gets_dependency_graph() {
  # R18: step 6. The deps check (dependency-review) needs the dependency graph.
  # Turning on Dependabot alerts turns it on.
  local d; d=$(copy_repo)
  fake_github public
  assert_status 0 gh_bs "$d" '' --template
  assert_contains "$(writes)" "PUT $REPO_API/vulnerability-alerts"
  assert_contains "$OUT" 'changed: dependency graph and Dependabot alerts turned on'
}

test_honor_mode_ruleset_step_is_not_ok() {
  # R15
  fake_github private
  gh_reply POST "$REPO_API/rulesets" '' 403
  assert_status 0 gh_bs "$(copy_repo)" '' --template
  assert_not_contains "$OUT" 'ok: ruleset'
  assert_contains "$OUT" 'skipped: ruleset'
}

test_dry_run_prints_reads_and_ignores_org_rulesets() {
  # AC-1-29: the reads are printed too. R18: only this repo's rulesets match by name.
  fake_github public
  assert_status 0 gh_bs "$(copy_repo)" '' --template --dry-run
  assert_contains "$OUT" "dry-run: read: gh api $REPO_API/rulesets?includes_parents=false"
  assert_contains "$(cat "$GH_STATE/calls")" "GET $REPO_API/rulesets?includes_parents=false"
}

# --- --add-agent (T10c) -------------------------------------------------------

# fake_tarball REPO TAG: the fake GitHub serves the working tree under test as the
# tarball of REPO at TAG. GitHub puts every file under one "<owner>-<repo>-<sha>/" folder.
fake_tarball() {
  local f="$GH_STATE/GET repos_${1//\//_}_tarball_$2"
  (cd "$HARNESS_ROOT" && git ls-files -co --exclude-standard | while IFS= read -r p; do
    [[ -e $p || -L $p ]] && printf '%s\n' "$p"; done |
    tar -czf "$f" --no-recursion --transform 's,^,acme-tpl-abc1234/,S' -T -)
}

# template_version DIR KEY: a value from DIR/.template-version.
template_version() { sed -n "s/^$2=//p" "$1/.template-version"; }

test_template_repo_recorded() {
  # R18 --add-agent: bootstrap records the template repo. GitHub names it for a repo
  # made with "Use this template"; otherwise TEMPLATE_REPO from .harness/config.
  local d default; d=$(copy_repo)
  default=$(bash -c 'source "$1"; printf %s "$TEMPLATE_REPO"' _ "$HARNESS_ROOT/.harness/config")
  [[ $default == */* ]] || fail "TEMPLATE_REPO in .harness/config: '$default'"
  fake_github public
  gh_reply GET "$REPO_API" '{"full_name": "acme/demo", "html_url": "https://github.com/acme/demo", "visibility": "public",
    "template_repository": {"full_name": "tpl/base"}}'
  assert_status 0 gh_bs "$d" 'name=demo agents=claude'
  assert_eq "$(template_version "$d" repo)" tpl/base
  d=$(copy_repo)
  assert_status 0 gh_bs "$d" 'name=demo agents=claude' --local
  assert_eq "$(template_version "$d" repo)" "$default"
  sed -i 's/^repo=.*/repo=mine\/fork/' "$d/.template-version"
  assert_status 0 gh_bs "$d" '' --local
  assert_eq "$(template_version "$d" repo)" mine/fork 'a re-run keeps the repo'
}

test_release_tag_is_v_version() {
  # R18 --add-agent downloads the tag v<version>, so release-please must tag the root package so.
  assert_eq "$(jq -r '.packages["."]["include-component-in-tag"]' "$HARNESS_ROOT/release-please-config.json")" false
}

test_add_agent_copies_only_its_paths() {
  # R18 --add-agent
  local d; d=$(copy_repo)
  assert_status 0 gh_bs "$d" 'name=demo agents=claude' --local
  sed -i 's/^repo=.*/repo=acme\/tpl/; s/^version=.*/version=0.4.2/' "$d/.template-version"
  fake_github public
  fake_tarball acme/tpl v0.4.2
  assert_status 0 gh_bs "$d" 'attribution=remove' --add-agent copilot
  assert_contains "$(cat "$GH_STATE/calls")" 'GET repos/acme/tpl/tarball/v0.4.2'
  assert_eq "$(writes)" '' 'no GitHub write'
  assert_status 0 cmp "$d/.github/copilot-instructions.md" "$HARNESS_ROOT/.github/copilot-instructions.md"
  assert_status 0 cmp "$d/.github/hooks/guard.json" "$HARNESS_ROOT/.github/hooks/guard.json"
  assert_file "$d/.github/skills/tdd/SKILL.md"
  assert_no_file "$d/.codex"
  assert_no_file "$d/.agents/hooks.json"
  assert_eq "$(template_version "$d" agents)" claude,copilot
  assert_eq "$(template_version "$d" version)" 0.4.2
  assert_eq "$(jq -c . "$d/.github/copilot/settings.json")" '{"includeCoAuthoredBy":false}'
  # Other agents keep their attribution.
  assert_status 0 cmp "$d/.claude/settings.json" "$HARNESS_ROOT/.claude/settings.json"
  assert_status 0 "$d/.harness/check/symlinks.sh" "$d"
  assert_not_contains "$OUT" 'RELEASE_PLEASE_TOKEN'
  assert_not_contains "$OUT" 'check-app'
}

test_add_agent_claude_trust_step_and_plugins() {
  # R18 --add-agent: the added agent also gets its plugin check and its trust step.
  local d c=$TEST_TMP/home/.claude; d=$(copy_repo)
  assert_status 0 gh_bs "$d" 'name=demo agents=codex' --local
  fake_github public
  fake_tarball "$(template_version "$d" repo)" "v$(template_version "$d" version)"
  mkdir -p "$c/plugins/cache/dup/skills/tdd"
  touch "$c/plugins/cache/dup/skills/tdd/SKILL.md"
  printf '{"enabledPlugins": {"dup@mkt": true}}\n' > "$c/settings.json"
  printf '{"plugins": {"dup@mkt": [{"installPath": "%s"}]}}\n' "$c/plugins/cache/dup" > "$c/plugins/installed_plugins.json"
  assert_status 0 gh_bs "$d" '' --add-agent claude
  assert_eq "$(jq -c .enabledPlugins "$d/.claude/settings.json")" '{"dup@mkt":false}'
  assert_eq "$(readlink "$d/CLAUDE.md")" AGENTS.md
  assert_contains "$OUT" 'Claude Code: start claude'
  assert_not_contains "$OUT" '/hooks'
  assert_eq "$(template_version "$d" agents)" codex,claude
  # The owner deleted the files by hand; the agent is listed once.
  rm "$d/CLAUDE.md"; rm -r "$d/.claude"
  assert_status 0 gh_bs "$d" '' --add-agent claude
  assert_eq "$(template_version "$d" agents)" codex,claude
}

test_add_agent_refuses_and_changes_nothing() {
  # R18 --add-agent: on any problem, stop before a file changes.
  local d before version; d=$(copy_repo)
  assert_status 0 gh_bs "$d" 'name=demo agents=claude,codex' --local
  version=$(template_version "$d" version)
  fake_github public
  fake_tarball "$(template_version "$d" repo)" "v$version"
  before=$(git -C "$d" status --porcelain --untracked-files=all; cat "$d/.template-version")
  assert_status 1 gh_bs "$d" '' --add-agent codex
  assert_contains "$OUT" '.codex'
  assert_contains "$OUT" 'exists'
  assert_status 1 gh_bs "$d" '' --add-agent cursor
  assert_contains "$OUT" 'unknown agent: cursor'
  assert_status 1 gh_bs "$d" '' --add-agent copilot --template
  assert_status 1 gh_bs "$d" '' --add-agent
  sed -i 's/^version=.*/version=9.9.9/' "$d/.template-version"
  assert_status 1 gh_bs "$d" '' --add-agent copilot
  assert_contains "$OUT" 'v9.9.9'
  assert_contains "$OUT" 'gh auth login'
  sed -i "s/^version=.*/version=$version/" "$d/.template-version"
  assert_status 1 gh_bs "$d" 'attribution=maybe' --add-agent copilot
  assert_contains "$OUT" 'answer keep or remove'
  assert_status 0 gh_bs "$d" '' --add-agent copilot --dry-run
  assert_contains "$OUT" 'dry-run: cp'
  assert_eq "$(git -C "$d" status --porcelain --untracked-files=all; cat "$d/.template-version")" "$before"
  rm "$d/.template-version"
  assert_status 1 gh_bs "$d" '' --add-agent copilot
  assert_contains "$OUT" 'run scripts/bootstrap first'
}
