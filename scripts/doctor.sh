#!/usr/bin/env bash
#
# doctor: read-only diagnosis of the environment and of this checkout.
#
#   trellis doctor
#
# One line per check, prefixed ok / warn / info / FAIL, and exit 1 on any FAIL. It never writes and
# never fetches: the repository state is read from local refs. Env files are checked for presence
# and never read.
#
# FAIL: a key of trellis.config outside lib/schema, a value outside the accepted ones of an enum
# key of lib/schema (project.locale, tracker.kind, workspace.kind and the rest), workspace.kind =
# other without [hygiene] namedExt, or a command name that names no [command]; a tool of
# [toolchain] require missing or older than its minimum; core.hooksPath unset; the plugin
# not installed or Claude Code older than the minimum; node missing while hooks are active;
# ANTHROPIC_API_KEY exported (the subscription stops being used and every token is billed as API
# usage, silently, so it is a FAIL and not a warning); a branch that is neither the integration
# branch, the release branch nor an issue branch; a [command] secretScan configured and missing;
# a [toolchain] envFile missing.
# warn: a rung with pr = true that no file under .github/workflows/ runs (it holds the command's
# run text, or its ci text when set); no secret scanner configured; uncommitted changes, unpushed
# commits, worktrees of branches missing from origin. info: what the release is waiting for.

set -uo pipefail

TRELLIS_ROOT="${TRELLIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/config.sh
. "$TRELLIS_ROOT/lib/config.sh"

CLAUDE_MIN='2.1.324'

fail_count=0
warn_count=0
section() { printf '\n%s\n' "$1"; }
ok()   { printf '  ok    %s\n' "$1"; }
info() { printf '  info  %s\n' "$1"; }
warn() { printf '  warn  %s\n' "$1"; warn_count=$((warn_count + 1)); }
fail() { printf '  FAIL  %s\n' "$1"; fail_count=$((fail_count + 1)); }

# True when version $1 >= version $2, both dotted numbers.
version_ge() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    na = split(a, x, "."); nb = split(b, y, "."); n = na > nb ? na : nb
    for (i = 1; i <= n; i++) { if ((x[i] + 0) > (y[i] + 0)) exit 0; if ((x[i] + 0) < (y[i] + 0)) exit 1 }
    exit 0
  }'
}

# The first dotted number a command prints for --version.
version_of() {
  "$1" --version 2>&1 </dev/null | grep -Eo '[0-9]+(\.[0-9]+)+' | head -n 1
}

top="$(git rev-parse --show-toplevel 2>/dev/null)" || { printf 'doctor: not inside a git repository\n' >&2; exit 1; }
cd "$top" || exit 1

# ------------------------------------------------------------------------------------------------
section 'config'
config_file="$(tc_config_file)"
if [ ! -f "$config_file" ]; then
  fail "no trellis.config at $top (/trellis:init writes it)"
elif ! git config -f "$config_file" --list >/dev/null 2>&1; then
  fail "trellis.config does not parse: $(git config -f "$config_file" --list 2>&1 >/dev/null | head -n 1)"
else
  unknown="$(tc_unknown)"
  if [ -z "$unknown" ]; then
    ok 'every key of trellis.config is in the schema'
  else
    while IFS= read -r key; do
      fail "trellis.config: unknown key $key (lib/schema lists the keys)"
    done <<< "$unknown"
  fi
  if [ "$(tc_get workspace.kind)" = other ] && [ -z "$(tc_all hygiene.namedExt)" ]; then
    fail 'trellis.config: workspace.kind = other: declare [hygiene] namedExt, the extensions a rule names files by; without them the rule-loading check checks nothing'
  fi
  invalid="$(tc_invalid)"
  if [ -z "$invalid" ]; then
    ok 'every enum value of trellis.config is one the schema accepts'
  else
    while IFS='|' read -r key value accepted; do
      fail "trellis.config: $key = $value is not one of ${accepted//,/, }"
    done <<< "$invalid"
  fi
  missing_commands=''
  for name in $(tc_all command.check) $(tc_get command.secretScan) $(tc_get command.install); do
    [ -n "$(tc_get "command.$name.run")" ] || missing_commands="$missing_commands $name"
  done
  for rung in $(tc_subsections rung); do
    name="$(tc_get "rung.$rung.command")"
    [ -n "$name" ] && [ -z "$(tc_get "command.$name.run")" ] && missing_commands="$missing_commands $name"
  done
  if [ -z "$missing_commands" ]; then
    ok 'every command name has a [command "<name>"] run'
  else
    fail "named but without [command \"<name>\"] run:$missing_commands"
  fi
fi

# ------------------------------------------------------------------------------------------------
section 'toolchain'
if git_version="$(version_of git)" && [ -n "$git_version" ]; then
  ok "git $git_version"
else
  fail 'git not found'
fi
while IFS= read -r requirement; do
  [ -n "$requirement" ] || continue
  tool="${requirement%% *}"
  minimum=''
  [ "$tool" != "$requirement" ] && minimum="${requirement#* }"
  if ! command -v "$tool" >/dev/null 2>&1; then
    fail "$tool not found ([toolchain] require = $requirement)"
    continue
  fi
  if [ -z "$minimum" ]; then
    ok "$tool found"
    continue
  fi
  found="$(version_of "$tool")"
  if [ -z "$found" ]; then
    fail "$tool found but its version could not be read ($tool --version)"
  elif version_ge "$found" "$minimum"; then
    ok "$tool $found (>= $minimum)"
  else
    fail "$tool $found is older than $minimum"
  fi
done <<< "$(tc_all toolchain.require)"

# ------------------------------------------------------------------------------------------------
section 'claude code and plugin'
claude_version="$(command -v claude >/dev/null 2>&1 && version_of claude)"
if [ -z "$claude_version" ]; then
  fail "claude not found (Claude Code $CLAUDE_MIN or later)"
elif version_ge "$claude_version" "$CLAUDE_MIN"; then
  ok "Claude Code $claude_version (>= $CLAUDE_MIN)"
else
  fail "Claude Code $claude_version is older than $CLAUDE_MIN (the pinned marketplace needs it)"
fi
plugin_installed=false
if grep -q '"trellis@' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null; then
  plugin_installed=true
  ok 'plugin trellis installed'
else
  fail 'plugin trellis not installed (/plugin install trellis@trellis; enabledPlugins does not install)'
fi

hooks_path="$(git config --get core.hooksPath 2>/dev/null || true)"
if [ "$hooks_path" = '.githooks' ]; then
  ok 'git hooks installed (core.hooksPath = .githooks)'
elif [ -z "$hooks_path" ]; then
  fail 'core.hooksPath is unset: trellis setup sets it'
else
  fail "core.hooksPath is $hooks_path, expected .githooks"
fi

if command -v node >/dev/null 2>&1; then
  ok "node $(version_of node)"
elif [ "$plugin_installed" = true ] || [ -n "$hooks_path" ]; then
  fail 'node not found while hooks are active: guard-git has no opinion and the git hooks skip their checks'
else
  warn 'node not found (trellis hygiene, ratchet and pr-check need it)'
fi

# ------------------------------------------------------------------------------------------------
# pr = true means the project's own CI runs the rung's command on every pull request: the consumer
# workflow never runs rungs, because it does not install a stack's toolchain.
section 'rungs a pull request runs'
unrun=''
checked=0
for rung in $(tc_subsections rung); do
  [ "$(tc_get "rung.$rung.pr")" = false ] && continue
  name="$(tc_get "rung.$rung.command")"
  [ -n "$name" ] || continue
  text="$(tc_get "command.$name.ci")"
  [ -n "$text" ] || text="$(tc_get "command.$name.run")"
  [ -n "$text" ] || continue
  checked=$((checked + 1))
  if ! grep -rqF -- "$text" .github/workflows 2>/dev/null; then
    warn "rung $rung has pr = true but no workflow under .github/workflows/ runs $text: the project's CI owns the rungs, so add the step or set pr = false"
    unrun=1
  fi
done
if [ "$checked" -eq 0 ]; then
  info 'no rung with pr = true'
elif [ -z "$unrun" ]; then
  ok 'every rung with pr = true is run by a workflow of the project'
fi

# ------------------------------------------------------------------------------------------------
section 'billing (presence only)'
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  fail 'ANTHROPIC_API_KEY is exported: the subscription stops being used and every token is billed as API usage (unset it in the shell profile)'
else
  ok 'ANTHROPIC_API_KEY is not exported'
fi

# ------------------------------------------------------------------------------------------------
section 'secrets'
scan_name="$(tc_get command.secretScan)"
if [ -z "$scan_name" ]; then
  warn 'no secret scanner configured ([command] secretScan)'
else
  scan_run="$(tc_get "command.$scan_name.run")"
  scan_tool="${scan_run%% *}"
  if [ -n "$scan_tool" ] && command -v "$scan_tool" >/dev/null 2>&1; then
    ok "secret scanner $scan_tool found"
  else
    fail "secret scanner ${scan_tool:-?} of [command \"$scan_name\"] not found"
  fi
fi

# ------------------------------------------------------------------------------------------------
section 'env files (presence only, no value is read)'
env_files="$(tc_all toolchain.envFile)"
if [ -z "$env_files" ]; then
  info 'no [toolchain] envFile listed'
else
  while IFS= read -r env_file; do
    [ -n "$env_file" ] || continue
    if [ -f "$env_file" ]; then ok "$env_file present"; else fail "$env_file missing"; fi
  done <<< "$env_files"
fi

# ------------------------------------------------------------------------------------------------
section 'repo state (local refs, no fetch)'
integration="$(tc_get git.integrationBranch)"
release="$(tc_get git.releaseBranch)"
issue_regex="$(tc_get git.issueBranch)"
branch="$(git branch --show-current 2>/dev/null)"
if [ -z "$branch" ]; then
  fail 'detached HEAD'
elif [ "$branch" = "$integration" ] || [ "$branch" = "$release" ]; then
  ok "branch $branch"
elif [[ "$branch" =~ $issue_regex ]]; then
  ok "branch $branch (issue branch)"
else
  fail "branch $branch is neither $integration, $release nor an issue branch ($issue_regex)"
fi

dirty_count="$(git status --porcelain -uall 2>/dev/null | grep -c '')"
if [ "$dirty_count" -eq 0 ]; then ok 'no uncommitted changes'; else warn "$dirty_count uncommitted change(s)"; fi

if [ -n "$branch" ]; then
  if git rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null; then
    unpushed="$(git rev-list --count "origin/$branch..HEAD" 2>/dev/null)"
    if [ "${unpushed:-0}" -eq 0 ]; then ok "nothing to push (origin/$branch)"; else warn "$unpushed commit(s) not pushed to origin/$branch"; fi
  else
    warn "branch $branch is not on origin (nothing of it is pushed)"
  fi
fi

if git rev-parse --verify --quiet "origin/$integration" >/dev/null && git rev-parse --verify --quiet "origin/$release" >/dev/null; then
  if [ "$integration" != "$release" ]; then
    info "$integration is $(git rev-list --count "origin/$release..origin/$integration") commit(s) ahead of $release (the pending release)"
  fi
else
  info "cannot compare $integration with $release (a remote-tracking ref is missing)"
fi

# The same candidates as worktree-prune, which decides which are safe: from local refs, a branch
# gone after its merge and one never pushed look the same, so this says "look", never "merged".
main_worktree="$(git worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')"
stale="$(git worktree list --porcelain |
  awk '/^worktree /{p=substr($0, 10)} /^branch /{b=$2; sub("refs/heads/", "", b); print p "\t" b}' |
  while IFS="$(printf '\t')" read -r p b; do
    [ "$p" = "$main_worktree" ] && continue
    git rev-parse --verify --quiet "refs/remotes/origin/$b" >/dev/null && continue
    base="$(git merge-base "origin/$integration" "refs/heads/$b" 2>/dev/null)" || continue
    [ "$(git rev-list --count "$base..refs/heads/$b" 2>/dev/null || echo 0)" != '0' ] && printf '%s\n' "$b"
  done | grep -c '')"
if [ "$stale" -eq 0 ]; then
  ok 'no worktree of a branch missing from origin (local refs; the prune fetches)'
else
  warn "$stale worktree(s) whose branch is not on origin: trellis worktree prune says which are safe"
fi

# ------------------------------------------------------------------------------------------------
printf '\n'
if [ "$fail_count" -gt 0 ]; then
  printf '%d FAIL, %d warn\n' "$fail_count" "$warn_count"
  exit 1
fi
printf 'no FAIL, %d warn\n' "$warn_count"
