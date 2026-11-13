#!/usr/bin/env bash
# PreToolUse(Bash) hook: fail-closed backstop for commands that the prefix deny
# rules in .claude/settings.json miss (R6, R7). Blocks with exit 2 and a
# one-line reason on stderr. A shell write to an R6 ask path prints an "ask"
# permission decision as JSON on stdout. Silent otherwise.
#
# Derived from mattpocock/skills git-guardrails-claude-code (MIT); see
# .agents/skills/VENDORED.md. Changes: python3 parser instead of jq and grep;
# splits compound commands and unwraps wrappers, `bash -c` and command
# substitution; plain `git push` to a feature branch is allowed; adds the R6 and
# AC-1-35 cases. The rules and limits are in specs/agent-configuration.md
# (R6, R7, "Guard limits").
set -uo pipefail

# shellcheck disable=SC2016 # the Python program is literal text
exec python3 -c '
import json, os, re, shlex, sys

def block(reason):
    print("Blocked by guard-bash: " + reason + ". The owner must run this.", file=sys.stderr)
    sys.exit(2)

try:
    sys.path.insert(0, sys.argv[1])
    from policy import SHELL_BLOCK as PROTECTED, SHELL_ASK as ASK_PATHS, SECRET
except BaseException:
    block("cannot load policy.py")

try:
    cmd = json.load(sys.stdin)["tool_input"]["command"]
    assert isinstance(cmd, str)
except Exception:
    block("cannot read the hook input")

# Wrapper commands that run another command, and the options of each that take a value.
WRAPPERS = {
    "env": {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"},
    "sudo": {"-u", "--user", "-g", "--group", "-h", "--host", "-p", "--prompt", "-C", "-D", "--chdir", "-U", "-r", "-t"},
    "nice": {"-n", "--adjustment"},
    "timeout": {"-s", "--signal", "-k", "--kill-after"},
    "xargs": {"-I", "-i", "-n", "-P", "-L", "-l", "-d", "-E", "-e", "-s", "-a"},
    "command": set(), "nohup": set(), "time": set(), "exec": {"-a"}, "stdbuf": {"-i", "-o", "-e"},
}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh", "fish"}
# Shell keywords that can start a segment in front of the real command.
KEYWORDS = {"{", "}", "!", "if", "then", "else", "elif", "do", "while", "until", "fi", "done"}
REDIRECTS = {">", ">>", ">|", "&>", "&>>"}
# PROTECTED (shell writes blocked), ASK_PATHS (shell writes asked) and SECRET come from policy.py.
ASKS = []
WRITERS = {"sed", "perl", "tee", "mv", "cp", "rm", "ln", "chmod", "truncate", "install", "dd", "patch"}
DQ, SQ, BT = chr(34), chr(39), chr(96)  # double quote, single quote, backtick

def longopt(a, full, minlen):
    """Git accepts any unique prefix of a long option, for example --no-veri for --no-verify."""
    name = a.split("=")[0]
    return len(name) >= minlen and full.startswith(name)

def prepare(text):
    """Quote-aware pass over the raw text. Drops comments and heredoc bodies (data, not code)
    and turns unquoted newlines and backticks into command separators."""
    out, i, n, quote, pending = [], 0, len(text), None, []
    while i < n:
        c = text[i]
        if quote:
            out.append(c)
            if c == "\\" and quote == DQ and i + 1 < n:
                out.append(text[i + 1]); i += 2; continue
            if c == quote:
                quote = None
            i += 1; continue
        if c == "\\" and i + 1 < n:
            out.append(text[i:i + 2]); i += 2; continue
        if c in (DQ, SQ):
            quote = c; out.append(c); i += 1; continue
        if c == BT:
            out.append(" ; "); i += 1; continue
        if c == "#" and (i == 0 or text[i - 1] in " \t\n;&|()"):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if text.startswith("<<", i) and not text.startswith("<<<", i):
            j, tabs = i + 2, False
            if j < n and text[j] == "-":
                tabs, j = True, j + 1
            while j < n and text[j] in " \t":
                j += 1
            m = re.match(DQ + "[^" + DQ + "\\n]*" + DQ + "|" + SQ + "[^" + SQ + "\\n]*" + SQ + "|[^\\s;&|()<>]+", text[j:])
            if m:
                pending.append((m.group(0).replace(DQ, "").replace(SQ, "").replace("\\", ""), tabs))
                out.append(" < /dev/null ")
                i = j + len(m.group(0)); continue
        if c == "\n":
            out.append(" ; "); i += 1
            for delim, tabs in pending:
                while i < n:
                    j = text.find("\n", i)
                    j = n if j < 0 else j
                    line, i = text[i:j], j + 1
                    if (line.lstrip("\t") if tabs else line) == delim:
                        break
            pending = []
            continue
        out.append(c); i += 1
    return "".join(out)

def tokens(text):
    lex = shlex.shlex(prepare(text), posix=True, punctuation_chars=";&|()<>")
    lex.whitespace_split = True
    lex.commenters = ""
    try:
        return list(lex)
    except ValueError:
        block("cannot parse the command")

def is_op(t):
    """A control operator: ; & && || | |& ( ) <( >( and runs of them. Redirects are not operators."""
    return t not in REDIRECTS and all(c in ";&|()<>" for c in t) and (any(c in t for c in ";|()") or t in ("&", "&&"))

def pipelines(toks):
    """Yield lists of segments; segments joined by | form one pipeline."""
    pipe, seg = [], []
    for t in toks:
        if t in ("|", "|&"):
            pipe.append(seg); seg = []
        elif is_op(t):
            pipe.append(seg); yield pipe; pipe, seg = [], []
        else:
            seg.append(t)
    pipe.append(seg); yield pipe

def strip(seg):
    """Drop leading VAR=value words, shell keywords, `function NAME` and wrapper commands with their options."""
    i = 0
    while i < len(seg):
        w = seg[i]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w):
            if "hookspath" in w.lower():
                block("a core.hooksPath variable skips the git hooks")
            i += 1; continue
        if w in KEYWORDS:
            i += 1; continue
        if w == "function":
            i += 2; continue
        name = os.path.basename(w)
        if name not in WRAPPERS:
            break
        i += 1
        while i < len(seg) and seg[i].startswith("-") and seg[i] != "--":
            i += 2 if seg[i] in WRAPPERS[name] else 1
        if i < len(seg) and seg[i] == "--":
            i += 1
        if name == "timeout" and i < len(seg):
            i += 1  # the DURATION argument
    return seg[i:]

def substitutions(word):
    """Yield the text of each $(...) and backtick command inside one word."""
    i = 0
    while True:
        i = word.find("$(", i)
        if i < 0:
            break
        depth, j = 1, i + 2
        while j < len(word) and depth:
            depth += {"(": 1, ")": -1}.get(word[j], 0)
            j += 1
        yield word[i + 2:j - 1]
        i = j
    yield from re.findall(BT + "([^" + BT + "]*)" + BT, word)

def current_branch():
    return os.popen("git branch --show-current 2>/dev/null").read().strip()

def git_sub(args):
    """Return (global options, subcommand, its args) for a git argv tail."""
    i, opts = 0, []
    while i < len(args) and args[i].startswith("-"):
        opts.append(args[i])
        if args[i] in ("-c", "-C") and i + 1 < len(args):
            opts.append(args[i + 1]); i += 1
        i += 1
    return opts, (args[i] if i < len(args) else ""), args[i + 1:]

def check_push(rest):
    flags, refs, repo, i = [], [], False, 0
    while i < len(rest):
        a = rest[i]
        if a in ("-o", "--push-option", "--receive-pack", "--exec") or (longopt(a, "--repo", 5) and "=" not in a):
            repo = repo or longopt(a, "--repo", 5)
            i += 2; continue
        repo = repo or longopt(a, "--repo", 5)
        (flags if a.startswith("-") else refs).append(a)
        i += 1
    dests = refs if repo else refs[1:]  # without --repo, the first word is the remote
    if any(re.match(r"^-[a-zA-Z]*f", f) or f.startswith("--force") or longopt(f, "--force", 4) for f in flags) \
            or any(r.startswith("+") for r in dests):
        block("force push")
    if any(longopt(f, "--no-verify", 6) for f in flags):
        block("git push --no-verify skips the git hooks")
    if any(longopt(f, o, 4) for f in flags for o in ("--mirror", "--all", "--branches")):
        block("git push --mirror or --all can update main")
    for r in dests:
        dest = r.split(":")[-1]
        if dest in ("HEAD", "@", ""):
            dest = current_branch()
        if re.sub(r"^(refs/)?(heads/)?", "", dest) == "main":
            block("push to main")
    if not dests and current_branch() == "main":
        block("push from main")

def check_commit(rest):
    # Options that take a value: their value (a message, a file) is not a flag.
    valued = {"-m", "-F", "-C", "-c", "-t", "--message", "--file", "--author", "--date", "--template",
              "--reuse-message", "--reedit-message", "--fixup", "--squash", "--trailer"}
    skip = False
    for a in rest:
        if skip:
            skip = False
        elif longopt(a, "--no-verify", 6):
            block("git commit --no-verify skips the git hooks")
        elif re.match(r"^-[a-zA-Z]+$", a):
            if "n" in a[1:].split("m")[0].split("F")[0]:
                block("git commit -n skips the git hooks")
            skip = a in valued or a[-1] in "mFCct"
        elif a in valued:
            skip = True

CONFIG_READS = {"--get", "--get-all", "--get-regexp", "--list", "-l"}
CONFIG_VALUED = {"-f", "--file", "--blob", "--type", "--default", "--comment"}

def config_keeps_hooks(rest):
    # True for a read of core.hooksPath, or a write that sets it to exactly .githooks.
    words, flags, skip = [], set(), False
    for a in rest:
        if skip:
            skip = False
        elif a.startswith("-"):
            flags.add(a.split("=")[0].lower())
            skip = a in CONFIG_VALUED
        else:
            words.append(a)
    if words[:1] == ["unset"] or any(f.startswith("--unset") for f in flags):
        return False
    if words[:1] in (["get"], ["list"]) or CONFIG_READS & flags:
        return True
    if words[:1] == ["set"]:
        words = words[1:]
    # A key alone is a read. A key and a value is a write. A third word is a value pattern.
    return len(words) == 1 or words[1:] == [".githooks"]

def check_git(args):
    opts, sub, rest = git_sub(args)
    if any("hookspath" in o.lower() for o in opts):
        block("git -c core.hooksPath skips the git hooks")
    if sub == "config" and any("hookspath" in a.lower() for a in rest) and not config_keeps_hooks(rest):
        block("changing core.hooksPath skips the git hooks")
    if sub == "push":
        check_push(rest)
    if sub == "commit":
        check_commit(rest)
    shorts = "".join(a[1:] for a in rest if re.match(r"^-[a-zA-Z]+$", a))
    has = lambda full, minlen: any(longopt(a, full, minlen) for a in rest)
    if sub == "reset" and has("--hard", 4):
        block("git reset --hard discards work")
    if sub == "clean" and ("f" in shorts or has("--force", 3)):
        block("git clean -f deletes files")
    if sub == "branch" and ("D" in shorts or ("d" in shorts or has("--delete", 4)) and ("f" in shorts or has("--force", 4))):
        block("git branch -D deletes unmerged work")
    if sub == "checkout" and "." in rest:
        block("git checkout . discards work")
    unstage_only = (has("--staged", 4) or "S" in shorts) and not (has("--worktree", 4) or "W" in shorts)
    if sub == "restore" and "." in rest and not unstage_only:
        block("git restore . discards work")
    if sub in ("checkout", "restore", "rm", "mv"):
        if any(PROTECTED.search(a) for a in rest):
            block("changing an agent policy file or git hook")
        ASKS.extend(a for a in rest if ASK_PATHS.search(a))

def check_gh(args):
    # Drop the global repository option so that the subcommand comes first.
    out, i = [], 0
    while i < len(args):
        if args[i] in ("-R", "--repo"):
            i += 2; continue
        if not args[i].startswith("--repo="):
            out.append(args[i])
        i += 1
    args = out
    if args[:2] == ["pr", "merge"]:
        block("only the owner merges")
    if args[:2] == ["release", "create"]:
        block("only the owner releases")
    if args[:1] == ["api"] and any(re.search(r"/merges?/?$", a.split("?")[0]) or
                                   re.search(r"mergePullRequest|enablePullRequestAutoMerge|mergeBranch", a)
                                   for a in args[1:]):
        block("only the owner merges")

def check_segment(seg, depth):
    """Check one simple command. SEG is already stripped."""
    if not seg:
        return
    prog, args = os.path.basename(seg[0]), seg[1:]
    for i, a in enumerate(seg):
        for sub in substitutions(a):
            run(sub, depth + 1)
        if a in REDIRECTS and i + 1 < len(seg):
            if PROTECTED.search(seg[i + 1]):
                block("writing to an agent policy file or git hook")
            if ASK_PATHS.search(seg[i + 1]):
                ASKS.append(seg[i + 1])
        if SECRET.search(a.lstrip("<>")):
            block("reading secrets (.env or ~/.ssh)")
    writes = prog in WRITERS and (prog not in ("sed", "perl") or
                                  any(re.match(r"^-[a-zA-Z]*i", a) or a.startswith("--in-place") for a in args))
    if writes and any(PROTECTED.search(a) for a in args):
        block("changing an agent policy file or git hook")
    if writes:
        ASKS.extend(a for a in args if ASK_PATHS.search(a))
    if prog == "eval":
        run(" ".join(args), depth + 1)
    if prog in SHELLS:
        # -c may sit in a cluster (bash -lc, sh -xc) and may be followed by --. The next argument is the script.
        for k, a in enumerate(args):
            if re.match(r"^-[a-zA-Z]*c[a-zA-Z]*$", a):
                rest = args[k + 1:]
                if rest[:1] == ["--"]:
                    rest = rest[1:]
                if rest:
                    run(rest[0], depth + 1)
                break
    if prog == "git":
        check_git(args)
    if prog == "gh":
        check_gh(args)

def run(text, depth=0):
    if depth > 3:
        block("too many nested shells")
    for pipe in pipelines(tokens(text)):
        segs = [strip(s) for s in pipe]
        for k, seg in enumerate(segs):
            check_segment(seg, depth)
            prog = os.path.basename((seg or [""])[0])
            if k and prog in SHELLS and "-c" not in seg and os.path.basename((segs[k - 1] or [""])[0]) in ("curl", "wget"):
                block("piping a download into a shell")

run(cmd)
if ASKS:
    # Not blocked, but it writes an R6 ask path: let the owner decide.
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "ask",
        "permissionDecisionReason": "guard-bash: this command changes " + ", ".join(sorted(set(ASKS))) + " (R6 ask path)",
    }}))
' "$(dirname "$0")"
