#!/usr/bin/env bash
#
# protected-head-ci: the protected-head job of the consumer CI. A pull request whose head is a branch
# of git.protected is closed and the job fails: with branches deleted on merge, its merge would
# delete that branch. The config is read on its own first, so a config that does not parse fails
# the job with its error instead of reading as an empty list.
#
#   HEAD_REF=<branch> NUMBER=<pull request> GITHUB_REPOSITORY=<owner/repo> bash scripts/protected-head-ci.sh

set -uo pipefail

TRELLIS_ROOT="${TRELLIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

protected="$(bash "$TRELLIS_ROOT/bin/trellis" config all git.protected)" || exit $?
while IFS= read -r branch; do
  [ -n "$branch" ] && [ "$branch" = "$HEAD_REF" ] || continue
  gh pr close "$NUMBER" --repo "$GITHUB_REPOSITORY" --comment "The head of this pull request is $HEAD_REF, a protected branch: merging it with branch deletion on would delete $HEAD_REF. Open it from an issue branch."
  echo "protected-head: $HEAD_REF is protected; the pull request is closed" >&2
  exit 1
done <<< "$protected"
echo "protected-head: $HEAD_REF is not protected"
