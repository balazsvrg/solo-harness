# shellcheck shell=bash
# Tests for repository layout and AGENTS.md (R1).

check() { "$HARNESS_ROOT/.harness/check/$1.sh" "${@:2}"; }

test_symlinks_resolve() {
  # AC-1-1
  [[ $(readlink "$HARNESS_ROOT/CLAUDE.md") == AGENTS.md ]] || fail 'CLAUDE.md -> AGENTS.md'
  [[ $(readlink "$HARNESS_ROOT/.github/skills") == ../.agents/skills ]] || fail '.github/skills -> ../.agents/skills'
  # R5: Antigravity reads AGENTS.md, so no GEMINI.md and no .gemini/.
  assert_no_file "$HARNESS_ROOT/GEMINI.md"
  [[ ! -e $HARNESS_ROOT/.gemini ]] || fail '.gemini/ must not exist'
  assert_status 0 check symlinks "$HARNESS_ROOT"
  local r; r=$(new_repo)
  ln -s missing.md "$r/CLAUDE.md"
  assert_status 1 check symlinks "$r"
  assert_contains "$OUT" CLAUDE.md
}

test_agents_md_length() {
  # AC-1-2
  local r; r=$(new_repo)
  cp "$HARNESS_ROOT/AGENTS.md" "$r/"
  assert_status 0 check agents-md "$r"
  while (( $(wc -l < "$r/AGENTS.md") <= 60 )); do echo filler >> "$r/AGENTS.md"; done
  assert_status 1 check agents-md "$r"
  assert_contains "$OUT" '60'
}

test_agents_md_content() {
  # AC-1-3
  assert_status 0 check agents-md "$HARNESS_ROOT"
  local r; r=$(new_repo)
  grep -v 'make check' "$HARNESS_ROOT/AGENTS.md" > "$r/AGENTS.md"
  assert_status 1 check agents-md "$r"
  assert_contains "$OUT" 'make check'
  { cat "$HARNESS_ROOT/AGENTS.md"; echo 'You MUST read this.'; } > "$r/AGENTS.md"
  assert_status 1 check agents-md "$r"
  assert_contains "$OUT" 'MUST'
  grep -v 'S/M/L' "$HARNESS_ROOT/AGENTS.md" > "$r/AGENTS.md"
  assert_status 1 check agents-md "$r"
  grep -v '.agents/skills' "$HARNESS_ROOT/AGENTS.md" > "$r/AGENTS.md"
  assert_status 1 check agents-md "$r"
}

test_model_advice_and_no_pin() {
  # AC-1-4
  local r; r=$(new_repo)
  grep -v 'strongest model' "$HARNESS_ROOT/AGENTS.md" > "$r/AGENTS.md"
  assert_status 1 check agents-md "$r"
  cp "$HARNESS_ROOT/AGENTS.md" "$r/"
  mkdir -p "$r/.claude/agents" "$r/.codex" "$r/.github/agents"
  echo '{"model": "opus"}' > "$r/.claude/settings.json"
  assert_status 1 check agents-md "$r"
  assert_contains "$OUT" .claude/settings.json
  echo '{}' > "$r/.claude/settings.json"
  printf -- '---\nname: x\nmodel: opus\n---\n' > "$r/.claude/agents/x.md"
  assert_status 1 check agents-md "$r"
  rm "$r/.claude/agents/x.md"
  echo 'model = "o3"' > "$r/.codex/config.toml"
  assert_status 1 check agents-md "$r"
  rm "$r/.codex/config.toml"
  printf -- '---\nmodel: gpt\n---\n' > "$r/.github/agents/r.agent.md"
  assert_status 1 check agents-md "$r"
  rm "$r/.github/agents/r.agent.md"
  assert_status 0 check agents-md "$r"
}

test_change_folders() {
  # Change-folder structure lint (R10).
  assert_status 0 check change-folders "$HARNESS_ROOT"
  local r; r=$(new_repo)
  mkdir -p "$r/specs/changes/7-foo"
  touch "$r/specs/changes/7-foo/proposal.md"
  assert_status 1 check change-folders "$r"
  assert_contains "$OUT" tasks.md
  touch "$r/specs/changes/7-foo/tasks.md"
  assert_status 0 check change-folders "$r"
  echo '- **Size:** L' > "$r/specs/changes/7-foo/proposal.md"
  assert_status 1 check change-folders "$r"
  assert_contains "$OUT" design.md
  mkdir -p "$r/specs/changes/Bad_Name"
  touch "$r/specs/changes/7-foo/design.md"
  assert_status 1 check change-folders "$r"
  assert_contains "$OUT" Bad_Name
}

test_agents_md_code_review_rule() {
  # AC-1-41
  assert_status 0 check agents-md "$HARNESS_ROOT"
  local r; r=$(new_repo)
  grep -v 'Never skip it' "$HARNESS_ROOT/AGENTS.md" > "$r/AGENTS.md"
  assert_status 1 check agents-md "$r"
  assert_contains "$OUT" 'Never skip it'
}
