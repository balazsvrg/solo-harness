# Supervised posture: one main agent plus fresh-context reviewers

For one developer, review capacity is the binding constraint, not agent throughput. So one main agent works in small, test-first steps under the owner's eye, and `code-review` runs read-only reviewers in fresh contexts (standards and spec) once per ticket and before every PR. Parallel implementation agents (for example `implement-spec`, or one agent per frontier ticket in its own worktree) would produce more diff than one person can review, and they cost more tokens on a Pro plan.

## Consequences

Running agents in parallel on frontier tickets is a deferred idea. It reverses this decision for implementation, so it needs its own ADR.
