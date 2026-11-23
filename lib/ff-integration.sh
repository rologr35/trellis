#!/usr/bin/env bash
#
# ff_integration: bring the main checkout's integration branch up to its origin copy when that is a
# fast-forward, and say what happened when it is anything else.
#
# Sourced by worktree-add and worktree-prune, the two scripts that fetch origin at the moments the
# integration branch moves: an issue starts, and an issue is merged. Only a fast-forward, only when
# the main checkout is on the integration branch, only after the caller fetched. A local branch with
# commits of its own is never merged or reset: that is somebody's unpushed work, and the line says
# so. A fast-forward git refuses (an uncommitted change under a file the merge touches) is reported,
# not forced. Nothing is printed when the branch is already at the tip. Never fails the caller.
#
#   ff_integration <branch> '<prefix>'   prints '<prefix><branch> ...' lines; cwd = the main checkout

ff_integration() {
  local branch="$1" prefix="$2" current local_tip remote_tip
  remote_tip="$(git rev-parse --verify --quiet "refs/remotes/origin/$branch")" || return 0
  local_tip="$(git rev-parse --verify --quiet "refs/heads/$branch")" || return 0
  [ "$local_tip" = "$remote_tip" ] && return 0
  if ! git merge-base --is-ancestor "$local_tip" "$remote_tip"; then
    printf '%s%s kept at %s: it has commits origin/%s does not (git log origin/%s..%s)\n' \
      "$prefix" "$branch" "$(git rev-parse --short "$local_tip")" "$branch" "$branch" "$branch"
    return 0
  fi
  current="$(git branch --show-current 2>/dev/null)"
  if [ "$current" != "$branch" ]; then
    printf '%s%s kept at %s: the main checkout is on %s, not %s\n' \
      "$prefix" "$branch" "$(git rev-parse --short "$local_tip")" "${current:-a detached HEAD}" "$branch"
    return 0
  fi
  if git merge -q --ff-only --no-stat "origin/$branch" >/dev/null; then
    printf '%s%s fast-forwarded %s -> %s\n' \
      "$prefix" "$branch" "$(git rev-parse --short "$local_tip")" "$(git rev-parse --short "$remote_tip")"
  else
    printf '%s%s kept at %s: git refused the fast-forward (an uncommitted change in the way?)\n' \
      "$prefix" "$branch" "$(git rev-parse --short "$local_tip")"
  fi
  return 0
}
