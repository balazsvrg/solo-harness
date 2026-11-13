# Documentation is enforced by `docs-gate`, not by prompts

A prompt that says "keep the docs current" is advice, and agents and people skip advice. Only exit codes enforce. So a required CI job, `docs-gate`, reads `Size:`, `Change:`, `ADR:` and `Docs:` fields from the PR body and fails the PR when the size rules, the change archive, AC test coverage, the ADR files or the `.docs-map` rules are not met. The `code-review` standards reviewer adds a docs-drift rule for what the gate cannot see. The cost is a structured PR body that every PR, including bot PRs, must fill in.
