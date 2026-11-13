# shellcheck shell=bash
# Tests for the git hooks in .githooks/ (R11).

# hook_repo CHECK_RECIPE: print a fixture repo that uses .githooks and whose `make check` runs CHECK_RECIPE.
hook_repo() {
  local r
  r=$(new_repo)
  printf 'check:\n\t@%s\n' "$1" > "$r/Makefile"
  git -C "$r" config user.name t
  git -C "$r" config user.email t@t
  git -C "$r" config core.hooksPath "$HARNESS_ROOT/.githooks"
  git -C "$r" add Makefile
  printf '%s\n' "$r"
}

# with_gitleaks REPO: put the pinned gitleaks where the hook looks first.
with_gitleaks() {
  mkdir -p "$1/.harness/bin"
  ln -s "$HARNESS_ROOT/.harness/bin/gitleaks" "$1/.harness/bin/gitleaks"
  echo .harness/ >> "$1/.git/info/exclude"
}

# path_without_harness_bin: print PATH without .harness/bin, so gitleaks is not found.
path_without_harness_bin() { tr ':' '\n' <<<"$PATH" | grep -vx "$HARNESS_ROOT/.harness/bin" | paste -sd:; }

test_pre_commit_runs_check() {
  # AC-1-18
  local r
  r=$(hook_repo 'echo check-ran; exit 1')
  with_gitleaks "$r"
  assert_status 1 git -C "$r" commit -m 'feat: x'
  assert_contains "$OUT" 'check-ran'
  r=$(hook_repo 'echo check-ran')
  with_gitleaks "$r"
  assert_status 0 git -C "$r" commit -m 'feat: x'
  assert_contains "$OUT" 'check-ran'
}

test_pre_commit_blocks_staged_secret() {
  # AC-1-18
  local r
  r=$(hook_repo 'true')
  with_gitleaks "$r"
  printf 'token = "%s%s"\n' ghp_ 8f3Kq2LmZ9xW4vB7nR1tY6uP0sD5aE3hJ2cG > "$r/a.txt"  # split so scanners skip this file
  git -C "$r" add a.txt
  assert_status 1 git -C "$r" commit -m 'feat: x'
  assert_eq "$(git -C "$r" rev-list --all | wc -l)" 0 'no commit'
  # `commit -a` puts the secret only in git's temporary index.
  git -C "$r" rm -q --cached a.txt
  git -C "$r" commit -qm 'feat: x'
  printf '# token = "%s%s"\n' ghp_ 8f3Kq2LmZ9xW4vB7nR1tY6uP0sD5aE3hJ2cG >> "$r/Makefile"
  assert_status 1 git -C "$r" commit -am 'feat: y'
  assert_eq "$(git -C "$r" rev-list --all | wc -l)" 1 'no second commit'
}

test_pre_commit_warns_without_gitleaks() {
  # AC-1-18
  local r p
  r=$(hook_repo 'true')
  p=$(path_without_harness_bin)
  if PATH=$p command -v gitleaks >/dev/null; then
    echo 'SKIP: gitleaks is on PATH outside .harness/bin, so the test cannot hide it' >&2
    return 0
  fi
  assert_status 0 env PATH="$p" git -C "$r" commit -m 'feat: x'
  assert_contains "$OUT" 'gitleaks is not installed'
}

test_pre_commit_check_sees_no_git_env() {
  # AC-1-18 (the commits that `check` makes in other repos stay correct)
  local r o
  o=$(new_repo)
  touch "$o/inner"
  r=$(hook_repo "cd '$o' && git add inner && git -c user.name=t -c user.email=t@t commit -qm 'chore: inner'")
  with_gitleaks "$r"
  touch "$r/outer" && git -C "$r" add outer
  echo x >> "$r/outer"
  assert_status 0 git -C "$r" commit -am 'feat: outer'
  assert_eq "$(git -C "$o" ls-tree --name-only HEAD)" 'inner' 'inner repo tree'
  assert_eq "$(git -C "$r" log -1 --format=%s)" 'feat: outer'
  assert_eq "$(git -C "$r" status --porcelain)" '' 'outer repo clean'
}

commit_msg() { printf '%s' "$1" > "$TEST_TMP/msg"; "$HARNESS_ROOT/.githooks/commit-msg" "$TEST_TMP/msg"; }

test_commit_msg_accepts_only_conventional() {
  # AC-1-19
  local m
  for m in 'feat: add x' 'fix(guard): allow reads' 'feat!: drop y' 'refactor(api)!: rename z' 'chore: x' 'revert: undo x' \
    $'docs: x\n\nBody line.' $'# a comment\nci: pin actions\n' 'Merge branch '\''x'\'' into y' 'Revert "feat: add x"' \
    'Merge remote-tracking branch '\''origin/main'\''' 'Merge pull request #3 from o/x' 'Merge tag '\''v1'\''' \
    'Merge commit '\''abc'\''' 'fixup! feat: add x' 'squash! fix: y' 'amend! fix: y'; do
    assert_status 0 commit_msg "$m"
  done
  for m in 'add x' 'feature: add x' 'feat:add x' 'feat: ' 'feat(): x' 'Feat: x' 'feat x' '' $'# only a comment\n' \
    'wip' 'fix(guard) x' 'Merge stuff' 'Revert x'; do
    assert_status 1 commit_msg "$m"
    assert_contains "$OUT" 'Conventional Commits'
  done
}
