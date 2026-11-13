# Diagrams

## Mermaid everywhere (R21)

Every visual in the repo's documentation is a Mermaid code block. This covers `README.md`, `docs/architecture.md`, `docs/product.md`, ADRs, `design.md`, proposals and living specs. There are no image files or ASCII-art diagrams, so diagrams stay diffable and agent-readable.

- **AC-1-31** `check-harness` fails if any Mermaid block in any tracked `*.md` file is unterminated.
- **AC-1-32** `AGENTS.md` states the Mermaid rule in one line. `to-spec`, `finish` (for ADRs) and `domain-modeling` draw diagrams in Mermaid when one helps. `docs/architecture.md` ships with a Mermaid skeleton diagram.
- **AC-1-33** `check-harness` fails if a tracked `*.md` file under `docs/` or `specs/` embeds an image (`![…](….png|jpg|svg|gif)`).
