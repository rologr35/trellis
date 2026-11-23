#!/usr/bin/env bash
# Exercises scripts/worktree-add.sh and scripts/worktree-prune.sh against a local origin.
. "$(dirname "$0")/../lib/testlib.sh"

origin="$TL_TMP/origin.git"
git init -q --bare "$origin"
repo="$(tl_repo)"
cd "$repo" || exit 1
git remote add origin "$origin"
printf '.claude/worktrees/\ninstalled\n' > .gitignore
cat > trellis.config <<'CFG'
[command "install"]
	run = touch installed
[command]
	install = install
CFG
git add -A && git commit -q -m 'chore: config'
git switch -q -c develop
git push -q origin main develop

add() { "$TRELLIS" worktree add "$@" 2>"$TL_TMP/err.txt"; }

printf '\nadd\n'
path="$(add 5 first-thing)"
tl_eq 'prints the path last' "$repo/.claude/worktrees/5-first-thing" "$path"
tl_eq 'on its branch' '5-first-thing' "$(git -C "$path" branch --show-current)"
tl_eq 'born from origin/develop' "$(git rev-parse origin/develop)" "$(git -C "$path" rev-parse HEAD)"
tl_eq 'the install ran inside it' 'yes' "$([ -f "$path/installed" ] && echo yes)"
add x slug >/dev/null
tl_has 'refuses a non-number' 'must be the issue number' "$(cat "$TL_TMP/err.txt")"
add 6 Bad_Slug >/dev/null
tl_has 'refuses what git.issueBranch rejects' 'does not match git.issueBranch' "$(cat "$TL_TMP/err.txt")"
add 5 first-thing >/dev/null
tl_has 'refuses an existing branch' 'already exists locally' "$(cat "$TL_TMP/err.txt")"
nested="$(cd "$path" && "$TRELLIS" worktree add 6 from-inside 2>/dev/null)"
tl_eq 'from a worktree it still goes under the main checkout' "$repo/.claude/worktrees/6-from-inside" "$nested"

printf '\nprune\n'
# 5: committed, pushed, merged as a merge commit, branch deleted on origin.
(cd "$path" && printf 'a\n' > a.txt && git add a.txt && git commit -q -m 'feat: a (#5)' && git push -q origin 5-first-thing)
git merge -q --no-ff -m 'Merge pull request #9 from owner/5-first-thing' 5-first-thing
git push -q origin develop
git push -q origin --delete 5-first-thing
# 7: committed, never pushed, not merged.
kept="$(add 7 unmerged)"
tl_has 'the add removes the merged one on its way' "removed $path (5-first-thing)" "$(cat "$TL_TMP/err.txt")"
tl_eq 'its directory is gone' 'gone' "$([ -d "$path" ] || echo gone)"
(cd "$kept" && printf 'b\n' > b.txt && git add b.txt && git commit -q -m 'feat: b (#7)')
# 8: a squash merge, branch deleted on origin.
squash="$(add 8 squashed)"
(cd "$squash" && printf 'c\n' > c.txt && git add c.txt && git commit -q -m 'feat: c (#8)')
printf 'c\n' > c.txt && git add c.txt && git commit -q -m 'feat: c, squashed (#8)'
git push -q origin develop
# 6: fresh, no commits; dirty after this.
printf 'd\n' > "$nested/dirty.txt"

out="$("$TRELLIS" worktree prune 2>&1)"
tl_has 'removes the squashed one' "removed $squash (8-squashed)" "$out"
tl_has 'keeps the unmerged one' "$kept (7-unmerged): 1 commit(s) whose changes are not in origin/develop" "$out"
tl_has 'keeps the dirty one' "$nested (6-from-inside): 1 uncommitted change(s)" "$out"
rm "$nested/dirty.txt"
out="$(cd "$nested" && "$TRELLIS" worktree prune 2>&1)"
tl_has 'keeps the one the caller stands in' "$nested (6-from-inside): is the current directory" "$out"
out="$("$TRELLIS" worktree prune 2>&1)"
tl_has 'keeps a fresh one' "(6-from-inside): no commits yet" "$out"
tl_eq 'the main checkout stays' "$repo" "$(git worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')"

tl_done
