#!/usr/bin/env bash
# Plain-bash test runner. Runs every test_* function in .harness/tests/test_*.sh.
# Usage: run.sh [NAME_FILTER]. Prints only failures and a summary.
set -uo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HARNESS_ROOT=$(cd "$TESTS_DIR/../.." && pwd)
export HARNESS_ROOT
filter=${1:-}
pass=0 failed=()

for file in "$TESTS_DIR"/test_*.sh; do
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
