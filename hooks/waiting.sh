#!/usr/bin/env bash
#
# waiting: the Notification hook. A session that waits for a person says so outside its own screen.
#
#   - Local (no CLAUDE_CODE_REMOTE): for permission_prompt, idle_prompt, elicitation_dialog and
#     agent_needs_input it appends one JSON line to trellis/waiting.log under the common git directory, which
#     every worktree of the clone shares: time, session_id, dir, branch, notification_type and message.
#     `trellis waiting` reads it. Where osascript exists it also shows a notification of the system with the
#     branch and the message.
#   - Cloud (CLAUDE_CODE_REMOTE set): for permission_prompt, elicitation_dialog and agent_needs_input (not
#     idle_prompt, which is also the end of a run), on an issue branch (git.issueBranch) with
#     tracker.kind = github, it stops the issue: `trellis issue stop <n> --body-file <file>` with Done (the
#     word for none of the locale), Missing (the run waits for a person, with the type) and Needs (the
#     message). Once per session: the first run creates trellis/stopped/<session_id> under the common git
#     directory with mkdir, which only one of two racing runs wins (the plugin and the copy together run
#     every hook twice). A stop the command refuses is left.
#
# The trellis that stops is the plugin's when this hook runs from CLAUDE_PLUGIN_ROOT, else the one the
# project of CLAUDE_PROJECT_DIR brings (lib/find-trellis.sh). The directory is the cwd of the payload, else
# CLAUDE_PROJECT_DIR. It never fails the session: it prints nothing and every path exits 0.
# Works with bash 3.2.

set -uo pipefail

TRELLIS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v node >/dev/null 2>&1 || exit 0
exec >/dev/null 2>&1

PAYLOAD="$(cat)"
field() {
  node -e 'try { const v = JSON.parse(require("fs").readFileSync(0, "utf8"))[process.argv[1]]; process.stdout.write(typeof v === "string" ? v : ""); } catch { }' "$1" <<< "$PAYLOAD"
}

type="$(field notification_type)"
session="$(field session_id)"
message="$(field message)"
dir="$(field cwd)"
[ -n "$dir" ] || dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$dir" || exit 0
common="$(git rev-parse --path-format=absolute --git-common-dir)" || exit 0
branch="$(git symbolic-ref --short -q HEAD)"

if [ -z "${CLAUDE_CODE_REMOTE:-}" ]; then
  case "$type" in permission_prompt | idle_prompt | elicitation_dialog | agent_needs_input) ;; *) exit 0 ;; esac
  mkdir -p "$common/trellis" || exit 0
  node -e '
    const [session, dir, branch, type, message] = process.argv.slice(1);
    const line = {time: new Date().toISOString(), session_id: session, dir, branch, notification_type: type, message};
    process.stdout.write(JSON.stringify(line) + "\n");
  ' "$session" "$(pwd -P)" "$branch" "$type" "$message" >> "$common/trellis/waiting.log" || exit 0
  if command -v osascript >/dev/null; then
    osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' \
      "${branch:-$(basename "$(pwd -P)")}" "${message:-$type}"
  fi
  exit 0
fi

case "$type" in permission_prompt | elicitation_dialog | agent_needs_input) ;; *) exit 0 ;; esac
[ -n "$session" ] && [ -n "$branch" ] || exit 0
# shellcheck source=../lib/config.sh
. "$TRELLIS_ROOT/lib/config.sh"
[ "$(tc_get tracker.kind)" = github ] || exit 0
printf '%s\n' "$branch" | grep -Eq -- "$(tc_get git.issueBranch)" || exit 0
n="${branch%%[!0-9]*}"
[ -n "$n" ] || exit 0

if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ "$TRELLIS_ROOT" -ef "$CLAUDE_PLUGIN_ROOT" ]; then
  trellis="$TRELLIS_ROOT/bin/trellis"
else
  # shellcheck source=../lib/find-trellis.sh
  . "$TRELLIS_ROOT/lib/find-trellis.sh"
  trellis="$(project_trellis "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}")"
fi
[ -n "$trellis" ] && [ -f "$trellis" ] || exit 0

mkdir -p "$common/trellis/stopped" || exit 0
mkdir "$common/trellis/stopped/$session" || exit 0

body="$(mktemp)" || exit 0
node --input-type=module -e '
  const [root, locale, type, message] = process.argv.slice(1);
  const {PR_SECTIONS, STOP, UNATTENDED} = await import(`${root}/lib/locale.mjs`);
  const l = locale === "es" ? "es" : "en";
  const [done, missing, needs] = STOP[l].sections;
  const asks = message.trim() || type;
  process.stdout.write(`**${done}**: ${PR_SECTIONS[l].noneWord}\n\n**${missing}**: ${UNATTENDED[l].waiting(type)}\n\n**${needs}**: ${asks}\n`);
' "$TRELLIS_ROOT" "$(tc_get project.locale)" "$type" "$message" > "$body" \
  && bash "$trellis" issue stop "$n" --body-file "$body"
rm -f "$body"
exit 0
