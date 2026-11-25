#!/usr/bin/env bash
#
# lesson: bring a lesson of this project to the repository of trellis, with the approval of a person.
#
#   trellis lesson --title <t> --body-file <file> --search <words> [--issue <n> [--reopen]]
#                  [--approved <digest>]
#
# The body, in English, has one line `Kind: defect` or `Kind: rule` and the sections **Incident** and
# **What must stop happening**, none empty; a defect brings its case in the first one, in a code block. The
# title and the body keep the style of what is published and name nothing private: neither a term of this
# project (its name, the owner and the name of its origin, where it is in this machine, its tracked paths
# with a folder, a reference or a URL of another repository) nor one of the list of the machine (see
# `trellis private-names`), whatever project.public says. A repository that GitHub says is private, or that
# cannot be asked, publishes nothing unless that list has the name of the project or the one of its origin.
#
# It prints what the search finds in the issues of trellis.upstream, where the lesson goes, the exact text
# and the digest of everything it was given, and exits 4. --approved with that digest publishes: an issue
# with the label lesson or, with --issue, the body as a comment on that one, another case of it. A closed
# issue stays closed without --reopen. A person approves at every autonomy.level, so a run without one
# (CLAUDE_CODE_REMOTE) publishes nothing. The project whose repository is the upstream uses
# `trellis issue follow-up`.
#
# Exit 0 published, 1 refused or failed, 2 wrong use, 4 proposed.

set -uo pipefail

TRELLIS_ROOT="${TRELLIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/config.sh
. "$TRELLIS_ROOT/lib/config.sh"
# shellcheck source=../lib/gh.sh
. "$TRELLIS_ROOT/lib/gh.sh"

usage() {
  printf 'usage: trellis lesson --title <t> --body-file <file> --search <words> [--issue <n> [--reopen]] [--approved <digest>]\n' >&2
  exit 2
}
refuse() { printf 'lesson: %s\n' "$1" >&2; exit 1; }
judge() { node "$TRELLIS_ROOT/scripts/lesson.mjs" "$@"; }

title='' file='' words='' issue='' reopen=false approved=''
while [ $# -gt 0 ]; do
  flag="$1"
  shift
  case "$flag" in
    --reopen) reopen=true; continue ;;
    --*=*) value="${flag#*=}"; flag="${flag%%=*}" ;;
    --title | --body-file | --search | --issue | --approved)
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
    --issue) issue="$value" ;;
    --approved) approved="$value" ;;
    *) usage ;;
  esac
done
[ -n "$title" ] && [ -f "$file" ] && [ -n "$words" ] || usage
[ -z "$issue" ] || [[ "$issue" =~ ^[1-9][0-9]*$ ]] || usage
[ "$reopen" = false ] || [ -n "$issue" ] || usage

[ -z "$approved" ] || [ -z "${CLAUDE_CODE_REMOTE:-}" ] \
  || refuse 'a run without a person (CLAUDE_CODE_REMOTE) publishes nothing: the proposal is left for one to approve'

# What is judged, shown and published is one reading of the file.
tmp="$(mktemp -d "${TMPDIR:-/tmp}/trellis-lesson.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT
body="$tmp/body"
cat -- "$file" > "$body" || refuse "$file could not be read"

# A repository by its URL: a text without a scheme nor a user is a path of this machine.
is_url() { case "$1" in *://* | *@*:*) ;; *) return 1 ;; esac; }

url="$(judge upstream)" || exit 1
{ is_url "$url" && gh_repo . "$url"; } || refuse "trellis.upstream ($url) is not a repository of GitHub"
upstream="$GH_REPO_PATH"
host="$GH_REPO_HOST"
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
origin="$(git remote get-url origin 2>/dev/null)" || origin=''
if is_url "$origin"; then
  gh_split "$origin"
  [ "$(lower "$GH_SPLIT_OWNER/$GH_SPLIT_NAME")" != "$(lower "$upstream")" ] \
    || refuse "this is the repository of $upstream: here a lesson goes through trellis issue follow-up"
fi

listed="$(judge judge "$title" "$body" "$upstream")" || exit 1
if [ "$listed" != 'listed' ]; then
  said='this repository cannot be asked whether it is private'
  if is_url "$origin" && gh_repo . "$origin" \
      && gh_as_owner . "$(gh_owner . "$origin")" api "repos/$GH_REPO_PATH" ${GH_REPO_HOST:+--hostname "$GH_REPO_HOST"} --jq .private; then
    said="$GH_AS_OUT"
    case "$said" in true) said='this repository is private' ;; false) ;; *) said='GitHub does not say whether this repository is private' ;; esac
  fi
  [ "$said" = 'false' ] || refuse "$said, and $listed: it publishes nothing until a person writes one of them there"
fi

digest="$(judge digest "$body" "$title" "$host" "$upstream" "$words" "$issue" "$reopen")" || exit 1
[ -z "$approved" ] || [ "$approved" = "$digest" ] \
  || refuse "$approved is not the digest of this lesson: its text, title, destination and flags are not the ones a person read"

if [ -n "$issue" ]; then
  gh_api . "$url" "issues/$issue" --jq '"\(.state) \(if .pull_request then "pull" else "issue" end) \(.title)"' \
    || refuse "issue $issue of $upstream could not be read as $GH_AS_ACCOUNT: ${GH_AS_ERR:-gh failed}"
  read -r state kind issue_title <<< "$GH_AS_OUT"
  [ "$kind" = 'issue' ] || refuse "$issue is a pull request of $upstream, not an issue"
  where="a comment on issue $issue of $upstream, $state"
  if [ "$state" = 'closed' ]; then
    if [ "$reopen" = true ]; then where="$where, which is opened"; else where="$where (--reopen opens it)"; fi
  fi
  where="$where: $issue_title"
else
  where="a new issue of $upstream, with the label lesson"
fi

if [ -z "$approved" ]; then
  gh_search . "$url" "$words" || refuse "the issues of $upstream could not be searched as $GH_AS_ACCOUNT: ${GH_AS_ERR:-gh failed}"
  printf 'The issues of %s, searched by "%s": %s\n' "$upstream" "$words" "$GH_AS_OUT"
  printf '\nNothing is published yet. The proposal, for a person to read and approve:\n\nWhere: %s\n' "$where"
  [ -n "$issue" ] || printf 'Title: %s\n' "$title"
  printf '\n'
  cat "$body"
  printf '\nDigest: %s\n' "$digest"
  exit 4
fi

unpublished() { refuse "it could not be published as $GH_AS_ACCOUNT: ${GH_AS_ERR:-gh failed}"; }
if [ -n "$issue" ]; then
  if [ "$reopen" = true ] && [ "$state" = 'closed' ]; then
    gh_api . "$url" "issues/$issue" -X PATCH -f state=open || unpublished
  fi
  gh_api . "$url" "issues/$issue/comments" -F "body=@$body" --jq .html_url || unpublished
else
  gh_label . "$url" lesson BFD4F2 'What a project learned' \
    || refuse "the label lesson could not be read or created as $GH_AS_ACCOUNT: ${GH_AS_ERR:-gh failed}"
  gh_api . "$url" issues -f "title=$title" -F "body=@$body" -f 'labels[]=lesson' --jq .html_url || unpublished
fi
printf '%s\n' "$GH_AS_OUT"
