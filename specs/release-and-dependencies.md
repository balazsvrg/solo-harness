# Release and dependencies

## release-please (R16)

release-please runs with `release-type: simple` (`version.txt`, `CHANGELOG.md`), starting at `0.1.0`. The owner merges the release PR. Overlays switch the release type.

The release PR must pass the ruleset like any other PR. `release-please-config.json` sets `pull-request-footer` to `Size: S`, `Change: none` and `ADR: none – …`, so `docs-gate` passes. The workflow uses `secrets.RELEASE_PLEASE_TOKEN || github.token`. A PR made with `github.token` does not start workflows, so without the secret the owner closes and reopens the release PR before the merge. Bootstrap prints this as a human step.

## Dependabot (R17)

Dependabot covers the `github-actions` ecosystem only: weekly, with a 7-day cooldown (zizmor flags less than 7 days), minor and patch updates grouped. Overlays add ecosystems. Pin-only Dependabot PRs pass `docs-gate` and `test-oracle` (see `verification.md`).
