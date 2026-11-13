# shellcheck shell=bash
# Tests for the PR template and issue forms (R19). docs-gate (R13) parses the PR template fields.

GH=$HARNESS_ROOT/.github
PR_TEMPLATE=$GH/PULL_REQUEST_TEMPLATE.md

# form_labels FILE: the field labels of an issue form, one per line.
form_labels() { sed -nE 's/^ +label: *"?([^"]*)"? *$/\1/p' "$1"; }

test_pr_template_has_r19_parts() {
  # R19: Size, Change, ADR and optional Docs fields, summary, how it was tested, linked issue.
  assert_file "$PR_TEMPLATE"
  local t; t=$(cat "$PR_TEMPLATE")
  local want
  for want in $'\nSize: ' $'\nChange: ' $'\nADR: ' 'Docs: unchanged – ' '## Summary' '## How I tested it' 'Closes #'; do
    assert_contains $'\n'"$t" "$want"
  done
}

test_pr_template_fields_match_docs_gate() {
  # AC-1-20: the unfilled template fails docs-gate; with its values filled in, it passes.
  local gate=$HARNESS_ROOT/.harness/ci/docs-gate.sh
  git init -q .
  printf '1\t0\tsrc/a.py\0' > changes
  assert_status 1 "$gate" changes "$PR_TEMPLATE"
  assert_contains "$OUT" 'AC-1-20'
  sed -e 's/^Size: .*/Size: S/' -e 's/^Change: .*/Change: none/' -e 's/^ADR: .*/ADR: none – typo fix/' \
    "$PR_TEMPLATE" > body.md
  assert_status 0 "$gate" changes body.md
}

test_issue_form_change_request() {
  # R19: issue form "Change request" asks for the problem, acceptance ideas and a proposed size.
  local f=$GH/ISSUE_TEMPLATE/change-request.yml
  assert_file "$f"
  grep -qx 'name: Change request' "$f" || fail "$f: name is not 'Change request'"
  assert_eq "$(form_labels "$f" | xargs -d '\n')" 'Problem Acceptance ideas Proposed size'
  grep -qE '^ +- (S|M|L)$' "$f" || fail "$f: proposed size has no S/M/L options"
}

test_issue_form_bug() {
  # R19: issue form "Bug" asks for expected and actual behaviour and the reproduction steps.
  local f=$GH/ISSUE_TEMPLATE/bug.yml
  assert_file "$f"
  grep -qx 'name: Bug' "$f" || fail "$f: name is not 'Bug'"
  assert_eq "$(form_labels "$f" | xargs -d '\n')" 'Expected behaviour Actual behaviour Steps to reproduce'
}
