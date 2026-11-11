#!/usr/bin/env bash
# AC-1-15, AC-1-16: the placeholder check-app. It passes while no app source
# exists and fails once any does. Replace the Makefile target to configure it.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
root=${1:-$(repo_root)}
log 'check-app: no app checks configured'
app=()
while IFS= read -r f; do
  is_app_source "$f" && app+=("$f")
done < <(list_files "$root")
(( ${#app[@]} == 0 )) && exit 0
err "app source exists but check-app is still the placeholder:"
printf '  %s\n' "${app[@]:0:10}" >&2
(( ${#app[@]} > 10 )) && printf '  ... and %d more\n' $(( ${#app[@]} - 10 )) >&2
err "fill the check-app target in the Makefile (see the README section on overlays)"
exit 1
