#!/usr/bin/env bash
# Exercises scripts/sync.sh: the blocks of CLAUDE.md and TESTING.md, the deny of settings.json and
# the copy of find-trellis.sh.
. "$(dirname "$0")/../lib/testlib.sh"

repo="$(tl_repo)"
cd "$repo" || exit 1
mkdir -p app .claude/rules .githooks
printf '# App package\n' > app/CLAUDE.md
printf -- '---\npaths:\n  - "app/lib/**/*.dart"\n---\n\n# Widgets\n' > .claude/rules/widgets.md
cat > trellis.config <<'CFG'
[git]
	protected = main
	protected = staging
[command "analyze"]
	run = flutter analyze
	description = The static analysis.
[command "golden"]
	run = flutter test --tags golden
[command]
	check = analyze
[rung "golden"]
	command = golden
	agent = false
	pr = false
	proves = The screenshots.
	offUntil = 2027-01-15
[gate "payments"]
	paths = app/lib/payments/**
	reason = moves money
CFG
cat > CLAUDE.md <<'MD'
# Project

<!-- trellis:method -->
<!-- /trellis:method -->

<!-- trellis:orientation -->
stale
<!-- /trellis:orientation -->

<!-- trellis:commands -->
<!-- /trellis:commands -->

<!-- trellis:gates -->
<!-- /trellis:gates -->

Hand-written text stays.
MD
printf '# Testing\n\n<!-- trellis:rungs -->\n<!-- /trellis:rungs -->\n' > TESTING.md
printf '{\n  "permissions": {\n    "deny": ["Bash(rm -rf *)", "Bash(git push * develop)"]\n  }\n}\n' > .claude/settings.json

out="$("$TRELLIS" sync 2>&1)"
tl_eq 'sync exits 0' '0' "$?"
claude_md="$(cat CLAUDE.md)"
tl_has 'orientation lists the nested file' '| `app/CLAUDE.md` | when a file under `app/` is read | App package |' "$claude_md"
tl_has 'orientation lists the rule with its globs' '| `.claude/rules/widgets.md` | `app/lib/**/*.dart` | Widgets |' "$claude_md"
tl_lacks 'the stale content is gone' 'stale' "$claude_md"
tl_has 'commands lists check' '`trellis check` runs, in order: `analyze`.' "$claude_md"
tl_has 'commands lists a command' '- `analyze`: `flutter analyze`. The static analysis.' "$claude_md"
tl_has 'gates' '- **payments** (`app/lib/payments/**`): moves money' "$claude_md"
tl_has 'the method of the default locale, en' '## Working method' "$claude_md"
tl_lacks 'without the principle ids' '<!-- p:' "$claude_md"
tl_has 'hand-written text stays' 'Hand-written text stays.' "$claude_md"
tl_has 'rungs table' '| golden | `flutter test --tags golden` | no | no | The screenshots. | 2027-01-15 |' "$(cat TESTING.md)"
deny="$(node -e 'console.log(require("./.claude/settings.json").permissions.deny.join("\n"))')"
tl_has 'the deny keeps what a person wrote' 'Bash(rm -rf *)' "$deny"
tl_has 'the deny of a rung Claude must not run' 'Bash(flutter test --tags golden*)' "$deny"
tl_has 'the deny of a push to a protected branch' 'Bash(git push *:staging)' "$deny"
tl_has 'the deny of a forced push' 'Bash(git push * +main)' "$deny"
tl_has 'the deny of a full ref' 'Bash(git push * refs/heads/main)' "$deny"
tl_has 'the deny of a push with -C' 'Bash(git -C * push * main)' "$deny"
for tool in merge_pull_request enable_pr_auto_merge push_files create_or_update_file delete_file; do
  tl_has "the deny of the GitHub tool $tool" "mcp__github__$tool" "$deny"
done
tl_eq 'and of no other one' '5' "$(printf '%s\n' "$deny" | grep -c '^mcp__')"
tl_lacks 'a branch no longer protected loses its push deny' 'develop' "$deny"
tl_eq 'the copy of find-trellis.sh' "$(cat "$TRELLIS_ROOT/lib/find-trellis.sh")" "$(cat .githooks/find-trellis.sh)"

out="$("$TRELLIS" sync 2>&1)"
tl_eq 'a second run changes nothing' 'sync: nothing to change' "$out"

git config -f trellis.config project.locale es
"$TRELLIS" sync >/dev/null 2>&1
claude_md="$(cat CLAUDE.md)"
tl_has 'with locale es, the es method' '## Método de trabajo' "$claude_md"
tl_has 'and the es labels' '| `app/CLAUDE.md` | al leer un fichero de `app/` | App package |' "$claude_md"
tl_has 'and the es rungs table' '| Escalón | Comando | Lo corre Claude |' "$(cat TESTING.md)"

printf '\nwith a copy\n'
node -e '
  const fs = require("fs");
  const s = JSON.parse(fs.readFileSync(".claude/settings.json", "utf8"));
  s.model = "sonnet";
  s.hooks = {PostToolUse: [{matcher: "Edit", hooks: [{type: "command", command: "fmt"}]}], PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "own"}]}]};
  fs.writeFileSync(".claude/settings.json", JSON.stringify(s, null, 2) + "\n");
'
before="$(cat .claude/settings.json)"
"$TRELLIS" sync >/dev/null 2>&1
tl_eq 'without one no hook is written' "$before" "$(cat .claude/settings.json)"
mkdir -p .trellis && printf '0.6.0 0123456789012345678901234567890123456789\n' > .trellis/VERSION
"$TRELLIS" sync >/dev/null 2>&1
at() { node -p "const s = require('$repo/.claude/settings.json'); JSON.stringify($1)"; }
tl_eq 'the guard is a hook of Bash' '[{"matcher":"Bash","hooks":[{"type":"command","command":"own"}]},{"matcher":"Bash","hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/.trellis/hooks/guard-git.sh"}]}]' "$(at s.hooks.PreToolUse)"
tl_eq 'setup is the one of the session start' '[{"hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/.trellis/bin/trellis setup --quiet"}]}]' "$(at s.hooks.SessionStart)"
tl_eq 'another hook of the project stays' '[{"matcher":"Edit","hooks":[{"type":"command","command":"fmt"}]}]' "$(at s.hooks.PostToolUse)"
tl_eq 'and another key' '"sonnet"' "$(at s.model)"
tl_has 'the copy is not edited' '"Edit(/.trellis/**)"' "$(at s.permissions.deny)"
tl_eq 'a second run changes nothing' 'sync: nothing to change' "$("$TRELLIS" sync 2>&1)"
node -e '
  const fs = require("fs");
  const s = JSON.parse(fs.readFileSync(".claude/settings.json", "utf8"));
  s.hooks.PreToolUse[1].hooks[0].async = true;
  fs.writeFileSync(".claude/settings.json", JSON.stringify(s, null, 2) + "\n");
'
"$TRELLIS" sync >/dev/null 2>&1
tl_eq 'a guard that does not wait does not stand for the guard' '3' "$(at s.hooks.PreToolUse.length)"
rm .claude/settings.json
"$TRELLIS" sync >/dev/null 2>&1
tl_eq 'the settings are written when there are none' '1' "$(at s.hooks.PreToolUse.length)"

printf '\nthe repository of trellis\n'
own="$(tl_upstream)"
cd "$own" || exit 1
sync() { bash "$own/bin/trellis" sync > "$TL_TMP/out.txt" 2>&1; echo $?; }
rm -rf .claude/skills .claude/agents
tl_eq 'its sync exits 0' '0' "$(sync)"
tl_eq 'the skills, all but init' 'trellis-debugging trellis-merge trellis-retro trellis-scaffold trellis-work' "$(ls .claude/skills 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
tl_eq 'the agents' 'trellis-plan-check.md trellis-plan-reviewer.md' "$(ls .claude/agents 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
tl_eq 'a skill carries the name of its folder' 'name: trellis-retro' "$(sed -n 2p .claude/skills/trellis-retro/SKILL.md)"
tl_eq 'and the rest of the source' "$(sed -n '3,$p' skills/retro/SKILL.md)" "$(sed -n '3,$p' .claude/skills/trellis-retro/SKILL.md)"
tl_eq 'as the copy of a project has it' '0' "$(cd "$(tl_repo)" && tl_copy "$own" && cmp -s .claude/skills/trellis-retro/SKILL.md "$own/.claude/skills/trellis-retro/SKILL.md"; echo $?)"
tl_eq 'a second run changes nothing' '0' "$(sync)"
tl_has 'and says it' 'nothing to change' "$(cat "$TL_TMP/out.txt")"
mkdir -p .claude/skills/trellis-gone .claude/skills/own
printf '# Gone\n' | tee .claude/skills/trellis-gone/SKILL.md > .claude/agents/trellis-gone.md
printf '# Own\n' | tee .claude/skills/own/SKILL.md > .claude/agents/own.md
printf 'by hand\n' >> .claude/agents/trellis-plan-check.md
git add -A && git commit -q --no-verify -m 'chore: by hand (#1)'
tl_eq 'the ones with no source' '0' "$(sync)"
tl_has 'are removed, and named' 'sync: removed .claude/skills/trellis-gone/SKILL.md' "$(cat "$TL_TMP/out.txt")"
tl_eq 'with their folder' 'no no' "$([ -e .claude/skills/trellis-gone ] && echo yes || echo no) $([ -e .claude/agents/trellis-gone.md ] && echo yes || echo no)"
tl_eq 'one edited by hand is written again' "$(sed -n '3,$p' agents/plan-check.md)" "$(sed -n '3,$p' .claude/agents/trellis-plan-check.md)"
tl_eq 'the ones without the prefix stay' '# Own# Own' "$(cat .claude/skills/own/SKILL.md)$(cat .claude/agents/own.md)"
mkdir -p .claude/skills/trellis-draft
printf '# Draft\n' | tee .claude/skills/trellis-draft/SKILL.md > .claude/agents/trellis-draft.md
git add .claude/agents/trellis-draft.md && git commit -q --no-verify -m 'chore: a draft (#1)'
printf 'a line more\n' >> .claude/agents/trellis-draft.md
tl_eq 'a left over one git cannot give back' '0' "$(sync)"
tl_eq 'stays when it is untracked' '# Draft' "$(cat .claude/skills/trellis-draft/SKILL.md 2>/dev/null)"
tl_has 'and says why' 'sync: kept .claude/skills/trellis-draft/SKILL.md, which has no source: it is not tracked' "$(cat "$TL_TMP/out.txt")"
tl_eq 'and when it is modified' 'a line more' "$(tail -1 .claude/agents/trellis-draft.md 2>/dev/null)"
tl_has 'and says why, too' 'sync: kept .claude/agents/trellis-draft.md, which has no source: it has changes that are not in the index' "$(cat "$TL_TMP/out.txt")"
tl_lacks 'and there was something to say' 'nothing to change' "$(cat "$TL_TMP/out.txt")"
git add -A
tl_eq 'once git can give them back' '0' "$(sync)"
tl_eq 'they go' 'no no' "$([ -e .claude/skills/trellis-draft ] && echo yes || echo no) $([ -e .claude/agents/trellis-draft.md ] && echo yes || echo no)"
git add -A && git commit -q --no-verify -m 'chore: no draft (#1)'
rm .claude/agents/trellis-plan-check.md && ln -s ../../agents/plan-check.md .claude/agents/trellis-plan-check.md
tl_eq 'a symbolic link to a source' '0' "$(sync)"
tl_eq 'is replaced, and the source stays' 'name: plan-check name: trellis-plan-check' "$(sed -n 2p agents/plan-check.md) $(sed -n 2p .claude/agents/trellis-plan-check.md)"
rm -rf .claude/skills/trellis-work && ln -s ../../skills/work .claude/skills/trellis-work
tl_eq 'a folder linked to the one of a source' '0' "$(sync)"
tl_eq 'too' 'name: work name: trellis-work' "$(sed -n 2p skills/work/SKILL.md) $(sed -n 2p .claude/skills/trellis-work/SKILL.md)"
git add -A && git commit -q --no-verify -m 'chore: generated (#1)'
# On a disk that ignores the case, the same folder under another one is the same checkout.
other="$(dirname "$own")/$(basename "$own" | tr '[:lower:][:upper:]' '[:upper:][:lower:]')"
if [ "$other" -ef "$own" ]; then
  tl_eq 'its path in another case is the same checkout' '0' "$(cd "$other" && bash "$other/bin/trellis" sync > "$TL_TMP/out.txt" 2>&1; echo $?)"
fi
tl_eq 'the sync of another checkout refuses' '1' "$(cd lib && bash "$TRELLIS" sync > "$TL_TMP/out.txt" 2>&1; echo $?)"
tl_has 'and says which to run' 'run bin/trellis' "$(cat "$TL_TMP/out.txt")"
tl_eq 'with nothing written' '' "$(git status --porcelain)"
git worktree add -q "$TL_TMP/wt" -b 2-wt
tl_eq 'the one of the main checkout, in a worktree, too' '1' "$(cd "$TL_TMP/wt" && bash "$own/bin/trellis" sync > "$TL_TMP/out.txt" 2>&1; echo $?)"
tl_eq 'and the one of the worktree runs' '0' "$(cd "$TL_TMP/wt" && bash bin/trellis sync > "$TL_TMP/out.txt" 2>&1; echo $?)"

tl_done
