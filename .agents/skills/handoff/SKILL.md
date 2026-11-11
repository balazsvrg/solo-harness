---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up.
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save it to `.scratch/handoffs/<YYYY-MM-DD>-change-<id>-<ticket>.md` in the repo (for example `2026-11-12-change-7-T3.md`; use a short slug when there is no change). `.scratch/` is gitignored, so the file is never committed.

Call the Skill tool with `asd-ste100` and write the document in its strict mode. Another agent reads it, so a wrong reading has a cost.

Include a "suggested skills" section in the document, naming which skills the next agent should call the Skill tool for.

Do not duplicate content already captured in other artifacts (specs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.
