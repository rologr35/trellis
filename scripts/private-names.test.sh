#!/usr/bin/env bash
# Exercises scripts/private-names.sh: the list of the machine, the spellings of a term, what is judged
# of the index, a file and a text, and the terms of a project that lib/private-names.mjs reads.
. "$(dirname "$0")/../lib/testlib.sh"

repo="$(tl_repo)"
cd "$repo" || exit 1
git switch -q -c 12-thing
list="$HOME/.config/trellis/private-names"
mkdir -p "$(dirname "$list")"
printf '[project]\n\tpublic = true\n' > trellis.config

names() { bash "$TRELLIS" private-names "$@" > "$TL_TMP/out.txt" 2>&1; echo $?; }
out() { cat "$TL_TMP/out.txt"; }
text() { names --text "$1"; }

printf '\nthe list\n'
tl_eq 'without a list it passes' '0' "$(text 'of acme')"
tl_has '  and says so' "no list of private names ($list): nothing was judged" "$(out)"
printf '# only a comment\n\n  # another\n---\n' > "$list"
tl_eq 'one that names nothing is none' '0' "$(text 'only a comment')"
tl_has '  and it says so' 'no list of private names' "$(out)"
printf '# clients\r\n\nacme   # the first one\n\tZephyr Cloud \nC#-tools\n' > "$list"
tl_eq 'a term of the list is refused' '1' "$(text 'a word
of acme here')"
tl_has '  naming it and its line' 'the text, line 2: "acme" is in the list of private names of this machine' "$(out)"
tl_eq 'a comment is not a term' '0' "$(text 'clients, the first one')"
tl_eq 'a term with # in it is one' '1' "$(text 'the C#-tools')"
tl_eq 'a text with none passes' '0' "$(text 'a word of nobody')"
tl_eq '  and prints nothing' '' "$(out)"
printf '\357\273\277zephyr\n' > "$TL_TMP/bom"
mkdir -p "$TL_TMP/xdg/trellis" && cp "$TL_TMP/bom" "$TL_TMP/xdg/trellis/private-names"
tl_eq 'the one of XDG_CONFIG_HOME, with its mark of UTF-8' '1' "$(XDG_CONFIG_HOME="$TL_TMP/xdg" names --text zephyr)"
tl_eq '  in place of the one of HOME' '0' "$(XDG_CONFIG_HOME="$TL_TMP/xdg" names --text acme)"
tl_eq 'an empty XDG_CONFIG_HOME is none' '1' "$(XDG_CONFIG_HOME='' names --text acme)"
mkdir -p "$TL_TMP/broken/trellis/private-names"
tl_eq 'a list that cannot be read is refused' '1' "$(XDG_CONFIG_HOME="$TL_TMP/broken" names --text nothing)"
tl_has '  and named' "($TL_TMP/broken/trellis/private-names) cannot be read" "$(out)"

printf '\nthe spellings\n'
printf 'Zephyr Cloud\nacme\nCafé Olé Bar\n' > "$list"
for spelling in 'zephyr cloud' 'ZEPHYR CLOUD' 'zephyr-cloud' 'zephyr_cloud' 'zephyr.cloud' 'zephyrcloud' 'ZephyrCloud' 'zephyr  cloud' \
  'myzephyrclouds' 'zephyr - cloud' 'cafe ole bar' 'CAFÉ-OLÉ-BAR' 'cafeolebar' 'acme' 'ACME' 'Acme.' '(acme)' 'acme_x' 'x-acme' 'myAcme' 'acmeCorp' 'ACMECorp' 'HTTPAcme' 'ACMEs' 'a/acme/b' 'ácme' \
  "$(printf 'ac\342\200\213me')" "$(printf 'zep\302\255hyr cloud')" "$(printf 'zephyr\302\240cloud')" "$(printf 'zephyr\342\200\221cloud')" "$(printf 'zephyr\ncloud')" "$(printf 'cafe\314\201 ole bar')" "$(printf '\357\275\201cme')"; do
  tl_eq "found: $spelling" '1' "$(text "x $spelling y")"
done
for other in 'acmed' 'pacme' 'acme2' '2acme' 'zephyr/cloud' 'zephyr' 'cloud' 'zephyr the cloud' 'ac me' 'ac-me'; do
  tl_eq "not found: $other" '0' "$(text "x $other y")"
done
printf 'he\ncat\n' > "$list"
tl_eq 'a capital letter belongs to the word that follows it' '0' "$(text 'The Scat')"
printf 'zephyrCloud\n' > "$list"
tl_eq 'the words of a term written in one' '1' "$(text 'the zephyr-cloud')"
printf 'acme.*\n' > "$list"
tl_eq 'a term is not a pattern' '0' "$(text 'acmeish')"
printf 'acme\nzephyr\n' > "$list"
text 'acme zephyr
acme' > /dev/null
tl_eq 'each term is named once per line' '3' "$(grep -c 'is in the list' "$TL_TMP/out.txt")"

printf '\na file\n'
printf 'one\ntwo acme\n' > body.md
tl_eq 'a file is judged' '1' "$(names --file body.md)"
tl_has '  by its lines' 'private-names: body.md:2: "acme"' "$(out)"
tl_eq 'a file and a text' '1' "$(names --file trellis.config --text zephyr)"
for wrong in '' '--file' '--file nope.md' '--text' '--other'; do
  # shellcheck disable=SC2086
  tl_eq "a wrong use: $wrong" '2' "$(names $wrong)"
done
rm body.md
git add -A && git commit -q -m 'chore: config (#12)'

printf '\nthe index\n'
staged() { names --staged; }
mkdir sub
printf 'a\nacme one\nb\n' > sub/x.md && git add -A
tl_eq 'an added line is refused' '1' "$(staged)"
tl_has '  with its file and its line' 'private-names: sub/x.md:2: "acme"' "$(out)"
tl_eq '  from a folder too' '1' "$(cd sub && staged)"
git config diff.noprefix true && git config diff.external false && git config color.ui always
tl_eq '  whatever the config of git' '1' "$(staged)"
tl_has '  and it is named the same' 'private-names: sub/x.md:2: "acme"' "$(out)"
git config --unset diff.noprefix && git config --unset diff.external && git config --unset color.ui
git commit -q -m 'chore: x (#12)'
tl_eq 'a line that is already there passes' '0' "$(staged)"
printf 'a\nb\nc\n' > sub/x.md && git add -A
tl_eq 'a removed line passes' '0' "$(staged)"
printf '++ acme\n' > sub/x.md && git add -A
tl_eq 'a line that looks like the head of a file is judged' '1' "$(staged)"
tl_has '  as what it is' 'private-names: sub/x.md:1: "acme"' "$(out)"
printf 'zephyr\n' > sub/y.md
git reset -q --hard
tl_eq 'a file that is not in the index is not judged' '0' "$(staged)"
rm -f sub/y.md
git mv sub/x.md sub/z.md
tl_eq 'a renamed file adds no line' '0' "$(staged)"
git reset -q --hard
mkdir acme && printf 'x\n' > acme/x.md && git add -A
tl_eq 'a path is refused' '1' "$(staged)"
tl_has '  naming it' 'private-names: the path acme/x.md: "acme"' "$(out)"
git commit -q -m 'chore: path (#12)'
tl_eq '  also when it was there' '1' "$(staged)"
git rm -rq acme
tl_eq 'a removed path passes' '0' "$(staged)"
git commit -q -m 'chore: no path (#12)'
printf 'the zephyr\n' > 'a "b" ñ.md' && git add -A
tl_eq 'a file with an odd name is judged' '1' "$(staged)"
git reset -q --hard
first="$(mktemp -d "$TL_TMP/first.XXXXXX")"
git -C "$first" init -q
printf '[project]\n\tpublic = true\n' > "$first/trellis.config"
printf 'acme\n' > "$first/x" && git -C "$first" add -A
tl_eq 'the first commit of a repository too' '1' "$(cd "$first" && staged)"

printf '\na project that is not public\n'
printf 'acme\n' > sub/x.md && git add -A
for value in false yes ''; do
  git config -f trellis.config project.public "$value"
  tl_eq "project.public = $value judges nothing" '0' "$(names --staged --text acme --file sub/x.md)"
  tl_eq '  and says nothing' '' "$(out)"
done
git config -f trellis.config --unset project.public
tl_eq 'nor unset' '0' "$(names --staged --text acme --file sub/x.md)"
rm "$list"
tl_eq '  without a list either' '0' "$(names --staged)"
tl_eq '  nor a word' '' "$(out)"
git reset -q --hard

printf '\nthe text of a pull request and of a project that is public\n'
printf 'acme\n' > "$list"
printf '[project]\n\tpublic = true\n' > trellis.config
good() { printf '%s\n' "$1" 'Closes #12' 'Lesson: none' '' '**Summary**' 'Something.' '' '**Verification**' 'ok' '' '**Before merging**' 'none' '' '**After merging**' 'none' > "$TL_TMP/body.md"; }
check() { GITHUB_BASE_REF=develop GITHUB_HEAD_REF=12-thing bash "$TRELLIS" pr-check --body "$TL_TMP/body.md" > "$TL_TMP/out.txt" 2>&1; echo $?; }
good 'Text.'
tl_eq 'pr-check passes a body with no private name' '0' "$(check)"
good 'Of acme.'
tl_eq 'and refuses one that has it' '1' "$(check)"
tl_has '  naming it' "body.md:1: \"acme\"" "$(out)"
tl_eq '--has-setback does not judge it' '' "$(bash "$TRELLIS" pr-check --has-setback --body "$TL_TMP/body.md" 2>&1)"
printf '[project]\n\tpublic = false\n' > trellis.config
tl_eq 'one of a project that is not public passes' '0' "$(check)"
printf '[project]\n\tpublic = true\n' > trellis.config
rm "$list"
tl_eq 'without a list it passes, in CI too' '0' "$(CI=true check)"
tl_has '  and says so' 'no list of private names' "$(out)"

printf '\nthe terms of a project\n'
project="$(tl_repo)"
cd "$project" || exit 1
# Prints what the project has of a text: the line and the term, one per line.
of_project() {
  node --input-type=module -e '
    import {pathToFileURL} from "node:url";
    const [root, lib, name, text] = process.argv.slice(1);
    const {projectTerms, termsIn, foreignRepositories} = await import(pathToFileURL(lib).href);
    const project = {root, name, hooksPath: ".githooks", upstream: "rologr35/trellis"};
    const found = [...termsIn(text, projectTerms(project)), ...foreignRepositories(text, project.upstream)];
    console.log(found.map(f => `${f.line} ${f.what}: ${f.term}`).join("\n"));
  ' "$project" "$TRELLIS_ROOT/lib/private-names.mjs" "${NAME-Zephyr App}" "$1"
}
tl_eq 'the name of the project' '2 the name of the project: Zephyr App' "$(of_project 'a
the zephyr_app here')"
tl_eq '  when it has one' '' "$(NAME='' of_project 'the zephyr_app here')"
tl_eq 'without an origin it has none' '' "$(of_project 'acme')"
for url in 'git@github.com:acme/warehouse.git' 'https://github.com/acme/warehouse' 'https://user:pass@github.com/acme/warehouse.git/' 'ssh://git@github.com/acme/warehouse.git' 'git@work:acme/warehouse.git' 'https://git.example.com/acme/team/warehouse.git'; do
  git remote add origin "$url"
  tl_eq "the owner and the name of $url" "1 the owner of the project: acme
1 the name of the repository: warehouse" "$(of_project 'of Acme, the WareHouse')"
  git remote remove origin
done
git remote add origin "$TL_TMP/acme/warehouse.git"
tl_eq 'a path has only a name' '1 the name of the repository: warehouse' "$(of_project 'of Acme, the WareHouse')"
git remote set-url origin "file://$TL_TMP/acme/warehouse.git"
tl_eq 'and a URL of a path' '1 the name of the repository: warehouse' "$(of_project 'of Acme, the WareHouse')"
git remote set-url origin 'git@github.com:Rologr35/warehouse.git'
tl_eq 'an owner that is also the one of the upstream is none' '' "$(of_project 'of rologr35')"
tl_eq '  and the name stays' '1 the name of the repository: warehouse' "$(of_project 'of rologr35/warehouse')"
tl_eq 'where the project is' "1 where the project is: $project" "$(of_project "in $project/x" | grep 'where')"
git worktree add -q "$TL_TMP/tree" -b 1-tree
tl_has '  its main checkout too, from a worktree' "where the project is: $project" "$(project="$TL_TMP/tree" of_project "in $project/x")"
git worktree remove --force "$TL_TMP/tree"
mkdir -p "$HOME/code"
git clone -q "$project" "$HOME/code/zed" 2> /dev/null
tl_has '  and from the home' 'where the project is: ~/code/zed' "$(project="$HOME/code/zed" of_project 'in ~/code/zed/x')"
tl_has 'the home of the machine' "the home of this machine: $HOME" "$(of_project "in $HOME/x")"
mkdir -p src/billing .githooks .claude/skills/trellis-x .github/workflows .trellis/lib
for file in src/billing/invoice.ts top.ts .githooks/pre-commit .githooks/own .claude/settings.json .claude/own.md .github/workflows/trellis.yml .github/workflows/own.yml .trellis/lib/x.sh untracked.ts; do printf 'x\n' > "$file"; done
git add -A && git reset -q untracked.ts
mkdir -p other && printf 'x\n' > other/untracked.ts
tl_eq 'a tracked path with a folder' '2 a file of the project: src/billing/invoice.ts' "$(of_project 'a
in `src/billing/invoice.ts:3`')"
tl_eq '  in another case' '1 a file of the project: src/billing/invoice.ts' "$(of_project 'Src/Billing/Invoice.ts')"
tl_eq '  as a whole word' '' "$(of_project 'src/billing/invoice.tsx')"
tl_eq '  a file without a folder is none' '' "$(of_project 'top.ts')"
tl_eq '  nor one that is not tracked' '' "$(of_project 'other/untracked.ts')"
tl_eq '  nor what trellis writes' '' "$(of_project '.githooks/pre-commit .claude/settings.json .github/workflows/trellis.yml .trellis/lib/x.sh')"
for file in .githooks/own .claude/own.md .github/workflows/own.yml; do
  tl_eq "  and $file is of the project" "1 a file of the project: $file" "$(of_project "$file")"
done
rm -rf .trellis .claude && git add -A
tl_copy "$(tl_upstream)"
git add -A
tl_eq '  a file of the copy is none' '' "$(of_project '.claude/skills/trellis-work/SKILL.md')"
tl_eq 'a reference to another repository' '1 a reference to another repository: zed/some.thing#4' "$(of_project 'see zed/some.thing#4')"
tl_eq '  and not to the upstream' '' "$(of_project 'see rologr35/Trellis#4 and #5')"
for url in 'https://github.com/zed/thing' 'github.com/zed/thing.git' 'http://www.github.com/zed/thing/issues/4' 'git@github.com:zed/thing.git' 'https://api.github.com/repos/zed/thing' 'https://github.com/rologr35/other' 'https://GitHub.com/zed/trellis' 'https://github.com/rologr35/trellis2'; do
  tl_has "a URL: $url" '1 a URL of another repository: ' "$(of_project "at $url.")"
done
for url in 'https://github.com/rologr35/trellis' 'https://github.com/Rologr35/trellis.git' 'https://github.com/rologr35/trellis/issues/4.' 'https://api.github.com/repos/rologr35/trellis/issues' 'git@github.com:rologr35/trellis.git' '(https://github.com/rologr35/trellis)' '[x](https://github.com/rologr35/trellis#readme)' 'https://docs.github.com/en/actions' 'notgithub.com/a/b'; do
  tl_eq "no other one: $url" '' "$(of_project "at $url")"
done

tl_done
