#!/usr/bin/env bash
# Exercises hooks/guard-git.sh with payloads as Claude Code sends them and a stubbed gh.
. "$(dirname "$0")/../lib/testlib.sh"

HOOK="$TRELLIS_ROOT/hooks/guard-git.sh"
stubs="$TL_TMP/stubs"
mkdir -p "$stubs"
# gh answers from files: issue state and pull request base.
cat > "$stubs/gh" <<'GH'
#!/bin/sh
case "$1 $2" in
  'issue view') cat "$GH_FIXTURES/issue-$3" 2>/dev/null || exit 1 ;;
  'pr view') cat "$GH_FIXTURES/pr-$3" 2>/dev/null || exit 1 ;;
  *) exit 0 ;;
esac
GH
chmod +x "$stubs/gh"
export GH_FIXTURES="$TL_TMP/gh"
mkdir -p "$GH_FIXTURES"
export PATH="$stubs:$PATH"

repo="$(tl_repo)"
cd "$repo" || exit 1
cat > trellis.config <<'CFG'
[git]
	integrationBranch = develop
	protected = main
	protected = develop
	assistantMayMergeInto = develop
CFG
git add -A && git commit -q -m 'chore: config'
git branch develop
git switch -q develop

# Prints "deny" when the hook refuses the command, "allow" otherwise.
verdict() {
  local command="$1" cwd="${2:-$repo}" transcript="${3:-}"
  local payload out
  payload="$(node -e 'console.log(JSON.stringify({tool_input: {command: process.argv[1]}, cwd: process.argv[2], transcript_path: process.argv[3]}))' "$command" "$cwd" "$transcript")"
  out="$(printf '%s' "$payload" | bash "$HOOK")"
  case "$out" in *'"deny"'*) echo deny ;; *) echo allow ;; esac
}

printf '\npush\n'
tl_eq 'push to main by refspec' 'deny' "$(verdict 'git push origin main')"
tl_eq 'push HEAD:develop' 'deny' "$(verdict 'git push origin HEAD:develop')"
tl_eq 'push +x:refs/heads/main' 'deny' "$(verdict 'git push -f origin +x:refs/heads/main')"
tl_eq 'bare push on develop' 'deny' "$(verdict 'git push')"
tl_eq 'chained after cd' 'deny' "$(verdict "cd $repo && git -c a=b push origin main")"
tl_eq 'push of an issue branch' 'allow' "$(verdict 'git push origin 4-thing')"
tl_eq 'protected names come from the config' 'allow' "$(verdict 'git push origin staging')"
git config -f trellis.config --add git.protected staging
tl_eq 'and follow it' 'deny' "$(verdict 'git push origin staging')"
tl_eq 'a double-quoted refspec' 'deny' "$(verdict 'git push origin "main"')"
tl_eq 'a single-quoted HEAD:main' 'deny' "$(verdict "git push origin 'HEAD:main'")"
tl_eq '@ on develop' 'deny' "$(verdict 'git push origin @')"
tl_eq '@:main' 'deny' "$(verdict 'git push origin @:main')"
tl_eq 'HEAD on develop' 'deny' "$(verdict 'git push -u origin HEAD')"
tl_eq 'a remote without refspec on develop' 'deny' "$(verdict 'git push origin')"
git switch -q -c 9-up
git config branch.9-up.remote origin
git config branch.9-up.merge refs/heads/main
tl_eq 'a bare push whose upstream is protected' 'deny' "$(verdict 'git push')"
git config --unset branch.9-up.merge
tl_eq 'a bare push of an issue branch without upstream' 'allow' "$(verdict 'git push')"
git switch -q develop
git branch -q -D 9-up

printf '\nthe directory the command runs in\n'
elsewhere="$(tl_repo)"
plain="$TL_TMP/plain"
mkdir -p "$plain"
tl_eq '-C into the project from a directory without config' 'deny' "$(verdict "git -C $repo push origin main" "$plain")"
tl_eq 'cd into the project from a directory without config' 'deny' "$(verdict "cd $repo && git push origin main" "$plain")"
tl_eq 'cd out of the project into one without config' 'allow' "$(verdict "cd $elsewhere && git push origin main")"

printf '\na directory that needs the shell to expand it\n'
home="$TL_TMP/home"
mkdir -p "$home"
ln -s "$repo" "$home/proj"
spaced="$TL_TMP/my dir"
mkdir -p "$spaced"
cp -R "$repo" "$spaced/proj"
tl_eq 'a variable assigned in the same command' 'deny' "$(verdict "REPO=$repo; cd \$REPO && git push origin main" "$plain")"
tl_eq 'a variable in -C, braced and quoted' 'deny' "$(verdict "R=$repo && git -C \"\${R}\" push origin main" "$plain")"
tl_eq 'a variable with a quoted literal value' 'deny' "$(verdict "REPO='$repo'; cd \"\$REPO\" && git push origin main" "$plain")"
tl_eq 'a variable built from an earlier one' 'deny' "$(verdict "BASE=$TL_TMP; REPO=\$BASE/$(basename "$repo"); cd \$REPO && git push origin main" "$plain")"
tl_eq 'export of a variable' 'deny' "$(verdict "export REPO=$repo; cd \$REPO && git push origin main" "$plain")"
tl_eq '~ in cd' 'deny' "$(HOME="$home" verdict 'cd ~/proj && git push origin main' "$plain")"
tl_eq '~ in -C' 'deny' "$(HOME="$home" verdict 'git -C ~/proj push origin main' "$plain")"
tl_eq 'a quoted path with a space in cd' 'deny' "$(verdict "cd \"$spaced/proj\" && git push origin main" "$plain")"
tl_eq 'a single-quoted path with a space in -C' 'deny' "$(verdict "git -C '$spaced/proj' push origin main" "$plain")"
tl_eq 'an expanded directory without a push of a protected branch' 'allow' "$(verdict "REPO=$repo; cd \$REPO && git push origin 4-thing" "$plain")"
tl_eq 'a variable assigned for one command only is not set for the next' 'allow' "$(verdict "REPO=$repo true; cd \$REPO && git push origin main" "$plain")"
tl_eq 'an unresolved directory falls back to the session repository (cd)' 'deny' "$(verdict 'cd "$UNSET/x" && git push origin main')"
tl_eq 'an unresolved directory falls back to the session repository (-C)' 'deny' "$(verdict 'git -C "$(pwd)/x" push origin main')"
tl_eq 'an unresolved directory falls back to the session repository (cd -)' 'deny' "$(verdict 'cd - && git push origin main')"
tl_eq 'an unresolved directory, an issue branch' 'allow' "$(verdict 'cd "$UNSET/x" && git push origin 4-thing')"
tl_eq 'an unresolved directory with no config in the session either has no opinion' 'allow' "$(verdict 'cd "$UNSET/x" && git push origin main' "$plain")"
tl_eq 'a variable the command does not assign has no opinion from a bare session' 'allow' "$(verdict 'D=$(pwd); cd $D && git push origin main' "$plain")"

git -C "$repo" worktree add -q -b 16-words "$TL_TMP/on-issue-branch" develop
tl_eq 'an escaped quote does not swallow the refspec' 'deny' "$(verdict 'git push -o "a\"b" origin main' "$TL_TMP/on-issue-branch")"
tl_eq 'two escaped quotes do not swallow the refspec' 'deny' "$(verdict 'git push -o "say \"hi\"" origin main' "$TL_TMP/on-issue-branch")"
tl_eq '-C belongs to its own command' 'deny' "$(verdict "git -C $elsewhere status && git push origin main")"
tl_eq '-C into the project does not stay for the next command' 'allow' "$(verdict "git -C $repo status && git push origin main" "$plain")"
tl_eq 'cd -- into the project' 'deny' "$(verdict "cd -- $repo && git push origin main" "$plain")"
tl_eq 'cd -P into the project' 'deny' "$(verdict "cd -P $repo && git push origin main" "$plain")"
long="$(head -c 60000 /dev/zero | tr '\0' 'a')"
started=$SECONDS
tl_eq 'a push after a long line' 'deny' "$(verdict "gh issue create --body \"$long\" && git push origin main")"
tl_eq 'a long line is split in linear time' 'fast' "$([ $((SECONDS - started)) -le 10 ] && echo fast || echo slow)"

printf '\nbranch switch on the main checkout\n'

tl_eq 'to an issue branch' 'deny' "$(verdict 'git switch -c 4-thing')"
tl_eq 'checkout -b to an issue branch' 'deny' "$(verdict 'git checkout -b 4-thing origin/develop')"
tl_eq 'to another branch' 'allow' "$(verdict 'git switch main')"
tl_eq 'checkout -t of a remote issue branch' 'deny' "$(verdict 'git checkout -t origin/12-foo')"
tl_eq 'checkout --track of a remote issue branch' 'deny' "$(verdict 'git checkout --track origin/12-foo')"
tl_eq 'switch --track of a remote issue branch' 'deny' "$(verdict 'git switch --track origin/12-foo')"
tl_eq 'switch -C to an issue branch' 'deny' "$(verdict 'git switch -C 12-foo')"
tl_eq 'a quoted issue branch' 'deny' "$(verdict 'git switch -c "12-foo"')"
tl_eq 'a path restore is not a switch' 'allow' "$(verdict 'git checkout -- file.txt')"
git branch 4-thing
git switch -q 4-thing
printf 'OPEN\n' > "$GH_FIXTURES/issue-4"
tl_eq 'away from a branch whose issue is open' 'deny' "$(verdict 'git switch develop')"
printf 'CLOSED\n' > "$GH_FIXTURES/issue-4"
tl_eq 'away from a branch whose issue is closed' 'allow' "$(verdict 'git switch develop')"
rm "$GH_FIXTURES/issue-4"
tl_eq 'gh failing is no opinion' 'allow' "$(verdict 'git switch develop')"
git switch -q develop
wt="$TL_TMP/wt"
git worktree add -q "$wt" -b 5-other
tl_eq 'a worktree is the session'"'"'s own' 'allow' "$(verdict 'git switch -c 6-more' "$wt")"

printf '\nissue creation\n'
transcript="$TL_TMP/transcript.jsonl"
printf '{"message": {"content": [{"type": "tool_use", "input": {"command": "ls"}}]}}\n' > "$transcript"
tl_eq 'without a search' 'deny' "$(verdict 'gh issue create --title x' "$repo" "$transcript")"
printf '{"message": {"content": [{"type": "tool_use", "input": {"command": "gh issue list --search login"}}]}}\n' >> "$transcript"
tl_eq 'after a search' 'allow' "$(verdict 'gh issue create --title x' "$repo" "$transcript")"
tl_eq 'no transcript is no opinion' 'allow' "$(verdict 'gh issue create --title x')"

printf '\nmerge\n'
printf 'develop\n' > "$GH_FIXTURES/pr-12"
printf 'main\n' > "$GH_FIXTURES/pr-13"
tl_eq 'into an allowed base' 'allow' "$(verdict 'gh pr merge 12 --merge')"
tl_eq 'into a base not allowed' 'deny' "$(verdict 'gh pr merge 13 --merge')"
tl_eq 'without naming the pull request' 'deny' "$(verdict 'gh pr merge --merge')"
tl_eq 'with an unreadable base' 'deny' "$(verdict 'gh pr merge 99')"
tl_eq 'from a cloud session' 'deny' "$(CLAUDE_CODE_REMOTE=1 verdict 'gh pr merge 12')"

printf '\na config that does not parse\n'
cp trellis.config "$TL_TMP/good.config"
printf '[git\n' > trellis.config
out="$(node -e 'console.log(JSON.stringify({tool_input: {command: "git push origin 4-thing"}, cwd: process.argv[1]}))' "$repo" | bash "$HOOK")"
tl_has 'refuses any push' '"deny"' "$out"
tl_has 'naming the parse error' 'does not parse' "$out"
tl_eq 'refuses a merge' 'deny' "$(verdict 'gh pr merge 12')"
tl_eq 'has no opinion on the rest' 'allow' "$(verdict 'git status')"
cp "$TL_TMP/good.config" trellis.config

printf '\nno opinion\n'
tl_eq 'a repository without trellis.config' 'allow' "$(verdict 'git push origin main' "$(tl_repo)")"
tl_eq 'a payload that does not parse' 'allow' "$(printf 'not json' | bash "$HOOK" | grep -c deny | sed 's/^0$/allow/')"

tl_done
