# Vendored skills

Third-party skills copied into `.agents/skills/` at a pinned commit. `make vendor-diff` prints how each local copy differs from upstream `HEAD`. To update a skill, copy the new upstream version, re-apply the change listed here, and update its row. License notices are in `THIRD_PARTY_LICENSES.md`.

`grilling` is vendored because `grill-with-docs` calls it. `.agents/skills/.shellcheckrc` silences two shellcheck findings in the unmodified `wizard/template.sh`.

| Skill | Source | Path | Commit | License | Changes |
|---|---|---|---|---|---|
| `asd-ste100` | danyuchn/asd-ste100-skill | . (SKILL.md, scripts/, references/, examples/) | a4905d922500dd7530ca8a0eb9e4940494255709 | MIT | unmodified |
| `code-review` | mattpocock/skills | skills/engineering/code-review | 4ae2317ddb22b046e26455e4f9c9b3aaaf62212d | MIT | Adds the docs-drift rule to the standards axis; finds the spec in `specs/changes/` instead of the issue tracker |
| `codebase-design` | mattpocock/skills | skills/engineering/codebase-design | 4ae2317ddb22b046e26455e4f9c9b3aaaf62212d | MIT | unmodified |
| `diagnosing-bugs` | mattpocock/skills | skills/engineering/diagnosing-bugs | 4ae2317ddb22b046e26455e4f9c9b3aaaf62212d | MIT | unmodified |
| `domain-modeling` | mattpocock/skills | skills/engineering/domain-modeling | 4ae2317ddb22b046e26455e4f9c9b3aaaf62212d | MIT | Adds a Diagrams section: draw diagrams as Mermaid code blocks |
| `grill-with-docs` | mattpocock/skills | skills/engineering/grill-with-docs | 4ae2317ddb22b046e26455e4f9c9b3aaaf62212d | MIT | unmodified |
| `grilling` | mattpocock/skills | skills/productivity/grilling | 4ae2317ddb22b046e26455e4f9c9b3aaaf62212d | MIT | unmodified |
| `handoff` | mattpocock/skills | skills/productivity/handoff | 4ae2317ddb22b046e26455e4f9c9b3aaaf62212d | MIT | Writes to gitignored `.scratch/handoffs/` instead of the OS temp directory; uses `asd-ste100` strict mode |
| `implement` | mattpocock/skills | skills/engineering/implement | 4ae2317ddb22b046e26455e4f9c9b3aaaf62212d | MIT | Reads tickets from `specs/changes/<id>-<slug>/tasks.md` instead of the issue tracker |
| `pr` | mattpocock/skills | skills/engineering/pr | 4ae2317ddb22b046e26455e4f9c9b3aaaf62212d | MIT | Adds the `docs-gate` fields (Size, Change, ADR, Docs) to the template; uses `asd-ste100` STE-flavored mode; `disable-model-invocation: true` and no implicit invocation in `agents/openai.yaml` |
| `retro` | mattpocock/skills | skills/engineering/retro | 4ae2317ddb22b046e26455e4f9c9b3aaaf62212d | MIT | unmodified |
| `tdd` | mattpocock/skills | skills/engineering/tdd | 4ae2317ddb22b046e26455e4f9c9b3aaaf62212d | MIT | unmodified |
| `to-spec` | mattpocock/skills | skills/engineering/to-spec | 4ae2317ddb22b046e26455e4f9c9b3aaaf62212d | MIT | Writes `specs/changes/<id>-<slug>/proposal.md` with ADDED/MODIFIED/REMOVED sections and `AC-<id>-<n>` IDs instead of publishing to a tracker; Mermaid diagrams |
| `to-tickets` | mattpocock/skills | skills/engineering/to-tickets | 4ae2317ddb22b046e26455e4f9c9b3aaaf62212d | MIT | Writes tickets as sections of one `specs/changes/<id>-<slug>/tasks.md` instead of publishing to a tracker |
| `wizard` | mattpocock/skills | skills/engineering/wizard | 4ae2317ddb22b046e26455e4f9c9b3aaaf62212d | MIT | unmodified |
| `writing-for-agents` | mattpocock/skills | skills/productivity/writing-for-agents | 4ae2317ddb22b046e26455e4f9c9b3aaaf62212d | MIT | unmodified |

## Original skills

Skills written for this repo. They have no upstream.

- `finish`: closes an M/L change inside its PR (R3).
