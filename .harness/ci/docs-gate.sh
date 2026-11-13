#!/usr/bin/env bash
# docs-gate (R13): check the PR-body fields and the documentation that the PR size needs.
# Usage: PR_LABELS=a,b [PR_AUTHOR=login PR_DIFF=file] docs-gate.sh CHANGES_FILE BODY_FILE
# A Dependabot PR that changes only uses: pins passes (dependabot_pin_only in common.sh).
# Run it at the root of the PR merge checkout. It writes a Markdown summary to
# $GITHUB_STEP_SUMMARY when that is set, else to stdout. Failures also go to stderr.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
[[ -n ${1:-} && -r $1 && -n ${2:-} && -r $2 ]] ||
  { err "usage: ${0##*/} CHANGES_FILE BODY_FILE (CHANGES_FILE: git diff --numstat -z --no-renames output)"; exit 2; }
load_changes "$1"
body_file=$2

# to_summary CMD...: run CMD with its output to $GITHUB_STEP_SUMMARY when that is set, else to stdout.
to_summary() { if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then "$@" >> "$GITHUB_STEP_SUMMARY"; else "$@"; fi; }

if dependabot_pin_only; then
  # shellcheck disable=SC2016 # literal backticks
  msg='Dependabot PR that changes only `uses:` pins: the field and docs checks do not apply.'
  to_summary printf '## docs-gate: pass\n\n%s\n' "$msg"
  exit 0
fi

failures=() notes=()
fail_ac() { failures+=("**$1** $2"); err "docs-gate: $1: $2"; }

# A reason after "none" or "unchanged": any dash a person types, then text that is not a <placeholder>.
DASH='[[:space:]]*(-|–|—)[[:space:]]*'
REASON='([^<[:space:]].*|<.*[^>[:space:]])'

# The body without CR characters and without HTML comments, which GitHub does not show.
body=$(tr -d '\r' < "$body_file" | awk '{
  out = ""
  while ($0 != "") {
    if (c) { i = index($0, "-->"); if (!i) break; $0 = substr($0, i + 3); c = 0 }
    else { i = index($0, "<!--"); if (!i) { out = out $0; break } out = out substr($0, 1, i - 1); $0 = substr($0, i + 4); c = 1 }
  }
  print out
}')

# field NAME: print the value of the first body line "NAME: value".
field() {
  local line
  while IFS= read -r line; do
    if [[ $line == "$1:"* ]]; then
      line=${line#"$1:"}
      line=${line#"${line%%[![:space:]]*}"}
      printf '%s' "${line%"${line##*[![:space:]]}"}"
      return 0
    fi
  done <<< "$body"
  return 1
}

# summary: print the Markdown summary.
summary() {
  local f
  printf '## docs-gate: %s\n\n' "$( ((${#failures[@]})) && echo fail || echo pass)"
  local q='`'
  printf -- '- Size: %s\n- Change: %s\n- ADR: %s\n' "$q${size:-}$q" "$q${change:-}$q" "$q${adr:-}$q"
  for f in "${failures[@]}"; do printf -- '- :x: %s\n' "$f"; done
  for f in "${notes[@]}"; do printf -- '- :warning: %s\n' "$f"; done
}

finish() {
  to_summary summary
  ((${#failures[@]} == 0))
}

# --- AC-1-20: fields ---------------------------------------------------------
size=$(field Size) || true
change=$(field Change) || true
adr=$(field ADR) || true

[[ $size =~ ^(S|M|L)$ ]] || fail_ac AC-1-20 "Size: must be S, M or L (got '${size:-missing}')"
[[ $change == none || $change =~ ^specs/changes/([0-9]+-[a-z0-9-]+)$ ]] ||
  fail_ac AC-1-20 "Change: must be specs/changes/<id>-<slug> or none (got '${change:-missing}')"
[[ $adr =~ ^docs/adr/[^/[:space:]]+$ || $adr =~ ^none${DASH}${REASON}$ ]] ||
  fail_ac AC-1-20 "ADR: must be docs/adr/<file> or 'none – <reason>' (got '${adr:-missing}')"
[[ $size =~ ^(M|L)$ && $change == none ]] && fail_ac AC-1-20 "Change: an $size PR must name its folder specs/changes/<id>-<slug>"
((${#failures[@]} == 0)) || { finish; exit 1; }

# is_living_spec PATH: specs/<capability>.md, directly in specs/.
is_living_spec() { [[ $1 =~ ^specs/[^/]+\.md$ ]]; }

# --- AC-1-21: S size ---------------------------------------------------------
if [[ $size == S ]]; then
  total=$(counted_lines) specs=()
  for p in "${CHANGE_PATHS[@]}"; do
    if is_living_spec "$p"; then specs+=("$p"); fi
  done
  if has_label size-exception; then
    ((total <= S_SIZE_MAX_LINES)) && ((${#specs[@]} == 0)) ||
      notes+=("S PR with $total changed lines${specs[*]:+ and living-spec changes}; passing because of label size-exception")
  else
    ((total <= S_SIZE_MAX_LINES)) ||
      fail_ac AC-1-21 "an S PR has at most $S_SIZE_MAX_LINES changed lines; this one has $total. Propose size M, or add the label size-exception."
    ((${#specs[@]} == 0)) ||
      fail_ac AC-1-21 "an S PR does not change living specs: ${specs[*]}. Propose size M, or add the label size-exception."
  fi
fi

# changed PATH: true if the PR changes PATH.
changed() { local p; for p in "${CHANGE_PATHS[@]}"; do [[ $p == "$1" ]] && return 0; done; return 1; }

# --- AC-1-22: archive for M/L ------------------------------------------------
archive=''
if [[ $size =~ ^(M|L)$ ]]; then
  name=${change#specs/changes/}
  for p in "${CHANGE_PATHS[@]}"; do
    if [[ $p =~ ^(specs/changes/archive/[0-9]{4}-[0-9]{2}-[0-9]{2}-$name)/[^/]+$ && -d ${BASH_REMATCH[1]} ]]; then
      archive=${BASH_REMATCH[1]}; break
    fi
  done
  if [[ -z $archive ]]; then
    fail_ac AC-1-22 "an $size PR adds specs/changes/archive/YYYY-MM-DD-$name/. Run the finish skill."
  else
    need=(proposal.md tasks.md); [[ $size == L ]] && need+=(design.md)
    for f in "${need[@]}"; do
      if [[ ! -f $archive/$f ]] || ! changed "$archive/$f"; then fail_ac AC-1-22 "$archive/$f is not in the PR"; fi
    done
    if [[ -f $archive/tasks.md ]] && grep -qE '^[[:space:]]*([-*+]|[0-9]+[.)]) \[ \]' "$archive/tasks.md"; then
      fail_ac AC-1-22 "$archive/tasks.md has unchecked tasks (- [ ])"
    fi
  fi
  spec_changed=0
  for p in "${CHANGE_PATHS[@]}"; do is_living_spec "$p" && spec_changed=1; done
  ((spec_changed)) || fail_ac AC-1-22 "an $size PR changes at least one living spec specs/<capability>.md"
fi

# test_files: print the files of the checkout that match TEST_GLOBS, NUL-terminated.
# Same result as is_test_path, but each glob becomes a regex one time, not one time per file.
test_files() {
  local res=() g f re
  for g in "${TEST_GLOBS[@]}"; do res+=("$(glob_to_regex "$g")"); done
  while IFS= read -r f; do
    for re in "${res[@]}"; do
      if [[ $f =~ $re ]]; then printf '%s\0' "$f"; break; fi
    done
  done < <(list_files .)
}

# --- AC-1-23: every AC id of the change is in a test file --------------------
if [[ -n $archive && -f $archive/proposal.md ]]; then
  id=${name%%-*}
  mapfile -t want < <(grep -ohE "AC-$id-[0-9]+" "$archive/proposal.md" | sort -u)
  mapfile -t have < <(test_files | xargs -0r grep -ohE 'AC-[0-9]+-[0-9]+' | sort -u)
  mapfile -t missing < <(comm -23 <(printf '%s\n' "${want[@]}") <(printf '%s\n' "${have[@]}") | grep . || true)
  ((${#missing[@]} == 0)) || fail_ac AC-1-23 "no test file names these criteria: ${missing[*]}"
fi

# --- AC-1-24: ADR --------------------------------------------------------------
if [[ $adr == docs/adr/* ]]; then
  [[ -f $adr ]] || fail_ac AC-1-24 "ADR: $adr is not in the checkout"
elif [[ $size == L ]]; then
  notes+=("ADR: none on an L PR. An L change makes a hard-to-reverse choice; check the reason.")
fi

# --- AC-1-25: .docs-map ----------------------------------------------------------
# Rule lines are "<glob> -> <doc path>". Blank lines and # comments are skipped.
docs_escape=''
if docs=$(field Docs); then
  if [[ $docs =~ ^unchanged${DASH}${REASON}$ ]]; then docs_escape=${BASH_REMATCH[2]}
  else fail_ac AC-1-25 "Docs: must be 'unchanged – <reason>' (got '$docs'). Delete the line if you do not need it."
  fi
fi
if [[ -f .docs-map ]]; then
  n=0
  while IFS= read -r line || [[ -n $line ]]; do
    n=$((n + 1))
    line=${line%$'\r'}
    [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
    if [[ ! $line =~ ^[[:space:]]*([^[:space:]]+)[[:space:]]+-\>[[:space:]]+([^[:space:]]+)[[:space:]]*$ ]]; then
      fail_ac AC-1-25 ".docs-map line $n is not '<glob> -> <doc path>': $line"; continue
    fi
    glob=${BASH_REMATCH[1]} doc=${BASH_REMATCH[2]} hit=''
    for p in "${CHANGE_PATHS[@]}"; do
      if [[ $p != "$doc" ]] && glob_match "$p" "$glob"; then hit=$p; break; fi
    done
    if [[ -z $hit ]] || changed "$doc"; then continue; fi
    if [[ -n $docs_escape ]]; then
      notes+=("$hit is mapped to $doc, which does not change. Docs: unchanged – $docs_escape")
    else
      fail_ac AC-1-25 "$hit is mapped to $doc in .docs-map. Change $doc, or add 'Docs: unchanged – <reason>' to the PR body."
    fi
  done < .docs-map
fi

finish
