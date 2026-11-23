#!/usr/bin/env bash
# Exercises scripts/doctor.sh with a PATH of its own: the config, the toolchain, Claude Code and
# the plugin, node with hooks active, ANTHROPIC_API_KEY, the secret scanner, env files, the branch.
. "$(dirname "$0")/../lib/testlib.sh"

# A PATH holding only what the doctor needs, plus stubs; node is added back on demand.
tools="$TL_TMP/tools"
mkdir -p "$tools"
for tool in git bash sh awk grep head tail sed cat tr wc cut dirname basename mktemp env uname sort; do
  ln -s "$(command -v "$tool")" "$tools/$tool"
done
stub() { printf '#!/bin/sh\necho "%s"\n' "$2" > "$tools/$1"; chmod +x "$tools/$1"; }
stub claude '2.1.330 (Claude Code)'
stub flutter 'Flutter 3.10.0 • channel stable'
NODE="$(command -v node)"

repo="$(tl_repo)"
cd "$repo" || exit 1
mkdir .githooks
git config core.hooksPath .githooks
mkdir -p "$HOME/.claude/plugins"
printf '{"plugins": {"trellis@trellis": [{"installPath": "/x"}]}}\n' > "$HOME/.claude/plugins/installed_plugins.json"
cat > trellis.config <<'CFG'
[command "scan"]
	run = gitleaks protect --staged
[command]
	secretScan = scan
CFG
stub gitleaks 'gitleaks 8.18.0'

doctor() { PATH="$tools" bash "$TRELLIS_ROOT/scripts/doctor.sh" > "$TL_TMP/out.txt" 2>&1; echo $?; }
out() { cat "$TL_TMP/out.txt"; }

ln -s "$NODE" "$tools/node"
tl_eq 'a healthy checkout passes' '0' "$(doctor)"
tl_has 'with its verdict' 'no FAIL' "$(out)"

printf '\nconfig\n'
git config -f trellis.config bogus.key 1
tl_eq 'an unknown key fails' '1' "$(doctor)"
tl_has 'and is named' 'unknown key bogus.key' "$(out)"
git config -f trellis.config --remove-section bogus
git config -f trellis.config --add command.check missing
tl_eq 'a command name without run fails' '1' "$(doctor)"
git config -f trellis.config --unset-all command.check

git config -f trellis.config project.locale es
tl_eq 'a locale in the schema passes' '0' "$(doctor)"
git config -f trellis.config project.locale ES
tl_eq 'a locale outside en|es fails' '1' "$(doctor)"
tl_has 'naming the value and the accepted ones' 'project.locale = ES is not one of en, es' "$(out)"
git config -f trellis.config --unset project.locale
git config -f trellis.config tracker.kind gitlab
tl_eq 'tracker.kind outside the schema fails' '1' "$(doctor)"
tl_has 'naming the value and the accepted ones' 'tracker.kind = gitlab is not one of github, none' "$(out)"
git config -f trellis.config --unset tracker.kind
git config -f trellis.config workspace.kind python
tl_eq 'workspace.kind outside the schema fails' '1' "$(doctor)"
tl_has 'naming the value and the accepted ones' 'workspace.kind = python is not one of flutter, dart, node' "$(out)"
git config -f trellis.config --unset workspace.kind
git config -f trellis.config rung.unit.agent maybe
tl_eq 'a subsection enum fails too' '1' "$(doctor)"
tl_has 'with its own name' 'rung.unit.agent = maybe is not one of true, false' "$(out)"
git config -f trellis.config --remove-section rung.unit
tl_eq 'a config back to valid values passes' '0' "$(doctor)"

printf '\ntoolchain\n'
git config -f trellis.config toolchain.require 'flutter 3.24.0'
tl_eq 'an old tool fails' '1' "$(doctor)"
tl_has 'with both versions' 'flutter 3.10.0 is older than 3.24.0' "$(out)"
git config -f trellis.config toolchain.require 'flutter 3.9'
tl_eq 'a new enough tool passes' '0' "$(doctor)"
git config -f trellis.config toolchain.require 'dart'
tl_eq 'a missing tool fails' '1' "$(doctor)"
git config -f trellis.config --unset-all toolchain.require

printf '\nclaude code, plugin, node\n'
stub claude '2.1.300 (Claude Code)'
tl_eq 'an old Claude Code fails' '1' "$(doctor)"
stub claude '2.1.330 (Claude Code)'
mv "$HOME/.claude/plugins/installed_plugins.json" "$TL_TMP/plugins.json"
tl_eq 'the plugin not installed fails' '1' "$(doctor)"
mv "$TL_TMP/plugins.json" "$HOME/.claude/plugins/installed_plugins.json"
rm "$tools/node"
tl_eq 'node missing with hooks active fails' '1' "$(doctor)"
tl_has 'and says why' 'node not found while hooks are active' "$(out)"
ln -s "$NODE" "$tools/node"
git config --unset core.hooksPath
tl_eq 'core.hooksPath unset fails' '1' "$(doctor)"
git config core.hooksPath .githooks

printf '\nbilling, secrets, env files\n'
tl_eq 'ANTHROPIC_API_KEY exported fails' '1' "$(ANTHROPIC_API_KEY=x doctor)"
tl_has 'and says why' 'billed as API usage' "$(out)"
rm "$tools/gitleaks"
tl_eq 'a configured scanner missing fails' '1' "$(doctor)"
git config -f trellis.config --unset command.secretScan
tl_eq 'no scanner configured passes' '0' "$(doctor)"
tl_has 'with a warning' 'no secret scanner configured' "$(out)"
git config -f trellis.config toolchain.envFile .env
tl_eq 'a missing env file fails' '1' "$(doctor)"
touch .env
tl_eq 'a present env file passes' '0' "$(doctor)"

printf '\nbranch\n'
git switch -q -c feature/x
tl_eq 'a branch out of the shapes fails' '1' "$(doctor)"
git switch -q -c 3-thing
tl_eq 'an issue branch passes' '0' "$(doctor)"

tl_done
