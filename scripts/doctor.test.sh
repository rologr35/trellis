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
for key in pullRequestCheck issueCheck commitCheck; do
  git config -f trellis.config "command.$key" missing
  tl_eq "command.$key without run fails" '1' "$(doctor)"
  tl_has 'naming it' 'named but without [command "<name>"] run: missing' "$(out)"
  git config -f trellis.config --unset "command.$key"
done

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
git config -f trellis.config workspace.kind other
tl_eq 'workspace.kind = other without namedExt fails' '1' "$(doctor)"
tl_has 'saying to declare the extensions' 'workspace.kind = other: declare [hygiene] namedExt' "$(out)"
git config -f trellis.config hygiene.namedExt py
tl_eq 'workspace.kind = other with namedExt passes' '0' "$(doctor)"
git config -f trellis.config --unset-all hygiene.namedExt
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
stub claude '2.1.324 (Claude Code)'
tl_eq 'Claude Code below the verified --scope local fails' '1' "$(doctor)"
tl_has 'and names what needs it' 'the pinned marketplace and --scope local need it' "$(out)"
stub claude '2.1.330 (Claude Code)'
mv "$HOME/.claude/plugins/installed_plugins.json" "$TL_TMP/plugins.json"
tl_eq 'the plugin not installed fails' '1' "$(doctor)"
mkdir -p .claude-plugin lib && printf '{\n  "name": "trellis"\n}\n' > .claude-plugin/plugin.json
tl_lacks 'a plugin.json alone is not the repository of trellis' 'this is the trellis of' "$(doctor; out)"
touch lib/find-trellis.sh
tl_eq 'the repository of trellis asks for no plugin' '0' "$(doctor)"
tl_has 'the code of another checkout is a warning' 'warn  this is the trellis of' "$(out)"
own="$(tl_upstream)"
tl_has 'it runs from its tree' 'ok    trellis runs from its tree' "$(cd "$own" && PATH="$tools" bash bin/trellis doctor 2>&1)"
tl_lacks 'the plugin is not asked for' 'plugin trellis' "$(cd "$own" && PATH="$tools" bash bin/trellis doctor 2>&1)"
rm "$tools/node"
tl_lacks 'without node it asks for no plugin' 'plugin trellis not installed' "$(doctor; out)"
tl_has 'and says it was not recognized' 'info  the repository of trellis was not recognized (node not found)' "$(out)"
ln -s "$NODE" "$tools/node"
printf '{"name": "another", "author": {"name": "x"}}\n' > .claude-plugin/plugin.json
tl_eq 'a project with another name asks for the plugin' '1' "$(doctor)"
rm -r .claude-plugin lib
mv "$TL_TMP/plugins.json" "$HOME/.claude/plugins/installed_plugins.json"
rm "$tools/node"
tl_eq 'node missing with hooks active fails' '1' "$(doctor)"
tl_has 'and says why' 'node not found while hooks are active' "$(out)"
ln -s "$NODE" "$tools/node"
git config --unset core.hooksPath
tl_eq 'core.hooksPath unset fails' '1' "$(doctor)"
git config core.hooksPath .githooks

printf '\nthe installed plugin against the pinned sha\n'
plugins="$HOME/.claude/plugins/installed_plugins.json"
cp "$plugins" "$TL_TMP/plugins.keep"
main_path="$(git rev-parse --show-toplevel)"
pin_settings() { mkdir -p .claude; printf '{"extraKnownMarketplaces": {"trellis": {"source": {"source": "github", "repo": "rologr35/trellis", "ref": "%s"}, "autoUpdate": false}}}\n' "$1" > .claude/settings.json; }
install_entry() { printf '{"plugins": {"trellis@trellis": [{"scope": "%s", "projectPath": "%s", "gitCommitSha": "%s"}]}}\n' "$1" "$2" "$3" > "$plugins"; }
long_a=0323c98aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
long_b=c6050747bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
pin_settings "$long_a"
install_entry project "$main_path" "$long_a"
doctor > /dev/null
tl_has 'an install at the pinned sha is ok' 'ok    plugin trellis is at the pinned sha 0323c98' "$(out)"
install_entry project "$main_path" "$long_b"
tl_eq 'a different sha is a warning, not a FAIL' '0' "$(doctor)"
tl_has 'showing both short shas' 'warn  plugin trellis is at c605074, the project pins 0323c98' "$(out)"
tl_has 'naming the marketplace command' 'claude plugin marketplace add rologr35/trellis@0323c98aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --scope project' "$(out)"
tl_has 'naming the update command' 'claude plugin update trellis@trellis --scope project' "$(out)"
tl_has 'and the restore of settings.json' 'git checkout -- .claude/settings.json' "$(out)"
install_entry project "$TL_TMP/elsewhere" "$long_b"
doctor > /dev/null
tl_lacks 'an entry of another project is not the one that applies' 'plugin trellis is at c605074' "$(out)"
tl_has 'so there is nothing to compare' 'info  plugin trellis: no install entry applies to this project' "$(out)"
install_entry user "" "$long_a"
doctor > /dev/null
tl_has 'a user-scope entry applies' 'ok    plugin trellis is at the pinned sha 0323c98' "$(out)"
install_entry project "$main_path" "$long_b"
git worktree add -q -b 5-wt "$TL_TMP/wt"
pin_settings "$long_a"
mkdir -p "$TL_TMP/wt/.claude"; cp .claude/settings.json "$TL_TMP/wt/.claude/settings.json"
(cd "$TL_TMP/wt" && PATH="$tools" bash "$TRELLIS_ROOT/scripts/doctor.sh" > "$TL_TMP/out.txt" 2>&1)
tl_has 'from a worktree, the entry is found by the main checkout path' 'warn  plugin trellis is at c605074, the project pins 0323c98' "$(out)"
git worktree remove --force "$TL_TMP/wt"
git branch -q -D 5-wt
install_entry project "$main_path" ""
doctor > /dev/null
tl_has 'an entry without gitCommitSha is info' 'info  plugin trellis: the install entry has no gitCommitSha' "$(out)"
install_entry project "$main_path" "$long_b"
rm -r .claude
doctor > /dev/null
tl_has 'with no pin, the line is info' 'info  plugin trellis: the project does not pin a sha' "$(out)"
tl_lacks 'and no warning' 'plugin trellis is at' "$(out)"
pin_settings "$long_a"
rm "$tools/node"
doctor > /dev/null
tl_has 'without node the check is skipped with info' 'info  plugin trellis: pinned sha not compared (node not found)' "$(out)"
ln -s "$NODE" "$tools/node"
rm -r .claude
cp "$TL_TMP/plugins.keep" "$plugins"

printf '\na copy in place of the plugin\n'
mv "$plugins" "$TL_TMP/plugins.json"
git add -A && git commit -q -m 'chore: start (#1)'
tl_copy "$(tl_upstream)"
tl_eq 'with a whole copy no plugin is asked for' '0' "$(doctor)"
tl_has 'and its version is said' "ok    verify: trellis $(cut -d' ' -f1 .trellis/VERSION)" "$(out)"
tl_lacks 'the plugin is not' 'plugin trellis' "$(out)"
printf '# x\n' >> .trellis/hooks/guard-git.sh
tl_eq 'an edited copy fails' '1' "$(doctor)"
tl_has 'naming the file' 'FAIL  .trellis/hooks/guard-git.sh: is not the file that was copied' "$(out)"
rm .trellis/hooks/guard-git.sh
tl_eq 'a guard that is missing fails' '1' "$(doctor)"
tl_has 'naming it' 'FAIL  .trellis/hooks/guard-git.sh: is in the manifest and is not there' "$(out)"
rm -r .trellis
tl_eq 'the copy gone with the settings that load it fails' '1' "$(doctor)"
tl_has 'naming the manifest' 'FAIL  .trellis/MANIFEST' "$(out)"
bash "$TRELLIS" update v1 >/dev/null 2>&1
enabled='warn  the plugin trellis is enabled too'
mkdir -p "$HOME/.claude"
printf '{"enabledPlugins": {"trellis@trellis": true}}\n' > "$HOME/.claude/settings.json"
tl_eq 'the plugin enabled for the user too is a warning' '0' "$(doctor)"
tl_has 'saying why' "$enabled" "$(out)"
printf '{"enabledPlugins": {"trellis@trellis": false}}\n' > .claude/settings.local.json
doctor > /dev/null
tl_lacks 'unless this checkout turns it off' "$enabled" "$(out)"
printf '{"enabledPlugins": {"other@trellis-like": true}}\n' > "$HOME/.claude/settings.json"
rm .claude/settings.local.json
doctor > /dev/null
tl_lacks 'another plugin is not trellis' "$enabled" "$(out)"
printf '{"enabledPlugins": {"trellis@trellis": true}}\n' > .claude/settings.local.json
doctor > /dev/null
tl_has 'enabled in the local settings' "$enabled" "$(out)"
rm .claude/settings.local.json "$HOME/.claude/settings.json"
node -e 'const fs = require("fs"); const f = ".claude/settings.json"; const s = JSON.parse(fs.readFileSync(f)); s.enabledPlugins = {"trellis@trellis": true}; fs.writeFileSync(f, JSON.stringify(s));'
doctor > /dev/null
tl_has 'or in the ones of the project' "$enabled" "$(out)"
rm "$tools/node"
tl_eq 'without node it fails' '1' "$(doctor)"
tl_has 'saying the copy was not verified' 'info  the copy was not verified (node not found)' "$(out)"
tl_has 'and that the hooks need it' 'node not found while hooks are active' "$(out)"
ln -s "$NODE" "$tools/node"
git reset -q --hard && git clean -qfd
mv "$TL_TMP/plugins.json" "$plugins"

printf '\na newer version\n'
mkdir .trellis && printf '0.8.0 0123456789012345678901234567890123456789\n' > .trellis/VERSION
doctor > /dev/null
tl_lacks 'nothing asked yet says nothing' 'is out' "$(out)"
printf 'v0.9.0\n' > .git/trellis-version
doctor > /dev/null
tl_has 'a newer one is a warning' 'warn  trellis 0.9.0 is out and this project has 0.8.0' "$(out)"
tl_eq 'and the doctor writes nothing' 'trellis-version' "$(ls .git | grep trellis)"
printf 'v0.8.0\n' > .git/trellis-version
doctor > /dev/null
tl_lacks 'an equal one is not' 'is out' "$(out)"
rm -r .trellis .git/trellis-version

printf '\nthe private names of a public project\n'
names="$HOME/.config/trellis/private-names"
tl_lacks 'a project that is not public has no section' 'private names' "$(doctor; out)"
git config -f trellis.config project.public true
tl_eq 'without a list it is a warning' '0' "$(doctor)"
tl_has '  that names it' "warn  no list of private names ($names)" "$(out)"
tl_has 'hooks that do not call it are another' 'warn  .githooks/pre-commit, commit-msg, pre-push do not call trellis private-names: take them again from templates/githooks/' "$(out)"
mkdir -p "$(dirname "$names")" && printf 'acme\n' > "$names"
mkdir -p .githooks && cp "$TRELLIS_ROOT"/templates/githooks/* .githooks/
doctor > /dev/null
tl_has 'with a list it is ok' 'ok    the list of private names is there' "$(out)"
tl_has '  and the hooks too' 'ok    the git hooks call trellis private-names' "$(out)"
for hook in pre-commit commit-msg pre-push; do
  sed 's/^\(.*"$trellis" private-names\)/# \1/' "$TRELLIS_ROOT/templates/githooks/$hook" > ".githooks/$hook"
  doctor > /dev/null
  tl_has "$hook with its call commented out is named" "warn  .githooks/$hook do not call trellis private-names" "$(out)"
  cp "$TRELLIS_ROOT/templates/githooks/$hook" .githooks/
done
rm "$names" && mkdir "$names"
tl_eq 'a list that cannot be read is a warning' '0' "$(doctor)"
tl_has '  that says so' 'cannot be read' "$(out)"
rmdir "$names"
rm "$tools/node"
doctor > /dev/null
tl_has 'without node the list is not read' 'info  the list of private names is not read (node not found)' "$(out)"
ln -s "$NODE" "$tools/node"
rm .githooks/*
git config -f trellis.config --unset project.public

printf '\ngit.hooksPath\n'
git config -f trellis.config git.hooksPath tool/hooks
tl_eq 'core.hooksPath out of it fails' '1' "$(doctor)"
tl_has 'naming both' 'core.hooksPath is .githooks, expected tool/hooks' "$(out)"
git config core.hooksPath tool/hooks
tl_eq 'and at it passes' '0' "$(doctor)"
tl_has 'saying which' 'git hooks installed (core.hooksPath = tool/hooks)' "$(out)"
git config core.hooksPath .githooks
git config -f trellis.config --unset git.hooksPath

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

printf '\nrungs that a pull request runs\n'
git config -f trellis.config command.unit.run 'flutter test --coverage'
git config -f trellis.config command.unit.ci 'flutter test --coverage --no-pub'
git config -f trellis.config rung.unit.command unit
tl_eq 'a rung with pr = true and no workflow passes with a warning' '0' "$(doctor)"
tl_has 'naming the rung and the command' 'rung unit has pr = true but no workflow under .github/workflows/ runs flutter test --coverage --no-pub' "$(out)"
mkdir -p .github/workflows
printf 'jobs:\n  t:\n    steps:\n      - run: flutter test --coverage\n' > .github/workflows/ci.yml
doctor > /dev/null
tl_has 'the run text is not the ci text, so it still warns' 'rung unit has pr = true but' "$(out)"
printf 'jobs:\n  t:\n    steps:\n      - run: flutter test --coverage --no-pub\n' > .github/workflows/ci.yml
doctor > /dev/null
tl_lacks 'a workflow naming the ci text does not warn' 'rung unit has pr = true but' "$(out)"
git config -f trellis.config --unset command.unit.ci
printf 'jobs:\n  t:\n    steps:\n      - run: flutter test --coverage\n' > .github/workflows/ci.yml
doctor > /dev/null
tl_lacks 'a workflow naming the run text does not warn' 'rung unit has pr = true but' "$(out)"
rm .github/workflows/ci.yml
git config -f trellis.config rung.unit.pr false
doctor > /dev/null
tl_lacks 'a rung with pr = false is not asked for a workflow' 'rung unit has pr = true but' "$(out)"
git config -f trellis.config --remove-section rung.unit
git config -f trellis.config --remove-section command.unit
rm -rf .github

printf '\nthe close of a merged issue\n'
CLOSED='does not name consumer-closed.yml'
doctor > /dev/null
tl_lacks 'a project without the workflow is not asked' "$CLOSED" "$(out)"
mkdir -p .github/workflows
printf 'jobs:\n  trellis:\n    uses: x/y/.github/workflows/consumer-check.yml@1\n' > .github/workflows/trellis.yml
tl_eq 'a caller that only checks passes with a warning' '0' "$(doctor)"
tl_has 'naming what is missing' "$CLOSED" "$(out)"
git config -f trellis.config tracker.kind none
doctor > /dev/null
tl_lacks 'without a tracker it is not asked' "$CLOSED" "$(out)"
git config -f trellis.config --unset tracker.kind
printf '  closed:\n    uses: x/y/.github/workflows/consumer-closed.yml@1\n' >> .github/workflows/trellis.yml
doctor > /dev/null
tl_lacks 'a caller of both does not warn' "$CLOSED" "$(out)"
rm -rf .github

git config -f trellis.config rung.ghost.command nowhere
doctor > /dev/null
tl_lacks 'a pr = true rung with no command text is not "no rung with pr = true"' 'no rung with pr = true' "$(out)"
tl_has 'and is said to have nothing to look for' 'rung ghost has pr = true but its command has no text to look for' "$(out)"
git config -f trellis.config --remove-section rung.ghost

printf '\nbranch\n'

git switch -q -c feature/x
tl_eq 'a branch out of the shapes fails' '1' "$(doctor)"
git switch -q -c 3-thing
tl_eq 'an issue branch passes' '0' "$(doctor)"

tl_done
