# `finish` runs inside the change PR

The finish phase (archive the change into living specs, write ADRs, check the release) is the part other frameworks skip. A separate follow-up PR would be easy to forget, and `main` would hold code whose specs are not up to date. So `finish` is the last commit of the M or L change PR, and the code, the living specs, the archive and the ADRs land in one squash commit. `docs-gate` enforces this: an M/L PR fails unless it adds the archive folder with every task checked and changes at least one living spec.

## Consequences

Steps that happen after the merge (the merge itself, follow-up reminders) cannot be checkboxes in the archived `tasks.md`, because `docs-gate` rejects unchecked items. They go in plain text under an "After the merge" heading.
