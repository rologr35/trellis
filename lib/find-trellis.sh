#!/usr/bin/env bash
#
# find_trellis: print the path of the trellis command, or nothing. Sourced by the git hooks of a
# project; `trellis sync` keeps the copy in .githooks/ equal to the plugin's lib/find-trellis.sh.
#
# A git hook runs in a person's shell, where the plugin's bin/ is not on the PATH, so the command is
# looked up on the PATH first and then at the installPath of ~/.claude/plugins/installed_plugins.json
# (the cache path changes with every version, so it is read, never written down).

find_trellis() {
  local found
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
