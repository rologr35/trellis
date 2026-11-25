#!/usr/bin/env bash
#
# find_trellis: print the path of the trellis command, or nothing. Sourced by the git hooks of a
# project; `trellis sync` keeps the copy in .githooks/ equal to lib/find-trellis.sh. `setup` and
# `doctor` read from here which command a project brings.
#
# The command the project brings, the copy it commits or the tree of the repository of trellis, is the
# first one looked for, also when it cannot run: another version does not stand for it. Without node
# (a git client with a PATH of its own) it is not found, and the hooks skip their checks instead of
# refusing every commit. When it brings none, the PATH and then the installPath of
# ~/.claude/plugins/installed_plugins.json (the cache path changes with every version, so it is read,
# never written down): a git hook runs in a person's shell, where the plugin's bin/ is not on the PATH.

# Whether the folder is the repository of trellis, which runs from its own tree and not from a copy.
is_trellis() {
  [ -f "$1/lib/find-trellis.sh" ] && [ -f "$1/.claude-plugin/plugin.json" ] || return 1
  node -e 'process.exit(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).name === "trellis" ? 0 : 1)' "$1/.claude-plugin/plugin.json" 2>/dev/null
}

# The command the project at that top level brings, or nothing.
project_trellis() {
  if [ -f "$1/.trellis/bin/trellis" ]; then
    printf '%s\n' "$1/.trellis/bin/trellis"
  elif is_trellis "$1" && [ -f "$1/bin/trellis" ]; then
    printf '%s\n' "$1/bin/trellis"
  fi
}

find_trellis() {
  local found
  found="$(project_trellis "$(git rev-parse --show-toplevel 2>/dev/null)")"
  if [ -n "$found" ] && command -v node >/dev/null 2>&1; then
    printf '%s\n' "$found"
    return 0
  fi
  found="$(command -v trellis 2>/dev/null)"
  if [ -n "$found" ]; then
    printf '%s\n' "$found"
    return 0
  fi
  command -v node >/dev/null 2>&1 || return 0
  found="$(node -e '
    try {
      const fs = require("fs");
      const data = JSON.parse(fs.readFileSync(require("os").homedir() + "/.claude/plugins/installed_plugins.json", "utf8"));
      for (const [key, installs] of Object.entries(data.plugins || {})) {
        if (!key.startsWith("trellis@")) continue;
        for (const install of installs) {
          const bin = install.installPath + "/bin/trellis";
          if (fs.existsSync(bin)) { process.stdout.write(bin); process.exit(0); }
        }
      }
    } catch {}
  ' 2>/dev/null)"
  [ -n "$found" ] && printf '%s\n' "$found"
  return 0
}
