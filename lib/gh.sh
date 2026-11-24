#!/usr/bin/env bash
#
# Asking GitHub as the account that owns the repository, for the hook and for worktree prune.
#
#   . "$TRELLIS_ROOT/lib/gh.sh"
#   owner="$(gh_owner <dir> [<-R value or pull request URL>])"
#   gh_as_owner <dir> "$owner" pr view 8 --json baseRefName --jq .baseRefName
#
# The account gh has active is not always the one that sees the repository: a person signed in on
# two accounts keeps one active, and a private repository of the other answers "not found". The
# calls here are reads (`view`, `list`), so they borrow the token of the owner's account for that
# one gh call. The token is never printed, written or exported.
#
# gh_as_owner is not run in a command substitution: it sets, in the caller's shell,
#   GH_AS_OUT      what gh printed on stdout
#   GH_AS_ERR      the first line gh printed on stderr, with any token blanked
#   GH_AS_ACCOUNT  who was asked: "the owner's account (<owner>)" or "the active account"
# and returns gh's exit status. The result of each lookup is kept for the run, per owner.
#
# Works with bash 3.2.

GH_AS_OUT=''
GH_AS_ERR=''
GH_AS_ACCOUNT=''
# One record per owner looked up: "<owner>\001<token or empty>\n".
GH_TOKEN_CACHE=$'\n'

# The owner of a repository named as owner/repo, host/owner/repo, an https URL, an ssh URL or a
# scp-like remote. Prints nothing for another host or for a text that does not parse.
gh_owner_of() {
  local s="${1%%[?#]*}" host path owner
  case "$s" in
    http://* | https://*) s="${s#*://}"; s="${s#*@}"; host="${s%%/*}"; host="${host%%:*}"; path="${s#*/}" ;;
    ssh://*) s="${s#ssh://}"; s="${s#*@}"; host="${s%%/*}"; host="${host%%:*}"; path="${s#*/}" ;;
    *@*:*) s="${s#*@}"; host="${s%%:*}"; path="${s#*:}" ;;
    */*/*) host="${s%%/*}"; path="${s#*/}" ;;
    */*) host='github.com'; path="$s" ;;
    *) return 0 ;;
  esac
  host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
  [ "$host" = 'github.com' ] || return 0
  owner="${path%%/*}"
  [ -n "$owner" ] && [ "$owner" != "$path" ] || return 0
  printf '%s' "$owner"
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

# Sets GH_TOK to the token of <owner>'s account when gh holds one (empty otherwise), from the cache
# after the first lookup. Not run in a command substitution: the cache would be lost with the subshell.
gh_token_of() {
  local owner="$1" rest record tok
  GH_TOK=
  rest="$GH_TOKEN_CACHE"
  while [ -n "$rest" ]; do
    record="${rest%%$'\n'*}"
    rest="${rest#*$'\n'}"
    if [ "${record%%$'\001'*}" = "$owner" ] && [ -n "$record" ]; then
      GH_TOK="${record#*$'\001'}"
      return 0
    fi
  done
  tok="$(GH_PROMPT_DISABLED=1 gh auth token -h github.com -u "$owner" 2>/dev/null </dev/null)" || tok=''
  GH_TOKEN_CACHE="$GH_TOKEN_CACHE$owner"$'\001'"$tok"$'\n'
  GH_TOK="$tok"
}

# gh_as_owner <dir> <owner> <gh arguments>: runs gh in <dir>, as <owner>'s account when it can.
gh_as_owner() {
  local dir="$1" owner="$2" tok='' errfile status line
  shift 2
  GH_AS_OUT=''
  GH_AS_ERR=''
  GH_AS_ACCOUNT='the active account'
  if [ -z "${GH_TOKEN:-}${GITHUB_TOKEN:-}${GH_HOST:-}${GH_REPO:-}" ] && [ -n "$owner" ] \
     && command -v gh >/dev/null 2>&1; then
    gh_token_of "$owner"
    tok="$GH_TOK"
    [ -n "$tok" ] && GH_AS_ACCOUNT="the owner's account ($owner)"
  fi
  errfile="$(mktemp "${TMPDIR:-/tmp}/trellis-gh.XXXXXX")" || errfile=/dev/null
  if [ -n "$tok" ]; then
    GH_AS_OUT="$(cd "$dir" 2>/dev/null && GH_TOKEN="$tok" GH_PROMPT_DISABLED=1 gh "$@" 2>"$errfile" </dev/null)"
  else
    GH_AS_OUT="$(cd "$dir" 2>/dev/null && GH_PROMPT_DISABLED=1 gh "$@" 2>"$errfile" </dev/null)"
  fi
  status=$?
  IFS= read -r line < "$errfile" 2>/dev/null || true
  rm -f "$errfile"
  [ -n "$tok" ] && line="${line//"$tok"/***}"
  GH_AS_ERR="$line"
  return "$status"
}
