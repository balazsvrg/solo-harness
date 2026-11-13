# shellcheck shell=bash disable=SC2016
# Tests for scripts/install-tools (R22). The network is replaced by fixture functions.

# it_run OVERRIDES_FILE ARGS...: run install-tools main with fetch functions overridden.
it_run() {
  bash -c 'set -euo pipefail; source "$1"; source "$2"; shift 2; main "$@"' _ \
    "$HARNESS_ROOT/scripts/install-tools" "$@"
}

sha() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }

test_hash_mismatch_deletes_file() {
  # AC-1-37
  export TOOLS_LOCK=$TEST_TMP/tools.lock TOOLS_BIN=$TEST_TMP/bin
  local plat; plat=$(bash -c 'source "$1"; platform' _ "$HARNESS_ROOT/scripts/install-tools")
  printf 'osv-scanner 1.0.0 %s https://example.invalid/osv-scanner %s\n' "$plat" "$(sha good)" > "$TOOLS_LOCK"
  echo 'fetch_url() { printf bad > "$2"; }' > "$TEST_TMP/o.sh"
  assert_status 1 it_run "$TEST_TMP/o.sh"
  assert_contains "$OUT" 'sha256 mismatch'
  assert_no_file "$TOOLS_BIN/osv-scanner"
  [[ -z $(find "$TOOLS_BIN" -type f 2>/dev/null) ]] || fail "downloaded file not deleted: $(find "$TOOLS_BIN" -type f)"
}

test_install_raw_binary_and_skip_when_current() {
  # AC-1-37: a matching hash installs; a second run downloads nothing.
  export TOOLS_LOCK=$TEST_TMP/tools.lock TOOLS_BIN=$TEST_TMP/bin
  local plat; plat=$(bash -c 'source "$1"; platform' _ "$HARNESS_ROOT/scripts/install-tools")
  printf 'osv-scanner 1.0.0 %s https://example.invalid/osv-scanner %s\n' "$plat" "$(sha good)" > "$TOOLS_LOCK"
  echo 'fetch_url() { printf good > "$2"; echo fetched >&2; }' > "$TEST_TMP/o.sh"
  assert_status 0 it_run "$TEST_TMP/o.sh"
  assert_contains "$OUT" fetched
  [[ -x $TOOLS_BIN/osv-scanner ]] || fail 'binary not installed'
  assert_status 0 it_run "$TEST_TMP/o.sh"
  assert_not_contains "$OUT" fetched
}

test_update_rewrites_only_named_tool() {
  # AC-1-38
  export TOOLS_LOCK=$TEST_TMP/tools.lock TOOLS_BIN=$TEST_TMP/bin
  cat > "$TOOLS_LOCK" <<'LOCK'
# header comment
shellcheck 0.1.0 linux-amd64 https://old/sc-l-a aaaa
shellcheck 0.1.0 darwin-arm64 https://old/sc-d-a bbbb
actionlint 1.0.0 linux-amd64 https://old/al cccc
LOCK
  local before_al; before_al=$(grep -v '^shellcheck' "$TOOLS_LOCK")
  cat > "$TEST_TMP/o.sh" <<'O'
fetch_latest_version() { [[ $1 == koalaman/shellcheck ]] || exit 9; echo v9.9.9; }
fetch_url() { printf '%s' "$1" > "$2"; }
O
  assert_status 0 it_run "$TEST_TMP/o.sh" --update shellcheck
  assert_eq "$(grep -v '^shellcheck' "$TOOLS_LOCK")" "$before_al" 'other lines unchanged'
  local n=0 name ver plat url hash
  while read -r name ver plat url hash; do
    [[ $name == shellcheck ]] || continue
    n=$((n + 1))
    assert_eq "$ver" 9.9.9
    assert_contains "$url" 'koalaman/shellcheck/releases/download/v9.9.9/shellcheck-v9.9.9.'
    assert_eq "$hash" "$(sha "$url")" "hash of $url"
  done < "$TOOLS_LOCK"
  assert_eq "$n" 4 'one line per platform'
  [[ $(sed -n 2p "$TOOLS_LOCK") == shellcheck* ]] || fail 'shellcheck block must stay in place'
}

test_real_lock_covers_all_tools_and_platforms() {
  # R22: every tool is pinned for every platform.
  local t p
  for t in shellcheck actionlint gitleaks osv-scanner; do
    for p in linux-amd64 linux-arm64 darwin-amd64 darwin-arm64; do
      grep -qE "^$t [0-9][^ ]* $p https://[^ ]+ [0-9a-f]{64}$" "$HARNESS_ROOT/.harness/tools.lock" || fail "missing $t $p"
    done
  done
}

test_outdated_lists_only_stale_tools() {
  # R22 tools-outdated: one line per stale tool; current tools are not listed.
  export TOOLS_LOCK=$TEST_TMP/tools.lock
  cat > "$TOOLS_LOCK" <<'LOCK'
# comment
shellcheck 0.11.0 linux-amd64 https://example.invalid/a aa
shellcheck 0.11.0 darwin-arm64 https://example.invalid/b bb
gitleaks 8.30.1 linux-amd64 https://example.invalid/c cc
LOCK
  cat > "$TEST_TMP/o.sh" <<'O'
fetch_latest_version() {
  case $1 in koalaman/shellcheck) echo v0.12.0 ;; gitleaks/gitleaks) echo v8.30.1 ;; *) return 1 ;; esac
}
O
  assert_status 0 it_run "$TEST_TMP/o.sh" --outdated
  assert_eq "$OUT" '- shellcheck: pinned 0.11.0, latest 0.12.0'
}

test_outdated_prints_nothing_when_current() {
  # R22 tools-outdated: empty output means every pin is current.
  export TOOLS_LOCK=$TEST_TMP/tools.lock
  echo 'gitleaks 8.30.1 linux-amd64 https://example.invalid/c cc' > "$TOOLS_LOCK"
  echo 'fetch_latest_version() { echo v8.30.1; }' > "$TEST_TMP/o.sh"
  assert_status 0 it_run "$TEST_TMP/o.sh" --outdated
  assert_eq "$OUT" ''
}

test_outdated_ignores_pins_newer_than_latest() {
  # R22 tools-outdated: only a newer release is stale; 0.10.0 < 0.9.0 is not a string compare.
  export TOOLS_LOCK=$TEST_TMP/tools.lock
  printf '%s\n' 'gitleaks 8.31.0 linux-amd64 https://example.invalid/c cc' \
    'shellcheck 0.9.0 linux-amd64 https://example.invalid/a aa' > "$TOOLS_LOCK"
  cat > "$TEST_TMP/o.sh" <<'O'
fetch_latest_version() { case $1 in gitleaks/gitleaks) echo v8.30.1 ;; *) echo v0.10.0 ;; esac; }
O
  assert_status 0 it_run "$TEST_TMP/o.sh" --outdated
  assert_eq "$OUT" '- shellcheck: pinned 0.9.0, latest 0.10.0'
}

test_outdated_fails_when_release_unreadable() {
  # R22 tools-outdated: a failed lookup is an error, not "up to date".
  export TOOLS_LOCK=$TEST_TMP/tools.lock
  echo 'gitleaks 8.30.1 linux-amd64 https://example.invalid/c cc' > "$TOOLS_LOCK"
  echo 'fetch_latest_version() { return 1; }' > "$TEST_TMP/o.sh"
  assert_status 1 it_run "$TEST_TMP/o.sh" --outdated
  assert_contains "$OUT" 'gitleaks'
}
