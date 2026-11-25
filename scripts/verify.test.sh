#!/usr/bin/env bash
# Exercises scripts/verify.mjs on a project with a copy: what makes it whole, the index, and the
# comparison with the upstream that an edited manifest does not pass.
. "$(dirname "$0")/../lib/testlib.sh"

upstream="$(tl_upstream)"
up() { git -C "$upstream" "$@"; }

repo="$(tl_repo)"
cd "$repo" || exit 1
git config -f trellis.config trellis.upstream "$upstream"
git add -A && git commit -q -m 'chore: setup (#1)'

OUT="$TL_TMP/out.txt"
verify() { bash "$TRELLIS" verify "$@" > "$OUT" 2>&1; echo $?; }
out() { cat "$OUT"; }
restore() { git reset -q --hard && git clean -qfdx; }
sha_of() { node -e 'process.stdout.write(require("crypto").createHash("sha256").update(require("fs").readFileSync(process.argv[1])).digest("hex"))' "$1"; }
# The manifest as somebody hiding an edit would leave it.
rehash() { sed "s|^[0-9a-f]*  $1\$|$(sha_of "$1")  $1|" .trellis/MANIFEST > "$TL_TMP/m" && cp "$TL_TMP/m" .trellis/MANIFEST; }

printf '\nwithout a copy\n'
tl_eq 'a project without a copy fails' '1' "$(verify)"
tl_has 'and says what writes it' 'trellis update' "$(out)"

tl_copy "$upstream" && git add -A && git commit -q -m 'chore: the copy (#1)'

printf '\na whole copy\n'
tl_eq 'passes' '0' "$(verify)"
tl_has 'and says which' "$(cut -d' ' -f1 .trellis/VERSION)" "$(out)"
tl_eq 'passes against the upstream' '0' "$(verify --upstream)"
tl_eq 'passes staged' '0' "$(verify --staged)"
tl_eq 'an unknown option is a usage error' '2' "$(verify --nope)"
tl_eq 'run by the copy' '0' "$(.trellis/bin/trellis verify > "$OUT" 2>&1; echo $?)"

sha="$(cut -d' ' -f2 .trellis/VERSION)"
tl_eq 'passes when the sha expected is its own' '0' "$(verify --ref "$sha")"
tl_eq 'fails with any other' '1' "$(verify --ref 0123456789012345678901234567890123456789)"
tl_has 'naming both' "$sha" "$(out)"
tl_eq 'a short one is another' '1' "$(verify --ref "$(printf '%.10s' "$sha")")"
tl_eq 'none is a usage error' '2' "$(verify --ref)"
tl_eq 'empty too' '2' "$(verify --ref '')"

printf '\na copy that is not\n'
printf '# x\n' >> .trellis/hooks/guard-git.sh
tl_eq 'a changed file fails' '1' "$(verify)"
tl_has 'named' '.trellis/hooks/guard-git.sh' "$(out)"
tl_eq 'what is staged is still whole' '0' "$(verify --staged)"
git add -A
tl_eq 'and fails once staged' '1' "$(verify --staged)"
git show HEAD:.trellis/hooks/guard-git.sh > .trellis/hooks/guard-git.sh
tl_eq 'the working tree does not stand for the index' '1' "$(verify --staged)"
restore
printf 'x\n' >> .claude/skills/trellis-retro/SKILL.md
tl_eq 'a changed skill fails' '1' "$(verify)"
tl_has 'named' '.claude/skills/trellis-retro/SKILL.md' "$(out)"
restore
rm .claude/agents/trellis-plan-check.md
tl_eq 'a missing file fails' '1' "$(verify)"
tl_has 'named' '.claude/agents/trellis-plan-check.md' "$(out)"
restore
printf 'x\n' > .trellis/lib/extra.sh
tl_eq 'an extra file fails' '1' "$(verify)"
tl_has 'named' '.trellis/lib/extra.sh' "$(out)"
restore
cp .trellis/lib/schema "$TL_TMP/schema" && ln -sf "$TL_TMP/schema" .trellis/lib/schema
tl_eq 'a symbolic link with the same content fails' '1' "$(verify)"
git add -A
tl_eq 'staged too' '1' "$(verify --staged)"
restore
cp -R .trellis/lib "$TL_TMP/lib" && rm -rf .trellis/lib && ln -s "$TL_TMP/lib" .trellis/lib
tl_eq 'a linked folder fails' '1' "$(verify)"
restore
printf '0.0.0 main\n' > .trellis/VERSION; rehash .trellis/VERSION
tl_eq 'a VERSION without a sha fails' '1' "$(verify)"
restore
grep -v '  .trellis/VERSION$' .trellis/MANIFEST > "$TL_TMP/m"; cp "$TL_TMP/m" .trellis/MANIFEST
tl_eq 'a manifest without VERSION fails' '1' "$(verify)"
restore
printf '%s  trellis.config\n' "$(sha_of trellis.config)" >> .trellis/MANIFEST
tl_eq 'a manifest that names a file of the project fails' '1' "$(verify)"
restore
printf '%s  .trellis/../trellis.config\n' "$(sha_of trellis.config)" >> .trellis/MANIFEST
tl_eq 'by any spelling' '1' "$(verify)"
restore
rm .trellis/MANIFEST
tl_eq 'a copy without its manifest fails' '1' "$(verify)"
restore

printf '\nwhat the project does without: copy.without (#48)\n'
left='.claude/skills/trellis-work/SKILL.md: is in the manifest, and copy.without leaves it out: trellis update'
git config -f trellis.config --add copy.without trellis-work
git config -f trellis.config --add copy.without trellis-plan-check
tl_eq 'a manifest that lists what is left out fails' '1' "$(verify)"
tl_has 'naming the skill, and trellis update with the sha of VERSION' "$left $sha" "$(out)"
tl_has 'and the agent' '.claude/agents/trellis-plan-check.md: is in the manifest, and copy.without' "$(out)"
tl_has 'and nothing else' 'verify: 2 finding(s)' "$(out)"
tl_eq 'the index without the key passes' '0' "$(verify --staged)"
tl_lacks 'and the hygiene says nothing of it' 'copy.without' "$(bash "$TRELLIS" hygiene 2>&1)"
git add trellis.config && git show HEAD:trellis.config > trellis.config
tl_eq 'the index with the key and the working tree without it: staged fails' '1' "$(verify --staged)"
tl_has 'naming the skill' "$left" "$(out)"
tl_eq 'and the working tree passes' '0' "$(verify)"
git rm -qf --cached trellis.config
git config -f trellis.config copy.without trellis-work
tl_eq 'an index without a config has no key' '0' "$(verify --staged)"
restore
git config -f trellis.config copy.without trellis-nope
tl_eq 'a name nothing has passes without the upstream' '0' "$(verify)"
tl_eq 'and fails against it' '1' "$(verify --upstream)"
tl_has 'naming it' 'copy.without names trellis-nope, which is no skill or agent' "$(out)"
tl_has 'and the ones there are' 'trellis-scaffold, trellis-work' "$(out)"
restore
git config -f trellis.config copy.without trellis-work
rm -r .claude/skills/trellis-work; grep -v '/trellis-work/' .trellis/MANIFEST > "$TL_TMP/m"; cp "$TL_TMP/m" .trellis/MANIFEST
tl_eq 'a copy without what is left out passes' '0' "$(verify --upstream)"
git config -f trellis.config --unset copy.without
tl_eq 'and fails against the upstream without the key' '1' "$(verify --upstream)"
tl_has 'naming it' '.claude/skills/trellis-work/SKILL.md: is not the one of' "$(out)"
restore

printf '\nagainst the upstream\n'
printf '# x\n' >> .trellis/hooks/guard-git.sh; rehash .trellis/hooks/guard-git.sh
tl_eq 'a file and its line of the manifest pass locally' '0' "$(verify)"
tl_eq 'and fail against the upstream' '1' "$(verify --upstream)"
tl_has 'naming the file' '.trellis/hooks/guard-git.sh' "$(out)"
restore
rm .trellis/hooks/guard-git.sh; grep -v 'hooks/guard-git.sh$' .trellis/MANIFEST > "$TL_TMP/m"; cp "$TL_TMP/m" .trellis/MANIFEST
tl_eq 'a file taken out of both passes locally' '0' "$(verify)"
tl_eq 'and fails against the upstream' '1' "$(verify --upstream)"
restore
mkdir -p .claude/skills/trellis-mine; printf '# Mine\n' > .claude/skills/trellis-mine/SKILL.md
printf '%s  .claude/skills/trellis-mine/SKILL.md\n' "$(sha_of .claude/skills/trellis-mine/SKILL.md)" >> .trellis/MANIFEST
tl_eq 'a skill of the project in the manifest passes locally' '0' "$(verify)"
tl_eq 'and fails against the upstream' '1' "$(verify --upstream)"
tl_has 'naming it' 'trellis-mine' "$(out)"
restore
mode="$(git ls-files -s .trellis/bin/trellis | cut -c1-6)"
tl_eq 'the command is committed as executable' '100755' "$mode"
printf '%s %s\n' "$(cut -d' ' -f1 .trellis/VERSION)" 0123456789012345678901234567890123456789 > .trellis/VERSION; rehash .trellis/VERSION
tl_eq 'a sha the upstream does not have fails' '1' "$(verify --upstream)"
restore
printf '9.9.9 %s\n' "$(cut -d' ' -f2 .trellis/VERSION)" > .trellis/VERSION; rehash .trellis/VERSION
tl_eq 'another version of the same sha fails' '1' "$(verify --upstream)"
restore
printf 'x\n' >> "$upstream/README.md"; printf '\n' >> "$upstream/lib/schema"; up commit -qam 'chore: second (#1)'
tl_eq 'the upstream moving on changes nothing' '0' "$(verify --upstream)"
sha1="$(cut -d' ' -f2 .trellis/VERSION)"
up update-ref "refs/tags/$sha1" HEAD
tl_eq 'nor does a tag with the name of the sha' '0' "$(verify --upstream)"
git config -f trellis.config trellis.upstream "$TL_TMP/nowhere"
tl_eq 'an upstream that does not answer fails' '1' "$(verify --upstream)"

tl_done
