# solo-harness task runner. `make check` is the one verification command.
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := check
export PATH := $(CURDIR)/.harness/bin:$(PATH)

HARNESS_CHECKS := symlinks agents-md skills-frontmatter change-folders markdown

.PHONY: check check-harness check-app fmt tools test-harness

## check: everything that must pass before a merge
check: check-harness check-app

## check-harness: the harness's own rules, lints and tests
check-harness: tools
	@rc=0; for c in $(HARNESS_CHECKS) lint; do .harness/check/$$c.sh || rc=1; done; exit $$rc
	@$(MAKE) -s test-harness

## test-harness: plain-bash tests in .harness/tests (skipped inside a nested test run)
test-harness:
	@if [[ -z "$${HARNESS_NESTED:-}" ]]; then .harness/tests/run.sh; fi

## tools: install the pinned binaries from .harness/tools.lock into .harness/bin
tools:
	@scripts/install-tools

## check-app: project checks. Replace this recipe and delete the marker line below.
# solo-harness:check-app-placeholder
check-app:
	@.harness/check/app-placeholder.sh

## fmt: format FILE=<path>. No-op in the core; overlays fill it.
fmt:
	@:
