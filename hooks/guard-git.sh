#!/usr/bin/env bash
#
# guard-git: PreToolUse hook of the Bash tool. Refuses, for the assistant, in every permission mode:
#
#   1. a push to a branch of git.protected: by refspec (quotes, a leading +, refs/heads/, and HEAD
#      or @ as the checked-out branch are normalized), or, without a refspec, by the checked-out
#      branch and its upstream;
#   2. on the main checkout, a checkout or switch to an issue branch (git.issueBranch), created with
#      -b/-c/-C or by -t/--track from a remote branch: every issue is worked in its own worktree,
#      and the main checkout stays on the integration branch;
#   3. on the main checkout, a checkout or switch while the current branch is <n>-... and issue n is
#      still open: another session may be working there, and its next commit would land on the
#      wrong branch;
#   4. a `gh issue create` when the session's transcript holds no earlier `gh issue list` with
#      --search: a plan written without reading what was decided around it repeats a decision;
#   5. a `gh pr merge` that names no pull request, whose base cannot be read, that runs in a cloud
#      session (CLAUDE_CODE_REMOTE), or whose base is not in git.assistantMayMergeInto. Silence is not
#      a neutral opinion on a merge, unlike on the other guards.
#
# Guards 3 and 4 have no opinion with tracker.kind = none or without a working gh. A person pushes or
# switches from their own terminal, or with `!` in the session, which does not go through this hook.
#
# Protocol: the tool input arrives as JSON on stdin; printing the PreToolUse decision "deny" and
# exiting 0 refuses the call. No output and exit 0 is "no opinion", so a payload that does not parse,
# a missing node and a repository without trellis.config never block anything. A deny, not an
# "ask": an auto-mode session resolves an "ask" on its own.
#
# Reads the branches from the trellis.config of the repository each segment runs in, after its
# `cd <dir>` or `git -C <dir>`, through lib/config.sh. Works with bash 3.2.

set -uo pipefail

TRELLIS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v node >/dev/null 2>&1 || exit 0

PAYLOAD="$(cat)"
field() {
  node -e 'try { const p = JSON.parse(require("fs").readFileSync(0, "utf8")); const v = process.argv[1].split(".").reduce((o, k) => (o == null ? o : o[k]), p); process.stdout.write(typeof v === "string" ? v : ""); } catch { }' "$1" <<< "$PAYLOAD" 2>/dev/null
}
COMMAND="$(field tool_input.command)"
[ -n "$COMMAND" ] || exit 0
CWD="$(field cwd)"
CWD="${CWD:-${CLAUDE_PROJECT_DIR:-.}}"
TRANSCRIPT="$(field transcript_path)"

# shellcheck source=../lib/config.sh
. "$TRELLIS_ROOT/lib/config.sh"

# The config is the one of the repository a segment runs in, after its `cd` or `git -C`: a session
# standing outside a project can still push into it. A repository without trellis.config is no
# opinion. Loaded once per repository.
LOADED_TOP=''
HAS_CONFIG=false
load_config() {
  local top
  top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || return 1
  if [ "$top" != "$LOADED_TOP" ]; then
    LOADED_TOP="$top"
    HAS_CONFIG=false
    [ -f "$top/trellis.config" ] || return 1
    HAS_CONFIG=true
    export TRELLIS_CONFIG="$top/trellis.config"
    PROTECTED="$(tc_all git.protected)"
    MERGE_INTO="$(tc_all git.assistantMayMergeInto)"
    ISSUE_REGEX="$(tc_get git.issueBranch)"
    INTEGRATION="$(tc_get git.integrationBranch)"
    TRACKER="$(tc_get tracker.kind)"
  fi
  [ "$HAS_CONFIG" = true ]
}

deny() {
  node -e 'console.log(JSON.stringify({hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: process.argv[1]}}));' "$1"
  exit 0
}

in_list() {
  local needle="$1" item
  while IFS= read -r item; do
    [ -n "$item" ] && [ "$item" = "$needle" ] && return 0
  done <<< "$2"
  return 1
}

# The branch a refspec lands on: "+src:dst", "src:dst", "refs/heads/dst", ":dst" (a delete), or a
# bare name; HEAD and @ on the destination side are the branch checked out in $2.
refspec_target() {
  local spec="${1#+}" dir="$2"
  spec="${spec##*:}"
  spec="${spec#+}"
  spec="${spec#refs/heads/}"
  if [ "$spec" = 'HEAD' ] || [ "$spec" = '@' ]; then
    spec="$(git -C "$dir" branch --show-current 2>/dev/null)"
  fi
  printf '%s' "$spec"
}

# The main checkout, not a linked worktree: a worktree's git dir differs from the common dir.
is_main_checkout() {
  local git_dir common_dir
  git_dir="$(git -C "$1" rev-parse --path-format=absolute --git-dir 2>/dev/null)" || return 1
  common_dir="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [ "$git_dir" = "$common_dir" ]
}

branch_issue() {
  if [[ "$1" =~ ^([0-9]+)- ]]; then printf '%s' "${BASH_REMATCH[1]}"; fi
}

guard_branch_switch() {
  local dir="$1" target="$2" branch issue state
  is_main_checkout "$dir" || return 0
  if [ -n "$target" ] && [[ "$target" =~ $ISSUE_REGEX ]]; then
    deny "The main checkout stays on $INTEGRATION: every issue is worked in its own worktree. Run trellis worktree add <n> <slug> (fetches, creates .claude/worktrees/<n>-<slug>, installs, prints the path), then EnterWorktree with that path."
  fi
  [ "$TRACKER" = 'github' ] || return 0
  branch="$(git -C "$dir" branch --show-current 2>/dev/null)" || return 0
  issue="$(branch_issue "$branch")"
  [ -n "$issue" ] || return 0
  state="$(cd "$dir" && GH_PROMPT_DISABLED=1 gh issue view "$issue" --json state --jq .state 2>/dev/null </dev/null)" || return 0
  if [ "$state" = 'OPEN' ]; then
    deny "The main checkout is on $branch and issue $issue is still open: another session may be working there, and a switch puts its next commit on the wrong branch. Take the new work in a worktree: trellis worktree add <m> <slug>, then EnterWorktree. A person frees the checkout with !git checkout $INTEGRATION."
  fi
}

# True when the transcript holds, before this call, a `gh issue list` with --search or -S. A
# transcript that is missing or unreadable answers yes: no opinion.
session_searched_backlog() {
  [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || return 0
  node -e '
    const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n");
    const current = process.argv[2];
    const search = /gh\s+issue\s+list\b[^\n]*\s(--search|-S)\b/;
    let parsed = 0;
    for (const line of lines) {
      let entry;
      try { entry = JSON.parse(line); } catch { continue; }
      parsed++;
      const content = entry && entry.message && entry.message.content;
      if (!Array.isArray(content)) continue;
      for (const part of content) {
        const command = part && part.type === "tool_use" && part.input ? part.input.command : undefined;
        if (typeof command === "string" && command !== current && search.test(command)) process.exit(0);
      }
    }
    process.exit(parsed === 0 ? 2 : 1);
  ' "$TRANSCRIPT" "$COMMAND" 2>/dev/null
  [ $? -ne 1 ]
}

guard_gh_issue() {
  [ "${1:-}" = 'issue' ] && [ "${2:-}" = 'create' ] || return 0
  [ "$TRACKER" = 'github' ] || return 0
  command -v gh >/dev/null 2>&1 || return 0
  session_searched_backlog && return 0
  deny "An issue is created after the backlog was searched by concept, because the closed issues record what was already decided. Search first: gh issue list --state all --limit 60 --search '<concept>', read what is related, then repeat the creation."
}

guard_gh_merge() {
  [ "${1:-}" = 'pr' ] && [ "${2:-}" = 'merge' ] || return 0
  local dir="$DIR" target='' repo='' word base allowed
  if [ -n "${CLAUDE_CODE_REMOTE:-}" ]; then
    deny 'A cloud session never merges a pull request: the run that writes a change is not the one that merges it. A person merges.'
  fi
  shift 2
  while [ $# -gt 0 ]; do
    word="$1"
    case "$word" in
      -R | --repo) repo="${2:-}"; shift ;;
      --repo=*) repo="${word#*=}" ;;
      -b | --body | -F | --body-file | -t | --subject | -A | --author-email | --match-head-commit) shift ;;
      -*) ;;
      *) [ -z "$target" ] && target="$word" ;;
    esac
    shift
  done
  target="${target//[\"\']/}"
  allowed="$(printf '%s' "$MERGE_INTO" | tr '\n' ' ')"
  if [ -z "$target" ]; then
    deny "A merge names its pull request (number, URL or branch), so its base can be read first: gh pr merge <n>. The assistant merges only into: ${allowed:-nothing}."
  fi
  if [ -n "$repo" ]; then
    base="$(cd "$dir" 2>/dev/null && GH_PROMPT_DISABLED=1 gh pr view "$target" --json baseRefName --jq .baseRefName --repo "$repo" 2>/dev/null </dev/null)"
  else
    base="$(cd "$dir" 2>/dev/null && GH_PROMPT_DISABLED=1 gh pr view "$target" --json baseRefName --jq .baseRefName 2>/dev/null </dev/null)"
  fi
  base="${base//[[:space:]]/}"
  if [ -z "$base" ]; then
    deny "The base branch of pull request $target could not be read (gh pr view failed or answered nothing), and a merge whose base is unknown is refused. Check the pull request and gh's session, then repeat."
  fi
  if ! in_list "$base" "$MERGE_INTO"; then
    deny "Pull request $target merges into $base, and the assistant merges only into: ${allowed:-nothing}. A merge into $base is a person's."
  fi
}

# One tool call can chain several commands; every segment is judged on its own.
CHAINED="${COMMAND//&&/$'\n'}"
CHAINED="${CHAINED//||/$'\n'}"
CHAINED="${CHAINED//|/$'\n'}"
CHAINED="${CHAINED//;/$'\n'}"
DIR="$CWD"

while IFS= read -r segment; do
  words=()
  read -ra words <<< "$segment"
  count=${#words[@]}
  # Quotes are the shell's, not part of a branch name: "main" and 'HEAD:main' are main.
  k=0
  while [ "$k" -lt "$count" ]; do
    words[k]="${words[k]//\"/}"
    words[k]="${words[k]//\'/}"
    k=$((k + 1))
  done
  i=0
  while [ "$i" -lt "$count" ] && [[ "${words[i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    i=$((i + 1))
  done
  [ "$i" -lt "$count" ] || continue

  # `cd <dir>` moves where the later segments run.
  if [ "${words[i]}" = 'cd' ] && [ $((i + 1)) -lt "$count" ]; then
    case "${words[i + 1]}" in
      /*) DIR="${words[i + 1]}" ;;
      *) DIR="$DIR/${words[i + 1]}" ;;
    esac
    continue
  fi

  if [ "${words[i]}" = 'gh' ]; then
    load_config "$DIR" || continue
    rest=("${words[@]:i+1}")
    if [ "${#rest[@]}" -gt 0 ]; then
      guard_gh_merge "${rest[@]}"
      guard_gh_issue "${rest[@]}"
    fi
    continue
  fi

  [ "${words[i]}" = 'git' ] || continue
  i=$((i + 1))
  # Options between git and its subcommand: git -C dir push, git -c key=value push.
  while [ "$i" -lt "$count" ] && [[ "${words[i]}" == -* ]]; do
    case "${words[i]}" in
      -C) [ $((i + 1)) -lt "$count" ] && case "${words[i + 1]}" in /*) DIR="${words[i + 1]}" ;; *) DIR="$DIR/${words[i + 1]}" ;; esac; i=$((i + 2)) ;;
      -c | --git-dir | --work-tree | --namespace | --exec-path) i=$((i + 2)) ;;
      *) i=$((i + 1)) ;;
    esac
  done
  [ "$i" -lt "$count" ] || continue
  load_config "$DIR" || continue

  # A branch switch: checkout or switch without `--` and not `checkout .` (those restore paths).
  # The target is the name after -b/-B/-c/-C when a branch is created; with -t/--track and no name,
  # the remote-tracking branch's name without its remote, which is what git creates.
  if [ "${words[i]}" = 'checkout' ] || [ "${words[i]}" = 'switch' ]; then
    is_switch=true
    created=''
    positional=''
    track=false
    j=$((i + 1))
    while [ "$j" -lt "$count" ]; do
      word="${words[j]}"
      if [ "$word" = '--' ] || [ "$word" = '.' ]; then
        is_switch=false
        break
      fi
      case "$word" in
        -b | -B | -c | -C | --create | --force-create)
          [ $((j + 1)) -lt "$count" ] && [ -z "$created" ] && created="${words[j + 1]}"
          j=$((j + 1))
          ;;
        -t | --track | --track=*) track=true ;;
        -*) ;;
        *) [ -z "$positional" ] && positional="$word" ;;
      esac
      j=$((j + 1))
    done
    target="$created"
    if [ -z "$target" ]; then
      target="$positional"
      if [ "$track" = true ]; then
        target="${target#refs/remotes/}"
        target="${target#*/}"
      fi
    fi
    [ "$is_switch" = true ] && guard_branch_switch "$DIR" "$target"
    continue
  fi

  [ "${words[i]}" = 'push' ] || continue
  i=$((i + 1))
  # After push: the first non-flag word is the remote, every further one a refspec.
  remote_seen=false
  refspecs=()
  while [ "$i" -lt "$count" ]; do
    word="${words[i]}"
    if [[ "$word" == -* ]]; then
      case "$word" in
        -o | --push-option | --receive-pack | --exec) i=$((i + 2)) ;;
        *) i=$((i + 1)) ;;
      esac
      continue
    fi
    if [ "$remote_seen" = false ]; then remote_seen=true; else refspecs+=("$word"); fi
    i=$((i + 1))
  done

  # Without a refspec git pushes the checked-out branch to its upstream: both are judged.
  if [ "${#refspecs[@]}" -eq 0 ]; then
    current="$(git -C "$DIR" branch --show-current 2>/dev/null)"
    upstream=''
    [ -n "$current" ] && upstream="$(git -C "$DIR" config --get "branch.$current.merge" 2>/dev/null)"
    upstream="${upstream#refs/heads/}"
    for target in "$current" "$upstream"; do
      if [ -n "$target" ] && in_list "$target" "$PROTECTED"; then
        deny "A push without refspec pushes $current to ${upstream:-$current}, and a push to $target is refused for the assistant in every permission mode. Push an issue branch with an explicit refspec (git push origin <branch>) and open a pull request; a person pushes to $target."
      fi
    done
    continue
  fi
  for spec in "${refspecs[@]}"; do
    target="$(refspec_target "$spec" "$DIR")"
    if in_list "$target" "$PROTECTED"; then
      deny "A push to $target is refused for the assistant in every permission mode. Push an issue branch with an explicit refspec and open a pull request; a person pushes to $target."
    fi
  done
done <<< "$CHAINED"

exit 0
