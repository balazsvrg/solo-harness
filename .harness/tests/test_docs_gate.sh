# shellcheck shell=bash
# Tests for the docs-gate CI script (R13). The script reads a numstat changes file,
# a PR body file and PR_LABELS, and checks the checkout in the current directory.
# Each test turns its temp dir into a small repo. PR bodies are in fixtures/.

FIX=$HARNESS_ROOT/.harness/tests/fixtures

gate() { "$HARNESS_ROOT/.harness/ci/docs-gate.sh" "$@"; }

# body FIELD_LINE...: write a PR body with these field lines to ./body.md.
body() { { printf '%s\n' "$@"; printf '\n## Summary\n\nText.\n'; } > body.md; }

# put PATH [CONTENT]: create a file in the repo under test.
put() { mkdir -p "$(dirname "$1")"; printf '%s\n' "${2:-x}" > "$1"; }

init_repo() { git init -q .; printf 'changes\nbody.md\n' > .git/info/exclude; }

test_docs_gate_missing_fields_fail() {
  # AC-1-20: a body without Size, Change or ADR fails and names the field.
  init_repo
  numstat 1 0 src/a.py
  local f
  for f in Size Change ADR; do
    grep -v "^$f:" "$FIX/pr-body-s.md" > body.md
    assert_status 1 gate changes body.md
    assert_contains "$OUT" "AC-1-20"
    assert_contains "$OUT" "$f"
  done
  assert_status 0 gate changes "$FIX/pr-body-s.md"
}

test_docs_gate_invalid_fields_fail() {
  # AC-1-20: values outside the R13 format fail.
  init_repo
  numstat 1 0 src/a.py
  local bad
  for bad in 'Size: XL' 'Size: <S|M|L>' 'Change: specs/changes/Foo' 'Change: specs/changes/7-x/' \
    'ADR: none' 'ADR: none – <reason>' 'ADR: adr/0001-x.md' 'ADR: docs/adr/../../README.md'; do
    { printf 'Size: S\nChange: none\nADR: none - small fix\n' | grep -v "^${bad%%:*}:"; printf '%s\n' "$bad"; } > body.md
    assert_status 1 gate changes body.md
    assert_contains "$OUT" "AC-1-20"
  done
}

test_docs_gate_accepts_dashes_and_crlf() {
  # AC-1-20: the reason dash can be -, – or —, and the body can have Windows line endings.
  init_repo
  numstat 1 0 src/a.py
  local d
  for d in '-' '–' '—'; do
    printf 'Size: S\r\nChange: none\r\nADR: none %s typo fix\r\n' "$d" > body.md
    assert_status 0 gate changes body.md
  done
}

test_docs_gate_missing_input_fails() {
  # AC-1-20: no changes file or no body file is a usage error, not a pass.
  init_repo
  numstat 1 0 src/a.py
  assert_status 2 gate
  assert_status 2 gate changes
  assert_status 2 gate changes does-not-exist
  assert_contains "$OUT" 'BODY_FILE'
  assert_status 2 gate does-not-exist "$FIX/pr-body-s.md"
  assert_contains "$OUT" 'BODY_FILE'
}

test_docs_gate_s_over_150_lines_fails() {
  # AC-1-21: an S PR over 150 changed lines fails; lockfiles do not count; size-exception passes.
  init_repo
  numstat 100 50 src/a.py 9000 0 package-lock.json
  assert_status 0 gate changes "$FIX/pr-body-s.md"
  numstat 100 51 src/a.py
  assert_status 1 gate changes "$FIX/pr-body-s.md"
  assert_contains "$OUT" 'AC-1-21'
  assert_contains "$OUT" '151'
  PR_LABELS='bug,size-exception' assert_status 0 gate changes "$FIX/pr-body-s.md"
}

test_docs_gate_s_touching_living_spec_fails() {
  # AC-1-21: an S PR that changes specs/<capability>.md fails; a file in specs/changes/ does not count.
  init_repo
  numstat 1 0 specs/changes/7-x/tasks.md
  assert_status 0 gate changes "$FIX/pr-body-s.md"
  numstat 1 0 specs/ci.md
  assert_status 1 gate changes "$FIX/pr-body-s.md"
  assert_contains "$OUT" 'AC-1-21'
  assert_contains "$OUT" 'specs/ci.md'
  PR_LABELS='size-exception' assert_status 0 gate changes "$FIX/pr-body-s.md"
}

test_docs_gate_m_l_need_change_folder() {
  # AC-1-20: an M or L PR must name its change folder.
  init_repo
  numstat 1 0 src/a.py
  body 'Size: M' 'Change: none' 'ADR: none - no design choice'
  assert_status 1 gate changes body.md
  assert_contains "$OUT" 'AC-1-20'
}

ARCH=specs/changes/archive/2026-11-12-7-thing

# finished_l_change: a tree and changes file for an L PR after `finish` ran
# (pr-body-l.md). Every check passes on it.
finished_l_change() {
  init_repo
  put "$ARCH/proposal.md" '- **AC-7-1** One. - **AC-7-2** Two. Not ours: AC-1-99.'
  put "$ARCH/tasks.md" '- [x] done'
  put "$ARCH/design.md"
  put specs/thing.md
  put docs/adr/0001-use-thing.md
  put tests/test_thing.py $'# AC-7-1\n# AC-7-2'
  numstat 10 0 "$ARCH/proposal.md" 5 0 "$ARCH/tasks.md" 5 0 "$ARCH/design.md" 3 1 specs/thing.md \
    20 0 docs/adr/0001-use-thing.md 9 0 tests/test_thing.py 400 0 src/thing.py
}

test_docs_gate_finished_l_change_passes() {
  # AC-1-22: an L PR with the archive folder, all tasks checked and a living spec change passes.
  finished_l_change
  assert_status 0 gate changes "$FIX/pr-body-l.md"
}

test_docs_gate_m_l_without_archive_fails() {
  # AC-1-22: no archive folder for the change in Change: fails.
  finished_l_change
  numstat 3 1 specs/thing.md 400 0 src/thing.py
  assert_status 1 gate changes "$FIX/pr-body-l.md"
  assert_contains "$OUT" 'AC-1-22'
  assert_contains "$OUT" 'specs/changes/archive/YYYY-MM-DD-7-thing'
}

test_docs_gate_archive_needs_its_files() {
  # AC-1-22: the archive has proposal.md and tasks.md, plus design.md for L only.
  finished_l_change
  numstat 10 0 "$ARCH/proposal.md" 5 0 "$ARCH/tasks.md" 3 1 specs/thing.md
  assert_status 1 gate changes "$FIX/pr-body-l.md"
  assert_contains "$OUT" 'design.md'
  sed 's/^Size: L/Size: M/' "$FIX/pr-body-l.md" > body.md
  assert_status 0 gate changes body.md
  numstat 10 0 "$ARCH/proposal.md" 3 1 specs/thing.md
  assert_status 1 gate changes body.md
  assert_contains "$OUT" 'tasks.md'
}

test_docs_gate_archive_with_open_tasks_fails() {
  # AC-1-22: an unchecked "- [ ]" in the archived tasks.md fails.
  finished_l_change
  local open
  for open in '  - [ ] not done' '* [ ] not done' '+ [ ] not done' '1. [ ] not done'; do
    put "$ARCH/tasks.md" $'- [x] done\n'"$open"
    assert_status 1 gate changes "$FIX/pr-body-l.md"
    assert_contains "$OUT" 'AC-1-22'
    assert_contains "$OUT" 'unchecked'
  done
}

test_docs_gate_m_l_without_living_spec_fails() {
  # AC-1-22: an M/L PR changes at least one specs/<capability>.md.
  finished_l_change
  numstat 10 0 "$ARCH/proposal.md" 5 0 "$ARCH/tasks.md" 5 0 "$ARCH/design.md"
  assert_status 1 gate changes "$FIX/pr-body-l.md"
  assert_contains "$OUT" 'AC-1-22'
  assert_contains "$OUT" 'living spec'
}

test_docs_gate_uncovered_ac_fails() {
  # AC-1-23: an AC id of the change that no test file names fails, and the id is reported.
  finished_l_change
  put tests/test_thing.py '# AC-7-1'
  assert_status 1 gate changes "$FIX/pr-body-l.md"
  assert_contains "$OUT" 'AC-1-23'
  assert_contains "$OUT" 'AC-7-2'
  assert_not_contains "$OUT" 'AC-1-99'
}

test_docs_gate_ac_search_uses_test_globs_only() {
  # AC-1-23: an id only in a file outside TEST_GLOBS does not count, and AC-7-20 is not AC-7-2.
  finished_l_change
  put tests/test_thing.py $'# AC-7-1\n# AC-7-20'
  put src/thing.py '# AC-7-2'
  put docs/notes.md 'AC-7-2'
  assert_status 1 gate changes "$FIX/pr-body-l.md"
  assert_contains "$OUT" 'AC-7-2'
  put src/thing.test.ts '// AC-7-2'
  assert_status 0 gate changes "$FIX/pr-body-l.md"
}

test_docs_gate_missing_adr_file_fails() {
  # AC-1-24: ADR: names a file that is not in the checkout.
  init_repo
  numstat 1 0 src/a.py
  body 'Size: S' 'Change: none' 'ADR: docs/adr/0002-missing.md'
  assert_status 1 gate changes body.md
  assert_contains "$OUT" 'AC-1-24'
  assert_contains "$OUT" 'docs/adr/0002-missing.md'
  put docs/adr/0002-missing.md
  assert_status 0 gate changes body.md
}

test_docs_gate_adr_none_on_l_is_flagged() {
  # AC-1-24: ADR: none on an L PR passes, and the job summary flags it.
  finished_l_change
  sed 's|^ADR: .*|ADR: none – the choice is easy to reverse|' "$FIX/pr-body-l.md" > body.md
  GITHUB_STEP_SUMMARY=$PWD/summary.md assert_status 0 gate changes body.md
  assert_contains "$(cat summary.md)" 'ADR: none on an L PR'
  sed 's/^Size: L/Size: M/' body.md > body-m.md
  GITHUB_STEP_SUMMARY=$PWD/summary2.md assert_status 0 gate changes body-m.md
  assert_not_contains "$(cat summary2.md)" 'ADR: none on'
}

test_docs_gate_docs_map_rule() {
  # AC-1-25: a change to a mapped glob needs a change to its doc.
  init_repo
  put .docs-map $'# <glob> -> <doc path>\n\nsrc/api/** -> docs/api.md\n'
  numstat 5 0 src/api/users.py
  assert_status 1 gate changes "$FIX/pr-body-s.md"
  assert_contains "$OUT" 'AC-1-25'
  assert_contains "$OUT" 'docs/api.md'
  numstat 5 0 src/api/users.py 2 0 docs/api.md
  assert_status 0 gate changes "$FIX/pr-body-s.md"
  numstat 5 0 src/cli/main.py
  assert_status 0 gate changes "$FIX/pr-body-s.md"
}

test_docs_gate_docs_unchanged_escape() {
  # AC-1-25: "Docs: unchanged – <reason>" lets the PR pass; a placeholder reason does not.
  init_repo
  put .docs-map 'src/api/** -> docs/api.md'
  numstat 5 0 src/api/users.py
  body 'Size: S' 'Change: none' 'ADR: none – bugfix' 'Docs: unchanged – internal refactor, same API'
  assert_status 0 gate changes body.md
  assert_contains "$OUT" 'internal refactor'
  body 'Size: S' 'Change: none' 'ADR: none – bugfix' 'Docs: unchanged – <reason>'
  assert_status 1 gate changes body.md
  assert_contains "$OUT" 'AC-1-25'
}

test_docs_gate_invalid_docs_map_line_fails() {
  # AC-1-25: a .docs-map line without " -> " is an error, not an ignored rule.
  init_repo
  put .docs-map 'src/api/** docs/api.md'
  numstat 5 0 src/api/users.py
  assert_status 1 gate changes "$FIX/pr-body-s.md"
  assert_contains "$OUT" '.docs-map'
}

test_docs_map_ships_empty() {
  # AC-1-25: the template .docs-map has no rules, only comments that show the format.
  assert_file "$HARNESS_ROOT/.docs-map"
  assert_eq "$(grep -vcE '^[[:space:]]*(#|$)' "$HARNESS_ROOT/.docs-map")" 0 'rule lines'
  assert_contains "$(cat "$HARNESS_ROOT/.docs-map")" '<glob> -> <doc path>'
}

test_docs_gate_skips_html_comments() {
  # AC-1-20: a field line inside an HTML comment is not shown on GitHub, so it does not count.
  init_repo
  numstat 1 0 src/a.py
  printf '<!-- Size: S -->\nChange: none\n<!--\nSize: S\nADR: none - x\n-->\n' > body.md
  assert_status 1 gate changes body.md
  assert_contains "$OUT" 'Size: must be'
  printf 'Size: S <!-- small -->\nChange: none\nADR: none - x\n<!-- \nDocs: unchanged - <reason>\n-->\n' > body.md
  assert_status 0 gate changes body.md
}
