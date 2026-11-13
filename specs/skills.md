# Skills

Agent skills live in `.agents/skills/<name>/SKILL.md`. Most are vendored from upstream at a pinned commit; `finish` is original.

## Vendored skills (R2)

| Skill | Source | Modified? |
|---|---|---|
| `grill-with-docs`, `grilling`, `codebase-design`, `tdd`, `diagnosing-bugs`, `code-review`, `retro`, `writing-for-agents`, `domain-modeling`, `wizard`, `implement` | mattpocock/skills (MIT) | `code-review`: docs-drift rule added to the standards axis (see `verification.md`, AC-1-26). Others are unmodified unless a tracker reference is redirected to `specs/`. `grilling` is included because `grill-with-docs` calls it. |
| `to-spec` | mattpocock/skills | Writes `specs/changes/<id>-<slug>/proposal.md` with OpenSpec delta sections and `AC-<id>-<n>` IDs instead of publishing to a tracker |
| `to-tickets` | mattpocock/skills | Writes tickets as sections of one `specs/changes/<id>-<slug>/tasks.md` (title, delivers, blocked by, acceptance checkboxes) |
| `pr` | mattpocock/skills | Fills the PR template fields and calls `asd-ste100` in STE-flavored mode for the description |
| `handoff` | mattpocock/skills | Writes to gitignored `.scratch/handoffs/`; calls `asd-ste100` in strict mode |
| `asd-ste100` | danyuchn/asd-ste100-skill (MIT) | Unmodified (includes `scripts/ste-lint.py`) |

Pocock's tracker-setup skill is not vendored. Skills that refer to it point at `specs/` and `AGENTS.md` instead.

- **AC-1-5** `VENDORED.md` has one row per vendored skill: source repo, path, commit SHA, license, and `unmodified` or a one-line summary of changes.
- **AC-1-6** `THIRD_PARTY_LICENSES.md` contains the full MIT notice of each upstream and lists modified skills.
- **AC-1-7** `make vendor-diff` prints, per vendored skill, the diff between the local copy and upstream HEAD. It never writes files.
- **AC-1-8** GIVEN any `SKILL.md` WHEN `check-harness` runs THEN it fails if `name` or `description` frontmatter is missing.
- **AC-1-9** Skills with side effects (`to-spec`, `to-tickets`, `implement`, `handoff`, `pr`, `finish`, `retro`) have `disable-model-invocation: true`.

## `finish` (R3)

`finish` runs as the last commit inside an M or L PR, after review is green. Steps:

1. Verify every task in `tasks.md` is checked and every `AC-<id>-<n>` is referenced by a test. On failure, stop and report.
2. Apply the proposal's ADDED/MODIFIED/REMOVED deltas to `specs/<capability>.md`. Move the change folder to `specs/changes/archive/YYYY-MM-DD-<id>-<slug>/`.
3. Scan proposal, design and diff for hard-to-reverse or surprising decisions. For each, ask the owner, then use `domain-modeling` to write `docs/adr/NNNN-*.md` and update `GLOSSARY.md`. Fill the PR `ADR:` field.
4. Check the PR title is a valid Conventional Commit. Report the implied version bump and whether a release PR is open. Never edit `CHANGELOG.md`. Never merge the release PR.
5. Link or close the issue. Ask whether anything went wrong that should become a rule, hook or check; if yes, suggest `retro`.

- **AC-1-10** `finish` exists under `.agents/skills/finish/` and the steps above are its procedure.

## ASD-STE100 usage (R4)

Strict mode for handoff documents, reviewer findings and any text one agent writes for another. STE-flavored mode for PR descriptions and agent-written PR and issue comments. Spec files stay in normal prose.

- **AC-1-11** A CI job `ste-lint` runs `ste-lint.py` on the PR body. It is non-blocking (reports warnings, never a required check).
