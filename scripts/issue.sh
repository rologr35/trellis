#!/usr/bin/env bash
#
# issue: the plan of an issue, written from the mould (templates/<locale>/issue.md) and checked, and
# the close of the issue when its pull request is merged.
#
#   trellis issue check --body <file>    a body, before it is published
#   trellis issue check <n>              the plan of an issue of this repository, at pick-up
#   trellis issue check <n> --print      prints that plan and judges nothing
#   trellis issue create --title <t> --body-file <file>
#                                        checks the body, creates the issue, prints its URL
#   trellis issue close <pr> [--done]    closes the issues of a merged pull request; --done when its
#                                        pending actions are done
#
# The check: the five sections of project.locale present, once, in order and not empty; each item of
# Out of scope with its Source; the last line with text `Complexity: S`, M or L; every path in
# backticks of Layers and files, outside its New list, in origin/<git.integrationBranch>, which is
# fetched first; and the style of pr-check (no long dash, no attribution, no bare #N, with the
# references of a Depends on line allowed). The names per locale live in lib/locale.mjs.
#
# The plan of an issue is its body, with each section, and the complexity line, of the last comment
# headed `## Amendment (<date>)` that has it (a section as a `###` heading). Only what an owner, a member
# or a collaborator wrote counts, the body too: with the body of someone else, which the check says, the
# plan is what the amendments carry. At pick-up, also: every #n and owner/repo#n of the
# Depends on line of Context is closed. Other text there is printed for a person.
#
# The label of the issue created is the class of its complexity line. S, M and L are created when the
# repository lacks them.
#
# The close refuses a pull request that is not merged into git.integrationBranch. It takes the issues
# of this repository its body closes outside code (Closes, Fixes, Resolves) and skips the number of a
# pull request. With actions in the section After merging, each issue first gets the label
# pending-actions, created when the repository lacks it, and one comment with them, whose first line
# marks the pull request; then, whatever is pending, it is closed. The mark makes a rerun harmless: it
# writes neither the comment nor the label again. --done only takes the label off. A failure on one
# issue leaves it open and goes on with the next.
#
# GitHub is asked through REST, as the account of the repository's owner (lib/gh.sh).
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
    printf '       trellis issue close <pr> [--done]\n'
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
  if ! gh_api . "$hint" "issues/$n" --jq .state; then
    printf 'issue check: depends on %s, whose state could not be read as %s: %s\n' "$name" "$GH_AS_ACCOUNT" "${GH_AS_ERR:-gh failed}" >&2
    return 1
  fi
  case "$GH_AS_OUT" in
    closed) return 0 ;;
    open) printf 'issue check: depends on %s, which is open\n' "$name" >&2 ;;
    *) printf 'issue check: depends on %s, whose state gh answered as "%s"\n' "$name" "$GH_AS_OUT" >&2 ;;
  esac
  return 1
}

make_tmp() {
  ISSUE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/trellis-issue.XXXXXX")" || return 1
  trap 'rm -rf "$ISSUE_TMP"' EXIT
}

# The issue <n> and its comments, as REST gives them: issue.json, and comments.json with one per line.
read_issue() {
  gh_api . '' "issues/$1" || return 1
  printf '%s' "$GH_AS_OUT" > "$ISSUE_TMP/issue.json"
  gh_api . '' "issues/$1/comments?per_page=100" --paginate --jq '.[]' || return 1
  printf '%s' "$GH_AS_OUT" > "$ISSUE_TMP/comments.json"
}

check_issue() {
  local n="${1#\#}" print="$2" kind a b status=0 deps_ok=true
  case "$n" in '' | *[!0-9]*) usage ;; esac
  make_tmp || return 1
  if ! read_issue "$n"; then
    printf 'issue: #%s could not be read as %s: %s\n' "$n" "$GH_AS_ACCOUNT" "${GH_AS_ERR:-gh failed}" >&2
    return 1
  fi
  if [ "$print" = true ]; then
    judge print "$ISSUE_TMP/issue.json" "$ISSUE_TMP/comments.json"
    return $?
  fi
  fetch_integration
  judge issue "$ISSUE_TMP/issue.json" "$ISSUE_TMP/comments.json" || status=1
  judge deps "$ISSUE_TMP/issue.json" "$ISSUE_TMP/comments.json" > "$ISSUE_TMP/deps" || return 1
  while IFS=$'\t' read -r kind a b <&4; do
    case "$kind" in
      ref) check_dependency "$a" "$b" || deps_ok=false ;;
      text) printf 'issue: the plan depends on this, which a person confirms: %s\n' "$a" ;;
    esac
  done 4< "$ISSUE_TMP/deps"
  [ "$deps_ok" = true ] || status=1
  [ "$status" -eq 0 ] && printf 'issue check: ok (%s)\n' "$(judge issue-class "$ISSUE_TMP/issue.json" "$ISSUE_TMP/comments.json")"
  return "$status"
}

# ensure_label <name> <colour> <description>: makes sure the repository has the label. GitHub
# compares the names of labels without case.
ensure_label() {
  local name="$1" colour="$2" description="$3"
  if ! gh_api . '' 'labels?per_page=100' --paginate --jq '.[].name'; then
    printf 'issue: the labels could not be read as %s: %s\n' "$GH_AS_ACCOUNT" "${GH_AS_ERR:-gh failed}" >&2
    return 1
  fi
  printf '%s\n' "$GH_AS_OUT" | grep -qix -- "$name" && return 0
  if ! gh_api . '' labels -f "name=$name" -f "color=$colour" -f "description=$description"; then
    printf 'issue: the label %s could not be created as %s: %s\n' "$name" "$GH_AS_ACCOUNT" "${GH_AS_ERR:-gh failed}" >&2
    return 1
  fi
}

create_issue() {
  local title='' file='' class colour
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
  case "$class" in S) colour=0E8A16 ;; M) colour=FBCA04 ;; *) colour=B60205 ;; esac
  ensure_label "$class" "$colour" "Complexity $class" || return 1
  if ! gh_api . '' issues -f "title=$title" -F "body=@$file" -f "labels[]=$class" --jq .html_url; then
    printf 'issue: it could not be created as %s: %s\n' "$GH_AS_ACCOUNT" "${GH_AS_ERR:-gh failed}" >&2
    return 1
  fi
  printf '%s\n' "$GH_AS_OUT"
}

# close_write <what> <n> <endpoint> [<arguments of gh api>]: one call on issue <n>, and the error of gh
# when it fails.
close_write() {
  local what="$1" n="$2"
  shift 2
  gh_api . '' "$@" && return 0
  printf 'issue close: #%s: %s failed as %s: %s\n' "$n" "$what" "$GH_AS_ACCOUNT" "${GH_AS_ERR:-gh failed}" >&2
  return 1
}

# One issue of the pull request <pr> of <repo>. The label comes before the comment, whose mark says
# both are done, and the close comes last.
close_one() {
  local n="$1" repo="$2" pr="$3" done="$4" comment="$ISSUE_TMP/comment" answer state labelled commented
  if ! read_issue "$n"; then
    printf 'issue close: #%s: the read failed as %s: %s\n' "$n" "$GH_AS_ACCOUNT" "${GH_AS_ERR:-gh failed}" >&2
    return 1
  fi
  answer="$(node "$TRELLIS_ROOT/scripts/issue-close.mjs" issue "$ISSUE_TMP/issue.json" "$ISSUE_TMP/comments.json" "$repo" "$pr")" && [ -n "$answer" ] || return 1
  if [ "$answer" = 'skip' ]; then
    printf 'issue close: #%s is not an issue of %s\n' "$n" "$repo"
    return 0
  fi
  read -r state labelled commented <<< "$answer"
  if [ "$done" = true ]; then
    [ "$labelled" = true ] || return 0
    close_write 'the label' "$n" "issues/$n/labels/pending-actions" -X DELETE || return 1
    printf 'issue close: #%s: no actions pending\n' "$n"
    return 0
  fi
  if [ -s "$comment" ] && [ "$commented" = false ]; then
    if [ "$labelled" = false ]; then
      ensure_label pending-actions D93F0B 'Merged with actions pending' || return 1
      close_write 'the label' "$n" "issues/$n/labels" -f 'labels[]=pending-actions' || return 1
    fi
    close_write 'the comment' "$n" "issues/$n/comments" -F "body=@$comment" || return 1
    printf 'issue close: #%s: actions pending, in a comment\n' "$n"
  fi
  if [ "$state" = 'open' ]; then
    close_write 'the close' "$n" "issues/$n" -X PATCH -f state=closed || return 1
    printf 'issue close: #%s: closed\n' "$n"
  fi
}

close_issues() {
  local pr="${1#\#}" done="$2" answer repo='' n count=0 status=0
  case "$pr" in '' | *[!0-9]*) usage ;; esac
  if ! gh_api . '' "pulls/$pr"; then
    printf 'issue close: the pull request #%s could not be read as %s: %s\n' "$pr" "$GH_AS_ACCOUNT" "${GH_AS_ERR:-gh failed}" >&2
    return 1
  fi
  make_tmp || return 1
  printf '%s' "$GH_AS_OUT" > "$ISSUE_TMP/pr.json"
  answer="$(node "$TRELLIS_ROOT/scripts/issue-close.mjs" pr "$ISSUE_TMP/pr.json" "$ISSUE_TMP/comment")" && [ -n "$answer" ] || return 1
  while IFS= read -r n <&4; do
    if [ -z "$repo" ]; then repo="$n"; continue; fi
    count=$((count + 1))
    close_one "$n" "$repo" "$pr" "$done" || status=1
  done 4<<< "$answer"
  if [ "$count" -eq 0 ]; then
    printf 'issue close: #%s closes no issue of %s\n' "$pr" "$repo"
    [ ! -s "$ISSUE_TMP/comment" ] || printf 'issue close: its pending actions are only in its body\n'
  fi
  return "$status"
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
  close)
    number=''
    done=false
    for arg in "$@"; do
      case "$arg" in
        --done) done=true ;;
        -*) usage ;;
        *) [ -z "$number" ] || usage; number="$arg" ;;
      esac
    done
    close_issues "$number" "$done"
    ;;
  *) usage ;;
esac
