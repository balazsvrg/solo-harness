# shellcheck shell=bash
# Tests for .harness/lib/common.sh path helpers.

test_glob_match() {
  # Supports AC-1-16 and TEST_GLOBS consumers.
  source "$HARNESS_ROOT/.harness/lib/common.sh"
  glob_match test_x.py '**/test_*.*' || fail 'root test file'
  glob_match a/b/test_x.py '**/test_*.*' || fail 'nested test file'
  ! glob_match a/test_dir/x.py '**/test_*.*' || fail '* must not cross /'
  glob_match tests/a/b.py 'tests/**' || fail 'tests/**'
  ! glob_match x.md '.*' || fail 'dot glob'
}

test_app_source_classification() {
  # Supports AC-1-15, AC-1-16.
  source "$HARNESS_ROOT/.harness/lib/common.sh"
  is_app_source src/main.py || fail 'src is app source'
  is_app_source tests/test_api.py || fail 'tests/ is app source'
  is_app_source main.go || fail 'root code file is app source'
  ! is_app_source README.md || fail 'root md is harness'
  ! is_app_source .harness/tests/test_x.sh || fail 'harness tests are harness'
  ! is_app_source docs/product.md || fail 'docs are harness'
  ! is_app_source .gitignore || fail 'root dotfile is harness'
}

test_vendored_rows() {
  # Supports AC-1-5 and scripts/vendor-diff: one parser for VENDORED.md rows.
  source "$HARNESS_ROOT/.harness/lib/common.sh"
  # shellcheck disable=SC2016 # backticks are literal
  printf '%s\n' '# Vendored skills' '| Skill | Source |' '|---|---|' \
    '| `tdd` | o/r | skills/tdd | abc | MIT | unmodified |' \
    '|  `x`  |  o/r  |  . (SKILL.md, scripts/)  |  |  MIT  |  adds a rule  |' > table.md
  assert_eq "$(vendored_rows table.md)" $'tdd|o/r|skills/tdd|abc|MIT|unmodified\nx|o/r|. (SKILL.md, scripts/)||MIT|adds a rule'
}
