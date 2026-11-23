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

printf '\nbranch switch on the main checkout\n'
tl_eq 'to an issue branch' 'deny' "$(verdict 'git switch -c 4-thing')"
tl_eq 'checkout -b to an issue branch' 'deny' "$(verdict 'git checkout -b 4-thing origin/develop')"
tl_eq 'to another branch' 'allow' "$(verdict 'git switch main')"
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

printf '\nno opinion\n'
tl_eq 'a repository without trellis.config' 'allow' "$(verdict 'git push origin main' "$(tl_repo)")"
tl_eq 'a payload that does not parse' 'allow' "$(printf 'not json' | bash "$HOOK" | grep -c deny | sed 's/^0$/allow/')"

tl_done
