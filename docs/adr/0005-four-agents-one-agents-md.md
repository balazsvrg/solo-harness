# Four agents from one `AGENTS.md` and one skills directory

The template supports Claude Code, Codex CLI, GitHub Copilot and Antigravity CLI. All four read `AGENTS.md` (`CLAUDE.md` is a symlink) and `.agents/skills/` (`.claude/skills` and `.github/skills` are symlinks), so the guidance is written once. Each agent gets the shared permission policy and hooks in its native format. The hook scripts live in `.harness/hooks/`, and one adapter translates for Codex, Copilot and Antigravity. Bootstrap asks which agents a project uses and deletes the configs of the rest; `--add-agent` brings one back from the template repo.

Antigravity CLI is the fourth agent instead of Gemini CLI. Google replaced Gemini CLI with Antigravity CLI for unpaid accounts, and the project-level policy tier of Gemini CLI does not work.

## Consequences

Agents differ in what the repo can enforce. Copilot and Antigravity keep no permission rules in the repo, so their before-tool hook is the only in-repo layer. Codex hooks cannot ask, so ask paths become deny. Git hooks, CI and the ruleset cover these gaps.
