# Glossary

- **Harness**: everything around the agent that steers it (guides) or checks it (sensors).
- **Change**: one unit of work with a size S, M or L. M and L changes have a change folder.
- **Change folder**: `specs/changes/<issue>-<slug>/` with `proposal.md`, `tasks.md` and, for L, `design.md`.
- **Living spec**: `specs/<capability>.md`. It describes current behaviour. `finish` updates it when a change is archived.
- **Strict mode / honor mode**: whether GitHub can enforce the ruleset (public repo or paid plan) or not (private repo on GitHub Free).
- **Overlay**: a later, stack-specific addition (for example TypeScript or Python) that fills `check-app`, Dependabot ecosystems and the release type.
- **App source**: any file outside the harness paths in `.harness/config`. The placeholder `check-app` fails once app source exists.
