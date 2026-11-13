#!/usr/bin/env bash
# Plain-bash test runner. Runs every test_* function in .harness/tests/test_*.sh.
# Usage: run.sh [NAME_FILTER]. Prints only failures and a summary.
# TEST_FILES selects other files, as an extglob relative to this folder (make
# test-bootstrap uses bootstrap/test_*.sh).
set -uo pipefail
shopt -s extglob

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HARNESS_ROOT=$(cd "$TESTS_DIR/../.." && pwd)
export HARNESS_ROOT
filter=${1:-}
pass=0 failed=()

# Not exported to the tests: a nested run must pick its own files.
files=${TEST_FILES:-test_*.sh}
unset TEST_FILES
# The gate scripts read these from the CI job. A test sets the ones it needs.
unset GITHUB_STEP_SUMMARY PR_LABELS PR_AUTHOR PR_DIFF PR_BODY

for file in "$TESTS_DIR"/$files; do
  [[ -e $file ]] || continue
  mapfile -t fns < <(bash -c 'source "$1"; declare -F' _ "$file" | awk '$3 ~ /^test_/ {print $3}')
  for fn in "${fns[@]}"; do
    [[ -n $filter && $fn != *"$filter"* ]] && continue
    TEST_TMP=$(mktemp -d)
    out=$(
      export TEST_TMP
      cd "$TEST_TMP" || exit 1
      # shellcheck source=lib/assert.sh
      source "$TESTS_DIR/lib/assert.sh"
      # shellcheck disable=SC1090
      source "$file"
      set -e
      "$fn"
    ) 2>&1
    rc=$?
    rm -rf "$TEST_TMP"
    if [[ $rc == 0 ]]; then
      ((pass++))
    else
      failed+=("$fn")
      printf 'FAIL %s (%s)\n%s\n' "$fn" "${file##*/}" "$out"
    fi
  done
done

printf '%d passed, %d failed\n' "$pass" "${#failed[@]}"
[[ ${#failed[@]} == 0 ]]
