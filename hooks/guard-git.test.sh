#!/usr/bin/env bash
# Exercises hooks/guard-git.sh with payloads as Claude Code sends them and a stubbed gh.
. "$(dirname "$0")/../lib/testlib.sh"

HOOK="$TRELLIS_ROOT/hooks/guard-git.sh"
stubs="$TL_TMP/stubs"
mkdir -p "$stubs"
# gh answers from files: issue state and pull request base. Each call is logged with the token it
# ran with (fake values), `need-<n>` makes a pull request visible to that token only, and `auth
# token -u <user>` prints token-<user> or fails, as gh does for an account that is not signed in.
cat > "$stubs/gh" <<'GH'
#!/bin/sh
tok="${GH_TOKEN:-none}"
printf '%s %s %s token=%s\n' "$1" "$2" "$3" "$tok" >> "$GH_FIXTURES/calls.log"
fail() { echo "$1" >&2; exit 1; }
case "$1 $2" in
  'auth token')
    user=''; prev=''
    for a in "$@"; do [ "$prev" = -u ] && user="$a"; prev="$a"; done
    cat "$GH_FIXTURES/token-$user" 2>/dev/null || exit 1 ;;
  'issue view')
    [ -f "$GH_FIXTURES/issue-$3" ] || fail "HTTP 502: bad gateway (issue $3)"
    cat "$GH_FIXTURES/issue-$3" ;;
  'pr view')
    n="${3##*/}"
    if [ -f "$GH_FIXTURES/need-$n" ] && [ "$tok" != "$(cat "$GH_FIXTURES/need-$n")" ]; then
      fail "GraphQL: Could not resolve to a PullRequest with the number of $n."
    fi
    [ -f "$GH_FIXTURES/leak-$n" ] && fail "auth failed for token $tok"
    cat "$GH_FIXTURES/pr-$n" 2>/dev/null || fail "no pull request $n" ;;
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
tl_eq 'cd out of the project into one without config is judged by the session config too (#22)' 'deny' "$(verdict "cd $elsewhere && git push origin main")"

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

printf '\nthe expansion does not trust what may not have run (#21)\n'
wtb="$TL_TMP/on-issue-branch"
tl_eq 'ANSI-C quoting: an escaped quote does not swallow the refspec' 'deny' "$(verdict "git push -o \$'x\\'y' origin main" "$wtb")"
tl_eq 'ANSI-C quoting: a hex escape spells main' 'deny' "$(verdict "git push origin \$'\\x6dain'" "$wtb")"
tl_eq 'ANSI-C quoting: an octal escape spells main' 'deny' "$(verdict "git push origin \$'\\155ain'" "$wtb")"
tl_eq 'ANSI-C quoting: an issue branch passes' 'allow' "$(verdict "git push -o \$'x\\'y' origin 21-x" "$wtb")"
tl_eq 'a quote left open: every word is judged' 'deny' "$(verdict "git push -o 'x origin main" "$wtb")"
tl_eq 'a double quote left open: every word is judged' 'deny' "$(verdict 'git push -o "x origin main' "$wtb")"
# The variable held the repository, and the command may have set it to a directory without config.
for assign in "true || X=$plain" "false && X=$plain" "echo | X=$plain" "X=$plain | cat" "export X=$plain"; do
  tl_eq "a variable assigned where it may not run or last is unresolved: ${assign//$plain/PLAIN}" 'deny' "$(verdict "X=$repo; $assign; cd \"\$X\"; git push origin main" "$wtb")"
done
# The variable held a directory without config, and the command may have set it to the repository.
for assign in "X=\$(echo $repo)" "X=\`echo $repo\`" 'X+=/sub' 'read -r X' "printf -v X %s $repo" "for X in $repo; do :; done" "declare X=$repo" "local X=$repo" "typeset X=$repo" "readonly X=$repo"; do
  tl_eq "a variable the resolver cannot follow is unresolved: ${assign//$repo/REPO}" 'deny' "$(verdict "X=$plain; $assign; cd \"\$X\"; git push origin main" "$wtb")"
done
tl_eq 'a reassignment that did not run still falls back, to an issue branch push' 'allow' "$(verdict "X=$repo; true || X=$plain; cd \"\$X\"; git push origin 21-x" "$wtb")"
tl_eq 'a plain reassignment is still read' 'deny' "$(verdict "X=$plain; X=$repo; cd \"\$X\"; git push origin main" "$plain")"
tl_eq 'export makes the variable unresolved: a bare session has no opinion' 'allow' "$(verdict "export REPO=$repo; cd \$REPO && git push origin main" "$plain")"
tl_eq 'and the session repository judges it' 'deny' "$(verdict "export REPO=$repo; cd \$REPO && git push origin main" "$wtb")"
tl_eq 'HOME unset: ~ falls back to the session repository' 'deny' "$(unset HOME; verdict 'cd ~/x && git push origin main' "$wtb")"
tl_eq 'HOME unset: $HOME falls back too' 'deny' "$(unset HOME; verdict 'git -C $HOME/x push origin main' "$wtb")"
tl_eq 'HOME unset: ${HOME} falls back too' 'deny' "$(unset HOME; verdict 'git -C ${HOME}/x push origin main' "$wtb")"
tl_eq 'HOME empty: ~ is unresolved, not /x' 'deny' "$(HOME= verdict 'cd ~/x && git push origin main' "$wtb")"
tl_eq 'HOME empty: $HOME is unresolved too' 'deny' "$(HOME= verdict 'cd $HOME/x && git push origin main' "$wtb")"
tl_eq 'HOME unset: a push of an issue branch passes' 'allow' "$(unset HOME; verdict 'cd ~/x && git push origin 21-x' "$wtb")"
rm -f "$TL_TMP/canary"
verdict "cd \"\$(touch $TL_TMP/canary)/x\" && git push origin main" "$wtb" > /dev/null
verdict "X=\$(touch $TL_TMP/canary); git -C \"\$X\" push origin main" "$wtb" > /dev/null
verdict "git -C \`touch $TL_TMP/canary\` push origin main" "$wtb" > /dev/null
tl_eq 'a command substitution inside a path is never run' 'absent' "$([ -e "$TL_TMP/canary" ] && echo ran || echo absent)"

printf '\nwhat the hook cannot judge is refused (#22)\n'
# A project whose config protects other branches only, and the session's issue-branch worktree.
printf 'develop\n' > "$GH_FIXTURES/pr-12"
printf 'main\n' > "$GH_FIXTURES/pr-13"
other="$(tl_repo)"
printf '[git]\n\tprotected = release\n' > "$other/trellis.config"
deny_cases=(
  'a cd that fails::cd /nonexistent; git push origin main'
  'a cd after && that may not run::false && cd PLAIN; git push origin main'
  'a cd on the left of a pipe::cd PLAIN | true; git push origin main'
  'a cd in the background::cd PLAIN & git push origin main'
  'a cd in a subshell::(cd PLAIN); git push origin main'
  'a cd back out of the project, then push::cd PLAIN && git push origin main'
  'an unresolved cd keeps the directories it visited::cd REPO && cd $(pwd) && git push origin main'
  'a quoted operator is not an operator::git push -o "x;y" origin main'
  'a redirection glued to the refspec::git push origin main>/dev/null'
  'a redirection with a descriptor::git push origin main 2>&1'
  'a subshell::(git push origin main)'
  'a brace group::{ git push origin main; }'
  'a background push::git push origin main&'
  'a single & before a push::true & git push origin main'
  'a comment hides nothing::git push origin main # ok'
  'a variable as the refspec::B=main; git push origin $B'
  'a variable from a command as the refspec::B=$(echo main); git push origin $B'
  'a refspec read from input::read -r B <<< main; git push origin $B'
  'env::env git push origin main'
  'an absolute git::/usr/bin/git push origin main'
  'command::command git push origin main'
  'sh -c::sh -c "git push origin main"'
  'bash -lc::bash -lc "git push origin main"'
  'eval::eval "git push origin main"'
  'eval of a variable::C="git push origin main"; eval $C'
  'a piped script::echo "git push origin main" | sh'
  'xargs::echo main | xargs git push origin'
  'GIT_DIR::GIT_DIR=REPO/.git git push origin main'
  'an exported GIT_DIR::export GIT_DIR=REPO/.git; git push origin main'
  '--git-dir::git --git-dir=REPO/.git push origin main'
  'env -C::env -C REPO git push origin main'
  'a git alias::git -c alias.x="push origin main" x'
  'a substitution::echo $(git push origin main)'
  'a backtick::echo `git push origin main`'
  'a gh merge through sh::sh -c "gh pr merge 13"'
  'a gh merge by GH_REPO::GH_REPO=o/r gh pr merge 12'
)
for entry in "${deny_cases[@]}"; do
  label="${entry%%::*}"
  cmd="${entry#*::}"
  cmd="${cmd//PLAIN/$plain}"
  cmd="${cmd//REPO/$repo}"
  tl_eq "$label" 'deny' "$(verdict "$cmd" "$wtb")"
done
tl_eq 'a bare push after a failed cd' 'deny' "$(verdict 'cd /nonexistent; git push' "$repo")"
tl_eq 'a merge by -R in a project without config is read through -R and judged by the session config' 'allow' "$(verdict "cd $plain && gh pr merge 12 -R o/r" "$wtb")"
tl_eq 'a gh merge in a project without config, by -R, with no config anywhere' 'deny' "$(verdict "gh pr merge 12 -R o/r" "$plain")"
tl_eq 'a gh merge by GH_REPO with no config anywhere' 'deny' "$(verdict 'GH_REPO=o/r gh pr merge 12' "$plain")"
for form in '-Ro/r' '-R=o/r' '-dR o/r' '-dRo/r' '-sdRo/r' '--repo=o/r'; do
  tl_eq "a gh merge by $form with no config anywhere" 'deny' "$(verdict "gh pr merge 12 $form" "$plain")"
done
tl_eq 'a gh merge in another directory is judged by the session config' 'deny' "$(verdict "cd $plain && gh pr merge 13" "$wtb")"
tl_eq 'a push after a cd whose directory is unresolved, with no config anywhere' 'allow' "$(verdict 'cd $(pwd) && git push origin main' "$plain")"
# What stays free: a push of an issue branch in any plain form, and a project that protects other branches.
allow_cases=(
  'an explicit issue branch::git push origin 21-x'
  'a quoted issue branch::git push origin "21-x"'
  'HEAD on an issue branch::git push -u origin HEAD'
  'no refspec on an issue branch::git push'
  'a message that mentions main::git commit -m "stop pushing to main"'
  'a message that mentions push and main::git commit -m "refuse a push to main"'
  'main named by another git command::git log main..HEAD && git push origin 21-x'
  'git diff main::git diff main -- README.md && git push origin 21-x'
  'an echo about main::echo "never git push origin main" && git push origin 21-x'
  'a comment about main::git push origin 21-x # main is protected'
  'a heredoc about main::cat <<EOF
push to main is refused
EOF
git push origin 21-x'
  'the commit pattern with a heredoc::git commit -m "$(cat <<'"'"'EOF'"'"'
refuse a push to main
EOF
)" && git push origin 21-x'
  'a pr comment that says merge::gh pr comment 12 --body "ready to merge"'
  'a cd inside the project::cd REPO && git push origin 21-x'
  'a quoted branch next to a main word::git push origin "21-x" -o "main"'
)
for entry in "${allow_cases[@]}"; do
  label="${entry%%::*}"
  cmd="${entry#*::}"
  cmd="${cmd//REPO/$repo}"
  tl_eq "$label" 'allow' "$(verdict "$cmd" "$wtb")"
done
tl_eq 'a push of main from a project that protects other branches' 'allow' "$(verdict "git push origin main" "$other")"
tl_eq 'and after a cd into it from a session with no config' 'allow' "$(verdict "cd $other && git push origin main" "$plain")"
tl_eq 'a plain gh merge into an allowed base' 'allow' "$(verdict 'gh pr merge 12 --merge' "$wtb")"
tl_eq 'a merge into a base not allowed is still denied' 'deny' "$(verdict 'gh pr merge 13 --merge' "$wtb")"
tl_eq 'a session with no config anywhere has no opinion on any form' 'allow' "$(verdict 'env git push origin main && sh -c "git push origin main"' "$plain")"
tl_eq 'the denial says how to write the command' 'yes' "$(node -e 'console.log(JSON.stringify({tool_input: {command: process.argv[1]}, cwd: process.argv[2]}))' 'env git push origin main' "$wtb" | bash "$HOOK" | grep -q 'one invocation per command' && echo yes || echo no)"

printf '\nthe review of #24\n'
issueonly="$(tl_repo)"
git -C "$issueonly" switch -q -c 7-x
review_deny=(
  'a substitution in a message::git commit -m "$(git push origin main)"'
  'a substitution in a cd::cd "$(git push origin main; echo .)"'
  'a substitution in an assignment before a command::X=$(git push origin main) git status'
  'a process substitution::diff <(git push origin main) /dev/null'
  'a substitution in a gh body::gh issue comment 3 --body "$(git push origin main)"'
  'push --all::git push --all origin'
  'push --mirror::git push --mirror origin'
  'push --branches::git push --branches origin'
  'the refspec ":"::git push origin :'
  'the refspec "+:"::git push origin +:'
  'a glob refspec::git push origin "refs/heads/*:refs/heads/*"'
  'a star in a name::git push origin "ma*"'
  'heads/ without refs/::git push origin heads/main'
  'a brace list::git push origin {main,x}'
  'a default in a variable::git push origin ${B:-main}'
  'a default without colon::git push origin ${B-main}'
  'a quoted default::BRANCH=; git push origin "${BRANCH:-main}"'
  'a default assigned::git push origin ${B:=main}'
  'the current branch by substitution on develop::git push origin "$(git branch --show-current)"'
  'the current branch by rev-parse on develop::git push origin $(git rev-parse --abbrev-ref HEAD)'
  'a -c on a push::git -c core.x=y push origin 21-x && echo main'
)
for entry in "${review_deny[@]}"; do
  label="${entry%%::*}"
  cmd="${entry#*::}"
  case "$label" in *develop) cwd="$repo" ;; *) cwd="$wtb" ;; esac
  tl_eq "$label" 'deny' "$(verdict "$cmd" "$cwd")"
done
tl_eq 'the current branch by substitution on an issue branch' 'allow' "$(verdict 'git push origin "$(git branch --show-current)"' "$wtb")"
tl_eq 'a commit message with a substitution stays free' 'allow' "$(verdict 'git commit -m "$(date) fix"' "$wtb")"
tl_eq 'a bare push uses the checkout of its own directory' 'allow' "$(verdict "cd $issueonly && git push" "$repo")"
tl_eq 'HEAD too' 'allow' "$(verdict "cd $issueonly && git push origin HEAD" "$repo")"
tl_eq 'GIT_DIR names a project the session has no config for' 'deny' "$(verdict "GIT_DIR=$repo/.git git push origin main" "$plain")"
tl_eq '--git-dir too' 'deny' "$(verdict "git --git-dir=$repo/.git push origin main" "$plain")"
tl_eq 'env -C too' 'deny' "$(verdict "env -C $repo git push origin main" "$plain")"
tl_eq '$PWD is the tracked directory' 'deny' "$(verdict "cd $repo && cd \"\$PWD\" && git push origin main" "$plain")"
tl_eq 'a variable-looking word in a message is not an invocation' 'allow' "$(verdict 'git commit -m "docs: GH_REPO and --git-dir notes, push to main" && git push origin 21-x' "$wtb")"
out="$(node -e 'console.log(JSON.stringify({tool_input: {command: process.argv[1]}, cwd: process.argv[2]}))' 'env git push origin main' "$wtb" | bash "$HOOK")"
tl_has 'the backstop names what it could not judge' 'wrapper' "$out"
tl_has 'and says names, not pushes to' 'names a protected branch' "$out"
out="$(node -e 'console.log(JSON.stringify({tool_input: {command: process.argv[1]}, cwd: process.argv[2]}))' "cd $plain && git push origin main" "$wtb" | bash "$HOOK")"
tl_has 'a candidate denial says whose config judged' 'has no trellis.config' "$out"
chain=''
for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do chain="${chain}cd d$n && "; done
started_ms="$(node -e 'console.log(Date.now())')"
verdict "${chain}git push origin 21-x" "$wtb" > /dev/null
elapsed_ms=$(($(node -e 'console.log(Date.now())') - started_ms))
tl_eq '20 chained cd are judged in linear time' 'fast' "$([ "$elapsed_ms" -le 3000 ] && echo fast || echo "slow: $elapsed_ms ms")"
tl_eq '20 chained cd and a protected push are refused' 'deny' "$(verdict "${chain}git push origin main" "$wtb")"

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
# A group of short flags whose last letter takes a value: 12 is that value (develop, allowed) and 13 is
# the pull request (main, not allowed), so a guard that judges 12 lets the merge through.
for form in '-sb 12 13' '-mF 12 13' '-dt 12 13' '-rsA 12 13' '-bs 13' '-sbtext 13' '-dR x/y 13'; do
  tl_eq "a group of short flags $form judges pull request 13" 'deny' "$(verdict "gh pr merge $form")"
done
tl_eq 'a group ending in a value flag, then an allowed pull request' 'allow' "$(verdict 'gh pr merge -sb 13 12')"
tl_eq 'a group with a letter gh refuses keeps today'"'"'s reading' 'allow' "$(verdict 'gh pr merge -xb 12 13')"
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

printf '\nthe account GitHub is asked as\n'
printf 'tok-acme\n' > "$GH_FIXTURES/token-acme"
printf 'tok-other\n' > "$GH_FIXTURES/token-other"
printf 'tok-acme\n' > "$GH_FIXTURES/need-12"
printf 'tok-acme\n' > "$GH_FIXTURES/need-13"
printf 'tok-other\n' > "$GH_FIXTURES/need-14"
printf 'develop\n' > "$GH_FIXTURES/pr-14"
rawout() {
  node -e 'console.log(JSON.stringify({tool_input: {command: process.argv[1]}, cwd: process.argv[2]}))' "$1" "${2:-$repo}" | bash "$HOOK"
}
calls() { cat "$GH_FIXTURES/calls.log" 2>/dev/null; }
reset() { : > "$GH_FIXTURES/calls.log"; }
set_origin() { git remote remove origin 2>/dev/null; [ -z "${1:-}" ] || git remote add origin "$1"; }

set_origin https://github.com/acme/thing.git
reset
tl_eq 'a pull request only the owner sees is read, and judged by its base' 'allow' "$(verdict 'gh pr merge 12 --merge')"
tl_has 'the merge guard asks with the owner token' 'pr view 12 token=tok-acme' "$(calls)"
tl_eq 'a base not allowed is denied with the owner token' 'deny' "$(verdict 'gh pr merge 13 --merge')"
tl_has 'also read with the owner token' 'pr view 13 token=tok-acme' "$(calls)"
git switch -q 4-thing
printf 'OPEN\n' > "$GH_FIXTURES/issue-4"
reset
tl_eq 'the open-issue guard reads with the owner token' 'deny' "$(verdict 'git switch develop')"
tl_has 'the issue view' 'issue view 4 token=tok-acme' "$(calls)"
printf 'CLOSED\n' > "$GH_FIXTURES/issue-4"
git switch -q develop

printf '\nwhich owner is asked\n'
reset
tl_eq 'by -R' 'allow' "$(verdict 'gh pr merge 14 --merge -R other/thing')"
tl_has 'the -R owner token' 'pr view 14 token=tok-other' "$(calls)"
reset
verdict 'gh pr merge 14 --repo github.com/other/thing' >/dev/null
tl_has 'by --repo with a host' 'pr view 14 token=tok-other' "$(calls)"
reset
verdict 'gh pr merge 14 --repo=https://github.com/other/thing' >/dev/null
tl_has 'by --repo= with a URL' 'pr view 14 token=tok-other' "$(calls)"
reset
verdict 'gh pr merge https://github.com/other/thing/pull/14' >/dev/null
tl_has 'by the URL of the pull request' 'pr view https://github.com/other/thing/pull/14 token=tok-other' "$(calls)"
reset
verdict 'gh pr merge 14 --merge -Rother/thing' >/dev/null
tl_has 'by -R with the value attached' 'pr view 14 token=tok-other' "$(calls)"
for form in '-R=other/thing' '-dR other/thing' '-dRother/thing'; do
  reset
  verdict "gh pr merge 14 --merge $form" >/dev/null
  tl_has "by $form" 'pr view 14 token=tok-other' "$(calls)"
done
reset
verdict 'gh pr merge 12 && gh pr merge 14 -R other/thing' >/dev/null
tl_has 'two owners in one command: the first keeps its token' 'pr view 12 token=tok-acme' "$(calls)"
tl_has 'and the second gets its own' 'pr view 14 token=tok-other' "$(calls)"
reset
verdict 'gh pr merge https://github.com/other/thing/pull/14 -R acme/thing' >/dev/null
tl_has 'the URL of the pull request wins over -R' 'pr view https://github.com/other/thing/pull/14 token=tok-other' "$(calls)"
for form in 'https://github.com:443/acme/thing.git' 'https://github.com/acme/thing' 'https://someone@github.com/acme/thing.git' 'git@github.com:acme/thing.git' \
            'ssh://git@github.com/acme/thing.git' 'ssh://git@github.com:22/acme/thing.git'; do
  set_origin "$form"
  reset
  verdict 'gh pr merge 12' >/dev/null
  tl_has "by the origin $form" 'pr view 12 token=tok-acme' "$(calls)"
done
set_origin https://github.com/ghost/thing.git
reset
tl_eq 'an owner that is not signed in is asked as the active account' 'deny' "$(verdict 'gh pr merge 12')"
tl_has 'with no token' 'pr view 12 token=none' "$(calls)"
set_origin https://gitlab.com/acme/thing.git
reset
verdict 'gh pr merge 12' >/dev/null
tl_has 'another host is asked as the active account' 'pr view 12 token=none' "$(calls)"
tl_lacks 'and no token is looked up' 'auth token' "$(calls)"
set_origin ''
reset
verdict 'gh pr merge 12' >/dev/null
tl_has 'no origin is asked as the active account' 'pr view 12 token=none' "$(calls)"
set_origin 'git@github.com:'
reset
verdict 'gh pr merge 12' >/dev/null
tl_has 'an origin that does not parse is asked as the active account' 'pr view 12 token=none' "$(calls)"
printf 'tok-victim\n' > "$GH_FIXTURES/token-victim"
set_origin 'https://acme.ghe.com/x@github.com/victim/r'
reset
verdict 'gh pr merge 12' >/dev/null
tl_has 'a host hidden after an @ in the path is not github.com' 'pr view 12 token=none' "$(calls)"
tl_lacks 'and its token is not looked up' 'auth token' "$(calls)"
set_origin 'git@github-work:acme/thing.git'
reset
verdict 'gh pr merge 12' >/dev/null
tl_has 'an ssh host alias gives no owner' 'pr view 12 token=none' "$(calls)"
set_origin https://github.com/acme/thing.git

printf '\nan environment gh already reads is left alone\n'
reset
GH_TOKEN=preset verdict 'gh pr merge 12' >/dev/null
tl_has 'GH_TOKEN set' 'pr view 12 token=preset' "$(calls)"
tl_lacks 'no lookup' 'auth token' "$(calls)"
for var in GITHUB_TOKEN GH_HOST GH_REPO; do
  reset
  (export "$var=x"; verdict 'gh pr merge 12' >/dev/null)
  tl_has "$var set: asked as the active account" 'pr view 12 token=none' "$(calls)"
  tl_lacks "$var set: no lookup" 'auth token' "$(calls)"
done
reset
tl_eq 'a token assigned in the command, base allowed' 'allow' "$(verdict 'GH_TOKEN=$(gh auth token -u x) gh pr merge 12')"
tl_eq 'a token assigned in the command, base not allowed' 'deny' "$(verdict 'GH_TOKEN=$(gh auth token -u x) gh pr merge 13')"

printf '\nfailures are named\n'
out="$(rawout 'gh pr merge 99')"
tl_has 'an unreadable base is still a deny' '"deny"' "$out"
tl_has 'naming the account asked' "the owner's account (acme)" "$out"
tl_has 'and the error of gh' 'no pull request 99' "$out"
tl_lacks 'the token is not in the denial' 'tok-acme' "$out"
printf 'x\n' > "$GH_FIXTURES/leak-98"
out="$(rawout 'gh pr merge 98')"
tl_has 'an error that holds the token is still named' 'auth failed for token' "$out"
tl_lacks 'with the token blanked' 'tok-acme' "$out"
out="$(TMPDIR=/nonexistent/dir rawout 'gh pr merge 99' 2>&1)"
tl_has 'with no temporary directory the denial still comes' '"deny"' "$out"
tl_lacks 'and nothing else is printed' 'No such file' "$out"
tl_lacks 'nor an attempt to remove /dev/null' 'rm:' "$out"
set_origin ''
out="$(rawout 'gh pr merge 99')"
tl_has 'the active account when there is no owner' 'the active account' "$out"
set_origin https://github.com/acme/thing.git
git switch -q 4-thing
rm "$GH_FIXTURES/issue-4"
out="$(rawout 'git switch develop')"
tl_has 'a failing issue read is said' '"systemMessage"' "$out"
tl_has 'naming the issue' 'issue 4' "$out"
tl_has 'the account' "the owner's account (acme)" "$out"
tl_has 'and the error' 'HTTP 502: bad gateway' "$out"
tl_lacks 'with no decision' 'permissionDecision' "$out"
tl_eq 'as one object' '1' "$(printf '%s\n' "$out" | grep -c '')"
tl_lacks 'the token is not in the message' 'tok-acme' "$out"
out="$(rawout 'git switch develop && git push origin main')"
tl_eq 'a deny after it is one object holding the message' 'yes' "$(printf '%s' "$out" | node -e 'const o = JSON.parse(require("fs").readFileSync(0, "utf8")); console.log(o.hookSpecificOutput.permissionDecision === "deny" && /issue 4/.test(o.systemMessage) ? "yes" : "no")' 2>/dev/null)"
out="$(rawout 'git switch develop && git status')"
tl_eq 'no deny after it is still one object' 'yes' "$(printf '%s' "$out" | node -e 'const o = JSON.parse(require("fs").readFileSync(0, "utf8")); console.log(!o.hookSpecificOutput && /issue 4/.test(o.systemMessage) ? "yes" : "no")' 2>/dev/null)"
printf 'CLOSED\n' > "$GH_FIXTURES/issue-4"
reset
rawout 'git switch develop && git switch develop' >/dev/null
tl_eq 'two reads for one owner, one lookup of the token' '1' "$(calls | grep -c 'auth token')"
tl_eq 'for two reads' '2' "$(calls | grep -c 'issue view')"
git switch -q develop

tl_done
