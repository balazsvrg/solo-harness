# shellcheck shell=bash
# Tests for .harness/check/deny-rules.sh and .claude/settings.json (R6, R7, R9).

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
    'Edit(./.codex/**)' 'Edit(./.gemini/**)' 'Edit(./.githooks/**)'; do
    grep -qxF -- "$rule" <<<"$rules" || fail "deny-rules.sh does not require $rule"
  done
  assert_eq "$(settings_list deny | sort)" "$(sort <<<"$rules")" 'settings.json deny list = deny-rules.sh list'
}

test_deny_rules_missing_rule_fails() {
  # AC-1-12
  assert_status 0 deny_check "$HARNESS_ROOT"
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
  settings_list ask | grep -qxF 'Edit(./.harness/tools.lock)' || fail 'ask on tools.lock'
  settings_list deny | grep -qF 'tools.lock' && fail 'tools.lock must not be denied'
  local rule
  for rule in 'Edit(./.claude/hooks/**)' 'Edit(./.harness/check/deny-rules.sh)' \
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
  local f=$HARNESS_ROOT/.claude/agents/reviewer.md
  assert_file "$f"
  assert_eq "$(sed -n 's/^tools: //p' "$f")" 'Read, Grep, Glob'
}
