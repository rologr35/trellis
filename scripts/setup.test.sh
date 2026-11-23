#!/usr/bin/env bash
# Exercises scripts/setup.sh: only in a trellis project with .githooks/, idempotent, never overrides.
. "$(dirname "$0")/../lib/testlib.sh"

repo="$(tl_repo)"
cd "$repo" || exit 1
mkdir .githooks

"$TRELLIS" setup >/dev/null
tl_eq 'no trellis.config: untouched' '' "$(git config --get core.hooksPath)"

touch trellis.config
"$TRELLIS" setup >/dev/null
tl_eq 'sets core.hooksPath' '.githooks' "$(git config --get core.hooksPath)"
out="$("$TRELLIS" setup)"
tl_has 'idempotent' 'already .githooks' "$out"
tl_eq 'quiet prints nothing' '' "$("$TRELLIS" setup --quiet)"

git config core.hooksPath .hooks-elsewhere
out="$("$TRELLIS" setup)"
tl_eq 'another value is left alone' '.hooks-elsewhere' "$(git config --get core.hooksPath)"
tl_has 'and reported' 'left alone' "$out"

git config --unset core.hooksPath
other="$(tl_repo)"
(cd "$other" && CLAUDE_PROJECT_DIR="$repo" "$TRELLIS" setup --quiet)
tl_eq 'CLAUDE_PROJECT_DIR names the project' '.githooks' "$(git config --get core.hooksPath)"

tl_done
