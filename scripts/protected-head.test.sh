#!/usr/bin/env bash
# Exercises scripts/protected-head-ci.sh: a pull request from a protected branch is closed, one from
# an issue branch passes, and a config that does not parse fails the job instead of passing it.
. "$(dirname "$0")/../lib/testlib.sh"

SCRIPT="$TRELLIS_ROOT/scripts/protected-head-ci.sh"
stubs="$TL_TMP/stubs"
mkdir -p "$stubs"
printf '#!/bin/sh\necho "gh $*" >> "%s/gh.log"\n' "$TL_TMP" > "$stubs/gh"
chmod +x "$stubs/gh"
repo="$(tl_repo)"
cd "$repo" || exit 1
printf '[git]\n\tprotected = main\n\tprotected = develop\n' > trellis.config

run() { HEAD_REF="$1" NUMBER=7 GITHUB_REPOSITORY=o/r PATH="$stubs:$PATH" bash "$SCRIPT" > "$TL_TMP/out.txt" 2>&1; echo $?; }

tl_eq 'an issue branch passes' '0' "$(run 7-thing)"
tl_eq 'a protected head fails' '1' "$(run develop)"
tl_has 'and the pull request is closed' 'gh pr close 7' "$(cat "$TL_TMP/gh.log" 2>/dev/null)"
printf '[git\n' > trellis.config
rm -f "$TL_TMP/gh.log"
tl_eq 'a config that does not parse fails the job' '3' "$(run develop)"
tl_has 'naming the parse error' 'does not parse' "$(cat "$TL_TMP/out.txt")"

tl_done
