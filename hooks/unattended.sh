#!/usr/bin/env bash
#
# unattended: a hook of a session without a person. In a cloud session (CLAUDE_CODE_REMOTE set) it refuses
#
#   - as a PreToolUse hook of AskUserQuestion, the question: permissionDecision "deny";
#   - as a PermissionRequest hook, the request: decision.behavior "deny", without interrupt, so Claude
#     reads the message and goes on;
#
# with one reason for both, in the locale of the project (lib/locale.mjs, UNATTENDED): no person answers,
# what needs one is a stop (`trellis issue stop <n> --body-file <file>` with Done, Missing and Needs), and
# the run ends, as skills/work/SKILL.md says. Without CLAUDE_CODE_REMOTE it prints nothing: a local session
# asks as it always did.
#
# The project is the one of CLAUDE_PROJECT_DIR, or of the directory of the payload; its trellis.config gives
# the locale, en without one. Protocol: the payload arrives as JSON on stdin; the decision is printed and the
# exit is 0. No output and exit 0 is no opinion: a missing node, or an event of another name.
# Works with bash 3.2.

set -uo pipefail

[ -n "${CLAUDE_CODE_REMOTE:-}" ] || exit 0
TRELLIS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v node >/dev/null 2>&1 || exit 0

PAYLOAD="$(cat)"
field() {
  node -e 'try { const v = JSON.parse(require("fs").readFileSync(0, "utf8"))[process.argv[1]]; process.stdout.write(typeof v === "string" ? v : ""); } catch { }' "$1" <<< "$PAYLOAD" 2>/dev/null
}

event="$(field hook_event_name)"
case "$event" in
  PreToolUse) [ "$(field tool_name)" = AskUserQuestion ] || exit 0 ;;
  PermissionRequest) ;;
  *) exit 0 ;;
esac

dir="${CLAUDE_PROJECT_DIR:-$(field cwd)}"
[ -n "$dir" ] && cd "$dir" 2>/dev/null || true
# shellcheck source=../lib/config.sh
. "$TRELLIS_ROOT/lib/config.sh"
locale="$(tc_get project.locale 2>/dev/null)"

node --input-type=module -e '
  const [root, event, locale] = process.argv.slice(1);
  const {UNATTENDED, localeNamed} = await import(`${root}/lib/locale.mjs`);
  const reason = UNATTENDED[localeNamed(locale)].reason;
  const out = event === "PreToolUse"
    ? {hookEventName: event, permissionDecision: "deny", permissionDecisionReason: reason}
    : {hookEventName: event, decision: {behavior: "deny", message: reason}};
  console.log(JSON.stringify({hookSpecificOutput: out}));
' "$TRELLIS_ROOT" "$event" "$locale"
exit 0
