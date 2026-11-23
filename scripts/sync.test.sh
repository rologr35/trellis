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

tl_done
