#!/usr/bin/env bash
#
# issue: the plan of an issue, written from the mould (templates/<locale>/issue.md) and checked.
#
#   trellis issue check --body <file>    a body, before it is published
#
# The check: the five sections of project.locale present, once, in order and not empty; each item of
# Out of scope with its Source; the last line with text `Complexity: S`, M or L; every path in
# backticks of Layers and files, outside its New list, in origin/<git.integrationBranch>, which is
# fetched first; and the style of pr-check (no long dash, no attribution, no bare #N, with the
# references of a Depends on line allowed). The names per locale live in lib/locale.mjs.
#
# With tracker.kind = none the module is off and every form exits 2. Otherwise 0 when the check
# passes, 1 when it does not, with every miss printed, and 2 on a wrong use.

set -uo pipefail

TRELLIS_ROOT="${TRELLIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/config.sh
. "$TRELLIS_ROOT/lib/config.sh"

usage() {
  printf 'usage: trellis issue check --body <file>\n' >&2
  exit 2
}

if [ "$(tc_get tracker.kind)" = 'none' ]; then
  printf 'issue: the Cycle module is off in this project (tracker.kind = none)\n' >&2
  exit 2
fi

judge() { node "$TRELLIS_ROOT/scripts/issue-check.mjs" "$@"; }

# The paths are judged against the integration branch as it is now. Offline, the last fetch judges.
fetch_integration() {
  git remote get-url origin >/dev/null 2>&1 || return 0
  GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 \
    fetch --quiet origin "$(tc_get git.integrationBranch)" 2>/dev/null </dev/null \
    || printf 'issue: origin/%s could not be fetched, so the paths are judged by the last fetch\n' "$(tc_get git.integrationBranch)" >&2
}

check_body() {
  [ $# -eq 1 ] && [ -f "$1" ] || usage
  fetch_integration
  judge body "$1" || return 1
  printf 'issue check: ok (%s)\n' "$(judge class "$1")"
}

[ $# -gt 0 ] || usage
action="$1"
shift
case "$action" in
  check)
    case "${1:-}" in
      --body) shift; check_body "$@" ;;
      *) usage ;;
    esac
    ;;
  *) usage ;;
esac
