# shellcheck shell=bash
# Tests for .claude/hooks/fmt.sh (R7).

fmt_hook() { echo '{"tool_input":{"file_path":"x.md"}}' | CLAUDE_PROJECT_DIR=$1 "$HARNESS_ROOT/.claude/hooks/fmt.sh"; }

test_fmt_hook_silent_noop() {
  # AC-1-36
  assert_status 0 fmt_hook "$HARNESS_ROOT"
  assert_eq "$OUT" '' 'silent'
  local r; r=$(new_repo)
  printf 'fmt:\n\t@echo broken; exit 1\n' > "$r/Makefile"
  assert_status 0 fmt_hook "$r"
  assert_eq "$OUT" '' 'never blocks, even when fmt fails'
}
