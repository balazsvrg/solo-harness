# shellcheck shell=bash disable=SC2016 # command strings are literal test data
# Tests for .harness/hooks/adapter.sh: the Codex, Copilot and Antigravity hooks (R6, R7).

ADAPTER=$HARNESS_ROOT/.harness/hooks/adapter.sh

# adapt AGENT EVENT JSON: run the adapter with JSON on stdin.
adapt() { "$ADAPTER" "$1" "$2" <<<"$3"; }
# jfield KEY: print the value of KEY in the JSON object in $OUT.
jfield() { python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get(sys.argv[2], ""))' "$OUT" "$1"; }

codex_bash() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1"; }
codex_patch() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"apply_patch","tool_input":{"command":sys.argv[1]}}))' "$1"; }
copilot() { python3 -c 'import json,sys; print(json.dumps({"toolName":sys.argv[1],"toolArgs":json.dumps(json.loads(sys.argv[2]))}))' "$1" "$2"; }
antigravity() { python3 -c 'import json,sys; print(json.dumps({"toolCall":{"name":sys.argv[1],"args":json.loads(sys.argv[2])}}))' "$1" "$2"; }

test_adapter_codex_pre() {
  # R6, R7: Codex deny is exit 2 with a reason; an ask path is deny, because Codex hooks cannot ask.
  assert_status 2 adapt codex pre "$(codex_bash 'git push --force')"
  assert_contains "$OUT" 'force'
  assert_status 0 adapt codex pre "$(codex_bash 'git status')"
  assert_eq "$OUT" '' 'silent on allow'
  assert_status 2 adapt codex pre "$(codex_bash 'echo x > Makefile')"
  assert_contains "$OUT" 'ask the owner'
  assert_status 2 adapt codex pre "$(codex_patch $'*** Begin Patch\n*** Update File: .githooks/pre-commit\n@@\n-a\n+b\n*** End Patch')"
  assert_contains "$OUT" '.githooks/pre-commit'
  assert_status 2 adapt codex pre "$(codex_patch $'*** Begin Patch\n*** Add File: Makefile\n+x\n*** End Patch')"
  assert_contains "$OUT" 'ask the owner'
  assert_status 2 adapt codex pre "$(codex_patch $'*** Begin Patch\n*** Update File: notes.md\n*** Move to: .codex/x.toml\n*** End Patch')"
  assert_status 2 adapt codex pre "$(codex_patch $'*** Begin Patch\n*** Delete File: .harness/hooks/adapter.sh\n*** End Patch')"
  assert_status 0 adapt codex pre "$(codex_patch $'*** Begin Patch\n*** Add File: src/app.py\n+x\n*** End Patch')"
  assert_eq "$OUT" '' 'silent on allow'
  assert_status 0 adapt codex pre '{"tool_name":"update_plan","tool_input":{}}'
  assert_status 2 adapt codex pre '{not json'
}

test_adapter_copilot_pre() {
  # R6, R7: Copilot gets a permissionDecision JSON object; allow prints nothing.
  assert_status 0 adapt copilot pre "$(copilot bash '{"command":"gh pr merge 1"}')"
  assert_eq "$(jfield permissionDecision)" deny
  [[ -n $(jfield permissionDecisionReason) ]] || fail 'deny needs a reason'
  assert_status 0 adapt copilot pre "$(copilot bash '{"command":"git status"}')"
  assert_eq "$OUT" '' 'silent on allow'
  assert_status 0 adapt copilot pre "$(copilot edit '{"path":".github/hooks/guard.json","old_str":"a","new_str":"b"}')"
  assert_eq "$(jfield permissionDecision)" deny
  assert_status 0 adapt copilot pre "$(copilot create '{"path":".claude/settings.local.json","file_text":"{}"}')"
  assert_eq "$(jfield permissionDecision)" deny
  assert_status 0 adapt copilot pre "$(copilot edit '{"path":".github/workflows/ci.yml"}')"
  assert_eq "$(jfield permissionDecision)" ask
  assert_contains "$(jfield permissionDecisionReason)" 'ask the owner'
  assert_status 0 adapt copilot pre "$(copilot bash '{"command":"make check && npm install left-pad"}')"
  assert_eq "$(jfield permissionDecision)" ask 'package install'
  assert_status 0 adapt copilot pre "$(copilot bash '{"command":"echo npm install"}')"
  assert_eq "$OUT" '' 'npm install as text is not an install'
  assert_status 0 adapt copilot pre "$(copilot view '{"path":"config/.env.local"}')"
  assert_eq "$(jfield permissionDecision)" deny
  assert_status 0 adapt copilot pre "$(copilot edit '{"old_str":"a"}')"
  assert_eq "$(jfield permissionDecision)" deny 'edit without a path fails closed'
  assert_status 0 adapt copilot pre "$(copilot create '{"path":"src/a.py","file_text":"x"}')"
  assert_eq "$OUT" '' 'silent on allow'
  assert_status 0 adapt copilot pre "$(copilot grep '{"pattern":"x"}')"
  assert_eq "$OUT" '' 'other tools pass'
}

test_adapter_codex_install_left_to_rules() {
  # R6: Codex asks for a package install through .codex/rules, so its hook must not deny it.
  assert_status 0 adapt codex pre "$(codex_bash 'npm install left-pad')"
  assert_eq "$OUT" '' 'codex install passes the hook'
  assert_status 2 adapt codex pre "$(codex_bash 'npm install x && git push -f')"
}

test_adapter_unclean_paths() {
  # R6: a path with // or /./ or .. still hits the deny and ask rules.
  local p
  for p in '.claude//settings.json' '.claude/./settings.json' 'src/../.agents/hooks.json' '.github//hooks/guard.json'; do
    assert_status 0 adapt copilot pre "$(copilot edit "{\"path\":\"$p\"}")"
    assert_eq "$(jfield permissionDecision)" deny "edit $p"
  done
  assert_status 2 adapt codex pre "$(codex_patch $'*** Begin Patch\n*** Update File: .claude//settings.json\n*** End Patch')"
  assert_status 0 adapt copilot pre "$(copilot edit '{"path":".github/workflows//ci.yml"}')"
  assert_eq "$(jfield permissionDecision)" ask
  assert_status 0 adapt antigravity pre "$(antigravity view_file '{"AbsolutePath":"/w/repo/./.env"}')"
  assert_eq "$(jfield decision)" deny
}

test_adapter_unknown_tools() {
  # R6: a tool the adapter does not know is still denied on a secret or deny-path argument.
  assert_status 0 adapt copilot pre "$(copilot glob '{"pattern":"**/.env*"}')"
  assert_eq "$(jfield permissionDecision)" deny 'glob for secrets'
  assert_status 0 adapt copilot pre "$(copilot grep '{"pattern":"KEY","path":"config/.env.local"}')"
  assert_eq "$(jfield permissionDecision)" deny 'grep in a secret file'
  assert_status 0 adapt copilot pre "$(copilot write '{"path":".github/hooks/guard.json"}')"
  assert_eq "$(jfield permissionDecision)" deny 'unknown write tool'
  assert_status 0 adapt antigravity pre "$(antigravity new_tool '{"Opts":{"Files":["/w/repo/.codex/rules/x.rules"]}}')"
  assert_eq "$(jfield decision)" deny 'nested argument'
  assert_status 2 adapt codex pre '{"tool_name":"mcp__fs__read","tool_input":{"path":"/home/u/.ssh/id_rsa"}}'
  assert_status 0 adapt copilot pre "$(copilot glob '{"pattern":"src/**/*.py"}')"
  assert_eq "$OUT" '' 'harmless unknown tool passes'
}

test_adapter_antigravity_pre() {
  # R6, R7: Antigravity always gets a decision, because the field is required.
  assert_status 0 adapt antigravity pre "$(antigravity run_command '{"CommandLine":"git commit -n -m x","Cwd":"/w"}')"
  assert_eq "$(jfield decision)" deny
  [[ -n $(jfield reason) ]] || fail 'deny needs a reason'
  assert_status 0 adapt antigravity pre "$(antigravity run_command '{"CommandLine":"git status"}')"
  assert_eq "$(jfield decision)" allow
  assert_status 0 adapt antigravity pre "$(antigravity run_command '{"CommandLine":"echo x > Makefile"}')"
  assert_eq "$(jfield decision)" ask
  local c
  for c in 'pip install x' 'python3 -m pip install x' 'uv sync' 'cargo add serde' 'go get x' 'yarn' 'pnpm i' 'sudo npm ci'; do
    assert_status 0 adapt antigravity pre "$(antigravity run_command "$(python3 -c 'import json,sys; print(json.dumps({"CommandLine": sys.argv[1]}))' "$c")")"
    assert_eq "$(jfield decision)" ask "package install: $c"
  done
  assert_status 0 adapt antigravity pre "$(antigravity write_to_file '{"TargetFile":"/w/repo/.agents/hooks.json","CodeContent":"{}"}')"
  assert_eq "$(jfield decision)" deny
  assert_status 0 adapt antigravity pre "$(antigravity replace_file_content '{"TargetFile":"/w/repo/.harness/tools.lock"}')"
  assert_eq "$(jfield decision)" ask
  assert_status 0 adapt antigravity pre "$(antigravity multi_replace_file_content '{"TargetFile":"/w/repo/.harness/check/deny-rules.sh"}')"
  assert_eq "$(jfield decision)" ask
  assert_status 0 adapt antigravity pre "$(antigravity view_file '{"AbsolutePath":"/home/u/.ssh/id_ed25519"}')"
  assert_eq "$(jfield decision)" deny
  assert_status 0 adapt antigravity pre "$(antigravity write_to_file '{"TargetFile":"/w/repo/src/a.py"}')"
  assert_eq "$(jfield decision)" allow
  assert_status 0 adapt antigravity pre '{not json'
  assert_eq "$(jfield decision)" deny 'bad input fails closed'
}

test_adapter_post_never_blocks() {
  # R7: fmt runs per edited path and never blocks.
  assert_status 0 adapt codex post "$(codex_patch $'*** Begin Patch\n*** Add File: a.md\n+x\n*** End Patch')"
  assert_status 0 adapt antigravity post "$(antigravity write_to_file '{"TargetFile":"a.md"}')"
  assert_eq "$OUT" '{}'
  assert_status 0 adapt codex post '{not json'
}

# adapter_stop_repo RECIPE: a committed repo whose `make check` runs RECIPE.
adapter_stop_repo() {
  local r; r=$(new_repo)
  printf 'check:\n\t@%s\n' "$1" > "$r/Makefile"
  git -C "$r" add -A
  git -C "$r" -c user.name=t -c user.email=t@t commit -qm init
  printf '%s\n' "$r"
}
stop_in() { (cd "$1" && "$ADAPTER" "$2" stop <<<"${3:-"{}"}"); }

test_adapter_stop() {
  # R7: the stop check runs make check on a dirty tree; a failure makes the agent go on.
  local r; r=$(adapter_stop_repo 'echo broken; exit 1')
  assert_status 0 stop_in "$r" codex
  assert_eq "$OUT" '{}' 'codex clean tree'
  assert_status 0 stop_in "$r" antigravity
  assert_eq "$(jfield decision)" allow
  echo dirty > "$r/new.txt"
  assert_status 2 stop_in "$r" codex
  assert_contains "$OUT" broken
  assert_status 0 stop_in "$r" codex '{"stop_hook_active": true}'
  assert_status 0 stop_in "$r" antigravity
  assert_eq "$(jfield decision)" continue
  assert_contains "$(jfield reason)" broken
}

test_adapter_usage() {
  # R7
  assert_status 2 "$ADAPTER" claude pre
  assert_status 2 "$ADAPTER" codex
}

test_adapter_broken_policy_fails_closed() {
  # R6: a broken policy.py denies every tool call.
  local h=$TEST_TMP/hooks
  cp -r "$HARNESS_ROOT/.harness/hooks" "$h"
  echo 'raise SystemExit(1)' > "$h/policy.py"
  OUT=$(codex_bash 'git status' | "$h/adapter.sh" codex pre 2>&1) && fail 'codex must be denied'
  assert_contains "$OUT" policy.py
  OUT=$(antigravity view_file '{"AbsolutePath":"/w/a.md"}' | "$h/adapter.sh" antigravity pre)
  assert_eq "$(jfield decision)" deny
}
