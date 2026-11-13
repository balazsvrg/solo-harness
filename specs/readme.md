# README

## Contents (R20)

The README explains the whole pipeline in detail and uses Mermaid diagrams where a picture helps: lifecycle stages, S/M/L paths, enforcement layers (guides → hooks → git hooks → CI → ruleset), and the bootstrap flow. It also contains:

- Quick start (use template → `scripts/bootstrap`).
- Strict vs honor mode and the GitHub Free limitations (rulesets, dependency-review, CodeQL and push protection on private repos).
- How to enable the OS sandbox.
- How to write a stack overlay (fill `check-app`, add a Dependabot ecosystem, switch the release type, docstring linting on public or exported API only).
- **Recommended skills not included**, with reasons: `prototype` (UI and state design questions; `grill-with-docs` covers most cases), `triage` (only needed with inbound issues from others), `improve-codebase-architecture` (needs existing code; add it for cleanup passes), `research` (token-heavy background subagent), `implement-spec` (parallel subagents; conflicts with the supervised posture and the token budget).
- Why bootstrap disables plugin duplicates.
- The deferred decisions: required signed commits, parallel agents for frontier tickets, AI review in CI, a devcontainer with an egress firewall, a metrics workflow, stack overlays, an "update from template" mechanism, scheduled report-only agents, a tag ruleset and deployment environments.

The template-only README sections sit between markers. `scripts/bootstrap` deletes them in project mode.
