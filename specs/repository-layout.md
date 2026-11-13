# Repository layout and agent guidance

The repo has one canonical layout. Every agent reads one `AGENTS.md` and one skills directory.

## Canonical layout (R1)

The repo contains:

```
AGENTS.md                      # canonical, at most 60 lines
CLAUDE.md -> AGENTS.md
.agents/skills/<name>/SKILL.md # single canonical skills directory
.agents/skills/VENDORED.md
.claude/{settings.json,agents/reviewer.md}   .claude/skills -> ../.agents/skills
.agents/hooks.json             # Antigravity hooks
.codex/{hooks.json,rules/}     # Codex hooks and command rules
.github/{copilot-instructions.md,agents/,hooks/,skills -> ../.agents/skills}
.github/{workflows/,ISSUE_TEMPLATE/,PULL_REQUEST_TEMPLATE.md,dependabot.yml,ruleset.json}
.githooks/{pre-commit,commit-msg}
docs/{product.md,architecture.md,adr/}   GLOSSARY.md
specs/<capability>.md   specs/changes/<id>-<slug>/   specs/changes/archive/
.harness/                      # harness internals: config, checks, CI gate scripts, agent hooks, own tests
scripts/{bootstrap,install-tools,vendor-diff}   Makefile   .docs-map   version.txt   CHANGELOG.md
release-please-config.json   .release-please-manifest.json
LICENSE (MIT)   THIRD_PARTY_LICENSES.md   README.md
```

`<id>` is the GitHub issue number of the change. A change folder holds `proposal.md`, `tasks.md` and, for a Size L change, `design.md`. `finish` moves it to `specs/changes/archive/YYYY-MM-DD-<id>-<slug>/`.

- **AC-1-1** GIVEN a fresh clone WHEN `make check-harness` runs THEN every symlink above resolves to an existing target.

## Change sizes

| Size | Definition | Path |
|---|---|---|
| **S** | No new or changed requirement: bugfix against existing spec, chore, refactor, docs, dependency bump | (optional issue) → `implement` + `tdd` → `code-review` → PR |
| **M** | New or changed behaviour inside one capability | issue → `grill-with-docs` → `to-spec` → owner approves proposal → `to-tickets` → owner approves tasks → `handoff` → fresh session `implement` (+ `tdd`) → `code-review` → `finish` → `pr` |
| **L** | Spans capabilities, or makes an architectural or hard-to-reverse choice | As M, plus `design.md` and an expected ADR |

The agent proposes the size. The owner confirms it.

## `AGENTS.md`

- **AC-1-2** GIVEN `AGENTS.md` WHEN `check-harness` runs THEN it fails if the file exceeds 60 lines.
- **AC-1-3** `AGENTS.md` names `make check` as the verification command, describes S/M/L, and points to the skills. It contains no ALL-CAPS emphasis.
- **AC-1-41** `AGENTS.md` says to run `code-review` once at the end of every ticket and before every PR, never to skip it, and not to repeat it unless the owner asks.
- **AC-1-4** `AGENTS.md` suggests "plan with the strongest model, implement with the default" as advice. No agent config pins a model.
