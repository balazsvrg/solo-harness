# shellcheck shell=bash
# shellcheck disable=SC2016 # $(MAKE) is literal Makefile text
# Tests for scripts/bootstrap (R18), local project mode. Each test runs on a temp copy
# of the repo with scripted answers (BOOTSTRAP_ANSWERS) and a fake HOME.

# bs DIR ANSWERS ARGS...: run bootstrap in DIR. Output goes to $OUT via assert_status.
bs() {
  local d=$1 a=$2; shift 2
  mkdir -p "$TEST_TMP/home"
  (cd "$d" && BOOTSTRAP_ANSWERS=$a HOME=$TEST_TMP/home scripts/bootstrap "$@")
}

# Agent config files, from design §6 (the per-agent table) and T4/T5.
declare -A AGENT_FILES=(
  [claude]='CLAUDE.md .claude/settings.json .claude/agents/reviewer.md .claude/skills'
  [codex]='.codex/hooks.json .codex/rules/default.rules'
  [copilot]='.github/copilot-instructions.md .github/agents/reviewer.agent.md .github/hooks/guard.json .github/skills .github/workflows/copilot-setup-steps.yml'
  [antigravity]='.agents/hooks.json'
)

# The test files that read agent configs at the repo root.
AGENT_TEST_FILES='test_@(deny_rules|layout|vendor|workflows).sh'

# assert_agents DIR KEPT...: files of KEPT agents exist, files of the others do not.
assert_agents() {
  local d=$1 a f; shift
  for a in claude codex copilot antigravity; do
    for f in ${AGENT_FILES[$a]}; do
      if [[ " $* " == *" $a "* ]]; then assert_file "$d/$f"; else assert_no_file "$d/$f"; [[ ! -L $d/$f ]] || fail "dangling: $f"; fi
    done
  done
}

test_agent_selection_keeps_only_selected_agents() {
  # AC-1-28
  local sel d
  for sel in claude codex copilot antigravity 'claude codex copilot antigravity'; do
    d=$(copy_repo)
    assert_status 0 bs "$d" "name=demo agents=${sel// /,}" --local
    # shellcheck disable=SC2086 # one word per agent
    assert_agents "$d" $sel
    assert_status 0 "$d/.harness/check/symlinks.sh" "$d"
    assert_file "$d/.agents/skills/tdd/SKILL.md"
    assert_file "$d/AGENTS.md"
  done
  assert_status 1 bs "$(copy_repo)" 'agents=' --local
  assert_contains "$OUT" 'select at least one agent'
}

test_project_without_some_agents_passes_check_harness() {
  # R18: the two selections remove each agent at least once. The checks run in full;
  # of the tests, only the files that read agent configs (the full suite takes ~50 s).
  local sel d
  for sel in claude codex,copilot,antigravity; do
    d=$(copy_repo)
    assert_status 0 bs "$d" "name=demo agents=$sel" --local
    assert_status 0 env -C "$d" HARNESS_NESTED=1 make -s check-harness
    assert_status 0 env -C "$d" TEST_FILES="$AGENT_TEST_FILES" .harness/tests/run.sh
  done
}

# recipe TARGET: the recipe lines of a Makefile target.
recipe() { awk -v t="$1" '$0 ~ "^"t":" {on=1; next} on && !/^\t/ {on=0} on' "$HARNESS_ROOT/Makefile"; }

test_test_bootstrap_runs_in_check_harness() {
  # AC-1-30
  assert_contains "$(recipe check-harness)" '$(MAKE) -s test-bootstrap'
  assert_contains "$(recipe test-bootstrap)" "TEST_FILES='bootstrap/test_*.sh' .harness/tests/run.sh"
  [[ -n $(declare -F test_agent_selection_keeps_only_selected_agents) ]] || fail 'bootstrap tests live in this file'
}

# json_get FILE EXPR: print a Python expression over the JSON in FILE (as `d`), or MISSING.
json_get() { python3 -c 'import json,sys
try: d=json.load(open(sys.argv[1]))
except FileNotFoundError: print("MISSING"); sys.exit()
print(json.dumps(eval(sys.argv[2])))' "$1" "$2"; }

test_remove_attribution_turns_it_off() {
  # AC-1-40
  local d; d=$(copy_repo)
  assert_status 0 bs "$d" 'name=demo agents=claude,copilot,codex attribution=remove' --local
  assert_eq "$(json_get "$d/.claude/settings.json" 'd["attribution"]')" '{"commit": "", "pr": "", "sessionUrl": false}'
  assert_eq "$(json_get "$d/.github/copilot/settings.json" 'd["includeCoAuthoredBy"]')" false
  assert_eq "$(json_get "$d/.claude/settings.json" 'd["permissions"]')" \
    "$(json_get "$HARNESS_ROOT/.claude/settings.json" 'd["permissions"]')" 'other keys kept'
  assert_contains "$OUT" 'no attribution setting: codex'
}

test_default_attribution_writes_nothing() {
  # AC-1-40
  local d; d=$(copy_repo)
  assert_status 0 bs "$d" 'name=demo agents=claude,copilot' --local
  assert_status 0 cmp "$d/.claude/settings.json" "$HARNESS_ROOT/.claude/settings.json"
  assert_no_file "$d/.github/copilot/settings.json"
  local before
  d=$(copy_repo)
  before=$(git -C "$d" status --porcelain --untracked-files=all)
  assert_status 0 bs "$d" 'attribution=remove' --template --local
  assert_eq "$(git -C "$d" status --porcelain --untracked-files=all)" "$before" 'template mode changes no file'
}

test_check_app_notice_only_for_placeholder() {
  # AC-1-34
  local d; d=$(copy_repo)
  assert_status 0 bs "$d" 'name=demo agents=claude' --local
  assert_contains "$OUT" 'next: configure `check-app`'
  assert_contains "$OUT" 'Makefile'
  assert_contains "$OUT" '.docs-map'
  d=$(copy_repo)
  sed -i '/^# solo-harness:check-app-placeholder$/d' "$d/Makefile"
  assert_status 0 bs "$d" 'name=demo agents=claude' --local
  assert_not_contains "$OUT" 'configure `check-app`'
  assert_contains "$OUT" '.docs-map'
}

test_project_files_are_reset() {
  # R18: steps 1 and 10.
  local d; d=$(copy_repo)
  mkdir -p "$d/specs/changes/archive/2026-11-20-1-bootstrap-template" "$d/specs/changes/archive/2027-01-02-5-keep-me"
  echo 0.4.2 > "$d/version.txt"
  echo '## 0.4.2' >> "$d/CHANGELOG.md"
  printf '{\n  ".": "0.4.2"\n}\n' > "$d/.release-please-manifest.json"
  assert_status 0 bs "$d" 'name=acme-shop agents=claude' --local
  assert_eq "$(head -1 "$d/docs/product.md")" '# acme-shop'
  assert_eq "$(sed -n 's/^version=//p' "$d/.template-version")" 0.4.2 'template version kept'
  assert_eq "$(sed -n 's/^agents=//p' "$d/.template-version")" claude
  assert_eq "$(cat "$d/version.txt")" 0.1.0
  assert_eq "$(jq -c . "$d/.release-please-manifest.json")" '{".":"0.1.0"}'
  assert_not_contains "$(cat "$d/CHANGELOG.md")" '0.4.2'
  assert_contains "$(cat "$d/CHANGELOG.md")" '# Changelog'
  assert_no_file "$d/.template-only"
  assert_no_file "$d/specs/changes/archive/2026-11-20-1-bootstrap-template"
  assert_file "$d/specs/changes/archive/2027-01-02-5-keep-me"
}

test_rerun_keeps_owner_edits_and_answers() {
  # R18: a second run changes nothing the owner wrote and reuses the agent selection.
  local d; d=$(copy_repo)
  assert_status 0 bs "$d" 'name=acme-shop agents=claude,codex' --local
  printf '# Acme Shop\n\nOur shop.\n' > "$d/docs/product.md"
  echo 0.3.0 > "$d/version.txt"
  assert_status 0 bs "$d" 'name=other' --local
  assert_contains "$OUT" 'done: 0 change(s)'
  assert_eq "$(head -1 "$d/docs/product.md")" '# Acme Shop'
  assert_eq "$(cat "$d/version.txt")" 0.3.0
  assert_file "$d/.codex/hooks.json"
}

test_git_hooks_turned_on() {
  # R18: step 7.
  local d; d=$(copy_repo)
  git -C "$d" config --unset core.hooksPath || true
  rm -f "$d/.harness/bin/gitleaks"
  assert_status 0 env PATH=/usr/bin:/bin bash -c "$(declare -f bs); TEST_TMP=$TEST_TMP; bs '$d' agents=claude --local"
  assert_eq "$(git -C "$d" config --get core.hooksPath)" .githooks
  # A gitleaks in /usr/bin or /bin is a real install, so the note is then correctly absent.
  PATH=/usr/bin:/bin command -v gitleaks >/dev/null || assert_contains "$OUT" 'gitleaks is not installed'
}

# fake_plugins: a user config in the fake HOME with three plugins. dup@mkt (enabled)
# ships a skill named tdd, like .agents/skills/tdd; other@mkt (enabled) does not;
# off@mkt ships tdd but is disabled.
fake_plugins() {
  local c=$TEST_TMP/home/.claude p
  for p in dup other off; do mkdir -p "$c/plugins/cache/mkt/$p/1.0.0/skills"; done
  mkdir -p "$c/plugins/cache/mkt/dup/1.0.0/skills/engineering/tdd" "$c/plugins/cache/mkt/other/1.0.0/skills/unique-skill" \
    "$c/plugins/cache/mkt/off/1.0.0/skills/tdd"
  touch "$c/plugins/cache/mkt/dup/1.0.0/skills/engineering/tdd/SKILL.md" \
    "$c/plugins/cache/mkt/other/1.0.0/skills/unique-skill/SKILL.md" "$c/plugins/cache/mkt/off/1.0.0/skills/tdd/SKILL.md"
  printf '{"enabledPlugins": {"dup@mkt": true, "other@mkt": true, "off@mkt": false}}\n' > "$c/settings.json"
  printf '{"version": 2, "plugins": {%s, %s, %s}}\n' \
    "\"dup@mkt\": [{\"scope\": \"user\", \"installPath\": \"$c/plugins/cache/mkt/dup/1.0.0\"}]" \
    "\"other@mkt\": [{\"scope\": \"user\", \"installPath\": \"$c/plugins/cache/mkt/other/1.0.0\"}]" \
    "\"off@mkt\": [{\"scope\": \"user\", \"installPath\": \"$c/plugins/cache/mkt/off/1.0.0\"}]" > "$c/plugins/installed_plugins.json"
}

test_duplicate_plugins_disabled_in_project() {
  # R18: step 8.
  local d; d=$(copy_repo)
  fake_plugins
  assert_status 0 bs "$d" 'name=demo agents=claude' --local
  assert_eq "$(json_get "$d/.claude/settings.json" 'd["enabledPlugins"]')" '{"dup@mkt": false}'
  assert_contains "$OUT" 'dup@mkt'
  assert_status 0 bs "$d" 'name=demo agents=claude' --local
  assert_contains "$OUT" 'done: 0 change(s)'
}

test_template_mode_disables_no_plugin() {
  # R18: step 8. The template repo itself disables nothing.
  local d; d=$(copy_repo)
  fake_plugins
  assert_status 0 bs "$d" '' --template --local
  assert_status 0 cmp "$d/.claude/settings.json" "$HARNESS_ROOT/.claude/settings.json"
}

# tree_state DIR: the working tree and the hooks setting, to compare before and after.
tree_state() {
  git -C "$1" status --porcelain --untracked-files=all
  git -C "$1" config --get core.hooksPath || true
  (cd "$1" && git ls-files -co --exclude-standard -z | xargs -0 sha1sum 2>/dev/null) || true
}

test_dry_run_changes_nothing_and_second_run_is_clean() {
  # AC-1-27
  local d before; d=$(copy_repo)
  fake_plugins
  git -C "$d" config --unset core.hooksPath || true
  before=$(tree_state "$d")
  assert_status 0 bs "$d" 'name=demo agents=claude attribution=remove' --dry-run --local
  assert_contains "$OUT" 'dry-run: rm -rf -- .codex'
  assert_contains "$OUT" 'dry-run: git config core.hooksPath .githooks'
  assert_not_contains "$OUT" 'dry run: 0 change(s)'
  assert_eq "$(tree_state "$d")" "$before" 'dry run wrote nothing'
  assert_status 0 bs "$d" 'name=demo agents=claude attribution=remove' --local
  assert_status 0 bs "$d" 'name=demo agents=claude attribution=remove' --dry-run --local
  assert_contains "$OUT" 'dry run: 0 change(s) planned'
  assert_not_contains "$OUT" 'dry-run:'
}
