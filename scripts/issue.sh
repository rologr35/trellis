#!/usr/bin/env bash
#
# issue: the plan of an issue, written from the mould (templates/<locale>/issue.md) and checked.
#
#   trellis issue check --body <file>    a body, before it is published
#   trellis issue check <n>              the plan of an issue of this repository, at pick-up
#   trellis issue check <n> --print      prints that plan and judges nothing
#   trellis issue create --title <t> --body-file <file>
#                                        checks the body, creates the issue, prints its URL
#
# The check: the five sections of project.locale present, once, in order and not empty; each item of
# Out of scope with its Source; the last line with text `Complexity: S`, M or L; every path in
# backticks of Layers and files, outside its New list, in origin/<git.integrationBranch>, which is
# fetched first; and the style of pr-check (no long dash, no attribution, no bare #N, with the
# references of a Depends on line allowed). The names per locale live in lib/locale.mjs.
#
# The plan of an issue is its body, with each section, and the complexity line, of the last comment
# headed `## Amendment (<date>)` that has it (a section as a `###` heading). Only the comments of an
# owner, a member or a collaborator count. At pick-up, also: every #n and owner/repo#n of the
# Depends on line of Context is closed. Other text there is printed for a person.
#
# The label of the issue created is the class of its complexity line. S, M and L are created when the
# repository lacks them.
#
# GitHub is asked as the account of the repository's owner (lib/gh.sh).
#
# With tracker.kind = none the module is off and every form exits 2. Otherwise 0 when the check
# passes, 1 when it does not, with every miss printed, and 2 on a wrong use.

set -uo pipefail

TRELLIS_ROOT="${TRELLIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/config.sh
. "$TRELLIS_ROOT/lib/config.sh"
# shellcheck source=../lib/gh.sh
. "$TRELLIS_ROOT/lib/gh.sh"

usage() {
  {
    printf 'usage: trellis issue check --body <file> | check <n> [--print]\n'
    printf '       trellis issue create --title <t> --body-file <file>\n'
  } >&2
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

# One dependency: prints the miss when the issue is open or cannot be read.
check_dependency() {
  local repo="$1" n="$2" name="#$2" hint=''
  if [ "$repo" != '-' ]; then name="$repo#$n"; hint="$repo"; fi
  if ! gh_as_owner . "$(gh_owner . "$hint")" issue view "$n" --json state --jq .state ${hint:+--repo "$hint"}; then
    printf 'issue check: depends on %s, whose state could not be read as %s: %s\n' "$name" "$GH_AS_ACCOUNT" "${GH_AS_ERR:-gh failed}" >&2
    return 1
  fi
  case "$GH_AS_OUT" in
    CLOSED | MERGED) return 0 ;;
    OPEN) printf 'issue check: depends on %s, which is open\n' "$name" >&2 ;;
    *) printf 'issue check: depends on %s, whose state gh answered as "%s"\n' "$name" "$GH_AS_OUT" >&2 ;;
  esac
  return 1
}

check_issue() {
  local n="${1#\#}" print="$2" kind a b status=0 deps_ok=true
  case "$n" in '' | *[!0-9]*) usage ;; esac
  if ! gh_as_owner . "$(gh_owner .)" issue view "$n" --json body,comments; then
    printf 'issue: #%s could not be read as %s: %s\n' "$n" "$GH_AS_ACCOUNT" "${GH_AS_ERR:-gh failed}" >&2
    return 1
  fi
  ISSUE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/trellis-issue.XXXXXX")" || return 1
  trap 'rm -rf "$ISSUE_TMP"' EXIT
  printf '%s' "$GH_AS_OUT" > "$ISSUE_TMP/issue.json"
  if [ "$print" = true ]; then
    judge print "$ISSUE_TMP/issue.json"
    return $?
  fi
  fetch_integration
  judge issue "$ISSUE_TMP/issue.json" || status=1
  judge deps "$ISSUE_TMP/issue.json" > "$ISSUE_TMP/deps" || return 1
  while IFS=$'\t' read -r kind a b <&4; do
    case "$kind" in
      ref) check_dependency "$a" "$b" || deps_ok=false ;;
      text) printf 'issue: the plan depends on this, which a person confirms: %s\n' "$a" ;;
    esac
  done 4< "$ISSUE_TMP/deps"
  [ "$deps_ok" = true ] || status=1
  [ "$status" -eq 0 ] && printf 'issue check: ok (%s)\n' "$(judge issue-class "$ISSUE_TMP/issue.json")"
  return "$status"
}

# Makes sure the repository has the label $1. GitHub compares the names of labels without case.
ensure_label() {
  local class="$1" owner="$2" colour
  if ! gh_as_owner . "$owner" label list --limit 1000 --json name --jq '.[].name'; then
    printf 'issue: the labels could not be read as %s: %s\n' "$GH_AS_ACCOUNT" "${GH_AS_ERR:-gh failed}" >&2
    return 1
  fi
  printf '%s\n' "$GH_AS_OUT" | grep -qix -- "$class" && return 0
  case "$class" in S) colour=0E8A16 ;; M) colour=FBCA04 ;; *) colour=B60205 ;; esac
  if ! gh_as_owner . "$owner" label create "$class" --color "$colour" --description "Complexity $class"; then
    printf 'issue: the label %s could not be created as %s: %s\n' "$class" "$GH_AS_ACCOUNT" "${GH_AS_ERR:-gh failed}" >&2
    return 1
  fi
}

create_issue() {
  local title='' file='' class owner
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) [ $# -gt 1 ] || usage; title="$2"; shift ;;
      --title=*) title="${1#*=}" ;;
      --body-file) [ $# -gt 1 ] || usage; file="$2"; shift ;;
      --body-file=*) file="${1#*=}" ;;
      *) usage ;;
    esac
    shift
  done
  [ -n "$title" ] && [ -f "$file" ] || usage
  case "$file" in /*) ;; *) file="$PWD/$file" ;; esac
  fetch_integration
  judge body "$file" || return 1
  class="$(judge class "$file")"
  owner="$(gh_owner .)"
  ensure_label "$class" "$owner" || return 1
  if ! gh_as_owner . "$owner" issue create --title "$title" --body-file "$file" --label "$class"; then
    printf 'issue: it could not be created as %s: %s\n' "$GH_AS_ACCOUNT" "${GH_AS_ERR:-gh failed}" >&2
    return 1
  fi
  printf '%s\n' "$GH_AS_OUT"
}

[ $# -gt 0 ] || usage
action="$1"
shift
case "$action" in
  check)
    case "${1:-}" in
      --body) shift; check_body "$@" ;;
      *)
        number=''
        print=false
        for arg in "$@"; do
          case "$arg" in
            --print) print=true ;;
            -*) usage ;;
            *) [ -z "$number" ] || usage; number="$arg" ;;
          esac
        done
        check_issue "$number" "$print"
        ;;
    esac
    ;;
  create) create_issue "$@" ;;
  *) usage ;;
esac
