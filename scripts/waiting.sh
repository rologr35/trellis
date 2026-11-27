#!/usr/bin/env bash
#
# waiting: the last time each session of this clone waited for a person, from the log hooks/waiting.sh
# writes (trellis/waiting.log under the common git directory, which every worktree shares). The log holds
# waits, not answers: a session listed may have been answered since, or closed.
#
#   trellis waiting            the sessions whose last line is less than 24 hours old, one per session,
#                              newest first: time, branch, notification_type, message and directory
#   trellis waiting --follow   each new line of the log as it is written, in the same form, until stopped
#
# A log that does not exist is no session. Exit codes: 0, 1 outside a git repository, 2 for a usage error.
# Works with bash 3.2.

set -uo pipefail

usage() { printf 'usage: trellis waiting [--follow]\n' >&2; exit 2; }

follow=false
case "$#:${1:-}" in
  0:) ;;
  1:--follow) follow=true ;;
  *) usage ;;
esac

common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  || { printf 'waiting: not in a git repository\n' >&2; exit 1; }
log="$common/trellis/waiting.log"

# Reads JSON lines on stdin; prints one line each: with `last`, the last of each session of the last 24 hours.
format() {
  node -e '
    const last = process.argv[1] === "last";
    const rows = require("fs").readFileSync(0, "utf8").split("\n").flatMap(l => { try { return [JSON.parse(l)]; } catch { return []; } });
    const show = r => [r.time, r.branch || "-", r.notification_type, r.message, r.dir].join("  ");
    if (!last) { rows.forEach(r => console.log(show(r))); process.exit(0); }
    const since = Date.now() - 24 * 3600 * 1000;
    const bySession = new Map();
    for (const r of rows) bySession.set(r.session_id, r);
    [...bySession.values()].filter(r => Date.parse(r.time) > since)
      .sort((a, b) => Date.parse(b.time) - Date.parse(a.time)).forEach(r => console.log(show(r)));
  ' "${1:-}"
}

if [ "$follow" = false ]; then
  [ -f "$log" ] || exit 0
  format last < "$log"
  exit 0
fi

mkdir -p "$common/trellis" || exit 1
tail -n 0 -F "$log" 2>/dev/null | while IFS= read -r line; do
  printf '%s\n' "$line" | format
done
