#!/usr/bin/env bash
#
# Asking GitHub as an account that sees the repository, for the hook, worktree prune,
# trellis issue and trellis lesson.
#
#   . "$TRELLIS_ROOT/lib/gh.sh"
#   gh_api <dir> '' pulls/8 --jq .base.ref
#   gh_api <dir> <-R value or pull request URL> issues/4 --jq .state
#
# gh_api asks the REST interface of one repository: the one the second argument names, or the one of
# the origin remote of <dir>. GraphQL is refused in a cloud session, and a gh subcommand (`gh issue
# view`) is GraphQL. What an origin does not say (a local path, an ssh alias, no origin, GH_REPO set)
# is left to gh, which fills in {owner}/{repo}. gh_as_owner is the call under it, for the rest of gh.
#
# The account gh has active is not always the one that sees the repository: a person signed in on
# two accounts keeps one active, and a private repository of the other answers "not found". The
# calls here are reads, and the writes a person asks for with `trellis issue` (an issue, a comment, a
# label, an assignee, a state) and with `trellis lesson` (an issue, a comment, a label, a state). Each borrows the token of one account for that one gh
# call, and the account gh has active stays as it is. The token is never printed, written or exported.
#
# The account of a repository of github.com is the first of these that gh holds a token of:
#   1. the one tracker.account names, for the owner of the origin remote of <dir> only: it is read from
#      the config of <dir> (or TRELLIS_CONFIG), and says nothing about the repository of another owner;
#   2. the one named like the owner;
#   3. an owner that is no account (an organization): of the accounts gh is signed in to on github.com
#      (`gh auth status`), the active one first, the first that repos/<owner>/<name> answers;
# and with none, the active account, as gh would by itself.
#
# Neither is run in a command substitution: they set, in the caller's shell,
#   GH_AS_OUT      what gh printed on stdout
#   GH_AS_ERR      the first line gh printed on stderr, with any token blanked
#   GH_AS_ACCOUNT  who was asked: "the account of tracker.account (<name>)", "the owner's account
#                  (<owner>)", "the signed-in account (<name>)" or "the active account"
# and return gh's exit status. gh api prints the body of an error on stdout, so GH_AS_OUT is an answer
# only when the status is 0. The result of each lookup is kept for the run: a token per account, and
# the account of step 3 per owner.
#
# Works with bash 3.2.

command -v tc_get >/dev/null 2>&1 || . "$(dirname "${BASH_SOURCE[0]}")/config.sh"

GH_AS_OUT=''
GH_AS_ERR=''
GH_AS_ACCOUNT=''
# One record per owner looked up: "<owner>\001<token or empty>\n".
GH_TOKEN_CACHE=$'\n'
# One record per owner whose accounts were tried: "<owner>\001<account or empty>\n".
GH_FOUND_CACHE=$'\n'

# gh_split <text>: the host, owner and name of a repository named as owner/repo, host/owner/repo, an
# https URL (the one of a pull request too), an ssh URL or a scp-like remote, in GH_SPLIT_HOST,
# GH_SPLIT_OWNER, GH_SPLIT_NAME and GH_SPLIT_SSH. Empty for what does not parse.
gh_split() {
  local s="${1%%[?#]*}" path
  GH_SPLIT_HOST='' GH_SPLIT_OWNER='' GH_SPLIT_NAME='' GH_SPLIT_SSH=false
  case "$s" in
    http://* | https://*) s="${s#*://}"; GH_SPLIT_HOST="${s%%/*}"; path="${s#*/}" ;;
    ssh://*) s="${s#ssh://}"; GH_SPLIT_HOST="${s%%/*}"; path="${s#*/}"; GH_SPLIT_SSH=true ;;
    *@*:*) s="${s#*@}"; GH_SPLIT_HOST="${s%%:*}"; path="${s#*:}"; GH_SPLIT_SSH=true ;;
    */*/*) GH_SPLIT_HOST="${s%%/*}"; path="${s#*/}" ;;
    */*) GH_SPLIT_HOST='github.com'; path="$s" ;;
    *) return 0 ;;
  esac
  GH_SPLIT_HOST="${GH_SPLIT_HOST#*@}"
  GH_SPLIT_HOST="$(printf '%s' "${GH_SPLIT_HOST%%:*}" | tr '[:upper:]' '[:lower:]')"
  GH_SPLIT_OWNER="${path%%/*}"
  [ "$GH_SPLIT_OWNER" != "$path" ] || GH_SPLIT_OWNER=''
  path="${path#*/}"
  GH_SPLIT_NAME="${path%%/*}"
  GH_SPLIT_NAME="${GH_SPLIT_NAME%.git}"
}

# Whether a remote is a URL: without a scheme nor a user it is a path of this machine.
gh_is_url() { case "$1" in *://* | *@*:*) ;; *) return 1 ;; esac; }

# The owner of a repository of github.com. Prints nothing for another host or for a text that does not
# parse.
gh_owner_of() {
  gh_split "$1"
  [ "$GH_SPLIT_HOST" = 'github.com' ] || return 0
  printf '%s' "$GH_SPLIT_OWNER"
}

# The owner a gh call in <dir> reads: the one of <hint> when it names a repository (-R or a pull
# request URL), otherwise the one of the origin remote of <dir>. Prints nothing when unknown.
gh_owner() {
  local dir="$1" hint="${2:-}" url owner
  if [ -n "$hint" ]; then
    gh_owner_of "$hint"
    return 0
  fi
  url="$(git -C "$dir" remote get-url origin 2>/dev/null)" || return 0
  owner="$(gh_owner_of "$url")"
  printf '%s' "$owner"
}

# gh_repo <dir> [<hint>]: the repository a call in <dir> is about, as the path of its REST endpoints, in
# GH_REPO_PATH, and the host gh is told in GH_REPO_HOST (empty for the one gh takes by itself). Returns
# 1 for a hint that names no repository: the origin does not stand in for it.
gh_repo() {
  local text="${2:-}"
  GH_REPO_PATH='{owner}/{repo}'
  GH_REPO_HOST=''
  if [ -z "$text" ]; then
    [ -z "${GH_REPO:-}" ] || return 0
    text="$(git -C "$1" remote get-url origin 2>/dev/null)" || return 0
    gh_is_url "$text" || return 0
  fi
  gh_split "$text"
  if [[ ! "$GH_SPLIT_OWNER/$GH_SPLIT_NAME" =~ ^[A-Za-z0-9_-]+/[A-Za-z0-9._-]+$ ]] || [[ "$GH_SPLIT_NAME" =~ ^\.\.?$ ]] \
     || { [ "$GH_SPLIT_SSH" = true ] && [ "$GH_SPLIT_HOST" != 'github.com' ]; }; then
    [ -z "${2:-}" ]
    return
  fi
  GH_REPO_PATH="$GH_SPLIT_OWNER/$GH_SPLIT_NAME"
  # A text that is only owner/repo names no host: gh takes its own.
  case "$text" in */*/* | *@*:*) ;; *) return 0 ;; esac
  if [ "$GH_SPLIT_HOST" != 'github.com' ] || [ -n "${GH_HOST:-}" ]; then GH_REPO_HOST="$GH_SPLIT_HOST"; fi
}

# gh_api <dir> <hint or ''> <endpoint> [<arguments of gh api>]: the endpoint of a repository (gh_repo),
# asked as an account of it. Sets what gh_as_owner sets.
gh_api() {
  local dir="$1" hint="$2" endpoint="$3"
  shift 3
  if ! gh_repo "$dir" "$hint"; then
    GH_AS_OUT=''
    GH_AS_ERR="$hint names no repository"
    GH_AS_ACCOUNT='the active account'
    return 1
  fi
  gh_as_owner "$dir" "$(gh_owner "$dir" "$hint")" api "repos/$GH_REPO_PATH/$endpoint" \
    ${GH_REPO_HOST:+--hostname "$GH_REPO_HOST"} "$@"
}

# gh_search <dir> <hint or ''> <words>: what a search finds in the issues of a repository, open and closed,
# in GH_AS_OUT: how many, and one line for each.
gh_search() {
  gh_repo "$1" "$2" || true
  gh_as_owner "$1" "$(gh_owner "$1" "$2")" api search/issues -X GET ${GH_REPO_HOST:+--hostname "$GH_REPO_HOST"} \
    -F "q=repo:$GH_REPO_PATH is:issue $3" -F per_page=100 \
    --jq '"\(.total_count) match(es)", (.items[] | "#\(.number) \(.state) \(.title)")'
}

# gh_label <dir> <hint or ''> <name> <colour> <description>: makes sure the repository has the label.
# GitHub compares the names of labels without case.
gh_label() {
  gh_api "$1" "$2" 'labels?per_page=100' --paginate --jq '.[].name' || return 1
  printf '%s\n' "$GH_AS_OUT" | grep -qix -- "$3" && return 0
  gh_api "$1" "$2" labels -f "name=$3" -f "color=$4" -f "description=$5"
}

# gh_cached <cache> <key>: the value of the record of <key>, in GH_HIT. Returns 1 without one.
gh_cached() {
  local rest="$1" record
  GH_HIT=''
  while [ -n "$rest" ]; do
    record="${rest%%$'\n'*}"
    rest="${rest#*$'\n'}"
    if [ -n "$record" ] && [ "${record%%$'\001'*}" = "$2" ]; then
      GH_HIT="${record#*$'\001'}"
      return 0
    fi
  done
  return 1
}

# Sets GH_TOK to the token of <account> when gh holds one (empty otherwise), from the cache after the
# first lookup. Not run in a command substitution: the cache would be lost with the subshell.
gh_token_of() {
  local account="$1" tok
  if gh_cached "$GH_TOKEN_CACHE" "$account"; then
    GH_TOK="$GH_HIT"
    return 0
  fi
  tok="$(GH_PROMPT_DISABLED=1 gh auth token -h github.com -u "$account" 2>/dev/null </dev/null)" || tok=''
  GH_TOKEN_CACHE="$GH_TOKEN_CACHE$account"$'\001'"$tok"$'\n'
  GH_TOK="$tok"
}

gh_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# The accounts gh is signed in to on github.com, one per line, the active one first: asked first, it is
# the one kept for a repository every account sees. `gh auth status` fails when any account has a
# problem and still lists the rest, so its exit status says nothing.
gh_accounts() {
  GH_PROMPT_DISABLED=1 gh auth status --hostname github.com 2>&1 </dev/null | awk '
    function keep() { if (name != "") { if (active) first = first name "\n"; else others = others name "\n" } name = ""; active = 0 }
    /Logged in to|Failed to log in to/ {
      keep()
      if ($0 ~ /Logged in to/) for (i = 1; i < NF; i++) if ($i == "account") name = $(i + 1)
    }
    /Active account: true/ { active = 1 }
    END { keep(); printf "%s%s", first, others }
  '
}

# gh_find_account <owner>: the first signed-in account that the repository of GH_REPO_PATH (gh_repo, which
# every caller runs first) answers, in GH_FOUND (empty with none), kept per owner. Nothing is tried
# when that path is not one of <owner>.
gh_find_account() {
  local owner="$1" account
  GH_FOUND=''
  if gh_cached "$GH_FOUND_CACHE" "$owner"; then
    GH_FOUND="$GH_HIT"
    return 0
  fi
  [ "$(gh_lower "${GH_REPO_PATH%%/*}")" = "$(gh_lower "$owner")" ] || return 0
  # The list is read on its own descriptor, so that no gh call can read it.
  while IFS= read -r account <&3; do
    [ -n "$account" ] || continue
    gh_token_of "$account"
    [ -n "$GH_TOK" ] || continue
    if GH_TOKEN="$GH_TOK" GH_PROMPT_DISABLED=1 gh api "repos/$GH_REPO_PATH" \
         ${GH_REPO_HOST:+--hostname "$GH_REPO_HOST"} >/dev/null 2>&1 </dev/null; then
      GH_FOUND="$account"
      break
    fi
  done 3<<< "$(gh_accounts)"
  GH_FOUND_CACHE="$GH_FOUND_CACHE$owner"$'\001'"$GH_FOUND"$'\n'
}

# gh_account_for <dir> <owner>: the account a call about a repository of <owner> borrows (the head of
# this file says which), its token in GH_TOK (empty for the active one) and its name in GH_AS_ACCOUNT.
gh_account_for() {
  local dir="$1" owner="$2" named
  named="$(cd "$dir" 2>/dev/null && tc_get tracker.account)"
  if [ -n "$named" ] && [ "$(gh_lower "$(gh_owner "$dir")")" = "$(gh_lower "$owner")" ]; then
    gh_token_of "$named"
    if [ -n "$GH_TOK" ]; then
      GH_AS_ACCOUNT="the account of tracker.account ($named)"
      return 0
    fi
  fi
  gh_token_of "$owner"
  if [ -n "$GH_TOK" ]; then
    GH_AS_ACCOUNT="the owner's account ($owner)"
    return 0
  fi
  gh_find_account "$owner"
  # The tries leave their last token in GH_TOK: without an account found, none is borrowed.
  GH_TOK=''
  [ -n "$GH_FOUND" ] || return 0
  gh_token_of "$GH_FOUND"
  [ -z "$GH_TOK" ] || GH_AS_ACCOUNT="the signed-in account ($GH_FOUND)"
}

# gh_as_owner <dir> <owner> <gh arguments>: runs gh in <dir>, as an account of a repository of <owner>
# when it can. gh_repo is run before it, for the same repository.
gh_as_owner() {
  local dir="$1" owner="$2" tok='' errfile status line=''
  shift 2
  GH_AS_OUT=''
  GH_AS_ERR=''
  GH_AS_ACCOUNT='the active account'
  if [ -z "${GH_TOKEN:-}${GITHUB_TOKEN:-}${GH_HOST:-}${GH_REPO:-}" ] && [ -n "$owner" ] \
     && command -v gh >/dev/null 2>&1; then
    gh_account_for "$dir" "$owner"
    tok="$GH_TOK"
  fi
  errfile="$(mktemp "${TMPDIR:-/tmp}/trellis-gh.XXXXXX" 2>/dev/null)" || errfile=
  if [ -n "$tok" ]; then
    GH_AS_OUT="$(cd "$dir" 2>/dev/null && GH_TOKEN="$tok" GH_PROMPT_DISABLED=1 gh "$@" 2>"${errfile:-/dev/null}" </dev/null)"
  else
    GH_AS_OUT="$(cd "$dir" 2>/dev/null && GH_PROMPT_DISABLED=1 gh "$@" 2>"${errfile:-/dev/null}" </dev/null)"
  fi
  status=$?
  if [ -n "$errfile" ]; then IFS= read -r line < "$errfile" 2>/dev/null || true; rm -f "$errfile"; fi
  [ -n "$tok" ] && line="${line//"$tok"/***}"
  GH_AS_ERR="$line"
  return "$status"
}
