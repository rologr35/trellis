#!/usr/bin/env bash
# Exercises scripts/update.sh against a local upstream: the first copy, an upgrade, what stops it,
# the refs it takes, and that no test is copied.
. "$(dirname "$0")/../lib/testlib.sh"

upstream="$(tl_upstream)"
up() { git -C "$upstream" "$@"; }
sha1="$(up rev-parse HEAD)"

repo="$(tl_repo)"
cd "$repo" || exit 1
git config -f trellis.config trellis.upstream "$upstream"
git config -f trellis.config tracker.kind none
mkdir -p .claude/skills/trellis-own .claude/agents
printf '# Own\n' > .claude/skills/trellis-own/SKILL.md
printf '# Project\n\n<!-- trellis:method -->\n<!-- /trellis:method -->\n' > CLAUDE.md
git add -A && git commit -q -m 'chore: setup (#1)'

OUT="$TL_TMP/out.txt"
update() { bash "$TRELLIS" update "$@" > "$OUT" 2>&1; echo $?; }
out() { cat "$OUT"; }
sha_of() { node -e 'process.stdout.write(require("crypto").createHash("sha256").update(require("fs").readFileSync(process.argv[1])).digest("hex"))' "$1"; }
tracked() { git status --porcelain -uall; }

printf '\nrefs\n'
tl_eq 'no ref is a usage error' '2' "$(update)"
tl_eq 'an unknown ref is refused' '1' "$(update v9)"
tl_has 'and named' 'v9' "$(out)"
tl_eq 'a branch is not a pin' '1' "$(update main)"
tl_eq 'an unknown sha is refused' '1' "$(update 0123456789012345678901234567890123456789)"
tl_eq 'nothing was written' '' "$(tracked)"
git config -f trellis.config trellis.upstream "$TL_TMP/nowhere"
tl_eq 'an upstream that does not answer is refused' '1' "$(update v1)"
git config -f trellis.config trellis.upstream "$upstream"

printf '\nfirst copy\n'
tl_eq 'a tag is copied' '0' "$(update v1)"
tl_eq 'VERSION holds the version and the full sha' "$(node -p "require('$TRELLIS_ROOT/.claude-plugin/plugin.json').version") $sha1" "$(cat .trellis/VERSION)"
for f in bin/trellis hooks/guard-git.sh lib/schema scripts/update.sh hygiene/hygiene.mjs method/es.md templates/en/issue.md templates/githooks/pre-commit LICENSE; do
  tl_eq "$f is the upstream's" "$(sha_of "$upstream/$f")" "$(sha_of ".trellis/$f")"
done
tl_eq 'bin/trellis can be executed' 'yes' "$([ -x .trellis/bin/trellis ] && echo yes)"
tl_eq 'no test is copied' '' "$(find .trellis -name '*.test.*' -o -name 'testlib.sh')"
tl_eq 'nor hooks.json' '' "$(find .trellis -name hooks.json)"
tl_eq 'nor what is not runtime' 'LICENSE MANIFEST VERSION bin hooks hygiene lib method scripts templates' "$(ls .trellis | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
tl_eq 'the skills, all but init' 'trellis-debugging trellis-merge trellis-own trellis-retro trellis-scaffold' "$(ls .claude/skills | tr '\n' ' ' | sed 's/ $//')"
tl_eq 'the agents' 'trellis-plan-check.md trellis-plan-reviewer.md' "$(ls .claude/agents | tr '\n' ' ' | sed 's/ $//')"
tl_eq 'a skill carries the name of its folder' 'name: trellis-retro' "$(sed -n 2p .claude/skills/trellis-retro/SKILL.md)"
tl_eq 'and the rest of the source' "$(sed -n '3,$p' "$upstream/skills/retro/SKILL.md")" "$(sed -n '3,$p' .claude/skills/trellis-retro/SKILL.md)"
tl_eq 'an agent carries the name of its file' 'name: trellis-plan-reviewer' "$(sed -n 2p .claude/agents/trellis-plan-reviewer.md)"
listed="$(sed 's/^[0-9a-f]*  //' .trellis/MANIFEST)"
tl_eq 'the manifest lists every file written' "$( (find .trellis -type f; find .claude/skills .claude/agents -type f) | grep -v -e MANIFEST -e trellis-own | LC_ALL=C sort)" "$(printf '%s\n' "$listed" | LC_ALL=C sort)"
tl_eq 'with its sha256' "$(sha_of .trellis/lib/schema)  .trellis/lib/schema" "$(grep '/lib/schema$' .trellis/MANIFEST)"
tl_has 'it ends with sync, run from the new copy' '## Working method' "$(cat CLAUDE.md)"
tl_eq 'the copy runs' 'main' "$(.trellis/bin/trellis config get git.releaseBranch)"
tl_has 'a skill of the project is left as it is' '# Own' "$(cat .claude/skills/trellis-own/SKILL.md)"
git add -A && git commit -q -m 'chore: the copy (#1)'
tl_eq 'the same ref again changes nothing' '0' "$(update "$sha1")"
tl_eq 'not a file' '' "$(tracked)"
tl_eq 'a short sha is resolved' '0' "$(update "$(printf '%.10s' "$sha1")")"
tl_has 'to the full one' "$sha1" "$(cat .trellis/VERSION)"

printf '\nupgrade\n'
up rm -q lib/style.mjs skills/debugging/SKILL.md
printf 'new\n' > "$upstream/lib/new.txt"
printf '\n' >> "$upstream/lib/schema"
up add -A && up commit -q -m 'chore: second (#1)'
up tag -a v2 -m v2
sha2="$(up rev-parse HEAD)"
tl_eq 'an annotated tag, run by the copy itself' '0' "$(bash .trellis/bin/trellis update v2 > "$OUT" 2>&1; echo $?)"
tl_has 'is its commit' "$sha2" "$(cat .trellis/VERSION)"
tl_eq 'a file gone upstream is removed' 'no' "$([ -e .trellis/lib/style.mjs ] && echo yes || echo no)"
tl_eq 'a skill gone upstream too, with its folder' 'no' "$([ -e .claude/skills/trellis-debugging ] && echo yes || echo no)"
tl_eq 'a new file is written' 'new' "$(cat .trellis/lib/new.txt)"
tl_eq 'a changed one is changed' "$(sha_of "$upstream/lib/schema")" "$(sha_of .trellis/lib/schema)"
tl_eq 'the skill of the project stays' 'yes' "$([ -f .claude/skills/trellis-own/SKILL.md ] && echo yes)"
git add -A && git commit -q -m 'chore: upgrade (#1)'

printf '\na copy edited by hand\n'
restore() { git reset -q --hard && git clean -qfd; }
printf '# edit\n' >> .trellis/hooks/guard-git.sh
printf 'x\n' >> .claude/agents/trellis-plan-check.md
before="$(tracked)"
tl_eq 'stops the update' '1' "$(update v1)"
tl_has 'naming the file' '.trellis/hooks/guard-git.sh' "$(out)"
tl_has 'and the copied agent' '.claude/agents/trellis-plan-check.md' "$(out)"
tl_eq 'and nothing else changes' "$before" "$(tracked)"
restore
rm .trellis/lib/schema
tl_eq 'a missing file stops it' '1' "$(update v1)"
restore
printf 'x\n' > .trellis/lib/extra.sh
tl_eq 'an extra file stops it' '1' "$(update v1)"
restore
rm .trellis/MANIFEST
tl_eq 'a copy without its manifest stops it' '1' "$(update v1)"
restore
printf '%s  CLAUDE.md\n' "$(sha_of CLAUDE.md)" >> .trellis/MANIFEST
tl_eq 'a manifest naming a file that is not of a copy stops it' '1' "$(update v1)"
tl_eq 'and that file is not removed' 'yes' "$([ -f CLAUDE.md ] && echo yes)"
restore

printf '\nwhat is in the way\n'
git rm -rq .trellis .claude/skills/trellis-merge .claude/skills/trellis-retro .claude/skills/trellis-scaffold .claude/agents && git commit -q -m 'chore: no copy (#1)'
mkdir -p .claude/skills/trellis-merge && printf '# Mine\n' > .claude/skills/trellis-merge/SKILL.md
tl_eq 'a file of the project with the name of a copied one stops it' '1' "$(update v2)"
tl_has 'naming it' '.claude/skills/trellis-merge/SKILL.md' "$(out)"
tl_eq 'the file stays' '# Mine' "$(cat .claude/skills/trellis-merge/SKILL.md)"
restore
printf 'bin/\n' > .gitignore
tl_eq 'a copy git would ignore stops it' '1' "$(update v2)"
tl_has 'naming a file' '.trellis/bin/trellis' "$(out)"
tl_eq 'and writes nothing' 'no' "$([ -e .trellis ] && echo yes || echo no)"
rm .gitignore
mkdir "$TL_TMP/outside" && ln -s "$TL_TMP/outside" .trellis
tl_eq 'a symbolic link on the way stops it' '1' "$(update v2)"
tl_eq 'and nothing is written through it' '' "$(ls "$TL_TMP/outside")"
rm .trellis
tl_eq 'with the way clear it is written' '0' "$(update v2)"

printf '\na ref without the copy\n'
up rm -q lib/copy.mjs && up commit -q -m 'chore: before the copy (#1)' && up tag v0
tl_eq 'a version that cannot be copied is refused' '1' "$(update v0)"
tl_has 'and why' 'v0' "$(out)"

tl_done
