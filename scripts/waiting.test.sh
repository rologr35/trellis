#!/usr/bin/env bash
# Exercises `trellis waiting` on the log of a clone that hooks/waiting.sh writes.
. "$(dirname "$0")/../lib/testlib.sh"

repo="$(tl_repo)"
cd "$repo" || exit 1
log="$repo/.git/trellis/waiting.log"
line() { # <time> <session> <branch> <type> <message>
  printf '{"time":"%s","session_id":"%s","dir":"/w/%s","branch":"%s","notification_type":"%s","message":"%s"}\n' "$1" "$2" "$3" "$3" "$4" "$5"
}
iso() { node -e 'console.log(new Date(Date.now() - Number(process.argv[1]) * 1000).toISOString())' "$1"; }

echo 'waiting: the sessions of the clone'
out="$(bash "$TRELLIS" waiting)"; code=$?
tl_eq 'no log: no session, exit 0' '|0' "$out|$code"

mkdir -p "$repo/.git/trellis"
line "$(iso 600)" a 7-one idle_prompt 'Claude is waiting for your input' >> "$log"
line "$(iso 300)" a 7-one permission_prompt 'Claude needs your permission to use Edit' >> "$log"
out="$(bash "$TRELLIS" waiting)"
tl_eq 'one session: one line' 1 "$(printf '%s\n' "$out" | grep -c .)"
tl_has 'its last line' '7-one  permission_prompt  Claude needs your permission to use Edit  /w/7-one' "$out"

line "$(iso 90000)" b 8-old elicitation_dialog 'old' >> "$log"
line "$(iso 60)" c 9-new agent_needs_input 'new' >> "$log"
out="$(bash "$TRELLIS" waiting)"
tl_eq 'two sessions, the older past 24 hours: newest first' '9-new|7-one' "$(printf '%s\n' "$out" | awk '{print $2}' | paste -sd'|' -)"
tl_lacks 'the session past 24 hours is not listed' '8-old' "$out"

echo 'waiting: --follow'
bash "$TRELLIS" waiting --follow > "$TL_TMP/follow" 2>&1 &
pid=$!
sleep 1
line "$(iso 0)" d 10-live permission_prompt 'Claude needs your permission to use Write' >> "$log"
i=0
while [ "$i" -lt 50 ] && ! grep -q 10-live "$TL_TMP/follow"; do sleep 0.1; i=$((i + 1)); done
pkill -P "$pid" 2>/dev/null
{ kill "$pid"; wait "$pid"; } 2>/dev/null
out="$(cat "$TL_TMP/follow")"
tl_has 'a line appended after it starts is printed' '10-live  permission_prompt  Claude needs your permission to use Write' "$out"
tl_lacks 'the lines before it are not' '7-one' "$out"

echo 'waiting: the log the hook writes'
other="$(tl_repo)"
git -C "$other" checkout -q -b 11-hooked
printf '{"session_id":"e","cwd":"%s","notification_type":"idle_prompt","message":"Claude is waiting for your input"}' "$other" \
  | bash "$TRELLIS_ROOT/hooks/waiting.sh"
tl_has 'a wait the hook wrote is listed' '11-hooked  idle_prompt  Claude is waiting for your input' "$(cd "$other" && bash "$TRELLIS" waiting)"

out="$(bash "$TRELLIS" waiting --bogus 2>&1)"; code=$?
tl_eq 'a usage error exits 2' 2 "$code"

tl_done
