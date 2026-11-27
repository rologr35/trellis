#!/usr/bin/env bash
#
# waiting: the Notification hook. A session that waits for a person says so outside its own screen, the
# same in a local and in a cloud session. It never refuses anything: a wait is announced, not stopped.
#
#   - For every one of permission_prompt, elicitation_dialog, agent_needs_input and idle_prompt it appends
#     one JSON line to trellis/waiting.log under the common git directory, which every worktree of the
#     clone shares: time, session_id, dir, branch, notification_type and message. `trellis waiting` reads it.
#   - For the three that are not idle_prompt (a person has to give something) it also announces the wait:
#     a notification of the system where osascript exists, and the command of command.notify when the
#     project declares one. idle_prompt (a turn ended and asks nothing) is the line only.
#
# The command runs from the top level of the checkout, with nothing interpolated, its stdin empty, and the
# wait in its environment: TRELLIS_WAIT_TYPE, TRELLIS_WAIT_MESSAGE, TRELLIS_WAIT_BRANCH, TRELLIS_WAIT_ISSUE
# (the number of an issue branch by git.issueBranch, empty otherwise), TRELLIS_WAIT_SESSION (the
# session_id), TRELLIS_WAIT_DIR and TRELLIS_WAIT_REMOTE (true in a cloud session, false otherwise). The
# hook waits for it at most 10 seconds and ignores its exit and its output.
#
# Once per wait: the plugin and the copy together run every hook twice, so the first run creates
# trellis/notified/<session_id>-<digest of type and message> under the common git directory with mkdir,
# which only one of two racing runs wins, and only the winner announces. The same wait repeated in the
# same session is announced again once its marker is older than 10 minutes.
#
# The directory is the cwd of the payload, else CLAUDE_PROJECT_DIR. It never fails the session: it prints
# nothing and every path exits 0. Works with bash 3.2.

set -uo pipefail

TRELLIS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v node >/dev/null 2>&1 || exit 0
exec >/dev/null 2>&1

PAYLOAD="$(cat)"
field() {
  node -e 'try { const v = JSON.parse(require("fs").readFileSync(0, "utf8"))[process.argv[1]]; process.stdout.write(typeof v === "string" ? v : ""); } catch { }' "$1" <<< "$PAYLOAD"
}

type="$(field notification_type)"
case "$type" in
  permission_prompt | elicitation_dialog | agent_needs_input) announce=true ;;
  idle_prompt) announce=false ;;
  *) exit 0 ;;
esac
session="$(field session_id)"
message="$(field message)"
dir="$(field cwd)"
[ -n "$dir" ] || dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$dir" || exit 0
common="$(git rev-parse --path-format=absolute --git-common-dir)" || exit 0
branch="$(git symbolic-ref --short -q HEAD)"
here="$(pwd -P)"

mkdir -p "$common/trellis" || exit 0
node -e '
  const [session, dir, branch, type, message] = process.argv.slice(1);
  const line = {time: new Date().toISOString(), session_id: session, dir, branch, notification_type: type, message};
  process.stdout.write(JSON.stringify(line) + "\n");
' "$session" "$here" "$branch" "$type" "$message" >> "$common/trellis/waiting.log"
[ "$announce" = true ] || exit 0

# Without a session_id the directory stands for it, so one session does not silence another.
digest="$(node -e 'process.stdout.write(require("crypto").createHash("sha1").update(process.argv.slice(1).join("\n")).digest("hex").slice(0, 12))' "$type" "$message" "${session:-$here}")" || exit 0
notified="$common/trellis/notified"
marker="$notified/${session:-none}-$digest"
mkdir -p "$notified" || exit 0
# The lock makes the expiry of the old markers and the creation of this one a single step, so of the two
# runs of one wait only one creates its marker. A run waits for the lock at most 2 seconds; a lock older
# than a minute is of a run that died.
lock="$notified/.lock"
[ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ] && rmdir "$lock"
tries=0
until mkdir "$lock" 2>/dev/null; do
  tries=$((tries + 1))
  [ "$tries" -lt 20 ] || exit 0
  sleep 0.1
done
find "$notified" -mindepth 1 -maxdepth 1 -name '*-*' -mmin +10 -exec rmdir {} + 2>/dev/null
mkdir "$marker"; won=$?
rmdir "$lock"
[ "$won" -eq 0 ] || exit 0

if command -v osascript >/dev/null; then
  osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' \
    "${branch:-$(basename "$here")}" "${message:-$type}"
fi

# shellcheck source=../lib/config.sh
. "$TRELLIS_ROOT/lib/config.sh"
tc_check || exit 0
name="$(tc_get command.notify)"
[ -n "$name" ] || exit 0
run="$(tc_get "command.$name.run")"
[ -n "$run" ] || exit 0
issue=''
issue_regex="$(tc_get git.issueBranch)"
[ -n "$branch" ] && [[ "$branch" =~ $issue_regex ]] && issue="$(tc_branch_issue "$branch")"
remote=false
[ -n "${CLAUDE_CODE_REMOTE:-}" ] && remote=true
top="$(git rev-parse --show-toplevel)" || top="$here"

# Job control puts the command in a process group of its own, so the limit reaches what it starts too.
set -m
(cd "$top" && TRELLIS_WAIT_TYPE="$type" TRELLIS_WAIT_MESSAGE="$message" TRELLIS_WAIT_BRANCH="$branch" \
  TRELLIS_WAIT_ISSUE="$issue" TRELLIS_WAIT_SESSION="$session" TRELLIS_WAIT_DIR="$here" \
  TRELLIS_WAIT_REMOTE="$remote" exec bash -c "$run" </dev/null) &
pid=$!
set +m
ticks=0
while kill -0 "$pid" 2>/dev/null && [ "$ticks" -lt 100 ]; do
  sleep 0.1
  ticks=$((ticks + 1))
done
kill -- "-$pid" 2>/dev/null
exit 0
