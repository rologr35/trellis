#!/usr/bin/env bash
#
# private-names: refuse a private name in what a public project publishes.
#
#   trellis private-names (--staged | --file <file> | --text <text>)...
#
# With project.public = true it looks for each term of the list of the machine, which is the file
# private-names of ${XDG_CONFIG_HOME:-$HOME/.config}/trellis/: one term per line, with # for a comment.
#   --staged   the added lines of the index, and its paths (the pre-commit hook)
#   --file     the text of a file
#   --text     that text (the commit-msg hook with the message, pre-push with the name of a branch)
# A term is found in any letter case, without accents nor invisible characters, and with -, _, ., spaces
# or nothing between its words. One under six letters is found only as a whole word, which ends at
# anything that is not a letter or a digit and at a change of case. `trellis pr-check --body` and
# `trellis issue create`, follow-up and stop judge what they are given the same way.
#
# Exit 1 names each term and where it is, or the list that cannot be read. Without a list it says so and
# exits 0. With project.public unset it does nothing. lib/private-names.mjs defines the list and how a
# term is found.

set -uo pipefail

TRELLIS_ROOT="${TRELLIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

usage() { printf 'usage: trellis private-names (--staged | --file <file> | --text <text>)...\n' >&2; exit 2; }

[ $# -gt 0 ] || usage
args=("$@")
while [ $# -gt 0 ]; do
  case "$1" in
    --staged) shift ;;
    --file) [ $# -gt 1 ] && [ -f "$2" ] || usage; shift 2 ;;
    --text) [ $# -gt 1 ] || usage; shift 2 ;;
    *) usage ;;
  esac
done
exec node "$TRELLIS_ROOT/scripts/private-names.mjs" "${args[@]}"
