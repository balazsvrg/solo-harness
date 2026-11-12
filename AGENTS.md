# Agent guide

This repo uses the solo-harness workflow. One owner, one main agent, small test-first steps.

## Verify

- Run `make check` before you say a task is done. It must exit 0.
- `make check` = `make check-harness` (harness rules) + `make check-app` (project checks).
- A red `check` is a blocker. Fix it; do not work around it.

## Change sizes (S/M/L)

Propose a size. The owner confirms it.

- **S**: no new or changed requirement (bugfix, chore, refactor, docs, dependency bump). Path: `implement` + `tdd`, `code-review`, then `pr`.
- **M**: new or changed behaviour inside one capability. Path: `grill-with-docs`, `to-spec`, owner approves the proposal, `to-tickets`, owner approves the tasks, `handoff`, `implement` + `tdd` in a fresh session, `code-review`, `finish`, `pr`.
- **L**: spans capabilities or makes a hard-to-reverse choice. As M, plus `design.md` and an ADR.

## Where things live

- Skills: `.agents/skills/<name>/SKILL.md`. Read a skill before you do the work it covers.
- Specs: `specs/<capability>.md` (current behaviour) and `specs/changes/<issue>-<slug>/` (open changes).
- Product and architecture: `docs/product.md`, `docs/architecture.md`, decisions in `docs/adr/`.
- Terms: `GLOSSARY.md`. Use its words in code, specs and commits.
- Harness internals: `.harness/`. Project code lives outside the harness folders.

## Rules

- Write the test first. Each test names the criterion it covers on its first line, for example `# AC-12-3`.
- Commit messages and PR titles follow Conventional Commits.
- Never merge a PR, push to `main` or skip hooks. The owner merges.
- Run `code-review` once at the end of every ticket and before every PR. Never skip it. After you fix its findings, do not review again unless the owner asks.
- Draw every diagram as a Mermaid code block. No image files, no ASCII art.
- Text for another agent (handoffs, review findings) uses the `asd-ste100` skill in strict mode.

## Models

Advice, not a rule: plan with the strongest model, implement with the default one.
