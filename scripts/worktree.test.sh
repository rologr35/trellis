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

printf '\nadd --resume\n'
add 11 resumed --resume >/dev/null
tl_has 'refuses a branch that is not on origin' 'branch 11-resumed is not on origin' "$(cat "$TL_TMP/err.txt")"
git push -q origin origin/develop:refs/heads/11-resumed
add 11 resumed >/dev/null
tl_has 'without --resume one on origin is refused' 'branch 11-resumed already exists on origin' "$(cat "$TL_TMP/err.txt")"
from="$TL_TMP/from-another-clone"
git clone -q -b 11-resumed "$origin" "$from" 2>/dev/null
(cd "$from" && printf 'r\n' > r.txt && git add r.txt && git -c user.name=t -c user.email=t@example.com commit -q -m 'feat: r (#11)' && git push -q origin 11-resumed)
path="$(add 11 --resume resumed)"
tl_eq 'checks it out' "$repo/.claude/worktrees/11-resumed" "$path"
tl_eq 'on its branch' '11-resumed' "$(git -C "$path" branch --show-current)"
tl_eq 'as origin has it' "$(git rev-parse origin/11-resumed)" "$(git -C "$path" rev-parse HEAD)"
tl_eq 'with its files' 'r' "$(cat "$path/r.txt")"
tl_eq 'without an upstream' '' "$(git -C "$path" config branch.11-resumed.merge)"
tl_eq 'the install ran inside it' 'yes' "$([ -f "$path/installed" ] && echo yes)"
add 11 resumed --resume >/dev/null
tl_has 'refuses one that is checked out' 'already exists; nothing was created' "$(cat "$TL_TMP/err.txt")"
git worktree remove --force "$path"
(cd "$from" && printf 's\n' > s.txt && git add s.txt && git -c user.name=t -c user.email=t@example.com commit -q -m 'feat: s (#11)' && git push -q origin 11-resumed)
path="$(add 11 resumed --resume)"
tl_eq 'a branch that is here and behind origin is taken to it' "$(git rev-parse origin/11-resumed)" "$(git -C "$path" rev-parse HEAD)"
(cd "$path" && printf 't\n' > t.txt && git add t.txt && git commit -q -m 'feat: t (#11)')
git worktree remove --force "$path"
add 11 resumed --resume >/dev/null
tl_has 'one with commits of its own is refused' 'branch 11-resumed has commits here that origin does not have' "$(cat "$TL_TMP/err.txt")"
add 11 resumed more --resume >/dev/null
tl_has 'a third word is refused' 'usage: trellis worktree add <issue-number> <slug> [--resume]' "$(cat "$TL_TMP/err.txt")"
git branch -q -D 11-resumed
git push -q origin --delete 11-resumed

printf '\nprune asks GitHub as the owner\n'
# 9: merged with a merge commit whose subject does not name the branch, so only GitHub can say the
# pull request was this branch's. The origin of this repository is a local path, so a git shim
# answers `remote get-url origin` with a GitHub URL and passes everything else to git.
gpath="$(add 9 ghmerge)"
(cd "$gpath" && printf 'g\n' > g.txt && git add g.txt && git commit -q -m 'feat: g (#9)' && git push -q origin 9-ghmerge)
git merge -q --no-ff -m "Merge branch '9-ghmerge'" 9-ghmerge
git push -q origin develop
git push -q origin --delete 9-ghmerge
gtip="$(git rev-parse 9-ghmerge)"
# 10: the same, so that one prune asks GitHub twice for one owner.
gpath2="$(add 10 ghmerge-again)"
(cd "$gpath2" && printf 'h\n' > h.txt && git add h.txt && git commit -q -m 'feat: h (#10)' && git push -q origin 10-ghmerge-again)
git merge -q --no-ff -m "Merge branch '10-ghmerge-again'" 10-ghmerge-again
git push -q origin develop
git push -q origin --delete 10-ghmerge-again
gtip2="$(git rev-parse 10-ghmerge-again)"
shim="$TL_TMP/shim"
mkdir -p "$shim"
export REAL_GIT="$(command -v git)"
cat > "$shim/git" <<'SHIM'
#!/bin/sh
case " $* " in
  *' remote get-url origin '*) echo 'https://github.com/acme/thing.git'; exit 0 ;;
esac
exec "$REAL_GIT" "$@"
SHIM
# gh answers only `api`, as in a cloud session, where the rest is refused with the text below. It lists the
# merged pull requests of a branch only to the owner's token (fake), and logs each call.
cat > "$shim/gh" <<'GH'
#!/bin/sh
printf '%s %s token=%s\n' "$1" "$2" "${GH_TOKEN:-none}" >> "$GH_CALLS"
case "$1 $2" in
  'auth token') cat "$GH_TOKEN_FILE" 2>/dev/null || exit 1 ;;
  'api repos/acme/thing/pulls')
    case " $* " in *' --paginate '*'-F head=acme:9-ghmerge -f state=closed '* | *' --paginate '*'-F head=acme:10-ghmerge-again -f state=closed '*) ;;
      *) echo "unexpected call: $*" >&2; exit 1 ;; esac
    [ -f "$GH_FAIL" ] && { echo 'HTTP 401: Bad credentials' >&2; exit 1; }
    [ "${GH_TOKEN:-none}" = 'tok-acme' ] || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
    cat "$GH_HEADS" ;;
  *) echo 'GitHub GraphQL is not available from Claude Code sessions; use the REST API' >&2; exit 1 ;;
esac
GH
chmod +x "$shim/git" "$shim/gh"
export GH_CALLS="$TL_TMP/gh-calls.log" GH_TOKEN_FILE="$TL_TMP/gh-token" GH_FAIL="$TL_TMP/gh-fail" GH_HEADS="$TL_TMP/gh-heads"
printf 'tok-acme\n' > "$GH_TOKEN_FILE"
printf '%s\n%s\n' "$gtip" "$gtip2" > "$GH_HEADS"
: > "$GH_CALLS"
: > "$GH_FAIL"
out="$(PATH="$shim:$PATH" "$TRELLIS" worktree prune 2>&1)"
tl_has 'a failing gh is named' "GitHub could not be asked as the owner's account (acme): HTTP 401: Bad credentials" "$out"
tl_has 'and keeps the worktree' "$gpath (9-ghmerge): GitHub could not be asked" "$out"
tl_eq 'its directory is still there' 'there' "$([ -d "$gpath" ] && echo there)"
tl_lacks 'the token is not printed' 'tok-acme' "$out"
rm "$GH_FAIL"
: > "$GH_CALLS"
out="$(PATH="$shim:$PATH" "$TRELLIS" worktree prune 2>&1)"
tl_has 'a merged pull request is seen and the worktree removed' "removed $gpath (9-ghmerge)" "$out"
tl_has 'with the owner token' 'repos/acme/thing/pulls token=tok-acme' "$(cat "$GH_CALLS")"
tl_has 'and the second one too' "removed $gpath2 (10-ghmerge-again)" "$out"
tl_eq 'two reads, one lookup of the token' '1' "$(grep -c 'auth token' "$GH_CALLS")"
tl_eq 'for two reads' '2' "$(grep -c '/pulls' "$GH_CALLS")"
tl_lacks 'the token is not printed either' 'tok-acme' "$out"

tl_done
