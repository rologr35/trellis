#!/usr/bin/env bash
#
# sync: rewrite what the plugin generates in a project, so each piece has one source.
#
#   trellis sync
#
#   - the blocks `<!-- trellis:<id> -->` of the root CLAUDE.md (method, orientation, commands,
#     gates) and of TESTING.md (rungs), from method/base.md, the config and the tree;
#   - in .claude/settings.json, the deny of each rung with agent = false and of each push to a
#     branch of git.protected: defense in depth, and the only push guard in a cloud session, where
#     the plugin may not load. A push entry of a branch no longer protected is removed. A merge has
#     no deny: a permission rule cannot see a pull request's base and a deny beats every allow, so
#     the merge line lives only in hooks/guard-git.sh;
#   - .githooks/find-trellis.sh, the copy of lib/find-trellis.sh, when .githooks/ exists.
#
# Only blocks already present are rewritten: where a block goes is the template's decision.
# Prints one line per file it changed.

set -uo pipefail

TRELLIS_ROOT="${TRELLIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
exec node "$TRELLIS_ROOT/scripts/sync.mjs" "$@"
