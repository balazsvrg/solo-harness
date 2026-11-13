# shellcheck shell=bash
# Tests for .harness/check/deny-rules.sh, .claude/settings.json and the other agents' policy files (R6, R7, R9).

SETTINGS=$HARNESS_ROOT/.claude/settings.json
deny_check() { "$HARNESS_ROOT/.harness/check/deny-rules.sh" "$@"; }
# settings_list KEY: print each rule of permissions.KEY on its own line.
settings_list() { python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["permissions"][sys.argv[2]]))' "$SETTINGS" "$1"; }
# settings_hooks EVENT: print the hook config for EVENT as JSON.
settings_hooks() { python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["hooks"][sys.argv[2]]))' "$SETTINGS" "$1"; }
sandbox_enabled() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sandbox"]["enabled"])' "$SETTINGS"; }

test_deny_rules_cover_r6() {
  # AC-1-12: one rule per R6 deny item, written here as fixed text.
  local rules rule
  rules=$(deny_check --list)
  for rule in 'Bash(git push * main)' 'Bash(git push *:main)' 'Bash(git push --force*)' 'Bash(git push -f*)' \
    'Bash(gh pr merge *)' 'Bash(gh release create *)' 'Bash(git commit --no-verify*)' \
    'Read(./.env*)' 'Read(**/.env*)' 'Read(~/.ssh/**)' 'Edit(./.claude/settings*.json)' \
    'Edit(./.codex/**)' 'Edit(./.agents/hooks.json)' 'Edit(./.github/hooks/**)' 'Edit(./.githooks/**)'; do
    grep -qxF -- "$rule" <<<"$rules" || fail "deny-rules.sh does not require $rule"
  done
  has_agent claude || return 0
  assert_eq "$(settings_list deny | sort)" "$(sort <<<"$rules")" 'settings.json deny list = deny-rules.sh list'
}

test_deny_rules_missing_rule_fails() {
  # AC-1-12
  assert_status 0 deny_check "$HARNESS_ROOT"
  has_agent claude || return 0
  local r rule; r=$(new_repo)
  mkdir -p "$r/.claude"
  while IFS= read -r rule; do
    python3 - "$SETTINGS" "$r/.claude/settings.json" "$rule" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
s["permissions"]["deny"].remove(sys.argv[3])
json.dump(s, open(sys.argv[2], "w"))
PY
    assert_status 1 deny_check "$r"
    assert_contains "$OUT" "$rule"
  done < <(settings_list deny)
  echo '{not json' > "$r/.claude/settings.json"
  assert_status 1 deny_check "$r"
}

test_settings_policy_shape() {
  # R6, R7, R9: ask on tools.lock (not deny), hooks registered, sandbox off
  has_agent claude || return 0
  settings_list ask | grep -qxF 'Edit(./.harness/tools.lock)' || fail 'ask on tools.lock'
  settings_list deny | grep -qF 'tools.lock' && fail 'tools.lock must not be denied'
  local rule
  for rule in 'Edit(./.harness/hooks/**)' 'Edit(./.harness/check/deny-rules.sh)' \
    'Bash(npm i)' 'Bash(pnpm i)' 'Bash(pnpm i *)' 'Bash(yarn)' 'Bash(npm ci*)' 'Bash(uv sync*)' \
    'Bash(uv tool install *)' 'Bash(python* -m pip install *)' 'Bash(yarn global add *)'; do
    settings_list ask | grep -qxF -- "$rule" || fail "ask list misses $rule"
  done
  settings_list allow | grep -qxF 'Bash(gh pr create)' || fail 'allow list misses Bash(gh pr create)'
  assert_eq "$(sandbox_enabled)" False 'sandbox off'
  assert_contains "$(settings_hooks PreToolUse)" 'guard-bash.sh'
  assert_contains "$(settings_hooks PostToolUse)" 'fmt.sh'
  assert_contains "$(settings_hooks Stop)" 'stop-check.sh'
  assert_contains "$(settings_hooks Stop)" '"timeout": 300'
}

test_reviewer_read_only() {
  # R8
  has_agent claude || return 0
  local f=$HARNESS_ROOT/.claude/agents/reviewer.md
  assert_file "$f"
  assert_eq "$(sed -n 's/^tools: //p' "$f")" 'Read, Grep, Glob'
}

CODEX_RULES=.codex/rules/default.rules
HOOK_FILES=(.codex/hooks.json .github/hooks/guard.json .agents/hooks.json)

# policy_repo: a repo with copies of the real Codex rules and agent hook files.
policy_repo() {
  local r f; r=$(new_repo)
  for f in "$CODEX_RULES" "${HOOK_FILES[@]}"; do
    [[ -e $HARNESS_ROOT/$f ]] || continue
    mkdir -p "$r/$(dirname "$f")"
    cp "$HARNESS_ROOT/$f" "$r/$f"
  done
  printf '%s\n' "$r"
}

test_codex_rules_cover_r6() {
  # AC-1-12: Codex rules forbid each R6 deny command that a prefix rule can express.
  has_agent codex || return 0
  local r pattern; r=$(policy_repo)
  assert_status 0 deny_check "$r"
  while IFS= read -r pattern; do
    grep -vxF -- "$pattern" "$HARNESS_ROOT/$CODEX_RULES" > "$r/$CODEX_RULES"
    assert_status 1 deny_check "$r"
    assert_contains "$OUT" "$CODEX_RULES"
  done < <(grep -E '^[[:space:]]*pattern = ' "$HARNESS_ROOT/$CODEX_RULES")
  python3 -c 'import sys; t=open(sys.argv[1]).read(); open(sys.argv[2],"w").write(t.replace("\"forbidden\"","\"prompt\"",1))' \
    "$HARNESS_ROOT/$CODEX_RULES" "$r/$CODEX_RULES"
  assert_status 1 deny_check "$r"
  assert_contains "$OUT" forbidden
}

test_hook_files_run_the_guard() {
  # AC-1-12: each agent's hook file sends its before-tool event to the adapter.
  local r f; r=$(policy_repo)
  for f in "${HOOK_FILES[@]}"; do
    [[ -e $HARNESS_ROOT/$f ]] || continue
    python3 -c 'import sys; t=open(sys.argv[1]).read(); open(sys.argv[2],"w").write(t.replace(" pre", " post"))' \
      "$HARNESS_ROOT/$f" "$r/$f"
    assert_status 1 deny_check "$r"
    assert_contains "$OUT" "$f"
    cp "$HARNESS_ROOT/$f" "$r/$f"
  done
  rm -f "$r/$CODEX_RULES" "${HOOK_FILES[@]/#/$r/}"
  assert_status 0 deny_check "$r"
}

test_copilot_reviewer_read_only() {
  # R8: the Copilot reviewer has only read tools and the same instructions as the Claude reviewer.
  has_agent copilot || return 0
  local f=$HARNESS_ROOT/.github/agents/reviewer.agent.md
  assert_file "$f"
  assert_eq "$(sed -n 's/^tools: //p' "$f")" '["read", "search"]'
  has_agent claude || return 0
  assert_eq "$(sed '1,/^---$/d' "$f" | sed '1,/^---$/d')" \
    "$(sed '1,/^---$/d' "$HARNESS_ROOT/.claude/agents/reviewer.md" | sed '1,/^---$/d')" 'same reviewer body'
}

test_copilot_instructions_point_to_agents_md() {
  # R5
  has_agent copilot || return 0
  # shellcheck disable=SC2016 # backticks are literal
  assert_contains "$(cat "$HARNESS_ROOT/.github/copilot-instructions.md")" 'Read `AGENTS.md`'
}
