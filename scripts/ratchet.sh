#!/usr/bin/env bash
#
# ratchet: refuse a change that loosens a ratchet. A ratchet keeps a cleanup from growing back;
# loosening one is sometimes right, but never by accident: the refusal says what regresses, its
# cost and the alternative, and the session waits for the person.
#
#   trellis ratchet                          the staged change against HEAD (the pre-commit hook)
#   trellis ratchet --base <ref>             HEAD against its merge base with <ref> (CI, full history:
#                                            a shallow clone gives false results)
#   trellis ratchet ... --allow-loosen       findings become a warning (CI, when the pull request
#                                            body carries a valid **Setback** section)
#
# What loosens, read by scripts/ratchet.mjs: a suppression of [ratchets] suppression added (net over
# the change's code files), a test of [ratchets] testFile deleted (a rename is not), a rule of a
# [ratchets] lintConfig file lowered or dropped, or a new entry there that switches something off
# (an analyzer error set to ignore, a rule set to false or off, inherited ones included, an excluded
# path, an ESLint rule off or ignored path), the default model of .claude/settings.json raised or
# a hook dropped, a limit or a frozen size of [hygiene] raised (a size frozen for the first time is
# not a rise; lowering is free), keepRef, namedElsewhere or mustNotLoad grown, a glob more in
# [workspace] notPackage, a value more in tracker.search or copy.without, autonomy.level raised, a [ratchets] list or [workspace] manifest shortened,
# a section in force dropped by [pr] section (the ones of the language when none is set), the last [pr] action
# taken out, style.bareReference set to allow, issue.class to label, a check of the project taken out
# (command.pullRequestCheck, issueCheck or commitCheck) and project.public from true to false.
#
# The local escape, set only after the person confirmed knowing the cost:
#   git config branch.<branch>.ratchet-loosened true
# It turns the findings into a warning, and `trellis pr-check` then asks the pull request for a
# **Setback** section (**Retroceso** in es). A merge in progress is not judged: what it brings was
# judged on its branch. A pass prints one line. The files of the copy of trellis, by .trellis/MANIFEST, are not judged.

set -uo pipefail

TRELLIS_ROOT="${TRELLIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

base=''
allow=false
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="${2:-}"; shift 2 ;;
    --allow-loosen) allow=true; shift ;;
    *) printf 'usage: trellis ratchet [--base <ref>] [--allow-loosen]\n' >&2; exit 2 ;;
  esac
done

if ! git rev-parse -q --verify HEAD >/dev/null; then
  echo 'ratchet: no commit yet, nothing to judge'
  exit 0
fi
if [ -z "$base" ] && git rev-parse -q --verify MERGE_HEAD >/dev/null; then
  echo 'ratchet: a merge in progress is not judged'
  exit 0
fi

branch="$(git branch --show-current 2>/dev/null)"
escaped=''
[ -n "$branch" ] && escaped="$(git config --get "branch.${branch}.ratchet-loosened" 2>/dev/null || true)"
[ "$allow" = true ] && escaped='true'

exec node "$TRELLIS_ROOT/scripts/ratchet.mjs" "${base:--}" "${branch:--}" "${escaped:-false}"
