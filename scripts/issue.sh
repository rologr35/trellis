#!/usr/bin/env bash
#
# issue: the plan of an issue, written from the mould (templates/<locale>/issue.md) and checked; the
# claim of the issue and its stop; the follow-up of what it leaves; and its close when its pull request
# is merged.
#
#   trellis issue check --body <file>    a body, before it is published
#   trellis issue check <n>              the plan of an issue of this repository, at pick-up
#   trellis issue check <n> --print      prints that plan and judges nothing
#   trellis issue gates <n>              the files of this branch that match a gate the plan does not name
#   trellis issue claim <n> [--unattended] [--resume]
#                                        takes the issue for this session
#   trellis issue stop <n> --body-file <file>
#                                        leaves the issue stopped, with what it needs in a comment
#   trellis issue create --title <t> --body-file <file>
#                                        checks the body, creates the issue, prints its URL
#   trellis issue follow-up --title <t> --body-file <file> --search <words> --checked <sha>
#                           [--reopen <date> | --when <fact>] [--approved]
#                                        what the work leaves for another issue
#   trellis issue close <pr> [--done]    closes the issues of a merged pull request; --done when its
#                                        pending actions are done
#
# The check: the five sections of project.locale present, once, in order and not empty; each item of
# Out of scope with its Source; the last line with text `Complexity: S`, M or L; every path in
# backticks of Layers and files, outside its New list, in origin/<git.integrationBranch>, which is
# fetched first; Risks opening with `Gates: none` or the names of the [gate] the plan touches, that exist
# and are every gate whose paths match one of Layers and files; and the style of pr-check (no long dash,
# no attribution, no bare #N, with the references of a Depends on line allowed). `Needs:` in Risks is
# optional: what a run cannot take. The names per locale live in lib/locale.mjs.
#
# The plan of an issue is its body, with each section, and the complexity line, of the last comment
# headed `## Amendment (<date>)` that has it (a section as a `###` heading). Only what an owner, a member
# or a collaborator wrote counts, the body too: with the body of someone else, which the check says, the
# plan is what the amendments carry. At pick-up, also: every #n and owner/repo#n of the Depends on line
# of Context is closed. Other text there is printed for a person.
# Each path of Layers and files that changed on the integration branch since the plan, or its last
# amendment, was written is printed, and fails nothing.
#
# The gates: every file the commits of the branch, one of the issue (<n>-*), change, from where it left origin/<git.integrationBranch>,
# which is fetched first, against the paths of each [gate] that Risks does not name. A gate that only
# the integration branch declares counts too.
#
# The claim refuses, in this order: an issue that is closed or is a pull request, one with the label
# stopped, one assigned to anybody (the own account too), one whose branch <n>-* is on origin, and a plan
# that does not pass the check. Then it assigns the account it asks as and reads the issue again: with
# another assignee it takes itself off and refuses. --resume takes what its own account already has: the
# assignment, the branch, and a stopped issue that is its own or nobody's, whose label it takes off.
# --unattended, for a run without a person, also refuses a plan with Gates other than none or any Needs,
# and a plan it refuses, for that or for the check, is stopped with the reasons. What is taken is not, nor
# a plan whose dependency could not be read.
#
# The stop is one comment, whose first line is a fixed mark, with the sections Done, Missing and Needs of
# the file, none of them empty (`none` counts), and the label stopped, created when the repository lacks
# it. The assignee, when there is one, stays.
#
# The label of the issue created is the class of its complexity line. S, M and L are created when the
# repository lacks them.
#
# The follow-up is refused unless --checked is the head of origin/<git.integrationBranch> after a fetch,
# where the problem was seen. It prints what the search of the backlog finds, open and closed. At
# autonomy.level careful it then prints the proposal and exits 4, with nothing created, until a person
# approved it (--approved); at the other levels it creates the issue. Its label is follow-up, or deferred
# with --reopen or --when, which write the first line of the body (`Reopen:`, per locale).
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
    printf '       trellis issue gates <n>\n'
    printf '       trellis issue claim <n> [--unattended] [--resume]\n'
    printf '       trellis issue stop <n> --body-file <file>\n'
    printf '       trellis issue create --title <t> --body-file <file>\n'
    printf '       trellis issue follow-up --title <t> --body-file <file> --search <words> --checked <sha>\n'
    printf '                               [--reopen <date> | --when <fact>] [--approved]\n'
    printf '       trellis issue close <pr> [--done]\n'
  } >&2
  exit 2
}

if [ "$(tc_get tracker.kind)" = 'none' ]; then
  printf 'issue: the Cycle module is off in this project (tracker.kind = none)\n' >&2
  exit 2
fi

judge() { node "$TRELLIS_ROOT/scripts/issue-check.mjs" "$@"; }

fetch_now() {
  GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 \
    fetch --quiet origin "$(tc_get git.integrationBranch)" 2>/dev/null </dev/null
}

# The paths are judged against the integration branch as it is now. Offline, the last fetch judges.
fetch_integration() {
  git remote get-url origin >/dev/null 2>&1 || return 0
  fetch_now || printf 'issue: origin/%s could not be fetched, so the paths are judged by the last fetch\n' "$(tc_get git.integrationBranch)" >&2
}

check_body() {
  [ $# -eq 1 ] && [ -f "$1" ] || usage
  fetch_integration
  judge body "$1" || return 1
  printf 'issue check: ok (%s)\n' "$(judge class "$1")"
}

# One dependency: prints the miss when the issue is open or cannot be read, and then returns 2.
check_dependency() {
  local repo="$1" n="$2" name="#$2" hint=''
  if [ "$repo" != '-' ]; then name="$repo#$n"; hint="$repo"; fi
  if ! gh_api . "$hint" "issues/$n" --jq .state; then
    printf 'issue check: depends on %s, whose state could not be read as %s: %s\n' "$name" "$GH_AS_ACCOUNT" "${GH_AS_ERR:-gh failed}" >&2
    return 2
  fi
  case "$GH_AS_OUT" in
    closed) return 0 ;;
    open) printf 'issue check: depends on %s, which is open\n' "$name" >&2 ;;
    *) printf 'issue check: depends on %s, whose state gh answered as "%s"\n' "$name" "$GH_AS_OUT" >&2 ;;
  esac
  return 1
}

make_tmp() {
  [ -z "${ISSUE_TMP:-}" ] || return 0
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

# The same, and the error of gh when it fails.
want_issue() {
  make_tmp || return 1
  read_issue "$1" && return 0
  printf 'issue: #%s could not be read as %s: %s\n' "$1" "$GH_AS_ACCOUNT" "${GH_AS_ERR:-gh failed}" >&2
  return 1
}

check_issue() {
  local n="${1#\#}" print="$2"
  case "$n" in '' | *[!0-9]*) usage ;; esac
  want_issue "$n" || return 1
  if [ "$print" = true ]; then
    judge print "$ISSUE_TMP/issue.json" "$ISSUE_TMP/comments.json"
    return $?
  fi
  check_plan || return 1
}

# The plan of the issue that was read. Returns 2 when all it lacks is the state of a dependency that could
# not be read.
check_plan() {
  local kind a b status=0 unread=false
  fetch_integration
  judge issue "$ISSUE_TMP/issue.json" "$ISSUE_TMP/comments.json" || status=1
  judge deps "$ISSUE_TMP/issue.json" "$ISSUE_TMP/comments.json" > "$ISSUE_TMP/deps" || return 1
  while IFS=$'\t' read -r kind a b <&4; do
    case "$kind" in
      ref)
        check_dependency "$a" "$b"
        case $? in 0) ;; 2) unread=true ;; *) status=1 ;; esac
        ;;
      text) printf 'issue: the plan depends on this, which a person confirms: %s\n' "$a" ;;
    esac
  done 4< "$ISSUE_TMP/deps"
  [ "$status" -ne 0 ] || [ "$unread" = false ] || status=2
  [ "$status" -eq 0 ] && printf 'issue check: ok (%s)\n' "$(judge issue-class "$ISSUE_TMP/issue.json" "$ISSUE_TMP/comments.json")"
  return "$status"
}

check_gates() {
  local n="${1#\#}"
  case "$n" in '' | *[!0-9]*) usage ;; esac
  [ $# -eq 1 ] || usage
  want_issue "$n" || return 1
  case "$(git branch --show-current)" in
    "$n"-*) ;;
    *) printf 'issue gates: %s is not a branch of #%s\n' "$(git branch --show-current | grep . || echo 'no branch')" "$n" >&2; return 1 ;;
  esac
  fetch_integration
  judge gates "$ISSUE_TMP/issue.json" "$ISSUE_TMP/comments.json" || return 1
  printf 'issue gates: ok\n'
}

# issue_facts: the state, the labels and the assignees of the issue that was read, one per line each.
issue_facts() {
  node -e '
    const issue = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const names = (list, key) => (list || []).map(x => x[key].toLowerCase()).join(" ");
    console.log(issue.pull_request ? "a pull request" : issue.state);
    console.log((issue.labels || []).some(l => l.name.toLowerCase() === "stopped"));
    console.log(names(issue.assignees, "login"));
  ' "$ISSUE_TMP/issue.json" > "$ISSUE_TMP/facts" || return 1
  { IFS= read -r ISSUE_STATE; IFS= read -r ISSUE_STOPPED; IFS= read -r ISSUE_ASSIGNEES; } < "$ISSUE_TMP/facts"
}

refuse_claim() {
  printf 'issue claim: #%s is not claimed: %s\n' "$1" "$2" >&2
  return 1
}

# issue_write <what> <n> <endpoint> [<arguments of gh api>]: one call on issue <n>, and the error of gh
# when it fails.
issue_write() {
  local what="$1" n="$2"
  shift 2
  gh_api . '' "$@" && return 0
  printf 'issue %s: #%s: %s failed as %s: %s\n' "$action" "$n" "$what" "$GH_AS_ACCOUNT" "${GH_AS_ERR:-gh failed}" >&2
  return 1
}

# The account GitHub is asked as, in ISSUE_ME.
whoami() {
  gh_repo . '' || true
  if ! gh_as_owner . "$(gh_owner . '')" api user ${GH_REPO_HOST:+--hostname "$GH_REPO_HOST"} --jq .login || [ -z "$GH_AS_OUT" ]; then
    printf 'issue: GitHub did not say who %s is: %s\n' "$GH_AS_ACCOUNT" "${GH_AS_ERR:-gh failed}" >&2
    return 1
  fi
  ISSUE_ME="$(printf '%s' "$GH_AS_OUT" | tr '[:upper:]' '[:lower:]')"
}

# The label comes before the comment: a run again after a failure writes one comment.
write_stop() {
  ensure_label stopped 5319E7 'Stopped: its last stop says what it needs' \
    && issue_write 'the label' "$1" "issues/$1/labels" -f 'labels[]=stopped' \
    && issue_write 'the comment' "$1" "issues/$1/comments" -F "body=@$ISSUE_TMP/stop" --jq .html_url || return 1
  printf 'issue %s: #%s is stopped: %s\n' "$action" "$1" "$GH_AS_OUT"
}

# refuse_plan <n> [<branches on origin>]: the stop of a plan a run without a person could not take.
refuse_plan() {
  judge refusal "$ISSUE_TMP/reasons" "$ISSUE_TMP/stop" "${2:-}" && write_stop "$1"
}

stop_issue() {
  local number='' file='' n
  while [ $# -gt 0 ]; do
    case "$1" in
      --body-file) [ $# -gt 1 ] || usage; file="$2"; shift ;;
      --body-file=*) file="${1#*=}" ;;
      -*) usage ;;
      *) [ -z "$number" ] || usage; number="$1" ;;
    esac
    shift
  done
  n="${number#\#}"
  case "$n" in '' | *[!0-9]*) usage ;; esac
  [ -f "$file" ] || usage
  make_tmp || return 1
  judge stop "$file" "$ISSUE_TMP/stop" && write_stop "$n"
}

claim_issue() {
  local number='' unattended=false resume=false arg n branches own checked
  for arg in "$@"; do
    case "$arg" in
      --unattended) unattended=true ;;
      --resume) resume=true ;;
      -*) usage ;;
      *) [ -z "$number" ] || usage; number="$arg" ;;
    esac
  done
  n="${number#\#}"
  case "$n" in '' | *[!0-9]*) usage ;; esac
  want_issue "$n" && whoami && issue_facts || return 1

  [ "$ISSUE_STATE" = 'open' ] || { refuse_claim "$n" "it is $ISSUE_STATE"; return 1; }
  if [ "$ISSUE_STOPPED" = true ] && [ "$resume" = false ]; then
    refuse_claim "$n" 'it is stopped: --resume takes it, when what its last stop needs is there'
    return 1
  fi
  own=false
  [ "$ISSUE_ASSIGNEES" = "$ISSUE_ME" ] && own=true
  if [ -n "$ISSUE_ASSIGNEES" ] && { [ "$resume" = false ] || [ "$own" = false ]; }; then
    refuse_claim "$n" "it is assigned to $ISSUE_ASSIGNEES"
    return 1
  fi
  if ! branches="$(GIT_TERMINAL_PROMPT=0 git ls-remote --heads origin "refs/heads/$n-*" 2>/dev/null </dev/null)"; then
    refuse_claim "$n" 'origin could not be asked for its branch'
    return 1
  fi
  branches="$(printf '%s\n' "$branches" | sed -n 's|^.*refs/heads/||p' | tr '\n' ' ' | sed 's/ $//')"
  if [ -n "$branches" ] && { [ "$resume" = false ] || { [ "$own" = false ] && [ "$ISSUE_STOPPED" = false ]; }; }; then
    refuse_claim "$n" "origin has its branch: $branches"
    return 1
  fi

  check_plan > "$ISSUE_TMP/said" 2> "$ISSUE_TMP/reasons"
  checked=$?
  cat "$ISSUE_TMP/said"
  cat "$ISSUE_TMP/reasons" >&2
  if [ "$checked" -eq 2 ]; then
    refuse_claim "$n" 'its plan could not be checked'
    return 1
  fi
  if [ "$checked" -ne 0 ]; then
    refuse_claim "$n" 'its plan does not pass the check'
    [ "$unattended" = false ] || refuse_plan "$n" "$branches"
    return 1
  fi
  if [ "$unattended" = true ]; then
    judge attended "$ISSUE_TMP/issue.json" "$ISSUE_TMP/comments.json" > "$ISSUE_TMP/attended" || return 1
    if [ -s "$ISSUE_TMP/attended" ]; then
      refuse_claim "$n" "a run without a person cannot take it: $(tr '\n' ';' < "$ISSUE_TMP/attended" | sed 's/;$//; s/;/; /g')"
      mv "$ISSUE_TMP/attended" "$ISSUE_TMP/reasons"
      refuse_plan "$n" "$branches"
      return 1
    fi
  fi

  if [ "$own" = false ]; then
    issue_write 'the assignment' "$n" "issues/$n/assignees" -f "assignees[]=$ISSUE_ME" || return 1
    if ! want_issue "$n" || ! issue_facts; then
      refuse_claim "$n" "it was assigned to $ISSUE_ME and could not be read again"
      return 1
    fi
    if [ "$ISSUE_ASSIGNEES" != "$ISSUE_ME" ]; then
      case " $ISSUE_ASSIGNEES " in
        *" $ISSUE_ME "*) issue_write 'taking the assignment off' "$n" "issues/$n/assignees" -X DELETE -f "assignees[]=$ISSUE_ME" ;;
      esac
      refuse_claim "$n" "after the assignment it is of ${ISSUE_ASSIGNEES:-nobody}: GitHub did not leave it to $ISSUE_ME alone"
      return 1
    fi
  fi
  if [ "$ISSUE_STOPPED" = true ]; then
    issue_write 'taking the label stopped off' "$n" "issues/$n/labels/stopped" -X DELETE || return 1
  fi
  printf 'issue claim: #%s is assigned to %s\n' "$n" "$ISSUE_ME"
  [ -z "$branches" ] || printf 'issue claim: its branch on origin: %s (trellis worktree add %s <slug> --resume)\n' "$branches" "$n"
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
  ensure_label "$class" "$colour" "Complexity $class" && post_issue "$title" "$file" "$class"
}

# post_issue <title> <file> <label>: creates the issue and prints its URL.
post_issue() {
  if ! gh_api . '' issues -f "title=$1" -F "body=@$2" -f "labels[]=$3" --jq .html_url; then
    printf 'issue: it could not be created as %s: %s\n' "$GH_AS_ACCOUNT" "${GH_AS_ERR:-gh failed}" >&2
    return 1
  fi
  printf '%s\n' "$GH_AS_OUT"
}

refuse_follow_up() {
  printf 'issue follow-up: nothing is created: %s\n' "$1" >&2
  return 1
}

follow_up() {
  local title='' file='' words='' checked='' reopen='' approved=false flag value branch head label level
  while [ $# -gt 0 ]; do
    flag="$1"
    shift
    case "$flag" in
      --approved) approved=true; continue ;;
      --*=*) value="${flag#*=}"; flag="${flag%%=*}" ;;
      --title | --body-file | --search | --checked | --reopen | --when)
        [ $# -gt 0 ] || usage
        value="$1"
        shift
        ;;
      *) usage ;;
    esac
    [ -n "$value" ] || usage
    case "$flag" in
      --title) title="$value" ;;
      --body-file) file="$value" ;;
      --search) words="$value" ;;
      --checked) checked="$value" ;;
      --reopen | --when)
        [ -z "$reopen" ] || usage
        reopen="$value"
        [ "$flag" = --when ] || node -e '
          const text = process.argv[1];
          const date = new Date(`${text}T00:00:00Z`);
          process.exit(/^\d{4}-\d{2}-\d{2}$/.test(text) && !Number.isNaN(date.getTime()) && date.toISOString().startsWith(text) ? 0 : 1);
        ' "$value" || { refuse_follow_up "--reopen takes a date, YYYY-MM-DD, and --when a fact"; return 1; }
        ;;
      *) usage ;;
    esac
  done
  [ -n "$title" ] && [ -f "$file" ] && [ -n "$words" ] && [ -n "$checked" ] || usage
  make_tmp || return 1
  judge follow-up "$file" "$ISSUE_TMP/follow-up" "$reopen" || return 1

  branch="$(tc_get git.integrationBranch)"
  fetch_now || { refuse_follow_up "origin/$branch could not be fetched"; return 1; }
  head="$(git rev-parse --verify --quiet "refs/remotes/origin/$branch")" || { refuse_follow_up "there is no origin/$branch"; return 1; }
  if [ "$checked" != "$head" ]; then
    refuse_follow_up "--checked is $checked and the head of origin/$branch is $head: look for the problem there, and name that sha"
    return 1
  fi

  gh_repo . '' || true
  if ! gh_as_owner . "$(gh_owner . '')" api search/issues -X GET ${GH_REPO_HOST:+--hostname "$GH_REPO_HOST"} \
      -F "q=repo:$GH_REPO_PATH is:issue $words" -F per_page=100 \
      --jq '"\(.total_count) match(es)", (.items[] | "#\(.number) \(.state) \(.title)")'; then
    refuse_follow_up "the backlog could not be searched as $GH_AS_ACCOUNT: ${GH_AS_ERR:-gh failed}"
    return 1
  fi
  printf 'The backlog, searched by "%s": %s\n' "$words" "$GH_AS_OUT"

  label=follow-up
  [ -z "$reopen" ] || label=deferred
  level="$(tc_get autonomy.level)"
  case "$level" in
    balanced | autonomous) ;;
    *)
      if [ "$approved" = false ]; then
        printf '\nNothing is created at autonomy.level careful. The proposal, for a person to approve (--approved creates it):\n\n'
        printf 'Title: %s\nLabel: %s\n\n' "$title" "$label"
        cat "$ISSUE_TMP/follow-up"
        return 4
      fi
      ;;
  esac
  case "$label" in
    deferred) ensure_label deferred C5DEF5 'Waits for what its first line says' || return 1 ;;
    *) ensure_label follow-up D4C5F9 'What another issue left' || return 1 ;;
  esac
  post_issue "$title" "$ISSUE_TMP/follow-up" "$label"
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
    issue_write 'the label' "$n" "issues/$n/labels/pending-actions" -X DELETE || return 1
    printf 'issue close: #%s: no actions pending\n' "$n"
    return 0
  fi
  if [ -s "$comment" ] && [ "$commented" = false ]; then
    if [ "$labelled" = false ]; then
      ensure_label pending-actions D93F0B 'Merged with actions pending' || return 1
      issue_write 'the label' "$n" "issues/$n/labels" -f 'labels[]=pending-actions' || return 1
    fi
    issue_write 'the comment' "$n" "issues/$n/comments" -F "body=@$comment" || return 1
    printf 'issue close: #%s: actions pending, in a comment\n' "$n"
  fi
  if [ "$state" = 'open' ]; then
    issue_write 'the close' "$n" "issues/$n" -X PATCH -f state=closed || return 1
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
  claim) claim_issue "$@" ;;
  stop) stop_issue "$@" ;;
  gates) check_gates "$@" ;;
  follow-up) follow_up "$@" ;;
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
