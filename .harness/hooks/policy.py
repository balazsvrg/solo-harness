"""R6 path rules, shared by guard-bash.sh and adapter.sh. Keep in sync with proposal R6.

Each pattern matches a path argument: a relative path, an absolute path or a
`key=path` word. A match on a folder name without a trailing part means the folder itself.
"""
import os
import re

_START = r"(^|/|=)"


class _PathRule:
    """A path regex that also tests the cleaned path, so `a//b`, `a/./b` and `x/../a` cannot slip past."""

    def __init__(self, pattern):
        self.pattern = pattern
        self._regex = re.compile(pattern)

    def search(self, path):
        return self._regex.search(path) or self._regex.search(os.path.normpath(path))


# R6 deny: editing an agent policy file or a git hook.
DENY_EDIT = _PathRule(_START + r"(\.claude/settings[^/]*\.json$|\.codex(/|$)|\.agents/hooks\.json$"
                       r"|\.github/hooks(/|$)|\.githooks(/|$))")

# R6 ask: editing these needs the owner's approval.
_ASK = r"Makefile$|CODEOWNERS$|\.github/workflows(/|$)|\.harness/tools\.lock$"
ASK_EDIT = _PathRule(_START + "(" + _ASK + r"|\.harness/hooks(/|$)|\.harness/check/deny-rules\.sh$)")

# Shell writes that guard-bash blocks: the deny paths, the hook scripts, the deny-rule check
# and the folders that hold them. An agent changes a hook script only with an edit tool, which asks.
SHELL_BLOCK = _PathRule(DENY_EDIT.pattern + "|" + _START + r"(\.claude/?$|\.agents/?$|\.harness/?$"
                         r"|\.harness/check/?$|\.harness/hooks(/|$)|\.harness/check/deny-rules\.sh$)")

# Shell writes that get an ask prompt, like the Edit(...) ask rules.
SHELL_ASK = _PathRule(_START + "(" + _ASK + r"|\.github/?$)")

# R6 ask: a package install. Matches the start of any command in a compound line.
_INSTALL = (r"npm\s+(install|i|add|ci)\b|pnpm\s+(install|i|add)\b|yarn(\s+(global\s+)?add\b|\s+install\b|\s*($|[;&|)]))"
            r"|pip3?\s+install\b|uv\s+(add|sync|pip\s+install|tool\s+install)\b|cargo\s+(add|install)\b|go\s+(get|install)\b")
PACKAGE_INSTALL = re.compile(r"(^|[;&|(]\s*)(sudo\s+)?(python3?\s+-m\s+)?(" + _INSTALL + ")", re.M)

# R6 deny: reading secrets.
SECRET = _PathRule(r"(^|/)\.env[^/]*$|(^|/)\.ssh(/|$)")
