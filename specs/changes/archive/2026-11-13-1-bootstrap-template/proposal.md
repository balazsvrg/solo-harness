# Change 1: Bootstrap the `solo-harness` template

- **Issue:** #1 (to be created when the GitHub repo exists)
- **Size:** L
- **Status:** proposed — awaiting owner approval
- **Source research:** `~/Projects/ai_native_sdlc_research/reports/AI driven SDLC for solo developers.md` (kept outside this repo)

## Problem statement

I am a solo developer on a Claude Pro plan and GitHub Free. I want to start future projects from a repo that already contains an AI-native development process: agents work from short specs in small, test-first steps, every merge passes deterministic gates, and documentation stays current. Today each project starts from nothing, so the process lives in my head and in prompts, and prompts are advisory. The research shows that only exit codes enforce, that review capacity is the binding constraint for one person, and that the "finish" phase (archive specs, ADRs, release, harness learning) is the part every existing framework skips.

## Solution

A public GitHub template repository named **`solo-harness`**. It is language-agnostic. It ships:

1. A right-sized lifecycle (S/M/L) with file-based specs in the OpenSpec layout and Pocock-style tickets.
2. Vendored, pinned agent skills (mostly Matt Pocock's, plus ASD-STE100) and one original `finish` skill.
3. Agent configuration for Claude Code, Codex CLI, GitHub Copilot and Antigravity CLI, all reading one `AGENTS.md` and one skills directory.
4. A layered enforcement stack: agent deny rules and hooks, git hooks, a single `make check`, required CI checks, a docs gate, and a ruleset with an empty bypass list.
5. An idempotent `scripts/bootstrap` that turns a fresh copy into a configured project.
6. A README that explains the pipeline in detail with Mermaid diagrams.

Token economy is a design constraint throughout: no MCP servers, a short `AGENTS.md`, hooks that print only failures, and no AI running in CI in v1.

## Glossary

- **Harness** — everything around the agent that steers it (guides) or checks it (sensors).
- **Change** — one unit of work with a size S, M or L. M/L changes have a change folder.
- **Change folder** — `specs/changes/<id>-<slug>/` holding `proposal.md`, `tasks.md` and, for L, `design.md`.
- **Living spec** — `specs/<capability>.md`; describes current behaviour; updated when a change is archived.
- **Strict mode / honor mode** — whether GitHub can enforce the ruleset (public repo or paid plan) or not (private repo on GitHub Free).
- **Overlay** — a later, stack-specific addition (e.g. TypeScript, Python) that fills `check-app`, Dependabot ecosystems and the release type.

## Change sizes and lifecycle

| Size | Definition | Path |
|---|---|---|
| **S** | No new or changed requirement: bugfix against existing spec, chore, refactor, docs, dependency bump | (optional issue) → `implement` + `tdd` → `code-review` → PR |
| **M** | New or changed behaviour inside one capability | issue → `grill-with-docs` → `to-spec` → **owner approves proposal** → `to-tickets` → **owner approves tasks** → `handoff` → fresh session `implement` (+ `tdd`) → `code-review` → `finish` → `pr` |
| **L** | Spans capabilities, or makes an architectural / hard-to-reverse choice | As M, plus `design.md` and an expected ADR |

The agent proposes the size. The owner confirms it.

`code-review` runs once at the end of every ticket and before every PR, for every size. It is never skipped to save tokens. After its findings are fixed, it does not run again unless the owner asks: repeated passes always find something, and the value drops with each pass.

## Requirements

All requirements below are **ADDED** (there are no living specs yet). Each acceptance criterion has a stable ID. Tests and checks that verify a criterion reference its ID.

### Capability: repository layout and agent guidance

**R1. Canonical layout.** The repo contains:

```
AGENTS.md                      # canonical, < 60 lines
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

- **AC-1-1** GIVEN a fresh clone WHEN `make check-harness` runs THEN every symlink above resolves to an existing target.
- **AC-1-2** GIVEN `AGENTS.md` WHEN `check-harness` runs THEN it fails if the file exceeds 60 lines.
- **AC-1-3** `AGENTS.md` names `make check` as the verification command, describes S/M/L, and points to the skills. It contains no ALL-CAPS emphasis.
- **AC-1-41** `AGENTS.md` says to run `code-review` once at the end of every ticket and before every PR, never to skip it, and not to repeat it unless the owner asks.
- **AC-1-4** `AGENTS.md` suggests "plan with the strongest model, implement with the default" as advice. No agent config pins a model.

### Capability: skills

**R2. Vendored skills.** These skills are copied from upstream at a pinned commit into `.agents/skills/`:

| Skill | Source | Modified? |
|---|---|---|
| `grill-with-docs`, `grilling`, `codebase-design`, `tdd`, `diagnosing-bugs`, `code-review`, `retro`, `writing-for-agents`, `domain-modeling`, `wizard`, `implement` | mattpocock/skills (MIT) | `code-review`: docs-drift rule added to standards axis (R13); others unmodified unless a tracker reference needs redirecting to `specs/`. `grilling` is included because `grill-with-docs` calls it. |
| `to-spec` | mattpocock/skills | Writes `specs/changes/<id>-<slug>/proposal.md` with OpenSpec delta sections and `AC-<id>-<n>` IDs instead of publishing to a tracker |
| `to-tickets` | mattpocock/skills | Writes tickets as sections of one `specs/changes/<id>-<slug>/tasks.md` (title, delivers, blocked by, acceptance checkboxes) |
| `pr` | mattpocock/skills | Fills the PR template fields (R10) and calls `asd-ste100` in STE-flavored mode for the description |
| `handoff` | mattpocock/skills | Writes to gitignored `.scratch/handoffs/`; calls `asd-ste100` in strict mode |
| `asd-ste100` | danyuchn/asd-ste100-skill (MIT) | Unmodified (includes `scripts/ste-lint.py`) |

Pocock's tracker-setup skill is not vendored. Skills that refer to it are patched to point at `specs/` and `AGENTS.md`.

- **AC-1-5** `VENDORED.md` has one row per vendored skill: source repo, path, commit SHA, license, and `unmodified` or a one-line summary of changes.
- **AC-1-6** `THIRD_PARTY_LICENSES.md` contains the full MIT notice of each upstream and lists modified skills.
- **AC-1-7** `make vendor-diff` prints, per vendored skill, the diff between the local copy and upstream HEAD. It never writes files.
- **AC-1-8** GIVEN any `SKILL.md` WHEN `check-harness` runs THEN it fails if `name` or `description` frontmatter is missing.
- **AC-1-9** Skills with side effects (`to-spec`, `to-tickets`, `implement`, `handoff`, `pr`, `finish`, `retro`) have `disable-model-invocation: true`.

**R3. Original `finish` skill.** Runs as the last commit inside an M/L PR, after review is green. Steps:

1. Verify every task in `tasks.md` is checked and every `AC-<id>-<n>` is referenced by a test. On failure, stop and report.
2. Apply the proposal's ADDED/MODIFIED/REMOVED deltas to `specs/<capability>.md`. Move the change folder to `specs/changes/archive/YYYY-MM-DD-<id>-<slug>/`.
3. Scan proposal, design and diff for hard-to-reverse or surprising decisions. For each, ask the owner, then use `domain-modeling` to write `docs/adr/NNNN-*.md` and update `GLOSSARY.md`. Fill the PR `ADR:` field.
4. Check the PR title is a valid Conventional Commit. Report the implied version bump and whether a release PR is open. Never edit `CHANGELOG.md`. Never merge the release PR.
5. Link or close the issue. Ask whether anything went wrong that should become a rule, hook or check; if yes, suggest `retro`.

- **AC-1-10** `finish` exists under `.agents/skills/finish/` and the steps above are its procedure.

**R4. ASD-STE100 usage.** Strict mode for handoff documents, reviewer findings and any text one agent writes for another. STE-flavored mode for PR descriptions and agent-written PR/issue comments. Spec files stay in normal prose.

- **AC-1-11** A CI job `ste-lint` runs `ste-lint.py` on the PR body. It is non-blocking (reports warnings, never a required check).

### Capability: agent configuration

**R5. Four agents.** Claude Code, Codex CLI, Copilot and Antigravity CLI are supported. Antigravity CLI replaced Gemini CLI on 2026-06-18. All read `AGENTS.md` and the skills in `.agents/skills/`. `design.md` §6.1 records the file names and features verified against each agent's current docs; where an agent lacks a feature, git hooks and CI cover the gap.

**R6. Shared permission policy**, expressed in each agent's native format:

- **Deny:** `git push` to `main`; `git push --force*`; `gh pr merge`; `gh release create`; `git commit --no-verify`; reading `.env*` and `~/.ssh/**`; editing any agent policy file (`.claude/settings*.json`, `.codex/**`, `.agents/hooks.json`, `.github/hooks/**`); editing `.githooks/**`.
- **Ask:** editing `.github/workflows/**`, `Makefile`, `CODEOWNERS`, `.harness/tools.lock`, the agent hook scripts (`.harness/hooks/**`) and `.harness/check/deny-rules.sh`; any package install (`npm|pnpm|yarn|pip|uv|cargo|go` add/install/get).
- **Allow:** `make *`; read-only `git`; `gh pr create|view|list|checks`; `gh issue *`.

Copilot and Antigravity keep no permission rules in the repo, so their before-tool hook is the only in-repo layer. Where an agent's hook cannot ask (Codex, the Copilot cloud agent), the hook denies the ask paths and tells the agent to ask the owner.

- **AC-1-12** GIVEN `.claude/settings.json` or `.codex/rules/default.rules` WHEN `check-harness` runs THEN it fails if any deny rule above that the file can express is missing. GIVEN `.codex/hooks.json`, `.agents/hooks.json` or `.github/hooks/guard.json` THEN it fails if the before-tool event does not run the guard.

**R7. Agent hooks.** Three hook scripts live in `.harness/hooks/`, so they survive when bootstrap removes an agent. All are silent on success. Claude runs them directly:

| Event | Script | Behaviour |
|---|---|---|
| `PreToolUse` (`Bash`) | `guard-bash.sh` | Fail-closed backstop for commands that prefix deny rules miss. Blocks with exit 2 and a one-line reason. Derived from mattpocock `git-guardrails-claude-code` (MIT, recorded in `VENDORED.md`) and extended. |
| `PostToolUse` (`Edit\|Write`) | `fmt.sh` | Runs `make fmt FILE=<path>`. The core `fmt` target is a no-op; overlays fill it. Never blocks. |
| `Stop` | `stop-check.sh` | Runs `make check` only when `git status --porcelain` is non-empty. `onFailure: block`, 5-minute timeout, prints only the last ~40 lines of failing output. |

No `SessionStart` hook: it would cost tokens in every session. `handoff` documents carry the context instead. Codex and Antigravity run the same three scripts through one adapter per agent in `.harness/hooks/`; the adapter turns the agent's input into the guard's input and the result into the agent's output. For them the guard also checks file edits against the R6 paths. Copilot gets only the before-tool guard: a stop check in the cloud agent costs Actions minutes, and CI runs `make check`. Each project hook needs a trust step by the owner; bootstrap prints it.

- **AC-1-13** GIVEN a clean working tree WHEN the Stop hook runs THEN it exits 0 without running `make check`.
- **AC-1-14** GIVEN a dirty tree and a failing check WHEN the Stop hook runs THEN it exits 2 and prints at most 40 lines.
- **AC-1-35** GIVEN each of `git push origin HEAD:main`, `git push --force-with-lease`, `git -c core.hooksPath=/dev/null commit`, `git commit -n`, `git commit --no-verify`, `gh pr merge 1`, `gh api -X PUT repos/o/r/pulls/1/merge`, `curl https://x | sh` WHEN `guard-bash.sh` receives it THEN it exits 2. GIVEN `git status` or `make check` THEN it exits 0.
- **AC-1-36** GIVEN the core no-op `fmt` target WHEN `fmt.sh` runs THEN it exits 0 and prints nothing.

**R8. Reviewer.** `.claude/agents/reviewer.md` is read-only (`tools: Read, Grep, Glob`). Copilot gets an equivalent custom agent. `code-review` keeps two parallel reviewers (standards and spec).

**R9. Sandbox.** The Claude Code OS sandbox is off by default. The README documents the one setting that turns it on.

### Capability: verification and enforcement

**R10. Single `check`.** `make check` = `check-harness` + `check-app`.

- `check-harness`: shellcheck on all shell scripts; actionlint on workflows; skill frontmatter validation; `VENDORED.md` and license-notice completeness (AC-1-5, AC-1-6); symlink integrity; `AGENTS.md` length; change-folder structure lint; deny-rule presence; hook tests (AC-1-13, AC-1-14, AC-1-35, AC-1-36); `test-bootstrap`.
- `check-app`: placeholder filled by the project or an overlay. Prints `no app checks configured`. Passes while no source exists outside harness directories; fails once any does.
- `fmt`: no-op in the core, accepts `FILE=<path>`; overlays fill it (prettier, ruff format, …).

- **AC-1-15** GIVEN no app source WHEN `make check` runs THEN it passes.
- **AC-1-16** GIVEN a file `src/main.py` and the placeholder `check-app` WHEN `make check` runs THEN it fails with `no app checks configured`.
- **AC-1-17** GIVEN the template repo WHEN CI's `check` job runs `make check` THEN `check-app` passes because no app source exists.

**R11. Git hooks** are plain shell in `.githooks/`, activated with `git config core.hooksPath .githooks`.

- **AC-1-18** pre-commit runs `make check` and `gitleaks git --staged`. If gitleaks is not installed, it warns and continues.
- **AC-1-19** commit-msg rejects messages that are not Conventional Commits.

**R12. CI workflows.** All actions are pinned to full SHAs. Every job sets least-privilege `permissions:`. No `pull_request_target`.

| Job | Behaviour | Required? |
|---|---|---|
| `check` | `make check` | Yes |
| `pr-title` | Conventional Commit title (`amannn/action-semantic-pull-request`) | Yes |
| `zizmor` | Workflow security audit | Yes |
| `secrets` | gitleaks binary on the PR commits | Yes |
| `deps` | `dependency-review-action` on public repos; `osv-scanner` on private repos | Yes |
| `docs-gate` | See R13 | Yes |
| `pr-size` | Fails over 400 changed lines (excluding lockfiles and `specs/changes/archive/`) unless label `size-exception` | Yes |
| `test-oracle` | Fails if tests, snapshots, workflows, CI config or `.harness/tools.lock` change and the PR does not touch `specs/` | Yes |
| `ste-lint` | R4 | No |
| `tools-outdated` | Separate monthly scheduled workflow (R22) | No |
| CodeQL, push protection | Enabled by bootstrap on public repos only | — |

**R13. Documentation gate (`docs-gate`).** Parses these PR-body fields: `Size: S|M|L`, `Change: specs/changes/<id>-<slug>|none`, `ADR: docs/adr/<file>[, docs/adr/<file>…]|none – <reason>` (a comma-separated list when the change records more than one ADR), `Docs: unchanged – <reason>` (optional).

- **AC-1-20** Missing or invalid `Size`/`Change`/`ADR` fields fail the job.
- **AC-1-21** An S PR fails if it exceeds 150 changed lines (excluding lockfiles) or modifies `specs/<capability>.md`, unless labelled `size-exception`.
- **AC-1-22** An M/L PR fails unless it adds `specs/changes/archive/YYYY-MM-DD-<id>-<slug>/` with `proposal.md` and `tasks.md` (plus `design.md` for L), the archived `tasks.md` has no unchecked `- [ ]`, and at least one `specs/<capability>.md` is modified.
- **AC-1-23** An M/L PR fails if any `AC-<id>-<n>` in its proposal is not found in a test file.
- **AC-1-24** `ADR:` pointing to a file fails if that file does not exist. `ADR: none` on an L PR passes but is flagged in the job summary.
- **AC-1-25** For each `.docs-map` rule (`<glob> -> <doc path>`), a PR that touches the glob but not the doc fails unless it has a `Docs: unchanged – <reason>` line. `.docs-map` ships empty.
- **AC-1-26** The `code-review` standards reviewer has the rule: user-visible behaviour, configuration, CLI flags or architecture changed → matching doc changed, or the PR says why not.

**R14. Ruleset.** `.github/ruleset.json` targets `main`: PR required, zero required approvals, required status checks from R12 (strict), linear history, squash merge only, required review-thread resolution, **empty bypass list**, block force-push and deletion. Signed commits are **not** required in v1.

**R15. Strict vs honor mode.** Bootstrap applies the ruleset. If GitHub returns 403 (private repo on GitHub Free), bootstrap prints that the repo runs in **honor mode**: CI still runs and reports, the agent deny rules still forbid merging and pushing to `main`, and merging is the owner's manual decision.

### Capability: release and dependencies

**R16. release-please** with `release-type: simple` (`version.txt`, `CHANGELOG.md`), starting at `0.1.0`. The owner merges the release PR. Overlays switch the release type.

**R17. Dependabot** for the `github-actions` ecosystem only, weekly, 7-day cooldown (zizmor flags less than 7 days), minor/patch grouped. Overlays add ecosystems.

### Capability: bootstrap

**R18. `scripts/bootstrap`** is idempotent bash. Each step checks state before it acts. Steps:

1. Ask the project name; replace placeholders.
2. Ask which agents are used (multi-select of Claude, Codex, Copilot, Antigravity); delete the configs of the rest.
3. Ask whether agents should stop adding AI attribution (`Co-Authored-By: Claude …` trailers, "Generated with" lines) to commits and PRs. Default: keep. On yes, turn attribution off in each selected agent's project config where the agent has such a setting (Claude Code: `.claude/settings.json`; the exact keys for all four agents are verified against their current docs during implementation, as in R5). Tell the owner which agents have no such setting. The template repo keeps attribution.
4. Set repo options via `gh api`: squash-only, delete branch on merge, PR title as the squash commit title and the list of commits as the squash commit message.
5. Create labels: `size/S`, `size/M`, `size/L`, `size-exception`, `agent`, `dependencies`.
6. Apply the ruleset; detect strict or honor mode (R15). On public repos, enable CodeQL, secret-scanning push protection and the dependency graph (through Dependabot alerts; the `deps` check needs it).
7. Run `git config core.hooksPath .githooks`; check that gitleaks is installed.
8. Detect globally installed Claude plugins whose skills duplicate vendored ones (e.g. `mattpocock-skills`). Disable them in the new project's `.claude/settings.json` and tell the owner what it did. The template repo itself disables nothing.
9. Guide human-only steps (e.g. secrets) in the `wizard` style.
10. Write `.template-version`; reset `version.txt`/`CHANGELOG.md`; delete template-only files (`specs/changes/archive/*-bootstrap-template/`, template README sections).
11. Print a summary. It includes a prominent **"next: configure `check-app`"** notice that names the Makefile target, explains that it fails once source code exists, and points to the README's overlay section. It also mentions `.docs-map` and suggests running the lifecycle on the first change.

Flags: `--template` (template mode: GitHub steps only), `--dry-run` (print every action and `gh api` call, change nothing), `--local` (skip all GitHub steps), `--add-agent <name>` (fetch that agent's files from the template repo).

- **AC-1-27** GIVEN `--dry-run --local` WHEN run twice on a temp copy THEN the second run reports no changes.
- **AC-1-28** GIVEN agent selection `claude` only THEN Codex, Copilot and Antigravity files are removed and all remaining symlinks resolve. Repeat for each single agent and for all four.
- **AC-1-29** GIVEN `--dry-run` THEN every GitHub step prints its `gh api` call and makes no network write.
- **AC-1-34** GIVEN a placeholder `check-app` WHEN bootstrap finishes THEN its output contains the "configure `check-app`" notice. GIVEN a filled `check-app` THEN the notice is absent.
- **AC-1-40** GIVEN agent selection `claude` and the answer "remove attribution" THEN the project's `.claude/settings.json` turns off commit and PR attribution. GIVEN the default answer, or template mode, THEN no attribution setting is written.
- **AC-1-30** `make test-bootstrap` runs AC-1-27…29, AC-1-34 and AC-1-40 in plain bash and is part of `check-harness`.

### Capability: issue and PR templates

**R19.** Issue form "Change request": problem, acceptance ideas, proposed size. Issue form "Bug": expected vs actual, reproduction. PR template: `Size:`, `Change:`, `ADR:`, optional `Docs:` fields, summary, "How I tested it" (manual-test notes), linked issue.

### Capability: README

**R20.** The README explains the whole pipeline in detail and uses Mermaid diagrams where a picture helps: lifecycle stages, S/M/L paths, enforcement layers (guides → hooks → git hooks → CI → ruleset), and the bootstrap flow. It also contains:

- Quick start (use template → `scripts/bootstrap`).
- Strict vs honor mode and the GitHub Free limitations (rulesets, dependency-review, CodeQL and push protection on private repos).
- How to enable the OS sandbox.
- How to write a stack overlay (fill `check-app`, add Dependabot ecosystem, switch release type, docstring linting on public/exported API only).
- **Recommended skills not included**, with reasons: `prototype` (UI/state design questions; `grill-with-docs` covers most cases), `triage` (only needed with inbound issues from others), `improve-codebase-architecture` (needs existing code; add for cleanup passes), `research` (token-heavy background subagent), `implement-spec` (parallel subagents; conflicts with the supervised posture and token budget).
- Why plugin duplicates are disabled by bootstrap.
- The deferred decisions list below.

### Capability: pinned tools

**R22. Tool lockfile.** `.harness/tools.lock` pins every external binary (shellcheck, actionlint, gitleaks, osv-scanner) by version, per-platform URL and SHA-256. `scripts/install-tools` installs them into gitignored `.harness/bin/` and refuses any download whose hash does not match. Dependabot cannot update this file, so two mechanisms keep it current:

- `scripts/install-tools --update <name|all>` finds the latest release via `gh api`, downloads it for every listed platform, computes the hashes and rewrites the lines. The owner runs it; the result goes through a normal PR.
- A monthly workflow `tools-outdated` compares the lockfile with the latest releases and opens or updates one issue listing stale tools. It is report-only: `contents: read`, `issues: write`, no AI, no code changes.

- **AC-1-37** GIVEN a downloaded file whose hash differs from `tools.lock` WHEN `install-tools` runs THEN it deletes the file and exits non-zero.
- **AC-1-38** GIVEN fixture release metadata and fixture files WHEN `install-tools --update shellcheck` runs THEN only the shellcheck lines change, with the new version, URLs and correct hashes.
- **AC-1-39** The `tools-outdated` workflow has only `contents: read` and `issues: write` permissions, runs on `schedule` and `workflow_dispatch` only, and contains no push or PR step.

### Capability: diagrams

**R21. Mermaid everywhere.** Every visual in the repo's documentation is a Mermaid code block. This covers `README.md`, `docs/architecture.md`, `docs/product.md`, ADRs, `design.md`, proposals and living specs. No image files or ASCII-art diagrams, so diagrams stay diffable and agent-readable.

- **AC-1-31** `check-harness` fails if any Mermaid block in any tracked `*.md` file is unterminated.
- **AC-1-32** `AGENTS.md` states the Mermaid rule in one line. `to-spec`, `finish` (for ADRs) and `domain-modeling` are patched to draw diagrams in Mermaid when one helps. `docs/architecture.md` ships with a Mermaid skeleton diagram.
- **AC-1-33** `check-harness` fails if a tracked `*.md` file under `docs/` or `specs/` embeds an image (`![…](….png|jpg|svg|gif)`).

## Decisions (ADR candidates for `finish`)

1. Language-agnostic core; stacks come later as overlays.
2. Supervised posture: one main agent plus fresh-context reviewers.
3. File-based specs (OpenSpec layout) with Pocock-style tickets; GitHub Issues track change-level status only.
4. Vendor public skills at pinned commits rather than depending on plugins.
5. Four agents supported from one `AGENTS.md` and one skills directory; bootstrap removes unused agents.
6. Zero required approvals; every gate is a status check; empty bypass list. Honor mode on GitHub Free private repos.
7. `finish` runs inside the change PR, so archive, ADR and code land in one squash commit.
8. Documentation is enforced by `docs-gate`, not by prompts.
9. Signed commits deferred (see below).

## Out of scope (deferred)

- **Required signed commits** — remind the owner to build this as a follow-up change.
- **Parallel agents for frontier tickets** — run agents in parallel for tickets that are not blocked and share no files, each in its own worktree, only after the owner approves each run. Reverses decision 2 for implementation, so it needs an ADR.
- AI review in CI (Claude Code Action with OAuth token), devcontainer with egress firewall, metrics workflow (tier C).
- Stack overlays (TypeScript, Python, …).
- "Update from template" mechanism (`.template-version` prepares for it).
- Scheduled report-only agents ("end-of-day agents").
- Tag ruleset and deployment environments (no deploy target in an agnostic core).

## Build order (input for `to-tickets`)

1. Repo skeleton, `AGENTS.md`, `Makefile` with `check-harness`.
2. Vendor skills, `VENDORED.md`, `THIRD_PARTY_LICENSES.md`, patches, `finish`.
3. Claude config: settings, Stop hook, reviewer.
4. Codex, Copilot and Antigravity configs.
5. Git hooks.
6. CI workflows, including `docs-gate`.
7. Issue and PR templates, labels list.
8. Bootstrap script and `test-bootstrap`.
9. release-please and Dependabot.
10. README.
11. Archive this change with `finish`.

Steps 1–2 are built by hand ("cold start"). From step 3 on, the build uses the vendored skills.
