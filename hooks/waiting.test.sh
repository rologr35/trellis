#!/usr/bin/env bash
# Exercises hooks/waiting.sh with Notification payloads: the log of the clone, the notification of the
# system and the command of command.notify, in a local and in a cloud session.
. "$(dirname "$0")/../lib/testlib.sh"

HOOK="$TRELLIS_ROOT/hooks/waiting.sh"
stubs="$TL_TMP/stubs"
mkdir -p "$stubs"
# osascript records what it would show, so no suite puts a notification on the screen.
printf '#!/bin/sh\nprintf "%%s|" "$@" >> "%s/osascript.log"\necho >> "%s/osascript.log"\n' "$TL_TMP" "$TL_TMP" > "$stubs/osascript"
chmod +x "$stubs/osascript"
export PATH="$stubs:$PATH"
unset CLAUDE_CODE_REMOTE

repo="$(tl_repo)"
cd "$repo" || exit 1
git checkout -q -b 7-some-work
git worktree add -q -b 8-other "$TL_TMP/wt" 2>/dev/null
log="$repo/.git/trellis/waiting.log"

payload() { # <type> <cwd> [<session>] [<message>]
  printf '{"hook_event_name":"Notification","session_id":"%s","cwd":"%s","notification_type":"%s","message":"%s"}' \
    "${3:-s1}" "$2" "$1" "${4:-Claude needs your permission to use Edit}"
}
count() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }
lines() { count "$log"; }
shown() { count "$TL_TMP/osascript.log"; }

echo 'waiting: a project with no command.notify'
n=0
for type in permission_prompt idle_prompt elicitation_dialog agent_needs_input; do
  out="$(payload "$type" "$repo" | bash "$HOOK")"; code=$?
  n=$((n + 1))
  tl_eq "$type: one line" "$n" "$(lines)"
  tl_eq "$type: no output, exit 0" "|0" "$out|$code"
done
last="$(tail -n 1 "$log" | node -e '
  const o = JSON.parse(require("fs").readFileSync(0, "utf8"));
  console.log([typeof o.time, o.session_id, o.dir, o.branch, o.notification_type, o.message].join("|"));
')"
tl_eq 'the fields of a line' "string|s1|$repo|7-some-work|agent_needs_input|Claude needs your permission to use Edit" "$last"
tl_eq 'three of the four are shown, idle_prompt is not' 3 "$(shown)"
tl_has 'the system notification carries the branch and the message' '7-some-work|Claude needs your permission to use Edit|' "$(cat "$TL_TMP/osascript.log")"
payload auth_success "$repo" | bash "$HOOK"
tl_eq 'another type appends nothing' 4 "$(lines)"
payload permission_prompt "$TL_TMP/wt" s2 | bash "$HOOK"
tl_eq 'a worktree appends to the same file' 5 "$(lines)"
tl_has 'with its branch' '"branch":"8-other"' "$(tail -n 1 "$log")"
tl_eq 'no log under the git directory of the worktree' no "$([ -e "$(git -C "$TL_TMP/wt" rev-parse --path-format=absolute --git-dir)/trellis" ] && echo yes || echo no)"
ro="$(tl_repo)"
mkdir -p "$ro/.git/trellis" && chmod 500 "$ro/.git/trellis"
payload permission_prompt "$ro" | bash "$HOOK"; code=$?
chmod 700 "$ro/.git/trellis"
tl_eq 'an unwritable directory exits 0' 0 "$code"

echo 'waiting: command.notify'
calls="$TL_TMP/notify.calls"
printf '#!/bin/sh\nif [ -f "%s/notify.hang" ]; then sleep 20 & echo $! > "%s/notify.child"; wait; fi\nprintf "%%s|" "$TRELLIS_WAIT_TYPE" "$TRELLIS_WAIT_MESSAGE" "$TRELLIS_WAIT_BRANCH" "$TRELLIS_WAIT_ISSUE" "$TRELLIS_WAIT_SESSION" "$TRELLIS_WAIT_DIR" "$TRELLIS_WAIT_REMOTE" "$(pwd -P)" >> "%s"\necho >> "%s"\necho noise\n[ -f "%s/notify.fail" ] && exit 1\nexit 0\n' \
  "$TL_TMP" "$TL_TMP" "$calls" "$calls" "$TL_TMP" > "$TL_TMP/notify.sh"
git config -f "$repo/trellis.config" command.notify ping
git config -f "$repo/trellis.config" command.ping.run "sh $TL_TMP/notify.sh"
calls_n() { count "$calls"; }

shown_before="$(shown)"
k=0
for type in permission_prompt elicitation_dialog agent_needs_input; do
  payload "$type" "$repo" n1 'Claude needs your input' | bash "$HOOK"
  k=$((k + 1))
  tl_eq "$type: the command runs once" "$k" "$(calls_n)"
done
tl_eq 'the seven variables, from the top level' "agent_needs_input|Claude needs your input|7-some-work|7|n1|$repo|false|$repo|" "$(tail -n 1 "$calls")"
tl_eq 'and each is shown' "$((shown_before + 3))" "$(shown)"
before="$(lines)"
payload idle_prompt "$repo" n1 | bash "$HOOK"
tl_eq 'idle_prompt: a line' "$((before + 1))" "$(lines)"
tl_eq 'idle_prompt: no command' 3 "$(calls_n)"

payload permission_prompt "$repo" n1 'Claude needs your input' | bash "$HOOK"
tl_eq 'the same wait again, within 30 seconds: no command' 3 "$(calls_n)"
tl_eq '  and no second line' "$((before + 1))" "$(lines)"
for m in "$repo"/.git/trellis/notified/n1-*; do printf '%s' "$(($(date +%s) - 31))" > "$m"; done
payload permission_prompt "$repo" n1 'Claude needs your input' | bash "$HOOK"
tl_eq 'the same wait after 30 seconds: announced again' 4 "$(calls_n)"
tl_eq '  with its line' "$((before + 2))" "$(lines)"

before="$(lines)"
( payload permission_prompt "$repo" n2 | bash "$HOOK" ) & ( payload permission_prompt "$repo" n2 | bash "$HOOK" ) & wait
tl_eq 'two runs together: one command' 5 "$(calls_n)"
tl_eq '  and one line' "$((before + 1))" "$(lines)"
# What a red case leaves, so a run on another system can be read without a rerun.
[ "$(calls_n)" = 5 ] || { ls -la --full-time "$repo/.git/trellis/notified" 2>/dev/null || ls -laT "$repo/.git/trellis/notified"; tail -n 3 "$calls"; date; }

cp "$repo/trellis.config" "$TL_TMP/wt/trellis.config"
payload permission_prompt "$TL_TMP/wt" n3 | bash "$HOOK"
tl_has 'a worktree: its branch and its issue' "|8-other|8|n3|$TL_TMP/wt|false|$TL_TMP/wt|" "$(tail -n 1 "$calls")"
git -C "$TL_TMP/wt" checkout -q -b 9x-not
payload permission_prompt "$TL_TMP/wt" n4 | bash "$HOOK"
tl_has 'a branch that is not an issue branch: no issue' "|9x-not||n4|$TL_TMP/wt|false|$TL_TMP/wt|" "$(tail -n 1 "$calls")"

before="$(lines)"
out="$(CLAUDE_CODE_REMOTE=true bash "$HOOK" < <(payload elicitation_dialog "$repo" c1))"; code=$?
tl_eq 'a cloud session: no output, exit 0' '|0' "$out|$code"
tl_eq 'a cloud session: its line' "$((before + 1))" "$(lines)"
tl_has 'a cloud session: TRELLIS_WAIT_REMOTE=true' '|c1|' "$(tail -n 1 "$calls")"
tl_has '  true' "|$repo|true|" "$(tail -n 1 "$calls")"

touch "$TL_TMP/notify.fail"
out="$(payload permission_prompt "$repo" f1 | bash "$HOOK")"; code=$?
rm "$TL_TMP/notify.fail"
tl_eq 'a command that fails: no output, exit 0' '|0' "$out|$code"
tl_eq '  it ran' 9 "$(calls_n)"

touch "$TL_TMP/notify.hang"
start="$(date +%s)"
out="$(payload permission_prompt "$repo" h1 | bash "$HOOK")"; code=$?
took=$(($(date +%s) - start))
rm "$TL_TMP/notify.hang"
tl_eq 'a command that hangs: no output, exit 0' '|0' "$out|$code"
tl_eq '  the hook returns within the limit' yes "$([ "$took" -ge 9 ] && [ "$took" -le 13 ] && echo yes || echo "no ($took s)")"
tl_eq '  and what the command started is stopped' gone "$(kill -0 "$(cat "$TL_TMP/notify.child")" 2>/dev/null && echo alive || echo gone)"

no_session() { # <cwd>
  printf '{"hook_event_name":"Notification","cwd":"%s","notification_type":"permission_prompt","message":"Claude needs your permission to use Edit"}' "$1"
}
no_session "$repo" | bash "$HOOK"
no_session "$TL_TMP/wt" | bash "$HOOK"
tl_eq 'without session_id, two directories are two waits' 11 "$(calls_n)"
old="$repo/.git/trellis/notified/old-0123456789ab"
mkdir "$old" && touch -t 202001010000 "$old"
payload permission_prompt "$repo" p1 | bash "$HOOK"
tl_eq 'a marker older than 10 minutes is removed' no "$([ -e "$old" ] && echo yes || echo no)"
tl_eq 'and the lock with it' no "$([ -e "$repo/.git/trellis/notified/.lock" ] && echo yes || echo no)"
mkdir "$repo/.git/trellis/notified/.lock" && printf '%s' "$(($(date +%s) - 10))" > "$repo/.git/trellis/notified/.lock/at"
payload permission_prompt "$repo" p2 | bash "$HOOK"
tl_eq 'a lock older than 5 seconds is of a dead run: the wait is announced' 13 "$(calls_n)"
i=0
while [ "$i" -lt 1001 ]; do echo '{}'; i=$((i + 1)); done >> "$log"
payload permission_prompt "$repo" p3 | bash "$HOOK"
tl_eq 'a log past 1000 lines keeps its last 500' 500 "$(lines)"
tl_eq '  the last one the new wait' '"session_id":"p3"' "$(tail -n 1 "$log" | grep -o '"session_id":"p3"')"

git config -f "$repo/trellis.config" command.notify ''
git config -f "$repo/trellis.config" --remove-section command.ping
git config -f "$repo/trellis.config" command.notify missing
out="$(payload permission_prompt "$repo" m1 | bash "$HOOK")"; code=$?
tl_eq 'a command name without run: no output, exit 0' '|0' "$out|$code"
tl_eq '  nothing runs' 14 "$(calls_n)"

tl_done
