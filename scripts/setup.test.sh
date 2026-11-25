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

printf '\nthe notice of a newer version\n'
up="$(tl_upstream)"
git -C "$up" tag v0.9.0
git -C "$up" tag v0.10.1
git -C "$up" tag v0.10.0
git -C "$up" tag v9.0.0-rc1
git -C "$up" tag next
project="$(tl_repo)"
cd "$project" || exit 1
printf '[trellis]\n\tupstream = %s\n' "$up" > trellis.config
mkdir .trellis
version() { printf '%s 0123456789012345678901234567890123456789\n' "$1" > .trellis/VERSION; }
version 0.9.0
common="$(git rev-parse --absolute-git-dir)"
# A session of another day, and one of another day that does not ask, which leaves no process behind.
tomorrow() { rm -f "$common/trellis-version-asked" "$common/trellis-version-said"; }
heard() { rm -f "$common/trellis-version-said"; date +%Y-%m-%d > "$common/trellis-version-asked"; }
asked() { local i=0; while [ $i -lt 100 ] && [ "$(cat "$common/trellis-version" 2>/dev/null)" != "$1" ]; do sleep 0.1; i=$((i + 1)); done; cat "$common/trellis-version" 2>/dev/null; }
session() { "$TRELLIS" setup --quiet 2>&1; }
tl_eq 'the first session says nothing' '' "$(session)"
tl_eq '  and leaves the newest tag that is a version' 'v0.10.1' "$(asked v0.10.1)"
tl_eq '  with no file half written' '' "$(ls "$common" | grep 'trellis-version\.')"
notice='trellis 0.10.1 is out and this project has 0.9.0: trellis update v0.10.1, in a pull request of its own'
tl_eq 'the next one says it, quiet and with no hooks folder' "$notice" "$(session)"
tl_eq '  once a day' '' "$(session)"
heard
tl_has 'and says it when it is not quiet' "$notice" "$("$TRELLIS" setup)"
heard
version 0.10.1
tl_eq 'an equal one is not said' '' "$(session)"
heard
version 0.11.0
tl_eq 'nor an older one' '' "$(session)"
heard
version 1.0.0
tl_eq 'nor one older in its first number' '' "$(session)"
heard
version 0.8.9
printf 'v0.08.10\n' > "$common/trellis-version"
tl_has 'a number with a zero before it is read' 'trellis 0.08.10 is out' "$(session)"
for text in 'v9.9.9; rm' '' 'v9.9'; do
  heard
  printf '%s\n' "$text" > "$common/trellis-version"
  tl_eq "what is no version is not said: $text" '' "$(session)"
done
heard
printf 'v9.9.9' > "$common/trellis-version"
printf 'edited\n' > .trellis/VERSION
tl_eq 'nor is anything without a version of the project' '' "$(session)"
version 0.9.0

printf '\nwhat asks\n'
rm -f "$common"/trellis-version*
session > /dev/null && asked v0.10.1 > /dev/null
git -C "$up" tag v0.12.0
session > /dev/null
sleep 1
tl_eq 'the same day nothing is asked again' 'v0.10.1' "$(asked v0.10.1)"
printf '2001-01-01\n' > "$common/trellis-version-asked"
session > /dev/null
tl_eq 'another day it is' 'v0.12.0' "$(asked v0.12.0)"
git worktree add -q "$TL_TMP/wt3" -b 3-wt
mkdir "$TL_TMP/wt3/.trellis" && cp .trellis/VERSION "$TL_TMP/wt3/.trellis/" && cp trellis.config "$TL_TMP/wt3/"
heard
tl_has 'a worktree reads the file of the clone' 'trellis 0.12.0 is out' "$(cd "$TL_TMP/wt3" && session)"
tl_eq '  and what it said is said' '' "$(session)"
tomorrow
git config -f trellis.config trellis.upstream "$TL_TMP/nowhere"
session > /dev/null
sleep 1
tl_eq 'without a network the file stays' 'v0.12.0' "$(cat "$common/trellis-version")"
tl_eq '  and no session fails' '0' "$(tomorrow; session > /dev/null; echo $?)"
mkdir "$TL_TMP/slow"
cat > "$TL_TMP/slow/git" <<SLOW
#!/bin/sh
case " \$* " in *' ls-remote '*) touch "$TL_TMP/hanging"; sleep 6 ;; esac
exec "$(command -v git)" "\$@"
SLOW
chmod +x "$TL_TMP/slow/git"
git config -f trellis.config trellis.upstream "$up"
tomorrow
from=$SECONDS
said="$(PATH="$TL_TMP/slow:$PATH" "$TRELLIS" setup --quiet 2>&1)"
took=$((SECONDS - from))
tl_has 'with an upstream that hangs it says what the file had' 'trellis 0.12.0 is out' "$said"
tl_eq '  and returns in under two seconds' 'yes' "$([ "$took" -lt 2 ] && echo yes || echo "$took")"
i=0; while [ $i -lt 50 ] && [ ! -e "$TL_TMP/hanging" ]; do sleep 0.1; i=$((i + 1)); done
tl_eq '  while it is asked' 'yes' "$([ -e "$TL_TMP/hanging" ] && echo yes)"
rm -rf .trellis "$common"/trellis-version*
session > /dev/null
tl_eq 'a project without a copy asks nothing' '' "$(ls "$common" | grep trellis)"
cd "$own" || exit 1
git checkout -q .claude-plugin
printf 'v99.0.0\n' > .git/trellis-version
tl_eq 'the repository of trellis hears nothing' '' "$(bash bin/trellis setup --quiet)"
tl_eq '  and asks nothing' 'trellis-version' "$(ls .git | grep trellis)"

tl_done
