---
name: finish
description: Close an M or L change inside its PR - verify, archive the change into living specs, record ADRs, check the release. Use after code review is green.
disable-model-invocation: true
---

Close change `<id>-<slug>` as the last commit of its PR. Code review is already green. The change folder is `specs/changes/<id>-<slug>/`; if the user did not name it and there is more than one open change, ask.

Work the steps in order. A step is done only when its completion criterion holds. Steps 2–3 edit files; the owner confirms each ADR, any PR edit and the final commit.

## 1. Verify

- Every box in `tasks.md` is `- [x]`.
- Every `AC-<id>-<n>` in `proposal.md` appears in at least one file matching `TEST_GLOBS` from `.harness/config`.
- `make check` exits 0.

Done when all three hold. If any fails, stop here: report the open tasks, the uncovered AC ids and the failing check, and end the skill. `finish` closes finished work; it does not finish it.

## 2. Archive

Apply each ADDED/MODIFIED/REMOVED delta in `proposal.md` to its living spec `specs/<capability>.md`:

- ADDED: copy the requirement and its ACs in. Create the file if the capability is new.
- MODIFIED: replace the old text with the new.
- REMOVED: delete the requirement and its ACs.

A living spec states current behaviour in normal prose. It carries no change history, dates or "was/now" wording.

Then move the folder with `git mv specs/changes/<id>-<slug> specs/changes/archive/YYYY-MM-DD-<id>-<slug>/`, using today's date.

Done when every requirement and AC in the proposal is in, changed in, or gone from its living spec, and `.harness/check/change-folders.sh` exits 0.

## 3. Record decisions

Collect candidates from the proposal (including any decisions section), `design.md`, and `git diff main...HEAD`. A candidate is a decision that is hard to reverse, surprising without context, and the result of a real trade-off.

Show the owner the full candidate list, one line each. For each candidate the owner confirms, call the Skill tool with `domain-modeling` and write `docs/adr/NNNN-<slug>.md` with the next free number. When a diagram helps the reader of an ADR, draw it as a Mermaid code block. Add new or sharpened terms to `GLOSSARY.md`.

Set the PR `ADR:` field to the new ADR files, or to `none – <reason>` when the owner confirmed none. On a Size L change, `none` is flagged by `docs-gate`; give a reason the reviewer will accept.

Done when every candidate is either an ADR file or rejected by the owner, and the PR `ADR:` field matches.

## 4. Check the release

Read the PR title with `gh pr view --json title`. It must be a valid Conventional Commit: `type(scope)?!?: subject`. If it is not, propose a fixed title to the owner.

Report the version bump the title implies once squash-merged:

| Title | Bump |
|---|---|
| `!` after type, or `BREAKING CHANGE:` in body | major |
| `feat` | minor |
| `fix`, `perf` | patch |
| anything else | none |

Report whether a release PR is open: `gh pr list --label "autorelease: pending"`.

release-please owns `CHANGELOG.md` and the release PR, and the owner merges it. Leave both as they are.

Done when the title is valid and the owner has the bump and release-PR status.

## 5. Close the loop

Make sure the PR body links the issue with `Closes #<id>`, so the squash merge closes it. Ask the owner before you edit the PR body.

Ask the owner: did anything go wrong in this change that should become a rule, hook or check? If yes, suggest the `retro` skill.

Ask the owner to approve the commit, then commit steps 2–3 as one commit: `docs(specs): finish change <id>`. Run `make check` first; it must exit 0.

Done when the commit is on the branch and you have reported: archive path, living specs changed, ADRs written, bump, and release-PR status.
