#!/usr/bin/env bash
#
# worktree-add: the worktree an issue is worked in, born from the integration branch as origin has
# it right now.
#
#   trellis worktree add <n> <slug>    creates .claude/worktrees/<n>-<slug> on branch <n>-<slug>
#
# Fetch, collision checks, creation, install and the printed path in one command, because the fetch
# is the step that gets skipped when they are separate, and a chained `git fetch && git worktree
# add` never matches the permission rule that allows a single command. The worktree lives under the
# main checkout's `.claude/worktrees/`, the folder where `EnterWorktree` works without a prompt; the
# folder is gitignored, so the main checkout's tooling does not see the nested tree.
#
# On the way: the main checkout's integration branch is fast-forwarded when that is all it takes
# (lib/ff-integration.sh), and the worktrees of merged branches are removed by worktree-prune.sh,
# launched from the caller's directory so that it keeps the worktree the caller stands in; its report
# goes to stderr and its failure does not stop the creation.
#
# Refuses, before creating anything: <n> that is not a number, <n>-<slug> that does not match
# git.issueBranch, a branch that exists locally or on origin, a directory that exists. A failed
# install ([command] install) leaves the worktree in place and says so. Works from any worktree:
# the new one always goes under the main checkout. The last line of a successful run is the
# absolute path of the worktree, what EnterWorktree takes.

set -uo pipefail

TRELLIS_ROOT="${TRELLIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/config.sh
. "$TRELLIS_ROOT/lib/config.sh"
# shellcheck source=../lib/ff-integration.sh
. "$TRELLIS_ROOT/lib/ff-integration.sh"

refuse() {
  printf 'worktree-add: %s\n' "$1" >&2
  exit 1
}

[ "${1:-}" = '--' ] && shift
[ $# -eq 2 ] || refuse 'usage: trellis worktree add <issue-number> <slug>'
issue="$1"
slug="$2"
[[ "$issue" =~ ^[0-9]+$ ]] || refuse "<n> must be the issue number, got '$issue'"
branch="$issue-$slug"

# Read before moving: the directory the cleanup must not remove.
caller_dir="$(pwd -P)"

# The main checkout: from inside a worktree, --show-toplevel answers the worktree itself.
main_worktree="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print substr($0, 10); exit}')"
[ -n "$main_worktree" ] || refuse 'not inside a git repository'
cd "$main_worktree" || exit 1

integration="$(tc_get git.integrationBranch)"
branch_regex="$(tc_get git.issueBranch)"
install_name="$(tc_get command.install)"
[[ "$branch" =~ $branch_regex ]] || refuse "'$branch' does not match git.issueBranch ($branch_regex)"

path="$main_worktree/.claude/worktrees/$branch"

# GIT_TERMINAL_PROMPT=0 turns a missing credential into a failure instead of a prompt nobody
# answers; the low-speed bound does the same for a host that stalls.
if ! GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 \
     fetch --prune --quiet origin; then
  refuse "could not fetch origin (see above), so origin/$integration may be stale; nothing was created"
fi
git rev-parse --verify --quiet "refs/remotes/origin/$integration" >/dev/null \
  || refuse "origin/$integration does not exist after the fetch; nothing was created"
ff_integration "$integration" 'worktree-add: '

if ! (cd "$caller_dir" && bash "$TRELLIS_ROOT/scripts/worktree-prune.sh") >&2; then
  printf 'worktree-add: the cleanup of merged worktrees failed (see above); creating the worktree anyway\n' >&2
fi

if git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
  refuse "branch $branch already exists locally; nothing was created"
fi
if git rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null; then
  refuse "branch $branch already exists on origin; nothing was created"
fi
[ -e "$path" ] && refuse "$path already exists; nothing was created"

git worktree add -q "$path" -b "$branch" "origin/$integration" || refuse 'git worktree add failed (see above)'
# The branch starts without an upstream: a push names its refspec.
git branch -q --unset-upstream "$branch" 2>/dev/null || true
printf 'worktree-add: %s on %s, from origin/%s at %s\n' \
  "$path" "$branch" "$integration" "$(git -C "$path" log -1 --format='%h %s')" >&2

if [ -n "$install_name" ]; then
  install_run="$(tc_get "command.$install_name.run")"
  [ -n "$install_run" ] || refuse "worktree created at $path, but [command \"$install_name\"] has no run"
  install_log="$(mktemp)"
  if ! (cd "$path" && bash -c "$install_run") >"$install_log" 2>&1; then
    cat "$install_log" >&2
    rm -f "$install_log"
    refuse "worktree created at $path on $branch, but the install failed (see above): run it inside the worktree"
  fi
  rm -f "$install_log"
fi

printf '%s\n' "$path"
