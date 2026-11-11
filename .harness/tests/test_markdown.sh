# shellcheck shell=bash disable=SC2016
# Tests for Markdown checks (R21).

test_unterminated_mermaid_fails() {
  # AC-1-31
  local r c="$HARNESS_ROOT/.harness/check/markdown.sh"
  assert_status 0 "$c" "$HARNESS_ROOT"
  r=$(new_repo)
  printf '# A\n\n```mermaid\nflowchart LR\n  a --> b\n```\n\n```bash\necho\n```\n' > "$r/ok.md"
  assert_status 0 "$c" "$r"
  printf '# B\n\n```mermaid\nflowchart LR\n  a --> b\n' > "$r/bad.md"
  assert_status 1 "$c" "$r"
  assert_contains "$OUT" 'bad.md:3'
  rm "$r/bad.md"
  printf '````md\n```mermaid\n````\n' > "$r/nested.md"
  assert_status 0 "$c" "$r"
}

test_image_embed_fails() {
  # AC-1-33
  local r c="$HARNESS_ROOT/.harness/check/markdown.sh"
  r=$(new_repo)
  mkdir -p "$r/docs" "$r/specs"
  printf 'See `![x](y.png)` and [link](a.png).\n' > "$r/docs/ok.md"
  printf '```\n![x](y.png)\n```\n' > "$r/specs/fenced.md"
  printf '![x](y.png)\n' > "$r/README.md"
  assert_status 0 "$c" "$r"
  printf 'Text ![diagram](img/arch.SVG "t") more\n' > "$r/docs/bad.md"
  printf '![x](./a.jpeg)\n' > "$r/specs/bad.md"
  assert_status 1 "$c" "$r"
  assert_contains "$OUT" 'docs/bad.md:1'
  assert_contains "$OUT" 'specs/bad.md:1'
}
