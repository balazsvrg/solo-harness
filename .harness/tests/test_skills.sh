# shellcheck shell=bash
# Tests for skill frontmatter validation (R2).

test_skill_frontmatter() {
  # AC-1-8
  local r c="$HARNESS_ROOT/.harness/check/skills-frontmatter.sh"
  r=$(new_repo)
  mkdir -p "$r/.agents/skills/"{good,noname,nodesc,nofm}
  printf -- '---\nname: good\ndescription: Does a thing.\n---\n# Good\n' > "$r/.agents/skills/good/SKILL.md"
  assert_status 0 "$c" "$r"
  printf -- '---\ndescription: x\n---\n' > "$r/.agents/skills/noname/SKILL.md"
  printf -- '---\nname: nodesc\ndescription:\n---\n' > "$r/.agents/skills/nodesc/SKILL.md"
  printf -- '# no frontmatter\nname: x\ndescription: y\n' > "$r/.agents/skills/nofm/SKILL.md"
  assert_status 1 "$c" "$r"
  assert_contains "$OUT" 'noname/SKILL.md: missing name'
  assert_contains "$OUT" 'nodesc/SKILL.md: missing description'
  assert_contains "$OUT" 'nofm/SKILL.md'
  assert_not_contains "$OUT" 'good/SKILL.md'
}
