#!/usr/bin/env bash
# Exercises hooks/unattended.sh with payloads as Claude Code sends them, in a cloud session and in a local one.
. "$(dirname "$0")/../lib/testlib.sh"

HOOK="$TRELLIS_ROOT/hooks/unattended.sh"
repo="$(tl_repo)"
cd "$repo" || exit 1

ask="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"AskUserQuestion\",\"tool_input\":{},\"cwd\":\"$repo\"}"
bash_call="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"},\"cwd\":\"$repo\"}"
permission="{\"hook_event_name\":\"PermissionRequest\",\"tool_name\":\"Edit\",\"tool_input\":{},\"cwd\":\"$repo\"}"

decision() {
  printf '%s' "$1" | node -e '
    const o = JSON.parse(require("fs").readFileSync(0, "utf8")).hookSpecificOutput;
    const d = o.decision ?? {};
    console.log([o.hookEventName, o.permissionDecision ?? d.behavior, "interrupt" in d, o.permissionDecisionReason ?? d.message].join("|"));
  ' 2>/dev/null
}

echo 'unattended: a local session'
out="$(printf '%s' "$ask" | bash "$HOOK")"; code=$?
tl_eq 'a question: no output' '' "$out"
tl_eq 'a question: exit 0' 0 "$code"
out="$(printf '%s' "$permission" | bash "$HOOK")"; code=$?
tl_eq 'a permission: no output' '' "$out"
tl_eq 'a permission: exit 0' 0 "$code"

echo 'unattended: a cloud session, en'
export CLAUDE_CODE_REMOTE=true
d="$(decision "$(printf '%s' "$ask" | bash "$HOOK")")"
tl_has 'a question is denied' 'PreToolUse|deny|false|' "$d"
tl_has 'its reason names the stop' 'trellis issue stop <n> --body-file <file>' "$d"
tl_has 'its reason names the sections' '**Done**' "$d"
reason_ask="${d##*|}"
d="$(decision "$(printf '%s' "$permission" | bash "$HOOK")")"
tl_has 'a permission is denied without interrupt' 'PermissionRequest|deny|false|' "$d"
tl_eq 'a permission: the same message' "$reason_ask" "${d##*|}"
out="$(printf '%s' "$bash_call" | bash "$HOOK")"
tl_eq 'another tool: no output' '' "$out"
out="$(printf 'not json' | bash "$HOOK")"; code=$?
tl_eq 'a payload that does not parse: no output' '' "$out"
tl_eq 'a payload that does not parse: exit 0' 0 "$code"

echo 'unattended: a cloud session, es'
git config -f trellis.config project.locale es
d="$(decision "$(printf '%s' "$ask" | bash "$HOOK")")"
tl_has 'a question is denied' 'PreToolUse|deny|' "$d"
tl_has 'its reason is in es' '**Hecho**' "$d"
tl_has 'its reason names the stop' 'trellis issue stop <n> --body-file <file>' "$d"
d="$(decision "$(printf '%s' "$permission" | bash "$HOOK")")"
tl_has 'a permission is denied in es' 'PermissionRequest|deny|false|Ninguna persona' "$d"
d="$(cd / && decision "$(printf '%s' "$ask" | CLAUDE_PROJECT_DIR="$repo" bash "$HOOK")")"
tl_has 'the project of CLAUDE_PROJECT_DIR gives the locale' '**Falta**' "$d"

tl_done
