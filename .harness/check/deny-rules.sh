#!/usr/bin/env bash
# AC-1-12: the Claude policy file contains every R6 deny rule. T5 adds the other agents.
# Usage: deny-rules.sh [ROOT]   check ROOT (default: the repo root)
#        deny-rules.sh --list   print the required Claude rules
# A missing policy file is fine: bootstrap deletes the files of agents the owner does not use.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
list=0
if [[ ${1:-} == --list ]]; then list=1; shift; fi
root=${1:-$(repo_root)}

# R6 deny rules in Claude Code syntax. Keep in sync with proposal R6.
claude_deny=(
  'Bash(git push * main)' 'Bash(git push * main *)' 'Bash(git push *:main)' 'Bash(git push *:main *)'
  'Bash(git push --force*)' 'Bash(git push * --force*)' 'Bash(git push -f*)' 'Bash(git push * -f*)'
  'Bash(gh pr merge)' 'Bash(gh pr merge *)' 'Bash(gh release create *)'
  'Bash(git commit --no-verify*)' 'Bash(git commit * --no-verify*)'
  'Read(./.env*)' 'Read(**/.env*)' 'Read(~/.ssh/**)'
  'Edit(./.claude/settings*.json)' 'Edit(./.codex/**)' 'Edit(./.gemini/**)' 'Edit(./.githooks/**)'
)

if (( list )); then printf '%s\n' "${claude_deny[@]}"; exit 0; fi

f=$root/.claude/settings.json
[[ -f $f ]] || exit 0
python3 - "$f" "${claude_deny[@]}" <<'PY'
import json, sys
path, want = sys.argv[1], sys.argv[2:]
try:
    deny = json.load(open(path))["permissions"]["deny"]
except Exception as e:
    sys.exit(f"error: .claude/settings.json: cannot read permissions.deny ({e})")
missing = [r for r in want if r not in deny]
for r in missing:
    print(f"error: .claude/settings.json: missing deny rule {r}", file=sys.stderr)
sys.exit(1 if missing else 0)
PY
