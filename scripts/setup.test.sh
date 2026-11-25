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

git config --unset core.hooksPath
git config -f trellis.config git.hooksPath tool/hooks
"$TRELLIS" setup >/dev/null
tl_eq 'a folder that does not exist is not set' '' "$(git config --get core.hooksPath)"
mkdir -p tool/hooks
"$TRELLIS" setup >/dev/null
tl_eq 'git.hooksPath names another folder' 'tool/hooks' "$(git config --get core.hooksPath)"
tl_has 'idempotent' 'already tool/hooks' "$("$TRELLIS" setup)"

printf '\nthe command of the copy on the PATH of a session\n'
spaced="$TL_TMP/a b"
mkdir "$spaced" && cd "$spaced" && git init -q && touch trellis.config
env_file="$TL_TMP/env.sh"
: > "$env_file"
CLAUDE_ENV_FILE="$env_file" "$TRELLIS" setup --quiet
tl_eq 'without a copy nothing is added' '' "$(cat "$env_file")"
mkdir -p .trellis/bin && printf '#!/bin/sh\necho the copy\n' > .trellis/bin/trellis && chmod +x .trellis/bin/trellis
"$TRELLIS" setup --quiet
tl_eq 'nor without CLAUDE_ENV_FILE' '' "$(cat "$env_file")"
printf 'export OTHER=1\n' > "$env_file"
CLAUDE_ENV_FILE="$env_file" "$TRELLIS" setup --quiet
tl_eq 'with both the copy is found first, without a git hooks folder' 'the copy' "$(. "$env_file"; trellis)"
tl_has 'what the file held stays' 'OTHER=1' "$(cat "$env_file")"
tl_has 'the PATH that was there stays' "$PATH" "$(. "$env_file"; printf '%s' "$PATH")"
CLAUDE_ENV_FILE="$env_file" "$TRELLIS" setup --quiet
tl_eq 'a second start adds nothing' '2' "$(grep -c '' "$env_file")"
rm trellis.config && : > "$env_file"
CLAUDE_ENV_FILE="$env_file" "$TRELLIS" setup --quiet
tl_eq 'no trellis.config: untouched' '' "$(cat "$env_file")"

printf '\nthe repository of trellis\n'
own="$(tl_upstream)"
cd "$own" || exit 1
: > "$env_file"
CLAUDE_ENV_FILE="$env_file" bash bin/trellis setup --quiet
tl_eq 'its own command is on the PATH of the session' "$own/bin/trellis" "$(. "$env_file"; command -v trellis)"
CLAUDE_ENV_FILE="$env_file" bash bin/trellis setup --quiet
tl_eq 'a second start adds nothing' '1' "$(grep -c '' "$env_file")"
git worktree add -q "$TL_TMP/wt" -b 2-wt
: > "$env_file"
(cd "$TL_TMP/wt" && CLAUDE_ENV_FILE="$env_file" bash "$own/bin/trellis" setup --quiet)
tl_eq 'the one of the worktree, in a worktree' "$TL_TMP/wt/bin/trellis" "$(. "$env_file"; command -v trellis)"
printf '{"name": "another"}\n' > .claude-plugin/plugin.json && : > "$env_file"
CLAUDE_ENV_FILE="$env_file" bash bin/trellis setup --quiet
tl_eq 'a project with another name adds nothing' '' "$(cat "$env_file")"

tl_done
