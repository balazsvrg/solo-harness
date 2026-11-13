# File-based specs; issues track only change-level status

Specs and tickets live in the repo, not in an issue tracker: a change folder `specs/changes/<id>-<slug>/` holds `proposal.md` (OpenSpec-style ADDED/MODIFIED/REMOVED deltas with `AC-<id>-<n>` IDs), `tasks.md` (Pocock-style tickets as sections) and, for L, `design.md`. Living specs `specs/<capability>.md` hold current behaviour. Agents read files cheaply and offline, the gates can check them (`docs-gate`, `test-oracle`), and spec changes are reviewed in the same PR as the code. A GitHub issue still exists for each change, and its number is the `<id>`, but it only tracks status and is closed by the squash merge.

## Considered options

- **Issues as tickets**, as in the upstream Pocock skills: one place for status, but the gates cannot read issues offline, and specs would drift from the code they describe.
