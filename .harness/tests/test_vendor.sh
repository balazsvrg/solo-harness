# shellcheck shell=bash disable=SC2016
# Tests for vendored skills, license notices and scripts/vendor-diff (R2).

VENDORED_SKILLS=(asd-ste100 code-review codebase-design diagnosing-bugs domain-modeling grill-with-docs
  grilling handoff implement pr retro tdd to-spec to-tickets wizard writing-for-agents)
SHA=4ae2317ddb22b046e26455e4f9c9b3aaaf62212d

vcheck() { "$HARNESS_ROOT/.harness/check/vendored.sh" "$@"; }

# fixture_repo: a repo with one vendored skill `foo` (modified) and its notices.
fixture_repo() {
  local r; r=$(new_repo)
  mkdir -p "$r/.agents/skills/foo"
  printf -- '---\nname: foo\ndescription: Local foo.\n---\nlocal line\n' > "$r/.agents/skills/foo/SKILL.md"
  cat > "$r/.agents/skills/VENDORED.md" <<EOF
| Skill | Source | Path | Commit | License | Changes |
|---|---|---|---|---|---|
| \`foo\` | acme/skills | skills/foo | $SHA | MIT | Adds a local line |
EOF
  cat > "$r/THIRD_PARTY_LICENSES.md" <<'EOF'
## acme/skills

Modified skills: `foo`.

MIT License

Copyright (c) 2026 Acme

Permission is hereby granted, free of charge, to any person obtaining a copy
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
EOF
  printf '%s\n' "$r"
}

test_vendored_rows_complete() {
  # AC-1-5
  assert_status 0 vcheck "$HARNESS_ROOT"
  local s rows
  rows=$(grep -oE '^\| `[a-z0-9-]+`' "$HARNESS_ROOT/.agents/skills/VENDORED.md" | tr -d '|` ' | sort)
  assert_eq "$rows" "$(printf '%s\n' "${VENDORED_SKILLS[@]}" | sort)" 'one row per vendored skill'
  for s in "${VENDORED_SKILLS[@]}"; do assert_file "$HARNESS_ROOT/.agents/skills/$s/SKILL.md"; done

  local r; r=$(fixture_repo)
  assert_status 0 vcheck "$r"
  sed -i "s/| $SHA |/| abc123 |/" "$r/.agents/skills/VENDORED.md"
  assert_status 1 vcheck "$r"
  assert_contains "$OUT" 'foo: commit'
  sed -i "s/| abc123 |/| $SHA |/; s/| MIT |/|  |/" "$r/.agents/skills/VENDORED.md"
  assert_status 1 vcheck "$r"
  assert_contains "$OUT" 'foo: empty'
  sed -i 's/|  |/| MIT |/' "$r/.agents/skills/VENDORED.md"
  mkdir -p "$r/.agents/skills/bar"
  printf -- '---\nname: bar\ndescription: x\n---\n' > "$r/.agents/skills/bar/SKILL.md"
  assert_status 1 vcheck "$r"
  assert_contains "$OUT" 'bar: no row'
  printf '\n## Original skills\n\n- `bar`\n' >> "$r/.agents/skills/VENDORED.md"
  assert_status 0 vcheck "$r"
  rm -r "$r/.agents/skills/foo"
  assert_status 1 vcheck "$r"
  assert_contains "$OUT" 'foo: missing'
}

test_skills_symlinks() {
  # AC-1-5: one skills directory, linked for Claude Code and Copilot.
  assert_eq "$(readlink "$HARNESS_ROOT/.claude/skills")" ../.agents/skills
  assert_eq "$(readlink "$HARNESS_ROOT/.github/skills")" ../.agents/skills
}

test_third_party_licenses() {
  # AC-1-6
  local f=$HARNESS_ROOT/THIRD_PARTY_LICENSES.md
  assert_contains "$(cat "$f")" 'Copyright (c) 2026 Matt Pocock'
  assert_contains "$(cat "$f")" 'Copyright (c) 2026 Dustin Yuchen Teng'
  [[ $(grep -c 'Permission is hereby granted, free of charge' "$f") -ge 2 ]] || fail 'two full MIT notices'
  [[ $(grep -c 'THE SOFTWARE IS PROVIDED "AS IS"' "$f") -ge 2 ]] || fail 'two full MIT notices'

  local r; r=$(fixture_repo)
  sed -i '/Modified skills/d' "$r/THIRD_PARTY_LICENSES.md"
  assert_status 1 vcheck "$r"
  assert_contains "$OUT" 'foo: modified but not listed'
  r=$(fixture_repo)
  sed -i '/Permission is hereby granted/d' "$r/THIRD_PARTY_LICENSES.md"
  assert_status 1 vcheck "$r"
  assert_contains "$OUT" 'acme/skills: no full MIT notice'
}

# vd_run REPO OVERRIDES_FILE ARGS...: run vendor-diff main against REPO with fetch overridden.
vd_run() {
  VENDOR_ROOT=$1 bash -c 'set -euo pipefail; source "$1"; source "$2"; shift 2; main "$@"' _ \
    "$HARNESS_ROOT/scripts/vendor-diff" "${@:2}"
}

snapshot() { (cd "$1" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum); }

test_vendor_diff_prints_and_writes_nothing() {
  # AC-1-7
  local r; r=$(fixture_repo)
  cat > "$TEST_TMP/o.sh" <<'O'
fetch_upstream() {
  [[ $1 == acme/skills ]] || exit 9
  mkdir -p "$2/skills/foo"
  printf -- '---\nname: foo\ndescription: Upstream foo.\n---\nupstream line\n' > "$2/skills/foo/SKILL.md"
  echo ffffffffffffffffffffffffffffffffffffffff
}
O
  local before; before=$(snapshot "$r")
  mkdir "$TEST_TMP/tmp"
  TMPDIR=$TEST_TMP/tmp assert_status 0 vd_run "$r" "$TEST_TMP/o.sh"
  assert_contains "$OUT" '== foo'
  assert_contains "$OUT" '-local line'
  assert_contains "$OUT" '+upstream line'
  assert_contains "$OUT" 'ffffffff'
  assert_eq "$(snapshot "$r")" "$before" 'repo unchanged'
  assert_eq "$(ls -A "$TEST_TMP/tmp")" '' 'temp files removed'

  cat > "$TEST_TMP/same.sh" <<'O'
fetch_upstream() { mkdir -p "$2/skills"; cp -r "$VENDOR_ROOT/.agents/skills/foo" "$2/skills/"; echo eeee; }
O
  assert_status 0 vd_run "$r" "$TEST_TMP/same.sh"
  assert_contains "$OUT" 'foo: no changes'
  assert_status 2 vd_run "$r" "$TEST_TMP/same.sh" nosuch
  assert_contains "$OUT" 'nosuch'
}

test_side_effect_skills_not_model_invoked() {
  # AC-1-9
  local s fm
  for s in to-spec to-tickets implement handoff pr finish retro; do
    fm=$(awk 'NR>1 && $0=="---" {exit} NR>1 {print}' "$HARNESS_ROOT/.agents/skills/$s/SKILL.md")
    grep -qx 'disable-model-invocation: true' <<<"$fm" || fail "$s: needs disable-model-invocation: true"
  done
}

test_code_review_docs_drift_rule() {
  # AC-1-26
  local f; f=$(cat "$HARNESS_ROOT/.agents/skills/code-review/SKILL.md")
  assert_contains "$f" '**Docs drift**'
  assert_contains "$f" 'user-visible behaviour, configuration, CLI flags or architecture'
  assert_contains "$f" 'or the PR says why not'
}

test_skills_draw_mermaid() {
  # AC-1-32 (skills part)
  local s
  for s in to-spec domain-modeling finish; do
    grep -q 'Mermaid code block' "$HARNESS_ROOT/.agents/skills/$s/SKILL.md" || fail "$s: no Mermaid instruction"
  done
}

test_no_tracker_setup_references() {
  # R2: tracker-setup is not vendored; no skill may send the user to it.
  local hits; hits=$(grep -rl 'setup-matt-pocock-skills' "$HARNESS_ROOT/.agents/skills" || true)
  assert_eq "$hits" '' 'skills that still name /setup-matt-pocock-skills'
}

test_finish_skill_steps() {
  # AC-1-10
  local d=$HARNESS_ROOT/.agents/skills/finish f
  assert_file "$d/SKILL.md"
  f=$(cat "$d/SKILL.md")
  assert_eq "$(grep -cE '^## [1-5]\. ' "$d/SKILL.md")" 5 'five numbered steps'
  # R3 step 1: verify tasks and AC coverage, stop on failure.
  assert_contains "$f" '## 1. Verify'
  assert_contains "$f" 'AC-<id>-<n>'
  # R3 step 2: apply deltas, archive with the folder name change-folders.sh accepts.
  assert_contains "$f" '## 2. Archive'
  assert_contains "$f" 'ADDED/MODIFIED/REMOVED'
  assert_contains "$f" 'specs/changes/archive/YYYY-MM-DD-<id>-<slug>/'
  # R3 step 3: ADRs through domain-modeling, glossary, PR ADR field.
  assert_contains "$f" '## 3. Record decisions'
  assert_contains "$f" 'domain-modeling'
  assert_contains "$f" 'GLOSSARY.md'
  assert_contains "$f" 'ADR:'
  # R3 step 4: release check, hands off CHANGELOG and the release PR.
  assert_contains "$f" '## 4. Check the release'
  assert_contains "$f" 'Conventional Commit'
  assert_contains "$f" 'CHANGELOG.md'
  # R3 step 5: issue and retro.
  assert_contains "$f" '## 5. Close the loop'
  assert_contains "$f" 'retro'
  assert_contains "$(cat "$d/agents/openai.yaml")" 'allow_implicit_invocation: false'
  grep -q -- '^- `finish`' "$HARNESS_ROOT/.agents/skills/VENDORED.md" || fail 'finish not listed as an original skill'
}
