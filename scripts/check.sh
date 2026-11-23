#!/usr/bin/env bash
#
# check: the project's own checks, the names listed in `[command] check`, run in order from the
# project root and stopped at the first failure.
#
#   trellis check
#
# Each name is a [command "<name>"] whose `run` is a shell command. No interpolation: a command
# runs exactly as written in the config.

set -uo pipefail

TRELLIS_ROOT="${TRELLIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/config.sh
. "$TRELLIS_ROOT/lib/config.sh"

top="$(git rev-parse --show-toplevel 2>/dev/null)" || top="$(pwd)"
names="$(tc_all command.check)"
if [ -z "$names" ]; then
  printf 'check: [command] check lists nothing\n' >&2
  exit 1
fi

while IFS= read -r name; do
  [ -n "$name" ] || continue
  run="$(tc_get "command.$name.run")"
  if [ -z "$run" ]; then
    printf 'check: [command "%s"] has no run\n' "$name" >&2
    exit 1
  fi
  printf 'check: %s: %s\n' "$name" "$run"
  if ! (cd "$top" && bash -c "$run"); then
    printf 'check: %s failed\n' "$name" >&2
    exit 1
  fi
done <<< "$names"
printf 'check: all passed\n'
