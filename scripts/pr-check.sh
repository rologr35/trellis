#!/usr/bin/env bash
#
# pr-check: a pull request body or a commit message checked before it is published.
#
#   trellis pr-check --body <file>                 a pull request body
#   trellis pr-check --commit <file>               a commit message (the commit-msg hook)
#   trellis pr-check --has-setback --body <file>   exit 0 when the body carries a valid **Setback**
#
# Both: no long dash, no AI attribution (Co-Authored-By, "Generated with", a session link), no bare
# #N that GitHub would link by mistake (a reference goes after a keyword such as Closes, Refs or
# See, or inside parentheses, or in backticks when it is not a reference).
# A bare #N is accepted with style.bareReference = allow.
# A body: the sections of project.locale (en: **Summary**, **Verification**; es: **Resumen**,
# **Verificación**), or the ones of pr.section in their place; a **Setback** (es: **Retroceso**) that says what regresses, its cost and why it
# was accepted, required when the branch has the ratchet's escape (ratchet-loosened). The names
# live in lib/locale.mjs.
# The body of a cycle pull request, the one of an issue branch (git.issueBranch) into the integration
# branch with tracker.kind = github, also closes the branch's issue (`Closes #n`) and carries
# **Before merging** and **After merging** (es: **Antes de mezclar**, **Después de mezclar**), each
# `none` (es: `nada`) or a list. With pr.action, each item of those two that is not inside another and is
# not `none` starts with one of its values, after the bullet, the check box and a backtick. In CI the two branches are GITHUB_HEAD_REF and GITHUB_BASE_REF;
# locally the head is the checked-out branch and the base is assumed to be the integration branch.
# A commit: `type(scope): message (#n)` on the first line when tracker.kind = github, the same
# without (#n) otherwise; on an issue branch <n>-..., the #n is that issue. Merge, revert, fixup!
# and squash! messages that git writes are not judged.
# After it, also when it fails, the check of the project (lib/project-check.sh): command.pullRequestCheck
# on a body, command.commitCheck on a commit whose shape is judged, with the message as git will write it.
#
# Read-only. On failure every miss is printed and the exit is 1.

set -uo pipefail

TRELLIS_ROOT="${TRELLIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/config.sh
. "$TRELLIS_ROOT/lib/config.sh"
# shellcheck source=../lib/project-check.sh
. "$TRELLIS_ROOT/lib/project-check.sh"

usage='usage: trellis pr-check --body <file> | --commit <file> | --has-setback --body <file>'
mode=''
file=''
setback=false
while [ $# -gt 0 ]; do
  case "$1" in
    --body) mode='body'; file="${2:-}"; shift 2 ;;
    --commit) mode='commit'; file="${2:-}"; shift 2 ;;
    --has-setback) setback=true; shift ;;
    *) printf '%s\n' "$usage" >&2; exit 2 ;;
  esac
done
[ -n "$mode" ] && [ -f "$file" ] || { printf '%s\n' "$usage" >&2; exit 2; }
[ "$setback" = true ] && [ "$mode" != 'body' ] && { printf '%s\n' "$usage" >&2; exit 2; }

branch="$(git branch --show-current 2>/dev/null || true)"
loosened=''
[ -n "$branch" ] && loosened="$(git config --get "branch.${branch}.ratchet-loosened" 2>/dev/null || true)"

integration="$(tc_get git.integrationBranch)"
issue_regex="$(tc_get git.issueBranch)"
head="$branch"
base="$integration"
if [ -n "${GITHUB_HEAD_REF:-}" ]; then
  head="$GITHUB_HEAD_REF"
  base="${GITHUB_BASE_REF:-}"
fi
cycle='-'
if [ "$(tc_get tracker.kind)" = 'github' ] && [ "$base" = "$integration" ] && [ -n "$head" ] && [[ "$head" =~ $issue_regex ]]; then
  cycle="$head"
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/trellis-pr-check.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT
status=0
node "$TRELLIS_ROOT/scripts/pr-check.mjs" "$mode" "$file" "$setback" "${branch:--}" "${loosened:-false}" "$cycle" "$tmp/message" || status=$?
[ "$setback" = false ] || exit "$status"
if [ "$mode" = 'body' ]; then
  project_check pullRequestCheck pr-check "$file" || status=1
elif [ -f "$tmp/message" ]; then
  project_check commitCheck pr-check "$tmp/message" || status=1
fi
exit "$status"
