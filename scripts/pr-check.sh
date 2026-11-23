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
# A body: the sections of project.locale (en: **Summary**, **Verification**; es: **Resumen**,
# **Verificación**); a **Setback** (es: **Retroceso**) that says what regresses, its cost and why it
# was accepted, required when the branch has the ratchet's escape (ratchet-loosened). The names
# live in lib/locale.mjs.
# A commit: `type(scope): message (#n)` on the first line when tracker.kind = github, the same
# without (#n) otherwise; on an issue branch <n>-..., the #n is that issue. Merge, revert, fixup!
# and squash! messages that git writes are not judged.
#
# Read-only. On failure every miss is printed and the exit is 1.

set -uo pipefail

TRELLIS_ROOT="${TRELLIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

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

exec node "$TRELLIS_ROOT/scripts/pr-check.mjs" "$mode" "$file" "$setback" "${branch:--}" "${loosened:-false}"
