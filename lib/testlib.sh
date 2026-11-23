#!/usr/bin/env bash
#
# Helpers of the *.test.sh files: an isolated HOME and git identity, throwaway repositories and
# assertions that print one line each and add up to an exit status.
#
#   . "$(dirname "$0")/../lib/testlib.sh"
#   repo="$(tl_repo)"
#   tl_eq 'name' 'expected' "$actual"
#   tl_has 'name' 'needle' "$haystack"
#   tl_lacks 'name' 'needle' "$haystack"
#   tl_done

set -uo pipefail

TRELLIS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TRELLIS_ROOT
TRELLIS="$TRELLIS_ROOT/bin/trellis"

TL_TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TL_TMP"' EXIT
mkdir -p "$TL_TMP/home"
export HOME="$TL_TMP/home"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
unset TRELLIS_CONFIG CLAUDE_CODE_REMOTE CLAUDE_PROJECT_DIR ANTHROPIC_API_KEY GH_TOKEN 2>/dev/null || true

TL_PASSED=0
TL_FAILED=0

# A fresh repository on main with one empty commit; prints its path.
tl_repo() {
  local dir
  dir="$(mktemp -d "$TL_TMP/repo.XXXXXX")"
  git -C "$dir" init -q
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" commit -q --allow-empty -m 'chore: start'
  printf '%s\n' "$dir"
}

tl_pass() { TL_PASSED=$((TL_PASSED + 1)); printf '  ok    %s\n' "$1"; }
tl_fail() { TL_FAILED=$((TL_FAILED + 1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        /'; return 0; }

tl_eq() {
  if [ "$2" = "$3" ]; then tl_pass "$1"; else tl_fail "$1" "expected: $2
actual:   $3"; fi
}

tl_has() {
  case "$3" in
    *"$2"*) tl_pass "$1" ;;
    *) tl_fail "$1" "missing: $2
in: $3" ;;
  esac
}

tl_lacks() {
  case "$3" in
    *"$2"*) tl_fail "$1" "unexpected: $2
in: $3" ;;
    *) tl_pass "$1" ;;
  esac
}

tl_done() {
  printf '\n%s passed, %s failed\n' "$TL_PASSED" "$TL_FAILED"
  [ "$TL_FAILED" -eq 0 ]
}
