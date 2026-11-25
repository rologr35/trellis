#!/usr/bin/env bash
# Exercises hooks/guard-git.sh with payloads as Claude Code sends them and a stubbed gh.
. "$(dirname "$0")/../lib/testlib.sh"

HOOK="$TRELLIS_ROOT/hooks/guard-git.sh"
stubs="$TL_TMP/stubs"
mkdir -p "$stubs"
# gh answers only `api`, as in a cloud session, where the rest is refused with the text below. It answers
# from files: the state of an issue, the base of a pull request, and the bases of the open ones of a
# branch. Each call is logged with the token it ran with (fake values), `need-<n>` makes a pull request
# visible to that token only, `where-<n>` is the only repository that has it, and `auth token -u <user>`
# prints token-<user> or fails, as gh does for an account that is not signed in. An error has its body on
# stdout, as that of gh api has.
cat > "$stubs/gh" <<'GH'
#!/bin/sh
tok="${GH_TOKEN:-none}"
printf '%s %s token=%s\n' "$1" "$2" "$tok" >> "$GH_FIXTURES/calls.log"
fail() { echo '{"message":"Not Found"}'; echo "$1" >&2; exit 1; }
if [ "$1 $2" = 'auth token' ]; then
  user=''; prev=''
  for a in "$@"; do [ "$prev" = -u ] && user="$a"; prev="$a"; done
  cat "$GH_FIXTURES/token-$user" 2>/dev/null || exit 1
  exit 0
fi
[ "$1" = 'api' ] || { echo 'GitHub GraphQL is not available from Claude Code sessions; use the REST API' >&2; exit 1; }
n="${2##*/}"
repo="${2#repos/}"
case "$2" in
  repos/*/*/issues/[0-9]*)
    [ -f "$GH_FIXTURES/issue-$n" ] || fail "HTTP 502: bad gateway (issue $n)"
    cat "$GH_FIXTURES/issue-$n" ;;
  repos/*/*/pulls/[0-9]*)
    if [ -f "$GH_FIXTURES/need-$n" ] && [ "$tok" != "$(cat "$GH_FIXTURES/need-$n")" ]; then
      fail "gh: Not Found (HTTP 404) (pull request $n)"
    fi
    if [ -f "$GH_FIXTURES/where-$n" ] && [ "${repo%/pulls/*}" != "$(cat "$GH_FIXTURES/where-$n")" ]; then
      fail "gh: Not Found (HTTP 404) (${repo%/pulls/*})"
    fi
    [ -f "$GH_FIXTURES/leak-$n" ] && fail "auth failed for token $tok"
    cat "$GH_FIXTURES/pr-$n" 2>/dev/null || fail "no pull request $n" ;;
  repos/*/*/pulls)
    for a in "$@"; do case "$a" in head=*) cat "$GH_FIXTURES/$a" 2>/dev/null ;; esac; done
    exit 0 ;;
  *) fail "gh: Not Found (HTTP 404)" ;;
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
printf 'open\n' > "$GH_FIXTURES/issue-4"
tl_eq 'away from a branch whose issue is open' 'deny' "$(verdict 'git switch develop')"
printf 'closed\n' > "$GH_FIXTURES/issue-4"
tl_eq 'away from a branch whose issue is closed' 'allow' "$(verdict 'git switch develop')"
rm "$GH_FIXTURES/issue-4"
tl_eq 'gh failing is no opinion' 'allow' "$(verdict 'git switch develop')"
git switch -q develop
wt="$TL_TMP/wt"
git worktree add -q "$wt" -b 5-other
tl_eq 'a worktree is the session'"'"'s own' 'allow' "$(verdict 'git switch -c 6-more' "$wt")"

printf '\na branch switch outside the project of the session (#47)\n'
clone="$TL_TMP/a clone"
git clone -q "$repo" "$clone"
git -C "$clone" switch -q develop
git -C "$clone" branch 8-done
mkdir -p "$clone/sub"
# A project with a repository of its own, whose main checkout is nothing of the session.
zephyr="$(tl_repo)"
cp trellis.config "$zephyr/"
ln -s "$repo" "$TL_TMP/link"
# at <command> [<directory of the session>]: the session as the project (the payload is then the
# clone) or as the directory of the payload.
at() {
  if [ "$as" = project ]; then
    CLAUDE_PROJECT_DIR="${2:-$repo}" verdict "$1" "$clone"
  else
    verdict "$1" "${2:-$repo}"
  fi
}
for as in project payload; do
  tl_eq "$as: a clone creates an issue branch" 'allow' "$(at "cd '$clone' && git switch -c 7-thing")"
  tl_eq "$as: and switches to one" 'allow' "$(at "cd '$clone' && git checkout 8-done")"
  tl_eq "$as: by git -C too" 'allow' "$(at "git -C '$clone' switch -c 7-thing")"
  tl_eq "$as: another project too" 'allow' "$(at "cd '$zephyr' && git switch -c 7-thing")"
  git -C "$clone" switch -q 8-done
  printf 'open\n' > "$GH_FIXTURES/issue-8"
  tl_eq "$as: a clone leaves a branch whose issue is open" 'allow' "$(at "cd '$clone' && git switch develop")"
  rm "$GH_FIXTURES/issue-8"
  git -C "$clone" switch -q develop
  tl_eq "$as: the main checkout of the session refuses to create one" 'deny' "$(at "cd '$repo' && git switch -c 7-thing")"
  tl_eq "$as: and to switch to one" 'deny' "$(at "cd '$repo' && git checkout 4-thing")"
  tl_eq "$as: from one of its worktrees" 'deny' "$(at "git -C '$repo' switch -c 7-thing" "$wt")"
  tl_eq "$as: by a path with a symbolic link" 'deny' "$(at "git -C '$TL_TMP/link' switch -c 7-thing")"
  tl_eq "$as: with the session on that path" 'deny' "$(at "git -C '$repo' switch -c 7-thing" "$TL_TMP/link")"
  tl_eq "$as: after a cd out and back" 'deny' "$(at "cd '$clone' && cd '$repo' && git switch -c 7-thing")"
  tl_eq "$as: a push to a protected branch of the clone is refused" 'deny' "$(at "cd '$clone' && git push origin main")"
  tl_eq "$as: and a merge" 'deny' "$(at "cd '$clone' && gh pr merge")"
  git switch -q 4-thing
  printf 'open\n' > "$GH_FIXTURES/issue-4"
  tl_eq "$as: the main checkout does not leave a branch whose issue is open" 'deny' "$(at "git -C '$repo' switch develop")"
  rm "$GH_FIXTURES/issue-4"
  git switch -q develop
done
tl_eq 'a session inside the clone, of another project' 'allow' "$(CLAUDE_PROJECT_DIR="$repo" verdict 'git switch -c 7-thing' "$clone/sub")"
tl_eq 'a session inside the clone, with no project, is judged as today' 'deny' "$(verdict 'git switch -c 7-thing' "$clone/sub")"
tl_eq 'a project in no repository is the directory of the payload' 'deny' "$(CLAUDE_PROJECT_DIR="$plain" verdict 'git switch -c 7-thing' "$clone")"
tl_eq '  which leaves the clone to itself' 'allow' "$(CLAUDE_PROJECT_DIR="$plain" verdict "cd '$clone' && git switch -c 7-thing" "$repo")"
tl_eq 'a project that is empty too' 'deny' "$(CLAUDE_PROJECT_DIR='' verdict 'git switch -c 7-thing' "$clone")"
tl_eq 'a session in no repository is judged as today' 'deny' "$(verdict "cd '$clone' && git switch -c 7-thing" "$plain")"
tl_eq '  with a project in none' 'deny' "$(CLAUDE_PROJECT_DIR="$plain" verdict "cd '$repo' && git switch -c 7-thing" "$plain")"

printf '\nthe command of a worktree: git.worktreeAdd (#48)\n'
# reason <command>: what the refusal says.
reason() {
  node -e 'console.log(JSON.stringify({tool_input: {command: process.argv[1]}, cwd: process.argv[2]}))' "$1" "$repo" | bash "$HOOK" |
    node -e 'const out = require("fs").readFileSync(0, "utf8"); process.stdout.write(out ? JSON.parse(out).hookSpecificOutput.permissionDecisionReason : "")'
}
printf 'open\n' > "$GH_FIXTURES/issue-4"
# away: the second refusal, from the branch of an open issue.
away() { git switch -q 4-thing; reason 'git switch develop'; git switch -q develop; }
cp trellis.config "$TL_TMP/config.keep"
to_default='The main checkout stays on develop: every issue is worked in its own worktree. Run trellis worktree add <n> <slug> (fetches, creates .claude/worktrees/<n>-<slug>, installs, prints the path), then EnterWorktree with that path.'
away_default='The main checkout is on 4-thing and issue 4 is still open: another session may be working there, and a switch puts its next commit on the wrong branch. Take the new work in a worktree: trellis worktree add <m> <slug>, then EnterWorktree. A person frees the checkout with !git checkout develop.'
tl_eq 'with no key, the refusal of a switch to an issue branch is the one of before' "$to_default" "$(reason 'git switch -c 7-thing')"
tl_eq '  and so is the one of a switch away' "$away_default" "$(away)"
git config -f trellis.config git.worktreeAdd 'trellis worktree add'
tl_eq 'with the default written, too' "$to_default" "$(reason 'git switch -c 7-thing')"
git config -f trellis.config git.worktreeAdd 'bin/tree new'
tl_eq 'with another, the refusal names it, without what trellis worktree add does' 'The main checkout stays on develop: every issue is worked in its own worktree. Run bin/tree new <n> <slug>, then EnterWorktree with that path.' "$(reason 'git switch -c 7-thing')"
tl_eq '  and so does the one of a switch away' "${away_default/trellis worktree add/bin/tree new}" "$(away)"
cp "$TL_TMP/config.keep" trellis.config
rm "$GH_FIXTURES/issue-4"

printf '\nissue creation\n'
transcript="$TL_TMP/transcript.jsonl"
printf '{"message": {"content": [{"type": "tool_use", "input": {"command": "ls"}}]}}\n' > "$transcript"
tl_eq 'without a search' 'deny' "$(verdict 'gh issue create --title x' "$repo" "$transcript")"
tl_eq 'trellis issue create without a search' 'deny' "$(verdict 'trellis issue create --title x --body-file b.md' "$repo" "$transcript")"
tl_eq 'after a cd and an assignment, too' 'deny' "$(verdict "cd $repo && X=1 trellis issue create --title x --body-file b.md" "$plain" "$transcript")"
tl_eq 'by the path of the script, too' 'deny' "$(verdict './bin/trellis issue create --title x --body-file b.md' "$repo" "$transcript")"
for form in 'issue new' '-R a/b issue new' '--repo a/b issue new' '--repo=a/b issue new' '-Ra/b issue new' 'issue -R a/b new' 'issue --repo=a/b new' 'issue new -R a/b' '-R a/b issue create' 'issue -R a/b create'; do
  tl_eq "gh $form without a search" 'deny' "$(verdict "gh $form --title x" "$repo" "$transcript")"
done
tl_eq 'gh issue list needs no search' 'allow' "$(verdict 'gh issue -R a/b list' "$repo" "$transcript")"
tl_eq 'a view of something named new needs no search' 'allow' "$(verdict 'gh issue view new' "$repo" "$transcript")"
tl_eq 'trellis issue check needs no search' 'allow' "$(verdict 'trellis issue check --body b.md' "$repo" "$transcript")"
tl_eq 'a title of trellis issue create without a search is denied for the search' 'deny' "$(verdict "trellis issue create --title 'never push to main' --body-file b.md" "$repo" "$transcript")"
printf '{"message": {"content": [{"type": "tool_use", "input": {"command": "gh issue list --search login"}}]}}\n' >> "$transcript"
tl_eq 'after a search' 'allow' "$(verdict 'gh issue create --title x' "$repo" "$transcript")"
for form in 'issue new' '-R a/b issue new' 'issue -R a/b new' 'issue new -R a/b' 'issue -R a/b create'; do
  tl_eq "gh $form after a search" 'allow' "$(verdict "gh $form --title x" "$repo" "$transcript")"
done
tl_eq 'trellis issue create after a search' 'allow' "$(verdict 'trellis issue create --title x --body-file b.md' "$repo" "$transcript")"
tl_eq 'the words of its title are data, as those of gh issue create are' 'allow' "$(verdict "trellis issue create --title 'never push to main, nor gh pr merge' --body-file b.md" "$repo" "$transcript")"
tl_eq 'a push in a substitution of its title is judged' 'deny' "$(verdict 'trellis issue create --title "$(git push origin main)" --body-file b.md' "$repo" "$transcript")"
tl_eq 'another trellis subcommand with those words is not judged' 'deny' "$(verdict "trellis other 'push main'" "$repo" "$transcript")"
tl_eq 'a wrapper in front of it is not judged either' 'deny' "$(verdict "env trellis issue create --title 'never push to main'" "$repo" "$transcript")"
for search in "gh api search/issues -X GET -f q='repo:a/b login'" "GH_TOKEN=x gh api -X GET search/issues -f q=login" \
  "gh api 'search/issues?q=login'" 'gh api "/search/issues?q=login"' 'gh api /search/issues?q=login' \
  'bash -c "gh api \"search/issues?q=login\""'; do
  node -e 'console.log(JSON.stringify({message: {content: [{type: "tool_use", input: {command: process.argv[1]}}]}}))' "$search" > "$transcript"
  tl_eq "after $search" 'allow' "$(verdict 'gh issue create --title x' "$repo" "$transcript")"
done
for other in "gh api 'search/issuesx?q=login'" "gh api 'repos/a/search/issues'" "gh api 'search/code?q=login'"; do
  node -e 'console.log(JSON.stringify({message: {content: [{type: "tool_use", input: {command: process.argv[1]}}]}}))' "$other" > "$transcript"
  tl_eq "after $other" 'deny' "$(verdict 'gh issue create --title x' "$repo" "$transcript")"
done
printf '{"message": {"content": [{"type": "tool_use", "input": {"command": "gh api repos/a/b/issues"}}]}}\n' > "$transcript"
tl_eq 'a read of the issues is not a search' 'deny' "$(verdict 'gh issue create --title x' "$repo" "$transcript")"
tl_eq 'no transcript is no opinion' 'allow' "$(verdict 'gh issue create --title x')"

printf '\nthe searches of a project: tracker.search (#48)\n'
# said <command>: a transcript where the session ran that command, and the creation.
said() {
  node -e 'for (const command of process.argv.slice(1)) console.log(JSON.stringify({message: {content: [{type: "tool_use", input: {command}}]}}))' "$1" 'gh issue create --title x' > "$transcript"
}
# The verdict of a creation after it.
created() { verdict 'gh issue create --title x' "$repo" "$transcript"; }
cp trellis.config "$TL_TMP/config.keep"
said 'bin/backlog find "login"'
tl_eq 'a search of the project does not count without the key' 'deny' "$(created)"
git config -f trellis.config tracker.search '(^|\s)bin/backlog (find|search) '
tl_eq 'with the key it does' 'allow' "$(created)"
tl_eq '  from the directory a cd names, whose config it is' 'allow' "$(verdict "cd '$repo' && gh issue create --title x" "$zephyr" "$transcript")"
tl_eq '  and not in a project without the key' 'deny' "$(verdict "cd '$zephyr' && gh issue create --title x" "$repo" "$transcript")"
tl_eq '  nor after a command in the one that has it' 'deny' "$(verdict "git push origin 5-x && cd '$zephyr' && gh issue create --title x" "$repo" "$transcript")"
said 'bin/backlog list'
tl_eq 'a command it does not match is no search' 'deny' "$(created)"
node -e 'console.log(JSON.stringify({message: {content: [{type: "tool_use", input: {command: process.argv[1]}}]}}))' 'gh issue create --title "a bin/backlog find x"' > "$transcript"
tl_eq 'nor is the creation itself' 'deny' "$(verdict 'gh issue create --title "a bin/backlog find x"' "$repo" "$transcript")"
git config -f trellis.config --add tracker.search 'issues-db\b'
said 'issues-db login'
tl_eq 'the second value counts' 'allow' "$(created)"
said 'cd x && bin/backlog find login'
tl_eq '  and the first still does' 'allow' "$(created)"
said 'gh issue list --state all --search login'
tl_eq 'a search by gh issue list counts with the key' 'allow' "$(created)"
said "gh api -X GET search/issues -f q='repo:a/b login'"
tl_eq '  and one by gh api' 'allow' "$(created)"
said 'ls'
tl_eq 'and what is neither does not' 'deny' "$(created)"
# A value that is none, for what the session says and for a command it would match.
for value in '(' 'x*' '' '^$|find' '^ls|find' 'git +st|find' '.'; do
  git config -f trellis.config --replace-all tracker.search "$value"
  said 'bin/backlog find ( x git status'
  tl_eq "a value that is none: '$value'" 'deny' "$(created)"
  git config -f trellis.config --add tracker.search 'backlog find'
  tl_eq '  and a good one beside it counts' 'allow' "$(created)"
done
# A value that matches a creation is none: a creation refused before is no search for the next one.
for value in 'issue' 'gh issue c' 'issue new' 'trellis issue'; do
  git config -f trellis.config --replace-all tracker.search "$value"
  for creation in 'gh issue create --title a' 'gh issue new --title a' 'trellis issue create --title a'; do
    said "$creation"
    tl_eq "a value that matches a creation: '$value', after $creation" 'deny' "$(created)"
  done
done
cp "$TL_TMP/config.keep" trellis.config

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
# Only x/y has pull request 23, so it is judged when x/y is what is read.
printf 'develop\n' > "$GH_FIXTURES/pr-23"
printf 'x/y\n' > "$GH_FIXTURES/where-23"
tl_eq 'a group ending in -R names the repository that is read' 'allow' "$(verdict 'gh pr merge -dR x/y 23')"
tl_eq 'and without it the one of origin is read' 'deny' "$(verdict 'gh pr merge -d 23')"
rm "$GH_FIXTURES/where-23"
tl_eq 'a group ending in a value flag, then an allowed pull request' 'allow' "$(verdict 'gh pr merge -sb 13 12')"
tl_eq 'a group with a letter gh refuses keeps today'"'"'s reading' 'allow' "$(verdict 'gh pr merge -xb 12 13')"
printf 'develop\n' > "$GH_FIXTURES/head={owner}:20-thing"
printf 'main\n' > "$GH_FIXTURES/head={owner}:21-thing"
printf 'develop\nmain\n' > "$GH_FIXTURES/head={owner}:22-thing"
printf 'develop\n' > "$GH_FIXTURES/head=fork:20-thing"
tl_eq 'a branch whose pull request goes into an allowed base' 'allow' "$(verdict 'gh pr merge 20-thing --merge')"
tl_eq 'a branch whose pull request does not' 'deny' "$(verdict 'gh pr merge 21-thing --merge')"
tl_eq 'a branch with two pull requests, one of them not' 'deny' "$(verdict 'gh pr merge 22-thing --merge')"
tl_eq 'a branch with no open pull request' 'deny' "$(verdict 'gh pr merge 23-thing --merge')"
tl_eq 'the branch of a fork' 'allow' "$(verdict 'gh pr merge fork:20-thing --merge')"
tl_eq 'a number written with #' 'allow' "$(verdict "gh pr merge '#12' --merge")"
tl_eq 'a URL that is not of a pull request' 'deny' "$(verdict 'gh pr merge https://github.com/acme/thing/issues/12')"
tl_eq 'a URL of one of its tabs' 'allow' "$(verdict 'gh pr merge https://github.com/acme/thing/pull/12/files')"
tl_eq 'a repository that does not parse is not read as the one of origin' 'deny' "$(verdict 'gh pr merge 12 -R nothing')"
tl_eq 'nor is a variable the shell would fill in' 'deny' "$(verdict 'gh pr merge 12 -R "$OTHER/thing"')"
tl_eq 'from a cloud session' 'deny' "$(CLAUDE_CODE_REMOTE=1 verdict 'gh pr merge 12')"

printf '\nwrites by gh api (#41)\n'
# Judged from a repository whose config protects main, develop and staging. R/ is a REST path.
R='repos/o/r'
api_deny=(
  'graphql: mergePullRequest::gh api graphql -f query="mutation{mergePullRequest(input:{pullRequestId:1}){clientMutationId}}"'
  'graphql: enablePullRequestAutoMerge::gh api graphql -f query="mutation { enablePullRequestAutoMerge(input: {}) { clientMutationId } }"'
  'graphql: enqueuePullRequest::gh api graphql -f query="mutation { enqueuePullRequest(input: {}) { clientMutationId } }"'
  'graphql: mergeBranch::gh api graphql -f query="mutation { mergeBranch(input: {}) { clientMutationId } }"'
  'graphql: createCommitOnBranch::gh api graphql -f query="mutation { createCommitOnBranch(input: {}) { clientMutationId } }"'
  'graphql: createRef::gh api graphql -f query="mutation { createRef(input: {}) { clientMutationId } }"'
  'graphql: updateRef::gh api graphql -f query="mutation { updateRef(input: {}) { clientMutationId } }"'
  'graphql: updateRefs::gh api graphql -f query="mutation { updateRefs(input: {}) { clientMutationId } }"'
  'graphql: deleteRef::gh api graphql -f query="mutation { deleteRef(input: {}) { clientMutationId } }"'
  'graphql: an aliased mutation on a line of its own::gh api graphql -f query='"'"'mutation($id: ID!) {
  x: mergePullRequest(input: {pullRequestId: $id}) { clientMutationId }
}'"'"' -F id=1'
  'graphql: --raw-field::gh api graphql --raw-field query="mutation{mergePullRequest}"'
  'graphql: --raw-field=::gh api graphql --raw-field=query="mutation{mergePullRequest}"'
  'graphql: --field::gh api graphql --field query="mutation{mergePullRequest}"'
  'graphql: -F::gh api graphql -F query="mutation{mergePullRequest}"'
  'graphql: a glued -f::gh api graphql -fquery="mutation{mergePullRequest}"'
  'graphql: -f= ::gh api graphql -f=query="mutation{mergePullRequest}"'
  'graphql: the field before the endpoint::gh api -f query="mutation{mergePullRequest}" graphql'
  'graphql: a group of short flags::gh api -if query="mutation{mergePullRequest}" graphql'
  'graphql: -X POST::gh api -X POST graphql -f query="mutation{mergePullRequest}"'
  'graphql: a leading slash::gh api /graphql -f query="mutation{mergePullRequest}"'
  'graphql: a URL::gh api https://api.github.com/graphql -f query="mutation{mergePullRequest}"'
  'graphql: the URL of another host::gh api https://ghe.example.com/api/graphql -f query="mutation{mergePullRequest}"'
  'graphql: after a pipe::echo x | gh api graphql -f query="mutation{mergePullRequest}"'
  'graphql: after an assignment::GH_TOKEN=x gh api graphql -f query="mutation{mergePullRequest}"'
  'graphql: in a substitution::echo "$(gh api graphql -f query="mutation{mergePullRequest}")"'
  'graphql: --input::gh api graphql --input q.json'
  'graphql: --input=::gh api graphql --input=q.json'
  'graphql: standard input::gh api graphql --input - <<EOF
{"query": "query { viewer { login } }"}
EOF'
  'graphql: a query of a file::gh api graphql -F query=@q.graphql'
  'graphql: a query of standard input::gh api graphql -F query=@- < q.graphql'
  'graphql: a query of a substitution::gh api graphql -f query="$(cat q.graphql)"'
  'graphql: a query of backticks::gh api graphql -f query="`cat q.graphql`"'
  'graphql: a query of a variable::gh api graphql -f query="$QUERY"'
  'graphql: a query of a variable in braces::gh api graphql -f query=${QUERY}'
  'graphql: a query of a variable the command assigned::Q="query{viewer{login}}"; gh api graphql -f query="$Q"'
  'graphql: part of the query of a variable::gh api graphql -f query='"'"'mutation { '"'"'"$M"'"'"' { id } }'"'"''
  'graphql: a query of a positional parameter::gh api graphql -f query="$1"'
  'graphql: a field only the shell can read::gh api graphql -f "$FIELD"'
  'merges: the form of the Context::gh api -X POST R/merges -f base=main -f head=x'
  'merges: the method by default::gh api R/merges -f base=main -f head=x'
  'merges: -F::gh api R/merges -F base=main -F head=x'
  'merges: a ref as base::gh api R/merges -f base=refs/heads/main -f head=x'
  'merges: no base::gh api R/merges -f head=x'
  'merges: a base of a variable::gh api R/merges -f base="$B" -f head=x'
  'merges: a base of a variable the command assigned::B=main; gh api R/merges -f base="$B" -f head=x'
  'merges: a base of a file::gh api R/merges -F base=@base.txt -f head=x'
  'merges: the branch gh fills in::gh api R/merges -F base={branch} -f head=x'
  'merges: the body of a file::gh api R/merges --input body.json'
  'merges: the body of a file, with a base field::gh api R/merges --input body.json -f base=41-x'
  'merges: a base in the query string::gh api -X POST "R/merges?base=main&head=x"'
  'merges: a placeholder repository::gh api repos/{owner}/{repo}/merges -f base=main -f head=x'
  'merges: the old placeholder::gh api repos/:owner/:repo/merges -f base=main -f head=x'
  'merges: the repository of a variable::gh api repos/$REPO/merges -f base=main -f head=x'
  'merges: owner and name of variables::gh api "repos/$O/$N/merges" -f base=main -f head=x'
  'merges: a method of a variable::gh api -X "$METHOD" R/merges -f base=main -f head=x'
  'merges: a numeric repository::gh api repositories/12/merges -f base=main -f head=x'
  'refs: the form of the Context::gh api -X PATCH R/git/refs/heads/main -f sha=abc'
  'refs: -XPATCH::gh api -XPATCH R/git/refs/heads/main -f sha=abc'
  'refs: -X=PATCH::gh api -X=PATCH R/git/refs/heads/main -f sha=abc'
  'refs: --method::gh api --method PATCH R/git/refs/heads/main -f sha=abc'
  'refs: --method=::gh api --method=PATCH R/git/refs/heads/main -f sha=abc'
  'refs: a lower-case method::gh api -X patch R/git/refs/heads/main -f sha=abc'
  'refs: a method glued to another short flag::gh api -iXPATCH R/git/refs/heads/main -f sha=abc'
  'refs: the last method counts::gh api -X GET -X PATCH R/git/refs/heads/main -f sha=abc'
  'refs: POST by default::gh api R/git/refs/heads/main -f sha=abc'
  'refs: a delete::gh api -X DELETE R/git/refs/heads/main'
  'refs: the flags after the endpoint::gh api R/git/refs/heads/main --silent -f sha=abc --jq .ref -X PATCH'
  'refs: a flag before api::gh -X PATCH api R/git/refs/heads/main -f sha=abc'
  'refs: after --::gh api -X DELETE -- R/git/refs/heads/main'
  'refs: a leading slash::gh api -X DELETE /R/git/refs/heads/main'
  'refs: a URL::gh api -X DELETE https://api.github.com/R/git/refs/heads/main'
  'refs: the URL of another host::gh api -X DELETE https://ghe.example.com/api/v3/R/git/refs/heads/main'
  'refs: quotes inside the path::gh api -X DELETE R/git/refs/heads/"ma"in'
  'refs: percent-encoded::gh api -X DELETE R/git/refs/heads%2Fmain'
  'refs: a percent-encoded letter::gh api -X DELETE R/git/%72efs/heads/main'
  'refs: an empty and a dot segment::gh api -X DELETE R//git/./refs/heads/main'
  'refs: a dot-dot segment::gh api -X DELETE R/issues/../git/refs/heads/main'
  'refs: another protected branch::gh api -X DELETE R/git/refs/heads/develop'
  'refs: the ref field::gh api R/git/refs -f ref=refs/heads/main -f sha=abc'
  'refs: the ref field of --input::gh api R/git/refs --input body.json'
  'refs: no ref field::gh api R/git/refs -f sha=abc'
  'refs: a ref of a variable::gh api R/git/refs -f ref=refs/heads/$B -f sha=abc'
  'refs: a path of a variable::gh api -X DELETE R/git/refs/heads/$b'
  'refs: a path of a substitution::gh api -X DELETE "R/git/refs/$(cat ref)"'
  'refs: the branch gh fills in::gh api -X DELETE R/git/refs/heads/{branch}'
  'refs: a variable in braces with a default::gh api -X DELETE R/git/refs/heads/${B:-main}'
  'refs: a variable the command assigned::B=main; gh api -X DELETE R/git/refs/heads/$B'
  'refs: an endpoint of a variable the command assigned::E=R/git/refs/heads/main; gh api -X DELETE "$E"'
  'refs: a brace list::gh api -X DELETE R/git/refs/heads/{main,x}'
  'refs: flags of a variable::gh api R/git/refs/heads/main $FLAGS'
  'contents: the form of the Context::gh api -X PUT R/contents/a.txt -f branch=main -f message=m -f content=eA=='
  'contents: no branch::gh api -X PUT R/contents/a.txt -f message=m -f content=eA=='
  'contents: a delete::gh api -X DELETE R/contents/a.txt -f branch=main -f message=m -f sha=abc'
  'contents: a delete with no branch::gh api --method=DELETE R/contents/a.txt -f message=m -f sha=abc'
  'contents: a branch in the query string::gh api -X DELETE "R/contents/a.txt?branch=main&sha=abc&message=m"'
  'contents: a branch of a variable::gh api -X PUT R/contents/a.txt -f branch=$B -f message=m'
  'contents: the body of a file::gh api -X PUT R/contents/a.txt --input body.json'
  'contents: a path of a variable::gh api -X PUT "R/contents/$f" -f branch=main'
  'contents: a placeholder repository::gh api -X PUT repos/{owner}/{repo}/contents/a.txt -f branch=develop'
  'contents: in a loop::for f in a b; do gh api -X PUT R/contents/$f -f message=m; done'
  'graphql: an escape of ANSI-C quoting::gh api graphql -f query=$'"'"'mutation{mergePull\x52equest}'"'"''
  'refs: words of a variable the command assigned::A="-X DELETE R/git/refs/heads/main"; gh api $A'
  'refs: words of an array::gh api "${ARGS[@]}" -X DELETE'
  'refs: the arguments of a script after the endpoint::gh api R/git/refs/heads/main "$@"'
  'refs: api in a variable::S=api; gh $S -X DELETE R/git/refs/heads/main'
  'refs: gh in a variable::GH=gh; $GH api -X DELETE R/git/refs/heads/main'
  'refs: an empty ref::gh api R/git/refs -f ref= -f sha=abc'
  'contents: an empty branch::gh api -X PUT R/contents/a.txt -f branch= -f message=m'
  'contents: a method in a header::gh api -H "X-HTTP-Method-Override: PUT" R/contents/a.txt -f message=m'
  'a write in a host of a variable::gh api -X PUT "https://api.github.com$P/x"'
  'a merge whose end is a variable::gh api -X PUT "R/pulls/$P"'
  'a wrapper: timeout::timeout 10 gh api graphql -F query=@x'
  'a wrapper: find -exec::find . -name x -exec gh api -X DELETE R/git/refs/heads/main \;'
  'a write in an endpoint of a variable::gh api -X PUT "$ENDPOINT" -f message=m'
  'a write in the owner of a variable::gh api -X PUT "repos/$O/r/contents/a.txt" -f message=m'
  'a write in an endpoint whose kind is a variable::gh api -X PUT "R/$KIND/a.txt" -f message=m'
  'pulls/<n>/merge::gh api -X PUT R/pulls/13/merge'
  'pulls/<n>/merge, percent-encoded::gh api -X PUT R/pulls/13/m%65rge'
  'a wrapper: env::env gh api -X DELETE R/git/refs/heads/main'
  'a wrapper: command::command gh api graphql -f query="mutation{mergePullRequest}"'
  'a wrapper: an absolute path::/usr/bin/gh api -X PUT R/contents/a.txt -f branch=main'
  'a wrapper: sh -c::sh -c "gh api -X PATCH R/git/refs/heads/main -f sha=abc"'
  'a wrapper: sh -c of graphql::sh -c "gh api graphql -f query=\"mutation{mergePullRequest}\""'
  'a wrapper: sh -c of a query of a file::bash -lc "gh api graphql -F query=@q.graphql"'
  'a wrapper: eval::eval "gh api R/merges -f base=main -f head=x"'
  'a wrapper: a command held in a variable::C="gh api R/merges -f base=main -f head=x"; $C'
  'a wrapper: a piped script::echo "gh api R/merges -f base=main -f head=x" | sh'
  'a wrapper: a here-document::bash <<EOF
gh api -X DELETE R/git/refs/heads/main
EOF'
  'a wrapper: xargs::echo main | xargs -I{} gh api -X DELETE R/git/refs/heads/{}'
  'a wrapper: xargs of the endpoint::echo R/contents/a.txt | xargs gh api -X PUT -f message=m'
  'a flag of a variable, glued::M=-XDELETE; gh api $M R/git/refs/heads/main'
  'a flag of a variable, long::M=--method=DELETE; gh api $M R/git/refs/heads/main'
  'a flag of a variable and its value::F=-X; gh api $F PUT R/contents/a.txt -f message=m'
  'a merge with a flag of a variable::M=-XPUT; gh api $M R/pulls/13/merge'
  'words of a variable the command does not assign::gh api $ARGS'
  'words of a substitution::gh api $(cat args)'
  'a variable that may hold the end of the path::gh api -X DELETE "repos/$X"'
  'a variable that may hold the end of the path, after the owner::gh api -X PUT "repos/o/$X" -f message=m'
  'a variable that may hold the end of the path, by id::gh api -X DELETE "repositories/$X"'
  'a field of a variable next to an issue branch::gh api R/merges -f base=41-x -f "$FIELD" -f head=x'
  'a field of a variable next to the branch of contents::gh api -X PUT R/contents/a.txt -f branch=41-x -f "$FIELD"'
  'a field whose name is a variable::gh api R/git/refs -f ref=refs/heads/41-x -f "$K=refs/heads/main" -f sha=abc'
  'graphql: an inline query next to --input::gh api graphql -f query="query{viewer{login}}" --input m.json'
  'graphql: an inline query next to flags of a variable::gh api graphql -f query="query{viewer{login}}" $FLAGS'
  'a wrapper: env, the endpoint of a variable::E=R/git/refs/heads/main; env gh api -X DELETE $E'
  'a wrapper: env, an endpoint that cannot be read::env gh api -X DELETE "$E"'
  'a wrapper: xargs, the endpoint of a file::xargs gh api -X DELETE < refs.txt'
  'a wrapper: the field before graphql::sh -c "gh api -F query=@q.graphql graphql"'
  'a wrapper: --input before graphql::sh -c "gh api --input q.json graphql"'
)
for entry in "${api_deny[@]}"; do
  label="${entry%%::*}"
  cmd="${entry#*::}"
  cmd="${cmd//R\//$R/}"
  tl_eq "$label" 'deny' "$(verdict "$cmd")"
done
# A read, or a write that touches no protected branch.
api_allow=(
  'a read::gh api R/pulls/13'
  'a read with a filter::gh api "R/pulls?state=all&per_page=100" --paginate --jq ".[] | {number, title}"'
  'a read of an unquoted query string::gh api R/pulls?state=all'
  'a read of the refs::gh api R/git/refs/heads/main --jq .object.sha'
  'a read of the contents::gh api R/contents/a.txt -H "Accept: application/vnd.github.raw+json"'
  'a read of the contents of main::gh api "R/contents/a.txt?ref=main"'
  'a read with fields::gh api -X GET R/contents/a.txt -f ref=main'
  'a read with fields, --method=get::gh api --method=get R/git/refs -f per_page=1'
  'a read of an endpoint of a variable::gh api "$URL" --jq .sha'
  'a search::gh api -X GET search/issues -f q="repo:o/r merges"'
  'a query::gh api graphql -f query="query { viewer { login } }"'
  'a query with variables::gh api graphql -F owner="$OWNER" -f query='"'"'query($owner: String!) { repository(owner: $owner, name: "r") { id } }'"'"''
  'a query in double quotes with its variables escaped::gh api graphql -F n=1 -f query="query(\$n: Int!) { repository(owner: \"o\", name: \"r\") { issue(number: \$n) { id } } }"'
  'a query of the state of a pull request::gh api graphql -f query="query { node(id: 1) { ... on PullRequest { mergeable mergeStateStatus autoMergeRequest { enabledAt } } } }"'
  'a mutation that touches no branch::gh api graphql -f query="mutation { addComment(input: {subjectId: 1, body: \"x\"}) { clientMutationId } }"'
  'a comment::gh api R/issues/4/comments -f body=hello'
  'a comment of a file::gh api R/issues/4/comments -F body=@c.md'
  'a comment by --input::gh api R/issues/4/comments --input c.json'
  'a comment about main::gh api R/issues/4/comments -f body="the branch main and git/refs/heads/main"'
  'a comment in the issue of a variable::gh api "repos/$REPO/issues/$n/comments" -f body="$BODY"'
  'a label in the issue of a variable::gh api -X DELETE "repos/$REPO/issues/$n/labels/$LABEL"'
  'flags of a variable::gh api R/issues/4/comments $FLAGS'
  'a body of a variable with spaces::B="hello world"; gh api R/issues/4/comments -f body="$B"'
  'a body of a here-document with the words::gh api R/issues/4/comments -f body="$(cat <<'"'"'EOF'"'"'
gh api -X DELETE R/git/refs/heads/main
EOF
)"'
  'a label::gh api R/issues/4/labels -f "labels[]=stopped"'
  'a label taken off::gh api -X DELETE R/issues/4/labels/stopped'
  'an assignee::gh api R/issues/4/assignees -f "assignees[]=o"'
  'a state::gh api -X PATCH R/issues/4 -f state=closed'
  'a pull request::gh api R/pulls -f head=41-x -f base=main -F title=@t -F body=@b -F draft=true'
  'the body of a pull request::gh api -X PATCH R/pulls/13 -F body=@b'
  'a dispatch of a workflow::gh api R/actions/workflows/ci.yml/dispatches -f ref=main'
  'a release of main::gh api R/releases -f tag_name=v1 -f target_commitish=main'
  'a blob::gh api R/git/blobs -f content=x'
  'a commit object::gh api R/git/commits -f message=m -f tree=abc'
  'the ref of an issue branch::gh api R/git/refs -f ref=refs/heads/41-x -f sha=abc'
  'the ref of an issue branch with a variable in it::gh api R/git/refs -f ref="refs/heads/41-$SLUG" -f sha="$SHA"'
  'a delete of an issue branch::gh api -X DELETE R/git/refs/heads/41-x'
  'a delete of an issue branch of a variable the command assigned::B=41-x; gh api -X DELETE R/git/refs/heads/$B'
  'a move of an issue branch by --input::gh api -X PATCH R/git/refs/heads/41-x --input body.json'
  'a branch whose name holds a protected one::gh api -X DELETE R/git/refs/heads/41-main'
  'a tag::gh api R/git/refs -f ref=refs/tags/v1 -f sha=abc'
  'a tag of a variable::gh api R/git/refs -f ref="refs/tags/$T" -f sha=abc'
  'a tag named as a protected branch::gh api -X DELETE R/git/refs/tags/main'
  'a merge into an issue branch::gh api R/merges -f base=41-x -f head=main'
  'a file of an issue branch::gh api -X PUT R/contents/a.txt -f branch=41-x -f message=m -f content=eA=='
  'a file of an issue branch, deleted::gh api -X DELETE R/contents/a.txt -f branch=41-x -f message=m -f sha=abc'
  'a file of an issue branch, in a substitution::SHA=$(gh api -X PUT R/contents/a.txt -f branch=41-x -f message=m --jq .content.sha)'
  'a repository named contents::gh api -X PATCH repos/o/contents -f description=x'
  'the words in another command::git commit -m "gh api graphql with mergePullRequest, and gh api -X PUT of R/contents/a.txt"'
  'the words printed::echo "gh api -X DELETE R/git/refs/heads/main"'
  'the words searched::grep -rn "gh api -X PUT repos/.*/contents/" hooks | head'
  'the words in the body of an issue::gh issue comment 4 --body "gh api -X DELETE R/git/refs/heads/main"'
  'a wrapper of a comment::env gh api R/issues/4/comments -f body=x'
  'a wrapper of a label in the issue of a variable::env gh api -X DELETE "R/issues/$n/labels/x"'
  'an environment in the repository of a variable::gh api -X PUT "repos/$REPO/environments/$ENV"'
  'a ruleset in the repository of a variable::gh api -X PATCH "repos/$REPO/rulesets/$ID" -f name=x'
  'a call of a library, its flags in the arguments::gh api "repos/$GH_REPO_PATH/$endpoint" "$@"'
  'a flag of a variable that reads::M=--paginate; gh api $M R/git/refs'
  'a flag of a variable and an issue branch::M=-XDELETE; gh api $M R/git/refs/heads/41-x'
  'a wrapper of a read::sh -c "gh api R/git/refs/heads/main"'
)
for entry in "${api_allow[@]}"; do
  label="${entry%%::*}"
  cmd="${entry#*::}"
  cmd="${cmd//R\//$R/}"
  tl_eq "$label" 'allow' "$(verdict "$cmd")"
done
tl_eq 'a read of pulls/<n>/merge (whether it is merged)' 'allow' "$(verdict "gh api $R/pulls/13/merge")"
tl_eq 'from a directory without config the session config judges it' 'deny' "$(verdict "cd $plain && gh api -X DELETE $R/git/refs/heads/main" "$repo")"
tl_eq '  and an issue branch passes' 'allow' "$(verdict "cd $plain && gh api -X DELETE $R/git/refs/heads/41-x" "$repo")"
api_other="$(tl_repo)"
printf '[git]\n\tprotected = release\n' > "$api_other/trellis.config"
tl_eq 'the config of the directory decides what is protected' 'allow' "$(verdict "gh api -X DELETE $R/git/refs/heads/main" "$api_other")"
tl_eq '  and its own branch is refused' 'deny' "$(verdict "gh api -X DELETE $R/git/refs/heads/release" "$api_other")"
tl_eq 'with no config anywhere, a write in a repository named in the endpoint' 'deny' "$(verdict "gh api -X DELETE $R/git/refs/heads/41-x" "$plain")"
tl_eq '  a mutation' 'deny' "$(verdict 'gh api graphql -f query="mutation{mergePullRequest}"' "$plain")"
tl_eq '  one by GH_REPO' 'deny' "$(verdict 'GH_REPO=o/r gh api -X DELETE repos/{owner}/{repo}/git/refs/heads/main' "$plain")"
tl_eq '  a write in the repository of the directory has no opinion' 'allow' "$(verdict 'gh api -X DELETE repos/{owner}/{repo}/git/refs/heads/main' "$plain")"
tl_eq '  nor a tag' 'allow' "$(verdict "gh api -X DELETE $R/git/refs/tags/v1" "$plain")"
tl_eq '  nor a comment' 'allow' "$(verdict "gh api $R/issues/4/comments -f body=x" "$plain")"
tl_eq '  nor a read' 'allow' "$(verdict "gh api $R/git/refs/heads/main" "$plain")"

# A hook that times out runs the command unjudged, and bash 3.2 takes quadratic time over a long text in
# a UTF-8 locale: the time of a long word the shell expands is that of a long word it does not.
api_long="$(node -e 'process.stdout.write("some words of a long body\n".repeat(1200))')"
api_time() {
  local began=$SECONDS
  LC_ALL=en_US.UTF-8 verdict "$1" > /dev/null
  if [ $((SECONDS - began)) -lt 5 ]; then echo short; else echo "$((SECONDS - began)) seconds"; fi
}
tl_eq 'a long message with a substitution is judged in a short time' 'short' "$(api_time "git commit -m \"\$(cat <<'EOF'
$api_long
EOF
)\"")"
tl_eq '  a long body of gh api' 'short' "$(api_time "gh api $R/issues/4/comments -f body=\"\$X $api_long\"")"
tl_eq '  and many variables' 'short' "$(api_time "gh api $R/issues/4/comments -f body=\"$(node -e 'process.stdout.write("$A b\n".repeat(4000))')\"")"

printf '\nwhat the refusal of gh api says (#41)\n'
api_says() {
  node -e 'console.log(JSON.stringify({tool_input: {command: process.argv[1]}, cwd: process.argv[2]}))' "${1//R\//$R/}" "$repo" | bash "$HOOK" |
    node -e 'let s = ""; process.stdin.on("data", d => s += d).on("end", () => { try { console.log(JSON.parse(s).hookSpecificOutput.permissionDecisionReason); } catch { console.log("no refusal"); } })'
}
says="$(api_says 'gh api -X DELETE R/git/refs/heads/main')"
tl_has 'a branch: what it is' 'A write in main by gh api' "$says"
tl_has '  that it is protected' 'it is a protected branch' "$says"
tl_has '  and the way' 'open a pull request' "$says"
says="$(api_says 'gh api -X PUT R/contents/a.txt -f message=m')"
tl_has 'no branch: the default one' 'default branch' "$says"
tl_has '  and the way' 'open a pull request' "$says"
says="$(api_says 'gh api -X DELETE R/git/refs/heads/$B')"
tl_has 'a branch of a variable: it cannot be read' 'cannot read' "$says"
tl_has '  and the way' 'pull request' "$says"
says="$(api_says 'gh api graphql -F query=@q.graphql')"
tl_has 'a query of a file: it cannot be read' 'cannot read this query' "$says"
tl_has '  and the way' 'Write the query inline' "$says"
says="$(api_says 'gh api graphql -f query="mutation{mergePullRequest}"')"
tl_has 'a mutation: its name' 'mergePullRequest' "$says"
tl_has '  and the way' 'gh pr merge <n>' "$says"
says="$(api_says 'sh -c "gh api -X DELETE R/git/refs/heads/main"')"
tl_has 'a wrapper: that it could not be judged' 'could not judge it' "$says"
tl_has '  and the way' 'one invocation per command' "$says"

printf '\na config that does not parse\n'
cp trellis.config "$TL_TMP/good.config"
printf '[git\n' > trellis.config
out="$(node -e 'console.log(JSON.stringify({tool_input: {command: "git push origin 4-thing"}, cwd: process.argv[1]}))' "$repo" | bash "$HOOK")"
tl_has 'refuses any push' '"deny"' "$out"
tl_has 'naming the parse error' 'does not parse' "$out"
tl_eq 'refuses a merge' 'deny' "$(verdict 'gh pr merge 12')"
tl_eq 'refuses a write in a branch by gh api' 'deny' "$(verdict "gh api -X DELETE $R/git/refs/heads/41-x")"
tl_eq 'a comment by gh api has no opinion' 'allow' "$(verdict "gh api $R/issues/4/comments -f body=x")"
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
tl_has 'the merge guard asks with the owner token' 'repos/acme/thing/pulls/12 token=tok-acme' "$(calls)"
tl_eq 'a base not allowed is denied with the owner token' 'deny' "$(verdict 'gh pr merge 13 --merge')"
tl_has 'also read with the owner token' 'repos/acme/thing/pulls/13 token=tok-acme' "$(calls)"
git switch -q 4-thing
printf 'open\n' > "$GH_FIXTURES/issue-4"
reset
tl_eq 'the open-issue guard reads with the owner token' 'deny' "$(verdict 'git switch develop')"
tl_has 'the issue view' 'repos/acme/thing/issues/4 token=tok-acme' "$(calls)"
printf 'closed\n' > "$GH_FIXTURES/issue-4"
git switch -q develop

printf '\nwhich owner is asked\n'
reset
tl_eq 'by -R' 'allow' "$(verdict 'gh pr merge 14 --merge -R other/thing')"
tl_has 'the -R owner token' 'repos/other/thing/pulls/14 token=tok-other' "$(calls)"
reset
verdict 'gh pr merge 14 --repo github.com/other/thing' >/dev/null
tl_has 'by --repo with a host' 'repos/other/thing/pulls/14 token=tok-other' "$(calls)"
reset
verdict 'gh pr merge 14 --repo=https://github.com/other/thing' >/dev/null
tl_has 'by --repo= with a URL' 'repos/other/thing/pulls/14 token=tok-other' "$(calls)"
reset
verdict 'gh pr merge https://github.com/other/thing/pull/14' >/dev/null
tl_has 'by the URL of the pull request' 'repos/other/thing/pulls/14 token=tok-other' "$(calls)"
reset
verdict 'gh pr merge 14 --merge -Rother/thing' >/dev/null
tl_has 'by -R with the value attached' 'repos/other/thing/pulls/14 token=tok-other' "$(calls)"
for form in '-R=other/thing' '-dR other/thing' '-dRother/thing'; do
  reset
  verdict "gh pr merge 14 --merge $form" >/dev/null
  tl_has "by $form" 'repos/other/thing/pulls/14 token=tok-other' "$(calls)"
done
reset
verdict 'gh pr merge 12 && gh pr merge 14 -R other/thing' >/dev/null
tl_has 'two owners in one command: the first keeps its token' 'repos/acme/thing/pulls/12 token=tok-acme' "$(calls)"
tl_has 'and the second gets its own' 'repos/other/thing/pulls/14 token=tok-other' "$(calls)"
reset
verdict 'gh pr merge https://github.com/other/thing/pull/14 -R acme/thing' >/dev/null
tl_has 'the URL of the pull request wins over -R' 'repos/other/thing/pulls/14 token=tok-other' "$(calls)"
for form in 'https://github.com:443/acme/thing.git' 'https://github.com/acme/thing' 'https://someone@github.com/acme/thing.git' 'git@github.com:acme/thing.git' \
            'ssh://git@github.com/acme/thing.git' 'ssh://git@github.com:22/acme/thing.git'; do
  set_origin "$form"
  reset
  verdict 'gh pr merge 12' >/dev/null
  tl_has "by the origin $form" 'repos/acme/thing/pulls/12 token=tok-acme' "$(calls)"
done
set_origin https://github.com/ghost/thing.git
reset
tl_eq 'an owner that is not signed in is asked as the active account' 'deny' "$(verdict 'gh pr merge 12')"
tl_has 'with no token' 'repos/ghost/thing/pulls/12 token=none' "$(calls)"
set_origin https://gitlab.com/acme/thing.git
reset
verdict 'gh pr merge 12' >/dev/null
tl_has 'another host is asked as the active account' 'repos/acme/thing/pulls/12 token=none' "$(calls)"
tl_lacks 'and no token is looked up' 'auth token' "$(calls)"
set_origin ''
reset
verdict 'gh pr merge 12' >/dev/null
tl_has 'no origin is asked as the active account' 'repos/{owner}/{repo}/pulls/12 token=none' "$(calls)"
set_origin 'git@github.com:'
reset
verdict 'gh pr merge 12' >/dev/null
tl_has 'an origin that does not parse is asked as the active account' 'repos/{owner}/{repo}/pulls/12 token=none' "$(calls)"
printf 'tok-victim\n' > "$GH_FIXTURES/token-victim"
set_origin 'https://acme.ghe.com/x@github.com/victim/r'
reset
verdict 'gh pr merge 12' >/dev/null
tl_has 'a host hidden after an @ in the path is not github.com' 'repos/{owner}/{repo}/pulls/12 token=none' "$(calls)"
tl_lacks 'and its token is not looked up' 'auth token' "$(calls)"
set_origin 'git@github-work:acme/thing.git'
reset
verdict 'gh pr merge 12' >/dev/null
tl_has 'an ssh host alias gives no owner' 'repos/{owner}/{repo}/pulls/12 token=none' "$(calls)"
set_origin https://github.com/acme/thing.git

printf '\nthe repository gh merges in\n'
printf 'acme/thing\n' > "$GH_FIXTURES/where-12"
tl_eq 'the one of origin' 'allow' "$(verdict 'gh pr merge 12')"
git remote add upstream https://github.com/up/thing.git
tl_eq 'the one of upstream, when there is one' 'deny' "$(verdict 'gh pr merge 12')"
reset
verdict 'gh pr merge 12' >/dev/null
tl_has '  which is read' 'repos/up/thing/pulls/12 ' "$(calls)"
tl_eq '-R says it' 'allow' "$(verdict 'gh pr merge 12 -R acme/thing')"
git config remote.origin.gh-resolved base
tl_eq 'the one gh repo set-default marked' 'allow' "$(verdict 'gh pr merge 12')"
git config remote.origin.gh-resolved up/thing
tl_eq 'the one it names' 'deny' "$(verdict 'gh pr merge 12')"
git config --unset remote.origin.gh-resolved
git remote set-url upstream "$TL_TMP/nowhere"
tl_eq 'a path of this machine is not a repository of GitHub' 'allow' "$(verdict 'gh pr merge 12')"
git remote remove upstream
rm "$GH_FIXTURES/where-12"

printf '\nan environment gh already reads is left alone\n'
reset
GH_TOKEN=preset verdict 'gh pr merge 12' >/dev/null
tl_has 'GH_TOKEN set' 'repos/acme/thing/pulls/12 token=preset' "$(calls)"
tl_lacks 'no lookup' 'auth token' "$(calls)"
for var in GITHUB_TOKEN GH_HOST GH_REPO; do
  reset
  (export "$var=x"; verdict 'gh pr merge 12' >/dev/null)
  tl_has "$var set: asked as the active account" '/pulls/12 token=none' "$(calls)"
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
printf 'closed\n' > "$GH_FIXTURES/issue-4"
reset
rawout 'git switch develop && git switch develop' >/dev/null
tl_eq 'two reads for one owner, one lookup of the token' '1' "$(calls | grep -c 'auth token')"
tl_eq 'for two reads' '2' "$(calls | grep -c 'issues/4')"
git switch -q develop

tl_done
