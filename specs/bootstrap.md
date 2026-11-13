# Bootstrap

## `scripts/bootstrap` (R18)

`scripts/bootstrap` is idempotent bash. Each step checks state before it acts. Steps:

1. Ask the project name; replace placeholders.
2. Ask which agents are used (multi-select of Claude, Codex, Copilot, Antigravity); delete the configs of the rest.
3. Ask whether agents should stop adding AI attribution (`Co-Authored-By: Claude …` trailers, "Generated with" lines) to commits and PRs. Default: keep. On yes, turn attribution off in each selected agent's project config where the agent has such a setting (Claude Code: `.claude/settings.json`). Tell the owner which agents have no such setting. The template repo keeps attribution.
4. Set repo options via `gh api`: squash-only, delete branch on merge, PR title as the squash commit title and the list of commits as the squash commit message.
5. Create labels: `size/S`, `size/M`, `size/L`, `size-exception`, `agent`, `dependencies`.
6. Apply the ruleset; detect strict or honor mode (see `verification.md`). On public repos, enable CodeQL, secret-scanning push protection and the dependency graph (through Dependabot alerts; the `deps` check needs it).
7. Run `git config core.hooksPath .githooks`; check that gitleaks is installed.
8. Detect globally installed Claude plugins whose skills duplicate vendored ones (for example `mattpocock-skills`). Disable them in the new project's `.claude/settings.json` and tell the owner what it did. The template repo itself disables nothing.
9. Guide human-only steps (for example secrets and hook trust) in the `wizard` style.
10. Write `.template-version`; reset `version.txt` and `CHANGELOG.md`; delete the template-only paths listed in `.template-only` (the archived bootstrap change folder and the template-only tests) and the README sections between the template-only markers.
11. Print a summary. It includes a prominent **"next: configure `check-app`"** notice that names the Makefile target, explains that it fails once source code exists, and points to the README's overlay section. It also mentions `.docs-map` and suggests running the lifecycle on the first change.

Flags: `--template` (template mode: GitHub steps only), `--dry-run` (print every action and `gh api` call, change nothing), `--local` (skip all GitHub steps), `--add-agent <name>` (copy that agent's files from the template repo, at the tag of the version in `.template-version`; it cannot run with `--template` or `--local`).

```mermaid
flowchart TD
  A[scripts/bootstrap] --> M{flags}
  M -- --add-agent --> F[copy the agent files from the template repo] --> AA[steps 3, 8, 9] --> S
  M -- --template --> G1[GitHub steps 4-6] --> H1[human steps 9] --> S
  M -- default or --local --> L[steps 1-3] --> Q{--local?}
  Q -- no --> G2[GitHub steps 4-6] --> R
  Q -- yes --> R[steps 7-8] --> H2[human steps 9] --> T[template files 10] --> S
  S[summary 11]
```

- **AC-1-27** GIVEN `--dry-run --local` WHEN run twice on a temp copy THEN the second run reports no changes.
- **AC-1-28** GIVEN agent selection `claude` only THEN Codex, Copilot and Antigravity files are removed and all remaining symlinks resolve. Repeat for each single agent and for all four.
- **AC-1-29** GIVEN `--dry-run` THEN every GitHub step prints its `gh api` call and makes no network write.
- **AC-1-34** GIVEN a placeholder `check-app` WHEN bootstrap finishes THEN its output contains the "configure `check-app`" notice. GIVEN a filled `check-app` THEN the notice is absent.
- **AC-1-40** GIVEN agent selection `claude` and the answer "remove attribution" THEN the project's `.claude/settings.json` turns off commit and PR attribution. GIVEN the default answer, or template mode, THEN no attribution setting is written.
- **AC-1-30** `make test-bootstrap` runs AC-1-27…29, AC-1-34 and AC-1-40 in plain bash and is part of `check-harness`.
