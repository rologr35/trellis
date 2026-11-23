#!/usr/bin/env bash
# Exercises templates/githooks/ installed in a project: the release branch, the ratchet, the commit
# message, the branch name on push, and the pass-through when trellis cannot be found.
. "$(dirname "$0")/../lib/testlib.sh"

bin="$TL_TMP/bin"
mkdir -p "$bin"
ln -s "$TRELLIS" "$bin/trellis"

origin="$TL_TMP/origin.git"
git init -q --bare "$origin"
repo="$(tl_repo)"
cd "$repo" || exit 1
git remote add origin "$origin"
mkdir .githooks
cp "$TRELLIS_ROOT"/templates/githooks/* .githooks/
cp "$TRELLIS_ROOT/lib/find-trellis.sh" .githooks/find-trellis.sh
printf '[git]\n\treleaseBranch = main\n' > trellis.config
git add -A && git commit -q -m 'chore: setup (#1)'
git config core.hooksPath .githooks

commit() { PATH="$bin:$PATH" git commit -q "$@" > "$TL_TMP/out.txt" 2>&1; echo $?; }

printf '\npre-commit\n'
printf 'z\n' > z.txt && git add -A
tl_eq 'a commit on the release branch is refused' '1' "$(commit -m 'chore: z (#1)')"
git switch -q -c 1-setup
tl_eq 'a commit on an issue branch passes' '0' "$(commit -m 'chore: z (#1)')"
mkdir lib && printf '// ignore: unused_import\nvoid main() {}\n' > lib/main.dart && git add -A
tl_eq 'a new Dart // ignore: is refused by the ratchet' '1' "$(commit -m 'feat: main (#1)')"
tl_has 'with what regresses' 'adds 1 suppression' "$(cat "$TL_TMP/out.txt")"
printf 'void main() {}\n' > lib/main.dart && git add -A
tl_eq 'the clean version passes' '0' "$(commit -m 'feat: main (#1)')"

mkdir app && printf '# App\n\nLa app ya no usa la caché.\n' > app/CLAUDE.md && git add -A
tl_eq 'a narrative line in a CLAUDE.md is refused by the hygiene' '1' "$(commit -m 'docs: app (#1)')"
tl_has 'and named' 'narrates history' "$(cat "$TL_TMP/out.txt")"
git rm -q --cached -r app && rm -rf app

printf '\ncommit-msg\n'
printf 'x\n' > a.txt && git add -A
tl_eq 'an AI attribution is refused' '1' "$(commit -m 'feat: a (#1)' -m 'Co-Authored-By: Claude <noreply@anthropic.com>')"
tl_eq 'a shapeless message is refused' '1' "$(commit -m 'stuff')"
tl_eq 'a good message passes' '0' "$(commit -m 'feat: a (#1)')"

printf '\npre-push\n'
push() { PATH="$bin:$PATH" git push -q origin "$@" > "$TL_TMP/out.txt" 2>&1; echo $?; }
tl_eq 'an issue branch is pushed' '0' "$(push 1-setup)"
git branch feature/x
tl_eq 'a branch out of git.issueBranch is refused' '1' "$(push feature/x)"
tl_eq 'the release branch is a person'"'"'s to push' '0' "$(push main)"

printf '\nwithout trellis\n'
printf 'y\n' > b.txt && git add -A
tl_eq 'the hooks let the commit through' '0' "$(PATH="/usr/bin:/bin" git commit -q -m 'whatever' > "$TL_TMP/out.txt" 2>&1; echo $?)"
tl_has 'and warn' 'trellis not found' "$(cat "$TL_TMP/out.txt")"

tl_done
