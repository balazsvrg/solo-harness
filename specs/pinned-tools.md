# Pinned tools

## Tool lockfile (R22)

`.harness/tools.lock` pins every external binary (shellcheck, actionlint, gitleaks, osv-scanner) by version, per-platform URL and SHA-256. `scripts/install-tools` installs them into gitignored `.harness/bin/` and refuses any download whose hash does not match. Dependabot cannot update this file, so two mechanisms keep it current:

- `scripts/install-tools --update <name|all>` finds the latest release via `gh api`, downloads it for every listed platform, computes the hashes and rewrites the lines. The owner runs it; the result goes through a normal PR.
- A monthly workflow `tools-outdated` compares the lockfile with the latest releases and opens or updates one issue listing stale tools. It is report-only: `contents: read`, `issues: write`, no AI, no code changes.

- **AC-1-37** GIVEN a downloaded file whose hash differs from `tools.lock` WHEN `install-tools` runs THEN it deletes the file and exits non-zero.
- **AC-1-38** GIVEN fixture release metadata and fixture files WHEN `install-tools --update shellcheck` runs THEN only the shellcheck lines change, with the new version, URLs and correct hashes.
- **AC-1-39** The `tools-outdated` workflow has only `contents: read` and `issues: write` permissions, runs on `schedule` and `workflow_dispatch` only, and contains no push or PR step.
