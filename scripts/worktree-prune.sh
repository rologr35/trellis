#!/usr/bin/env bash
#
# worktree-prune: remove the worktrees whose branch is gone on origin, when that is safe.
#
#   trellis worktree prune
#
# A worktree outlives its merge: a person merges, often after the session that created it is gone.
# `trellis doctor` reports those worktrees (read-only); this script removes them.
#
# Safe means: the branch is not on origin (the host deletes it on merge), the tree has no
# uncommitted change, and the branch's work is already in origin/<integration>. Anything else is
# kept and the reason is printed, every time. The main checkout is never touched, and neither is a
# worktree that contains the caller's directory: `git worktree remove` deletes the directory of the
# process that runs it.
#
# The script fetches with --prune itself, because "not on origin" is read from a remote-tracking
# ref, and a failed fetch means nothing is examined. A branch pushed with an explicit refspec has no
# upstream, so `[gone]` never fires for it: what says it is finished is that origin does not have
# it. The work is judged by content, not by commit identity, so a squash merge counts too.

set -uo pipefail

TRELLIS_ROOT="${TRELLIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/config.sh
. "$TRELLIS_ROOT/lib/config.sh"
# shellcheck source=../lib/ff-integration.sh
. "$TRELLIS_ROOT/lib/ff-integration.sh"
# shellcheck source=../lib/gh.sh
. "$TRELLIS_ROOT/lib/gh.sh"

caller_dir="$(pwd -P)"
main_worktree="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print substr($0, 10); exit}')"
[ -n "$main_worktree" ] || { printf 'worktree-prune: not inside a git repository\n' >&2; exit 1; }
cd "$main_worktree" || exit 1

integration="$(tc_get git.integrationBranch)"
tracker="$(tc_get tracker.kind)"
# GitHub is asked as the account of the repository's owner, which is not always the active one.
gh_account_owner=''
[ "$tracker" = 'github' ] && gh_account_owner="$(gh_owner "$main_worktree")"

if ! GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 \
     fetch --prune --quiet origin 2>/dev/null; then
  printf '  warn    could not fetch origin, so nothing was examined (git fetch --prune origin says why)\n'
  printf '\n0 removed, 0 kept, 0 failed\n'
  exit 0
fi
ff_integration "$integration" '  '

removed=0
kept=0
failed=0

keep() {
  printf '  kept    %s\n' "$1"
  kept=$((kept + 1))
}

remove() {
  if git worktree remove "$1" && git branch -D "$2" >/dev/null; then
    printf '  removed %s (%s)\n' "$1" "$2"
    removed=$((removed + 1))
  else
    printf '  FAIL    %s (%s): git worktree remove or git branch -D failed\n' "$1" "$2"
    failed=$((failed + 1))
  fi
}

while IFS= read -r path; do
  [ -n "$path" ] || continue
  [ "$path" = "$main_worktree" ] && continue
  branch="$(git -C "$path" branch --show-current 2>/dev/null)"
  if [ -z "$branch" ]; then
    keep "$path: detached, review by hand"
    continue
  fi
  real_path="$(cd "$path" 2>/dev/null && pwd -P)"
  if [ -n "$real_path" ] && [[ "$caller_dir/" == "$real_path/"* ]]; then
    keep "$path ($branch): is the current directory"
    continue
  fi
  if git rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null; then
    keep "$path ($branch): still on origin, not merged yet"
    continue
  fi
  dirty="$(git -C "$path" status --porcelain -uall 2>/dev/null | grep -c '')"
  if [ "$dirty" -ne 0 ]; then
    keep "$path ($branch): $dirty uncommitted change(s)"
    continue
  fi
  base="$(git merge-base "origin/$integration" "refs/heads/$branch" 2>/dev/null)"
  if [ -z "$base" ]; then
    keep "$path ($branch): no common history with origin/$integration"
    continue
  fi
  ahead="$(git rev-list --count "$base..refs/heads/$branch")"
  if [ "$ahead" = '0' ]; then
    # Nothing of its own is two situations. A worktree not committed in yet sits on a commit of the
    # integration branch's first-parent line; a branch merged as a merge commit has its tip as a
    # second parent, off that line. --is-ancestor is true for both, so the line is read instead.
    # The match is done in the shell: `grep -q` closes the pipe early and pipefail reads SIGPIPE as
    # a failure, which would delete the fresh worktree.
    tip="$(git rev-parse "refs/heads/$branch")"
    mainline="$(git rev-list --first-parent "origin/$integration")"
    if [[ $'\n'"$mainline"$'\n' == *$'\n'"$tip"$'\n'* ]]; then
      keep "$path ($branch): no commits yet"
      continue
    fi
    # A tip that is a second parent is not enough: a branch stacked on another one by fast-forward
    # shares that one's tip. The merge has to be this branch's own: a first-parent merge with the
    # tip as second parent and the host's subject naming the branch, or, with a GitHub tracker, a
    # merged pull request from this branch whose head was this tip.
    own_merge=''
    while read -r merge _ parent2 subject; do
      if [ "$parent2" = "$tip" ] && [[ "$subject" == 'Merge pull request #'*' from '*"/$branch" ]]; then
        own_merge="$merge"
        break
      fi
    done <<< "$(git log --first-parent --merges --format='%H %P %s' "origin/$integration")"
    if [ -z "$own_merge" ] && [ "$tracker" = 'github' ]; then
      if gh_as_owner "$main_worktree" "$gh_account_owner" pr list --head "$branch" --state merged --json headRefOid --jq '.[].headRefOid'; then
        if [[ $'\n'"$GH_AS_OUT"$'\n' == *$'\n'"$tip"$'\n'* ]]; then
          own_merge="github:$branch"
        fi
      else
        keep "$path ($branch): GitHub could not be asked as $GH_AS_ACCOUNT: ${GH_AS_ERR:-gh failed}"
        continue
      fi
    fi
    if [ -z "$own_merge" ]; then
      keep "$path ($branch): tip merged under another branch"
      continue
    fi
    remove "$path" "$branch"
    continue
  fi
  # Replay the branch's tree onto its merge base and ask whether the integration branch carries an
  # equivalent patch: `git cherry` compares patch ids, so a squashed commit counts; '-' means in.
  replay="$(git commit-tree "refs/heads/$branch^{tree}" -p "$base" -m 'worktree-prune probe' 2>/dev/null)"
  if [ -z "$replay" ] || [ "$(git cherry "origin/$integration" "$replay" | cut -c1)" != '-' ]; then
    keep "$path ($branch): $ahead commit(s) whose changes are not in origin/$integration"
    continue
  fi
  remove "$path" "$branch"
done <<< "$(git worktree list --porcelain | awk '/^worktree /{print substr($0, 10)}')"

git worktree prune
printf '\n%s removed, %s kept, %s failed\n' "$removed" "$kept" "$failed"
[ "$failed" -eq 0 ]
