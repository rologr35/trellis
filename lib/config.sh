#!/usr/bin/env bash
#
# The one reader of trellis.config, sourced by bin/trellis, the scripts and the hooks. The file is
# git-config syntax and is read with `git config -f`; lib/schema holds the keys and their defaults.
#
# Section and key names are case-insensitive in git config (it prints them lowercased) and
# subsection names are not, so every key is matched lowercased and printed in the schema's spelling.
#
#   tc_config_file          the path of the config in use (TRELLIS_CONFIG, else <toplevel>/trellis.config)
#   tc_list                 every effective key=value, defaults included, one per line
#   tc_get <key>            the value of a single key (the last one written), or its default
#   tc_all <key>            every value of a multi key, one per line, or its defaults
#   tc_subsections <sect>   the names of the subsections of a section, e.g. the commands
#   tc_unknown              the keys of the file that the schema does not know
#   tc_check                exit status 3 and the parse error on stderr when the file exists and
#                           does not parse; bin/trellis runs it before every subcommand but doctor
#
# A config that does not parse fails closed: every reader but the doctor stops on tc_check instead
# of answering the schema's defaults, which would quietly unprotect the branches the file names.
#
# Works with bash 3.2: no associative arrays, no mapfile.

TRELLIS_ROOT="${TRELLIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

tc_config_file() {
  if [ -n "${TRELLIS_CONFIG:-}" ]; then
    printf '%s\n' "$TRELLIS_CONFIG"
    return 0
  fi
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || top="$(pwd -P)"
  printf '%s/trellis.config\n' "$top"
}

tc_check() {
  local file error
  file="$(tc_config_file)"
  [ -f "$file" ] || return 0
  error="$(git config -f "$file" --list 2>&1 >/dev/null)" && return 0
  printf 'trellis: trellis.config does not parse: %s\n' "$(printf '%s' "$error" | head -n 1)" >&2
  return 3
}

# The raw key=value lines of the file, nothing when it is missing or does not parse.
_tc_raw() {
  local file
  file="$(tc_config_file)"
  [ -f "$file" ] || return 0
  git config -f "$file" --list 2>/dev/null
}

# mode=list prints the effective config; mode=unknown prints the keys the schema does not know.
_tc_awk() {
  _tc_raw | awk -v schema="$TRELLIS_ROOT/lib/schema" -v mode="$1" '
    BEGIN {
      while ((getline line < schema) > 0) {
        if (line ~ /^#/ || line == "") continue
        i1 = index(line, "|"); key = substr(line, 1, i1 - 1); rest = substr(line, i1 + 1)
        i2 = index(rest, "|"); kind = substr(rest, 1, i2 - 1); def = substr(rest, i2 + 1)
        lk = tolower(key)
        if (!(lk in canon)) { canon[lk] = key; kinds[key] = kind; order[++nkeys] = key }
        if (def != "") { ndef[key]++; defs[key, ndef[key]] = def }
      }
    }
    {
      eq = index($0, "="); k = eq ? substr($0, 1, eq - 1) : $0; v = eq ? substr($0, eq + 1) : "true"
      first = index(k, "."); rest = substr(k, first + 1)
      sect = substr(k, 1, first - 1)
      last = rest; sub_name = ""
      if (match(rest, /\.[^.]*$/)) { sub_name = substr(rest, 1, RSTART - 1); last = substr(rest, RSTART + 1) }
      if (sub_name == "" && (tolower(k) in canon)) {
        name = canon[tolower(k)]
      } else if (sub_name != "" && ((tolower(sect) ".*." tolower(last)) in canon)) {
        pattern = canon[tolower(sect) ".*." tolower(last)]
        p1 = index(pattern, ".*.")
        name = substr(pattern, 1, p1) sub_name substr(pattern, p1 + 2)
        if (!((sect, sub_name) in seen)) { seen[sect, sub_name] = 1; nsubs[sect]++; subs[sect, nsubs[sect]] = sub_name }
      } else {
        if (mode == "unknown") print k
        next
      }
      if (!(name in nval)) { written[++nwritten] = name }
      if (kinds[pattern_of(name)] == "single") { nval[name] = 1; vals[name, 1] = v }
      else { nval[name]++; vals[name, nval[name]] = v }
    }
    function pattern_of(name,   a, n) {
      n = split(name, a, ".")
      if (n == 2) return name
      return a[1] ".*." a[n]
    }
    END {
      if (mode != "list") exit
      for (i = 1; i <= nkeys; i++) {
        key = order[i]
        if (index(key, ".*.")) continue
        if (key in nval) { for (j = 1; j <= nval[key]; j++) print key "=" vals[key, j] }
        else { for (j = 1; j <= ndef[key]; j++) print key "=" defs[key, j] }
      }
      for (i = 1; i <= nkeys; i++) {
        key = order[i]
        p1 = index(key, ".*.")
        if (!p1) continue
        sect = substr(key, 1, p1 - 1)
        for (s = 1; s <= nsubs[sect]; s++) {
          name = sect "." subs[sect, s] "." substr(key, p1 + 3)
          if (name in nval) { for (j = 1; j <= nval[name]; j++) print name "=" vals[name, j] }
          else { for (j = 1; j <= ndef[key]; j++) print name "=" defs[key, j] }
        }
      }
    }
  '
}

tc_list() { _tc_awk list; }

tc_unknown() { _tc_awk unknown; }

tc_all() {
  tc_list | awk -v key="$1" 'BEGIN { lk = tolower(key) } { eq = index($0, "="); if (tolower(substr($0, 1, eq - 1)) == lk) print substr($0, eq + 1) }'
}

tc_get() {
  tc_all "$1" | tail -n 1
}

tc_subsections() {
  tc_list | awk -v sect="$1" '
    BEGIN { ls = tolower(sect) "." }
    {
      eq = index($0, "="); k = substr($0, 1, eq - 1)
      if (tolower(substr(k, 1, length(ls))) != ls) next
      rest = substr(k, length(ls) + 1)
      if (!match(rest, /\.[^.]*$/)) next
      name = substr(rest, 1, RSTART - 1)
      if (!(name in seen)) { seen[name] = 1; print name }
    }'
}
