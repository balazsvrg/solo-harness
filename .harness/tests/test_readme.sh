# shellcheck shell=bash
# Tests for the template README (R20, T11). This file is template-only: bootstrap
# deletes it, because a project writes its own README.

MARK_START='<!-- solo-harness:template-only:start -->'
MARK_END='<!-- solo-harness:template-only:end -->'

# section HEADING: the README text under `## HEADING`, up to the next `## ` heading.
section() { awk -v h="## $1" '$0 == h {on=1; next} on && /^## / {exit} on' "$HARNESS_ROOT/README.md"; }

# assert_section HEADING NEEDLE...: the section exists and contains each NEEDLE.
assert_section() {
  local h=$1 text n; shift
  text=$(section "$h")
  [[ -n $text ]] || fail "README: no '## $h' section"
  for n in "$@"; do assert_contains "$text" "$n"; done
}

test_readme_has_r20_sections() {
  # R20
  local h
  for h in 'Quick start' 'Lifecycle and change sizes' 'Enforcement layers' 'Bootstrap' \
    'Strict and honor mode' 'Sandbox' 'Stack overlays' 'Recommended skills not included' \
    'Plugin duplicates' 'Dependabot PRs' 'Deferred decisions'; do
    grep -qxF "## $h" "$HARNESS_ROOT/README.md" || fail "README: no '## $h' heading"
  done
}

test_readme_diagrams() {
  # R20, R21: the lifecycle, the enforcement layers and the bootstrap flow are Mermaid diagrams.
  local h
  for h in 'Lifecycle and change sizes' 'Enforcement layers' 'Bootstrap'; do
    assert_section "$h" '```mermaid'
  done
}

test_readme_section_content() {
  # R20
  assert_section 'Lifecycle and change sizes' '**S**' '**M**' '**L**' 'code-review' 'finish'
  assert_section 'Strict and honor mode' 'honor mode' '403' 'dependency-review' 'CodeQL' 'push protection'
  assert_section 'Sandbox' '"sandbox"' '"enabled": true' '.claude/settings.json'
  assert_section 'Stack overlays' 'check-app' 'fmt' 'dependabot.yml' 'release-type' 'public'
  assert_section 'Recommended skills not included' 'prototype' 'triage' 'improve-codebase-architecture' 'research' 'implement-spec'
  assert_section 'Plugin duplicates' 'enabledPlugins'
  assert_section 'Deferred decisions' 'signed commits' 'overlays'
}

test_readme_bootstrap_usage() {
  # R18, design §8: flags, .template-version, TEMPLATE_REPO and release tags.
  assert_section 'Bootstrap' '--template' '--dry-run' '--local' '--add-agent <name>' \
    '.template-version' 'repo=' 'version=' 'agents=' 'TEMPLATE_REPO' '.harness/config' 'v<version>'
}

test_readme_dependabot_prs() {
  # R17: which Dependabot PRs pass docs-gate and test-oracle (design §7).
  assert_section 'Dependabot PRs' 'dependabot[bot]' '.github/workflows/' 'uses:' 'docs-gate' 'test-oracle' 'SHA'
}

test_readme_template_only_sections() {
  # R18 step 10: template sections sit between markers; bootstrap deletes them and this file.
  local h
  for h in 'Quick start' 'Deferred decisions'; do
    awk -v s="$MARK_START" -v e="$MARK_END" -v h="## $h" \
      '$0 == s {on=1} $0 == e {on=0} $0 == h {found=1; exit !on} END {if (!found) exit 1}' \
      "$HARNESS_ROOT/README.md" || fail "README: '## $h' is not between the template-only markers"
  done
  grep -qxF .harness/tests/test_readme.sh "$HARNESS_ROOT/.template-only" || fail '.template-only must list this test file'
}
