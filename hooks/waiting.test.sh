#!/usr/bin/env bash
# Exercises hooks/waiting.sh with Notification payloads: the log of a local clone, and the stop of a cloud
# session through a fake trellis of the project.
. "$(dirname "$0")/../lib/testlib.sh"

HOOK="$TRELLIS_ROOT/hooks/waiting.sh"
stubs="$TL_TMP/stubs"
mkdir -p "$stubs"
# osascript records what it would show, so no suite puts a notification on the screen.
printf '#!/bin/sh\nprintf "%%s|" "$@" >> "%s/osascript.log"\necho >> "%s/osascript.log"\n' "$TL_TMP" "$TL_TMP" > "$stubs/osascript"
chmod +x "$stubs/osascript"
export PATH="$stubs:$PATH"

repo="$(tl_repo)"
cd "$repo" || exit 1
git checkout -q -b 7-some-work
git worktree add -q -b 8-other "$TL_TMP/wt" 2>/dev/null
log="$repo/.git/trellis/waiting.log"

payload() { # <type> <cwd> [<session>] [<message>]
  printf '{"hook_event_name":"Notification","session_id":"%s","cwd":"%s","notification_type":"%s","message":"%s"}' \
    "${3:-s1}" "$2" "$1" "${4:-Claude needs your permission to use Edit}"
}
lines() { [ -f "$log" ] && wc -l < "$log" | tr -d ' ' || echo 0; }

echo 'waiting: a local session'
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

echo 'waiting: a cloud session'
export CLAUDE_CODE_REMOTE=true CLAUDE_PROJECT_DIR="$repo"
mkdir -p "$repo/.trellis/bin"
cat > "$repo/.trellis/bin/trellis" <<'FAKE'
#!/bin/sh
dir="$(dirname "$0")"
printf '%s\n' "$*" >> "$dir/calls.log"
while [ $# -gt 0 ]; do [ "$1" = --body-file ] && cat "$2" > "$dir/body"; shift; done
[ -f "$dir/refuse" ] && exit 1
exit 0
FAKE
calls="$repo/.trellis/bin/calls.log"
count() { [ -f "$calls" ] && wc -l < "$calls" | tr -d ' ' || echo 0; }
before="$(lines)"

payload permission_prompt "$repo" c1 'Claude needs your permission to use Write' | bash "$HOOK"
tl_eq 'permission_prompt on an issue branch stops the issue' 'issue stop 7 --body-file' "$(sed 's/ [^ ]*$//' "$calls")"
body="$(cat "$repo/.trellis/bin/body")"
tl_has 'Done: none' '**Done**: none' "$body"
tl_has 'Missing: the run waits, with the type' '**Missing**: the run waits for a person (`permission_prompt`)' "$body"
tl_has 'Needs: the message' '**Needs**: Claude needs your permission to use Write' "$body"
tl_eq 'the cloud appends no line' "$before" "$(lines)"
payload agent_needs_input "$repo" c1 | bash "$HOOK"
tl_eq 'once per session' 1 "$(count)"

( payload elicitation_dialog "$repo" c2 | bash "$HOOK" ) & ( payload elicitation_dialog "$repo" c2 | bash "$HOOK" ) & wait
tl_eq 'two runs together stop once' 2 "$(count)"

payload idle_prompt "$repo" c3 | bash "$HOOK"
tl_eq 'idle_prompt does not stop' 2 "$(count)"
git -C "$repo" checkout -q -b 9x-not
payload permission_prompt "$repo" c4 | bash "$HOOK"
tl_eq 'a branch that is not an issue branch does not stop' 2 "$(count)"
git -C "$repo" checkout -q 7-some-work
git config -f "$repo/trellis.config" tracker.kind none
payload permission_prompt "$repo" c5 | bash "$HOOK"
tl_eq 'tracker.kind = none does not stop' 2 "$(count)"
git config -f "$repo/trellis.config" tracker.kind github
git config -f "$repo/trellis.config" project.locale es
touch "$repo/.trellis/bin/refuse"
out="$(payload agent_needs_input "$repo" c6 | bash "$HOOK")"; code=$?
tl_eq 'a refused stop: no output, exit 0' '|0' "$out|$code"
tl_eq 'a refused stop was asked' 3 "$(count)"
body="$(cat "$repo/.trellis/bin/body")"
tl_has 'es: Hecho' '**Hecho**: nada' "$body"
tl_has 'es: Falta' '**Falta**: la ejecución espera a una persona (`agent_needs_input`)' "$body"
tl_has 'es: Necesita' '**Necesita**: Claude needs your permission' "$body"

tl_done
