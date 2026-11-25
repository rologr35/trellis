#!/usr/bin/env bash
#
# The checks of the project, which run after the ones of trellis: `trellis pr-check` and `trellis issue
# check` source it, after lib/config.sh.
#
#   project_check <key> <who> <file>
#
# <key> is pullRequestCheck, issueCheck or commitCheck: the [command] its command.<key> names runs from
# the top level, with the text in the file of TRELLIS_FILE and the branch in TRELLIS_BRANCH, the one of
# the pull request in CI. Nothing is interpolated. Under CI (the variable CI, other than false and 0) its
# form is the `ci` of the command, when it has one. Its output goes to stdout. Returns 0 when it passes
# or none is named, 1 when it fails, said on stderr after <who>.

project_check() {
  local name run='' file="$3" top branch
  name="$(tc_get "command.$1")"
  [ -n "$name" ] || return 0
  case "${CI:-}" in '' | false | 0) ;; *) run="$(tc_get "command.$name.ci")" ;; esac
  [ -n "$run" ] || run="$(tc_get "command.$name.run")"
  if [ -z "$run" ]; then
    printf '%s: [command "%s"] has no run\n' "$2" "$name" >&2
    return 1
  fi
  case "$file" in /*) ;; *) file="$PWD/$file" ;; esac
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || top="$PWD"
  branch="${GITHUB_HEAD_REF:-$(git branch --show-current 2>/dev/null)}"
  (cd "$top" && TRELLIS_FILE="$file" TRELLIS_BRANCH="$branch" bash -c "$run" </dev/null 2>&1) && return 0
  printf '%s: the check of the project (%s) failed\n' "$2" "$name" >&2
  return 1
}
