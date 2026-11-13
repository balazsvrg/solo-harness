#!/usr/bin/env bash
# AC-1-12: the Claude and Codex policy files contain every R6 rule that they can express,
# and the hook file of Codex, Copilot and Antigravity sends the before-tool event to the adapter.
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
  'Edit(./.claude/settings*.json)' 'Edit(./.codex/**)' 'Edit(./.agents/hooks.json)' 'Edit(./.github/hooks/**)'
  'Edit(./.githooks/**)'
)

# R6 rules in Codex prefix_rule syntax: "decision|pattern" with the pattern as written in the file.
codex_rules=(
  'forbidden|["git", "push", ["--force", "--force-with-lease", "--force-if-includes", "-f"]]'
  'forbidden|["git", "push", "origin", ["main", "HEAD:main"]]'
  'forbidden|["git", "commit", ["--no-verify", "-n"]]'
  'forbidden|["gh", "pr", "merge"]'
  'forbidden|["gh", "release", "create"]'
  'prompt|[["npm", "pnpm", "yarn"], ["install", "i", "add", "ci"]]'
  'prompt|[["pip", "pip3", "uv", "cargo", "go"], ["install", "add", "get", "sync"]]'
)

if (( list )); then printf '%s\n' "${claude_deny[@]}"; exit 0; fi

rc=0
f=$root/.claude/settings.json
if [[ -f $f ]]; then
  python3 - "$f" "${claude_deny[@]}" <<'PY' || rc=1
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
fi

# Codex: each rule is one prefix_rule(...) block with its pattern and decision.
f=$root/.codex/rules/default.rules
if [[ -f $f ]]; then
  python3 - "$f" "${codex_rules[@]}" <<'PY' || rc=1
import re, sys
path, want = sys.argv[1], sys.argv[2:]
blocks = re.findall(r"prefix_rule\((.*?)\n\)", open(path).read(), re.S)
found = {}
for b in blocks:
    p = re.search(r"^\s*pattern = (.*),\s*$", b, re.M)
    d = re.search(r"^\s*decision = \"(\w+)\"", b, re.M)
    if p:
        found[p.group(1)] = d.group(1) if d else "allow"
bad = 0
for w in want:
    decision, pattern = w.split("|", 1)
    if found.get(pattern) != decision:
        print(f"error: .codex/rules/default.rules: needs a {decision} rule with pattern = {pattern}", file=sys.stderr)
        bad = 1
sys.exit(bad)
PY
fi

# Hook files: the before-tool event of each agent runs the adapter.
python3 - "$root" <<'PY' || rc=1
import json, os, sys
root = sys.argv[1]
def commands(groups, key):
    return [h.get(key, "") for g in groups for h in g.get("hooks", [g])]
# hook file -> (agent, the commands of its before-tool event)
hook_files = {
    ".codex/hooks.json": ("codex", lambda d: commands(d["hooks"]["PreToolUse"], "command")),
    ".agents/hooks.json": ("antigravity",
                           lambda d: [c for v in d.values() for c in commands(v.get("PreToolUse", []), "command")]),
    ".github/hooks/guard.json": ("copilot", lambda d: [h.get("bash", "") for h in d["hooks"]["preToolUse"]]),
}
bad = 0
for rel, (agent, get) in hook_files.items():
    path = os.path.join(root, rel)
    if not os.path.isfile(path):
        continue
    want = ".harness/hooks/adapter.sh " + agent + " pre"
    try:
        ok = any(want in c.replace(chr(34), "") for c in get(json.load(open(path))))
    except Exception:
        ok = False
    if not ok:
        print(f"error: {rel}: the before-tool hook must run .harness/hooks/adapter.sh {agent} pre", file=sys.stderr)
        bad = 1
sys.exit(bad)
PY
exit $rc
