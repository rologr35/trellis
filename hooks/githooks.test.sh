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
printf '# Project\n\n<!-- trellis:method -->\n<!-- /trellis:method -->\n' > CLAUDE.md
bash "$TRELLIS" sync > /dev/null
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

mkdir app && printf '# App\n\nThe app no longer uses the cache.\n' > app/CLAUDE.md && git add -A
tl_eq 'a narrative line in a CLAUDE.md is refused by the hygiene' '1' "$(commit -m 'docs: app (#1)')"
tl_has 'and named' 'narrates history' "$(cat "$TL_TMP/out.txt")"
git rm -q --cached -r app && rm -rf app

cp trellis.config "$TL_TMP/good.config"
printf '[git\n' > trellis.config
printf 'w\n' > w.txt && git add w.txt
tl_eq 'a config that does not parse refuses the commit' '1' "$(commit -m 'chore: w (#1)')"
tl_has 'naming the parse error' 'does not parse' "$(cat "$TL_TMP/out.txt")"
cp "$TL_TMP/good.config" trellis.config
git rm -q --cached w.txt && rm w.txt

printf '\nthe copy\n'
tl_copy "$(tl_upstream)"
git add -A
tl_eq 'a whole copy passes' '0' "$(commit -m 'chore: the copy (#1)')"
printf '# x\n' >> .trellis/lib/schema && git add -A
tl_eq 'a copy edited by hand is refused' '1' "$(commit -m 'chore: edit (#1)')"
tl_has 'naming the file' '.trellis/lib/schema' "$(cat "$TL_TMP/out.txt")"
git reset -q --hard
tl_eq 'the copy is the one found, without a PATH or a plugin that has it' "$repo/.trellis/bin/trellis" "$(. "$TRELLIS_ROOT/lib/find-trellis.sh"; PATH="$(dirname "$(command -v node)"):/usr/bin:/bin" find_trellis)"
tl_eq 'before the one of the PATH' "$repo/.trellis/bin/trellis" "$(. "$TRELLIS_ROOT/lib/find-trellis.sh"; PATH="$bin:$PATH" find_trellis)"
tl_eq 'from a folder of the project too' "$repo/.trellis/bin/trellis" "$(cd lib && . "$TRELLIS_ROOT/lib/find-trellis.sh"; PATH="$bin:$PATH" find_trellis)"
chmod -x .trellis/bin/trellis
printf 'w\n' > w.txt && git add w.txt
tl_eq 'a command that cannot run refuses the commit: no other one stands for it' '1' "$(commit -m 'chore: w (#1)')"
git reset -q --hard && rm -f w.txt
git rm -rq .trellis
tl_eq 'a commit that removes the copy is refused' '1' "$(commit -m 'chore: gone (#1)')"
git reset -q --hard

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

printf '\nthe repository of trellis\n'
own="$(tl_upstream)"
cd "$own" || exit 1
mkdir -p .githooks && cp "$TRELLIS_ROOT"/templates/githooks/* .githooks/
printf '[project]\n\tname = trellis\n' > trellis.config
printf '# Project\n\n<!-- trellis:method -->\n<!-- /trellis:method -->\n' > CLAUDE.md
rm -rf .claude TESTING.md
bash bin/trellis sync > /dev/null && bash bin/trellis hygiene --freeze > /dev/null
git add -A && git commit -q --no-verify -m 'chore: setup (#1)'
git config core.hooksPath .githooks
git worktree add -q "$TL_TMP/wt" -b 2-wt
cd "$TL_TMP/wt" || exit 1
found() { (. "$TRELLIS_ROOT/lib/find-trellis.sh"; PATH="$1" find_trellis); }
tl_eq 'its command is the one of the worktree, before the one of the PATH' "$TL_TMP/wt/bin/trellis" "$(found "$own/bin:$PATH")"
tl_eq 'from a folder of it too' "$TL_TMP/wt/bin/trellis" "$(cd lib && found "$own/bin:$PATH")"
tl_eq 'it is not found without node, which runs it' '' "$(found /usr/bin:/bin)"
own_commit() { PATH="$own/bin:$PATH" git commit -q "$@" > "$TL_TMP/out.txt" 2>&1; echo $?; }
printf 'x\n' > x.md && git add -A
tl_eq 'a commit of the worktree passes' '0' "$(own_commit -m 'docs: x (#2)')"
printf 'console.log("the hygiene of the worktree");\nprocess.exit(1);\n' > hygiene/hygiene.mjs
printf 'y\n' >> x.md && git add x.md
tl_eq 'the git hooks run its code' '1' "$(own_commit -m 'docs: y (#2)')"
tl_has 'and not the one of the PATH' 'the hygiene of the worktree' "$(cat "$TL_TMP/out.txt")"
printf '{"name": "another"}\n' > .claude-plugin/plugin.json
tl_eq 'a project with another name is not trellis' "$own/bin/trellis" "$(found "$own/bin:$PATH")"
printf '{"name": "another", "author": {"name": "trellis"}}\n' > .claude-plugin/plugin.json
tl_eq 'nor one whose author has the name' "$own/bin/trellis" "$(found "$own/bin:$PATH")"
for hook in pre-commit commit-msg pre-push; do
  tl_eq "its $hook is the one of the template" '0' "$(cmp -s "$TRELLIS_ROOT/templates/githooks/$hook" "$TRELLIS_ROOT/.githooks/$hook" && [ -x "$TRELLIS_ROOT/.githooks/$hook" ]; echo $?)"
done
cd "$repo" || exit 1

printf '\nwithout trellis\n'
printf 'y\n' > b.txt && git add -A
tl_eq 'the copy is not found without node, which runs it' '' "$(. "$TRELLIS_ROOT/lib/find-trellis.sh"; PATH=/usr/bin:/bin find_trellis)"
tl_eq 'the hooks let the commit through' '0' "$(PATH="/usr/bin:/bin" git commit -q -m 'whatever' > "$TL_TMP/out.txt" 2>&1; echo $?)"
tl_has 'and warn' 'trellis not found' "$(cat "$TL_TMP/out.txt")"

tl_done
