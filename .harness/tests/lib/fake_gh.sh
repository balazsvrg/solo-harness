# shellcheck shell=bash
# A fake GitHub for scripts/bootstrap tests. Sourced after the script, so this gh_api
# replaces the real one. State lives in files under $GH_STATE:
#   calls                one "METHOD PATH" line per call (query string kept)
#   "METHOD KEY"         the response body; KEY is the path without the query, '/' as '_'
#   "METHOD KEY.status"  an HTTP error code: the call prints the gh error line and fails
# A GET with no body file is a 404. A write with no body file returns {}.

gh_api() {
  local method=GET path='' key f
  while (($#)); do
    case $1 in
      -X | --method) method=$2; shift ;;
      -f | -F | --raw-field | --field | --input | --jq | -H | --header) shift ;;
      -*) ;;
      *) [[ -n $path ]] || path=$1 ;;
    esac
    shift
  done
  printf '%s %s\n' "$method" "$path" >> "$GH_STATE/calls"
  key=${path%%\?*}
  f="$GH_STATE/$method ${key//\//_}"
  if [[ -f $f.status ]]; then
    printf '{"message": "fake error"}'
    printf 'gh: fake error (HTTP %s)\n' "$(cat "$f.status")" >&2
    return 1
  fi
  if [[ -f $f ]]; then cat "$f"
  elif [[ $method == GET ]]; then printf 'gh: Not Found (HTTP 404)\n' >&2; return 1
  else printf '{}'
  fi
}
