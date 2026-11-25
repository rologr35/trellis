#!/usr/bin/env bash
#
# test.sh: the suites of this repository, every one or the ones of its argument.
#
#   ./test.sh [shell | node]
#
# shell runs each *.test.sh of lib/, scripts/ and hooks/; node runs hygiene/*.test.mjs. Every suite
# runs though one fails, and the exit code is 1 when any did.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

case "${1:-}" in
  '' | shell | node) ;;
  *) echo 'usage: ./test.sh [shell | node]' >&2; exit 2 ;;
esac
[ $# -le 1 ] || { echo 'usage: ./test.sh [shell | node]' >&2; exit 2; }

# In GitHub Actions each suite is a group of the log.
open='' close=''
[ "${GITHUB_ACTIONS:-}" = true ] && { open='::group::'; close='::endgroup::'; }

status=0
if [ "${1:-shell}" = shell ]; then
  for t in lib/*.test.sh scripts/*.test.sh hooks/*.test.sh; do
    [ -f "$t" ] || continue
    printf '%s%s\n' "$open" "$t"
    bash "$t" || status=1
    [ -z "$close" ] || printf '%s\n' "$close"
  done
fi
if [ "${1:-node}" = node ]; then
  node --test hygiene/*.test.mjs || status=1
fi
exit "$status"
