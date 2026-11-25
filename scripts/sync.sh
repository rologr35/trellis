#!/usr/bin/env bash
#
# sync: rewrite what trellis generates in a project, so each piece has one source.
#
#   trellis sync
#
#   - the blocks `<!-- trellis:<id> -->` of the root CLAUDE.md (method, orientation, commands,
#     gates) and of TESTING.md (rungs), from method/<project.locale>.md, the config and the tree;
#   - in .claude/settings.json, the deny of each rung with agent = false and of each push to a
#     branch of git.protected: defense in depth. A push entry of a branch no longer protected is
#     removed. `gh pr merge` has no deny: a permission rule cannot see a pull request's base and a
#     deny beats every allow, so that line lives only in hooks/guard-git.sh. The GitHub MCP tools of a
#     cloud session that merge, switch on auto-merge or write files in a branch, which that hook does
#     not see, are denied. Opening a pull request, commenting and marking it ready are not;
#   - in the same file, when the project has a copy of trellis (.trellis/VERSION): the hook of
#     guard-git, the one of `trellis setup` at the start of a session, and the deny of an edit of the
#     copy. The other hooks of the project stay as they are;
#   - .githooks/find-trellis.sh, the copy of lib/find-trellis.sh, when .githooks/ exists;
#   - in the repository of trellis, which runs from its own tree, .claude/skills/trellis-<name>/SKILL.md
#     and .claude/agents/trellis-<name>.md, from skills/ and agents/, as a copy holds them. One with no
#     source is removed. The code of another checkout refuses there, and so does the hygiene's.
#
# Only blocks already present are rewritten: where a block goes is the template's decision.
# Prints one line per file it changed or removed.

set -uo pipefail

TRELLIS_ROOT="${TRELLIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
exec node "$TRELLIS_ROOT/scripts/sync.mjs" "$@"
