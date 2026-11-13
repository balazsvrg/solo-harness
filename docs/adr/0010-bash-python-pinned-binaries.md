# Runtime: bash and stdlib `python3`; external binaries pinned by hash

The harness must run on a fresh Linux or macOS machine and on CI runners without a language toolchain. So scripts use only bash 4+, `git`, `make`, `gh` and `python3` with the standard library: no `jq`, no `pip install`, no Node. The external linters and scanners (shellcheck, actionlint, gitleaks, osv-scanner) are downloaded by `scripts/install-tools` into `.harness/bin/` and verified against the SHA-256 values in `.harness/tools.lock`, so local runs and CI run the same versions and a tampered download fails.

## Consequences

Dependabot cannot update `tools.lock`. `install-tools --update` and the monthly report-only `tools-outdated` workflow keep it current. `python3` is a hard requirement: without it the hook adapter cannot run, and `make check` fails first.
