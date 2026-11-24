#!/usr/bin/env bash
#
# setup: point git at the project's hooks, core.hooksPath = git.hooksPath (.githooks by
# default), when it is unset and the folder exists; and, at the start of a session, put the .trellis/bin of the project's copy on its
# PATH, through CLAUDE_ENV_FILE. Idempotent. Run by `init` and by the SessionStart hook, so every
# clone where Claude runs, a cloud one included, gets the git hooks.
#
#   trellis setup [--quiet]
#
# Does nothing outside a project that has trellis.config, so a plugin installed for the user never
# touches other repositories. A core.hooksPath set to something else is left alone and reported.

set -uo pipefail

TRELLIS_ROOT="${TRELLIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

quiet=false
[ "${1:-}" = '--quiet' ] && quiet=true
say() { [ "$quiet" = true ] || printf 'setup: %s\n' "$1"; }

dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || { say 'not a git repository, nothing to do'; exit 0; }
[ -f "$top/trellis.config" ] || { say 'no trellis.config, nothing to do'; exit 0; }

# The PATH of the session's Bash tool; the file is added to, because other hooks write it too.
if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -f "$top/.trellis/bin/trellis" ]; then
  line="export PATH=$(printf '%q' "$top/.trellis/bin"):\"\$PATH\""
  if ! grep -qxF -- "$line" "$CLAUDE_ENV_FILE" 2>/dev/null; then
    printf '%s\n' "$line" >> "$CLAUDE_ENV_FILE"
    say '.trellis/bin added to the PATH of the session'
  fi
fi

# shellcheck source=../lib/config.sh
. "$TRELLIS_ROOT/lib/config.sh"
hooks="$(cd "$top" && tc_get git.hooksPath)"
[ -d "$top/$hooks" ] || { say "no $hooks/, nothing to do"; exit 0; }

current="$(git -C "$top" config --get core.hooksPath 2>/dev/null || true)"
case "$current" in
  "$hooks") say "core.hooksPath already $hooks" ;;
  '')
    git -C "$top" config core.hooksPath "$hooks"
    say "core.hooksPath set to $hooks"
    ;;
  *) say "core.hooksPath is $current, left alone (trellis doctor reports it)" ;;
esac
exit 0
