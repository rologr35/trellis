#!/usr/bin/env bash
#
# setup: point git at the project's hooks, core.hooksPath = git.hooksPath (.githooks by
# default), when it is unset and the folder exists; and, at the start of a session, put the
# .trellis/bin of the project's copy (the bin of the repository of trellis) on its PATH, through
# CLAUDE_ENV_FILE. Idempotent. Run by `init` and by the SessionStart hook, so every
# clone where Claude runs, a cloud one included, gets the git hooks.
#
#   trellis setup [--quiet]
#   trellis setup --newer     only prints the notice of a newer version, when there is one
#
# A project with a copy hears of a newer version of trellis. The tags of trellis.upstream are asked in the
# background, once a day, and nothing waits for the network: the newest one is left, whole or not at all,
# in trellis-version of the common git directory, and the session says, once a day and with --quiet too,
# what that file already had when it is newer than .trellis/VERSION. So the notice is one session late.
#
# Does nothing outside a project that has trellis.config, so a plugin installed for the user never
# touches other repositories. A core.hooksPath set to something else is left alone and reported.

set -uo pipefail

TRELLIS_ROOT="${TRELLIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

quiet=false
[ "${1:-}" = '--quiet' ] && quiet=true
newer_only=false
[ "${1:-}" = '--newer' ] && newer_only=true && quiet=true
say() { [ "$quiet" = true ] || printf 'setup: %s\n' "$1"; }

dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || { say 'not a git repository, nothing to do'; exit 0; }
[ -f "$top/trellis.config" ] || { say 'no trellis.config, nothing to do'; exit 0; }

# newer: prints the notice of the version in trellis-version when it is newer than the one of the copy.
newer() {
  local have='' newest='' a b i
  local number='^v?([0-9]+)\.([0-9]+)\.([0-9]+)$'
  read -r have _ 2>/dev/null < "$top/.trellis/VERSION"
  read -r newest 2>/dev/null < "$common/trellis-version"
  [[ "$have" =~ $number ]] || return 1
  a=("${BASH_REMATCH[@]}")
  [[ "$newest" =~ $number ]] || return 1
  b=("${BASH_REMATCH[@]}")
  for i in 1 2 3; do
    [ "$((10#${b[i]}))" -le "$((10#${a[i]}))" ] || {
      printf 'trellis %s is out and this project has %s: trellis update %s, in a pull request of its own\n' \
        "${newest#v}" "${have#v}" "$newest"
      return 0
    }
    [ "$((10#${b[i]}))" -eq "$((10#${a[i]}))" ] || return 1
  done
  return 1
}

# The tags are asked by a process of its own, with nothing of the session open: it is not waited for.
ask() {
  (
    trap '' HUP
    cd "$top" && node --input-type=module -e '
      import {renameSync, writeFileSync} from "node:fs";
      import {pathToFileURL} from "node:url";
      const [root, upstream, file] = process.argv.slice(1);
      const {newestTag} = await import(pathToFileURL(`${root}/lib/copy.mjs`));
      const tag = newestTag(upstream);
      if (tag !== null) {
        writeFileSync(`${file}.${process.pid}`, `${tag}\n`);
        renameSync(`${file}.${process.pid}`, file);
      }
    ' "$TRELLIS_ROOT" "$(tc_get trellis.upstream)" "$common/trellis-version"
  ) </dev/null >/dev/null 2>&1 &
}

# today <stamp>: whether it was already done today; when not, it is from now on.
today() {
  local now last=''
  now="$(date +%Y-%m-%d)"
  read -r last 2>/dev/null < "$common/$1"
  [ "$last" != "$now" ] || return 0
  printf '%s\n' "$now" 2>/dev/null > "$common/$1"
  return 1
}

# shellcheck source=../lib/config.sh
. "$TRELLIS_ROOT/lib/config.sh"
common="$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
if [ "$newer_only" = true ]; then
  [ ! -f "$top/.trellis/VERSION" ] || newer
  exit 0
fi
if [ -f "$top/.trellis/VERSION" ] && [ -d "$common" ]; then
  notice="$(newer)" && { today trellis-version-said || printf '%s\n' "$notice"; }
  today trellis-version-asked || ask
fi

# The PATH of the session's Bash tool; the file is added to, because other hooks write it too.
# shellcheck source=../lib/find-trellis.sh
. "$TRELLIS_ROOT/lib/find-trellis.sh"
bin="$(project_trellis "$top")"
if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "$bin" ]; then
  bin="$(dirname "$bin")"
  line="export PATH=$(printf '%q' "$bin"):\"\$PATH\""
  if ! grep -qxF -- "$line" "$CLAUDE_ENV_FILE" 2>/dev/null; then
    printf '%s\n' "$line" >> "$CLAUDE_ENV_FILE"
    say "${bin#"$top"/} added to the PATH of the session"
  fi
fi

hooks="$(cd "$top" && tc_get git.hooksPath)"
[ -d "$top/$hooks" ] || { say "no $hooks/, nothing to do"; exit 0; }

current="$(git -C "$top" config --get core.hooksPath 2>/dev/null || true)"
case "$current" in
  "$hooks") say "core.hooksPath already $hooks" ;;
  '')
    git -C "$top" config core.hooksPath "$hooks"
    say "core.hooksPath set to $hooks"
    ;;
  *) say "core.hooksPath is $current, left alone (trellis doctor reports it)" ;;
esac
exit 0
