#!/usr/bin/env bash
#
# update: write in the project the copy of trellis at a tag or at a sha of trellis.upstream.
#
#   trellis update <tag|sha>
#
#   - .trellis/: the runtime (bin, hooks, lib, scripts, hygiene, method, templates, LICENSE) without
#     its tests; .trellis/VERSION, the version and the full sha; .trellis/MANIFEST, the sha256 of every
#     file written;
#   - .claude/skills/trellis-<name>/SKILL.md and .claude/agents/trellis-<name>.md, every skill but init.
#
# What the previous copy had and this one does not is removed. Nothing is written, and the files are
# named, when the previous copy was edited by hand, when a file of the project has the name of a copied
# one, or when git ignores one. It ends with `trellis sync`, run from the new copy.

set -uo pipefail

TRELLIS_ROOT="${TRELLIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# One function, read whole before it runs: the copy may be rewriting this file.
main() {
  local top
  if [ $# -ne 1 ] || [ -z "$1" ]; then
    printf 'usage: trellis update <tag|sha>\n' >&2
    exit 2
  fi
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || { printf 'update: not inside a git repository\n' >&2; exit 1; }
  cd "$top" || exit 1
  node --input-type=module -e '
    import {pathToFileURL} from "node:url";
    const [lib, root, ref] = process.argv.slice(1);
    const load = name => import(pathToFileURL(`${lib}/${name}`).href);
    const [{update}, {loadConfig}] = [await load("copy.mjs"), await load("config.mjs")];
    try {
      const done = await update(root, loadConfig({cwd: root}).get("trellis.upstream"), ref);
      console.log(`update: trellis ${done.version} (${done.sha}), ${done.files} files written, ${done.removed} removed`);
    } catch (error) {
      console.error(`update: ${error.message}`);
      process.exit(1);
    }
  ' "$TRELLIS_ROOT/lib" "$top" "$1" || exit 1
  unset TRELLIS_ROOT
  bash .trellis/bin/trellis sync
  exit $?
}
main "$@"
