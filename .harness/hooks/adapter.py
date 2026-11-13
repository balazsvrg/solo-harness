"""Hook adapter for Codex, Copilot and Antigravity (R6, R7). Run it through adapter.sh.

Usage: adapter.sh AGENT EVENT < hook-input.json
  AGENT: codex | copilot | antigravity
  EVENT: pre | post | stop (Copilot: pre only)

It turns the agent's hook input into the input of guard-bash.sh, fmt.sh or stop-check.sh,
checks file edits and reads against the R6 paths in policy.py, and prints the result in the
agent's own format. The rules are in specs/agent-configuration.md (R6, R7).
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
try:
    from policy import ASK_EDIT, DENY_EDIT, PACKAGE_INSTALL, SECRET
except BaseException:  # fail closed: a broken policy.py (even one that exits) must not let tool calls through
    ASK_EDIT = DENY_EDIT = PACKAGE_INSTALL = SECRET = None

EVENTS = {"codex": ("pre", "post", "stop"), "copilot": ("pre",), "antigravity": ("pre", "post", "stop")}
PATCH_PATH = re.compile(r"^\*\*\* (?:Add File|Update File|Delete File|Move to): (.+?)\s*$", re.M)
NO_ASK = " If you cannot get a prompt, stop and ask the owner to make this change."


def path_values(args):
    """Every non-empty string under a key that ends in "path" or "file" (TargetFile, AbsolutePath, path)."""
    if not isinstance(args, dict):
        return []
    return [v for k, v in args.items() if isinstance(v, str) and v and k.lower().endswith(("path", "file"))]


def strings(x):
    """Every non-empty string anywhere in a JSON value."""
    if isinstance(x, str):
        return [x] if x else []
    if isinstance(x, dict):
        x = list(x.values())
    return [s for v in x for s in strings(v)] if isinstance(x, list) else []


def normalize(agent, data):
    """Return (kind, value): ("shell", command), ("edit", paths), ("read", paths) or ("other", strings)."""
    if agent == "codex":
        name, args = data["tool_name"], data.get("tool_input") or {}
        if name == "Bash":
            return "shell", args["command"]
        if name == "apply_patch":
            return "edit", PATCH_PATH.findall(args["command"])
    elif agent == "copilot":
        name, args = data["toolName"], data.get("toolArgs")
        if isinstance(args, str):
            args = json.loads(args) if args.strip() else {}
        if name == "bash":
            return "shell", args["command"]
        if name in ("edit", "create"):
            return "edit", path_values(args)
        if name == "view":
            return "read", path_values(args)
    else:
        call = data["toolCall"]
        name, args = call["name"], call.get("args") or {}
        if name == "run_command":
            return "shell", args["CommandLine"]
        if name in ("write_to_file", "replace_file_content", "multi_replace_file_content"):
            return "edit", path_values(args)
        if name == "view_file":
            return "read", path_values(args)
    # A tool we do not know: we cannot tell its paths, so every argument string is a possible path.
    return "other", strings(args)


def run_hook(script, payload):
    env = dict(os.environ, CLAUDE_PROJECT_DIR=project_dir())
    return subprocess.run([os.path.join(HERE, script)], input=json.dumps(payload), capture_output=True,
                          text=True, env=env, check=False)


def project_dir():
    r = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=False)
    return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else os.getcwd()


def decide(kind, value, install_ask=True):
    """Return (decision, reason) with decision allow, ask or deny."""
    if DENY_EDIT is None:
        return "deny", "guard: cannot load .harness/hooks/policy.py"
    if kind == "shell":
        if not isinstance(value, str):
            return "deny", "guard: the shell command is not text"
        r = run_hook("guard-bash.sh", {"tool_input": {"command": value}})
        if r.returncode == 2:
            return "deny", r.stderr.strip()
        if r.returncode != 0:
            return "deny", "guard: guard-bash.sh failed"
        if r.stdout.strip():
            out = json.loads(r.stdout)["hookSpecificOutput"]
            return out["permissionDecision"], out["permissionDecisionReason"]
        # Claude asks through its settings and Codex through its rules; the others only through this hook.
        if install_ask and PACKAGE_INSTALL.search(value):
            return "ask", "guard: this command installs a package (R6 ask)"
        return "allow", ""
    if kind in ("edit", "read") and not value:
        return "deny", f"guard: cannot find the file path of this {kind}"
    if kind == "edit":
        for p in value:
            if DENY_EDIT.search(p):
                return "deny", f"guard: {p} is an agent policy file or git hook (R6 deny). The owner must change it."
        asks = [p for p in value if ASK_EDIT.search(p)]
        if asks:
            return "ask", "guard: this edit changes " + ", ".join(asks) + " (R6 ask path)"
    if kind == "read":
        for p in value:
            if SECRET.search(p):
                return "deny", f"guard: {p} holds secrets (R6 deny)."
    if kind == "other":
        for p in value:
            if SECRET.search(p) or DENY_EDIT.search(p):
                return "deny", f"guard: unknown tool with argument {p}, a secret or agent policy path (R6 deny)."
    return "allow", ""


def pre(agent, raw):
    try:
        decision, reason = decide(*normalize(agent, json.loads(raw)), install_ask=agent != "codex")
    except Exception:
        decision, reason = "deny", "guard: cannot read the hook input"
    if agent == "codex":
        if decision == "allow":
            return 0
        print(reason + (NO_ASK if decision == "ask" else ""), file=sys.stderr)
        return 2
    if agent == "copilot":
        # The cloud agent turns "ask" into deny, so the reason says what to do then.
        if decision != "allow":
            print(json.dumps({"permissionDecision": decision,
                              "permissionDecisionReason": reason + (NO_ASK if decision == "ask" else "")}))
        return 0
    out = {"decision": decision}
    if reason:
        out["reason"] = reason
    print(json.dumps(out))
    return 0


def post(agent, raw):
    try:
        kind, paths = normalize(agent, json.loads(raw))
        for p in paths if kind == "edit" else []:
            run_hook("fmt.sh", {"tool_input": {"file_path": p}})
    except Exception:
        pass
    if agent == "antigravity":
        print("{}")
    return 0


def stop(agent, raw):
    try:
        active = agent == "codex" and bool(json.loads(raw).get("stop_hook_active"))
    except Exception:
        active = False
    r = run_hook("stop-check.sh", {"stop_hook_active": active})
    failed = r.returncode == 2
    if agent == "codex":
        if failed:
            print(r.stderr, end="", file=sys.stderr)
            return 2
        print("{}")
        return 0
    print(json.dumps({"decision": "continue", "reason": r.stderr.strip()} if failed else {"decision": "allow"}))
    return 0


def main(argv):
    if len(argv) != 2 or argv[1] not in EVENTS.get(argv[0], ()):
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    agent, event = argv
    return {"pre": pre, "post": post, "stop": stop}[event](agent, sys.stdin.read())


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
