#!/usr/bin/env bash
# AC-1-31: no unterminated Mermaid fence in any *.md file.
# AC-1-33: no embedded images in *.md files under docs/ or specs/.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
root=${1:-$(repo_root)}
rc=0
while IFS= read -r f; do
  [[ $f == *.md && -f $root/$f ]] || continue
  images=0
  [[ $f == docs/* || $f == specs/* ]] && images=1
  awk -v file="$f" -v images="$images" '
    function fence_of(s,   m) { if (match(s, /^ {0,3}(`{3,}|~{3,})/)) { m = substr(s, RSTART, RLENGTH); sub(/^ +/, "", m); return m } return "" }
    {
      m = fence_of($0)
      if (open == "") {
        if (m != "") { open = m; start = NR; info = substr($0, index($0, m) + length(m)); gsub(/^[ \t]+|[ \t]+$/, "", info); next }
        if (images) {
          line = $0; gsub(/`[^`]*`/, "", line)
          if (tolower(line) ~ /!\[[^]]*\]\([^)]*\.(png|jpe?g|svg|gif)([ \t]+"[^"]*")?\)/) {
            printf "error: %s:%d: embedded image; use a Mermaid diagram\n", file, NR; bad = 1
          }
        }
      } else if (m != "" && substr(m, 1, 1) == substr(open, 1, 1) && length(m) >= length(open) && $0 ~ /^ *[`~]+[ \t]*$/) {
        open = ""
      }
    }
    END {
      if (open != "" && info ~ /^mermaid/) { printf "error: %s:%d: unterminated mermaid block\n", file, start; bad = 1 }
      exit bad
    }' "$root/$f" >&2 || rc=1
done < <(list_files "$root")
exit $rc
