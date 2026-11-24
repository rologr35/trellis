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
#   4. a `gh issue create` or a `trellis issue create` when the session's transcript holds no earlier
#      `gh issue list` with --search: a plan written without reading what was decided around it
#      repeats a decision;
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
# `cd <dir>` or `git -C <dir>`, through lib/config.sh. The directory is expanded without running
# anything: quotes (a path with a space), `~`, `~/x`, and `$NAME` / `${NAME}` for HOME and for the
# variables the command assigns literally (`REPO=/x; cd $REPO`). A directory that needs the shell
# (`~user`, `cd -`, `$(pwd)`, a backtick, a variable set elsewhere, an empty or unset HOME) is the
# session's own: the config of the session's repository judges the command, and with none there is
# no opinion. A variable is unresolved, never stale, when its assignment may not run or last (after
# && || or a pipe, or on the left of one) or the resolver cannot follow it (`NAME+=`, a value from a
# command, read, printf -v, for, export, declare, local, typeset, readonly, unset). A directory
# with no config is judged by the config of every directory the command visited with `cd` and of the
# session's. What the hook cannot parse it refuses: a command with `push` and a protected branch's
# name, or with `gh` and `merge`, is denied unless every git and gh invocation in it was judged (see
# `backstop`). Works with bash 3.2.

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
# shellcheck source=../lib/gh.sh
. "$TRELLIS_ROOT/lib/gh.sh"

# A note for the person that the hook prints with its answer (a `systemMessage`): what it could not
# ask GitHub. Held until the end, because the hook prints one JSON object.
HELD_MESSAGE=''
hold_message() {
  case "$HELD_MESSAGE" in *"$1"*) return 0 ;; esac
  HELD_MESSAGE="${HELD_MESSAGE:+$HELD_MESSAGE }$1"
}

# The config is the one of the repository a segment runs in, after its `cd` or `git -C`: a session
# standing outside a project can still push into it. A repository without trellis.config is no
# opinion. Loaded once per repository.
LOADED_TOP=''
HAS_CONFIG=false
CONFIG_ERROR=''
load_config() {
  local top
  top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || return 1
  if [ "$top" != "$LOADED_TOP" ]; then
    LOADED_TOP="$top"
    HAS_CONFIG=false
    [ -f "$top/trellis.config" ] || return 1
    HAS_CONFIG=true
    export TRELLIS_CONFIG="$top/trellis.config"
    CONFIG_ERROR="$(tc_check 2>&1)"
    PROTECTED="$(tc_all git.protected)"
    MERGE_INTO="$(tc_all git.assistantMayMergeInto)"
    ISSUE_REGEX="$(tc_get git.issueBranch)"
    INTEGRATION="$(tc_get git.integrationBranch)"
    TRACKER="$(tc_get tracker.kind)"
  fi
  [ "$HAS_CONFIG" = true ]
}

DENY_NOTE=''
deny() {
  node -e '
    const out = {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: process.argv[1]}};
    if (process.argv[2]) out.systemMessage = process.argv[2];
    console.log(JSON.stringify(out));
  ' "$1$DENY_NOTE" "$HELD_MESSAGE"
  exit 0
}

# The held message alone, when no decision was made.
print_held_message() {
  [ -n "$HELD_MESSAGE" ] || return 0
  node -e 'console.log(JSON.stringify({systemMessage: process.argv[1]}));' "$HELD_MESSAGE"
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
  spec="${spec#heads/}"
  if [ "$spec" = 'HEAD' ] || [ "$spec" = '@' ]; then
    spec="$(git -C "$dir" branch --show-current 2>/dev/null)"
  fi
  printf '%s' "$spec"
}

# A config that does not parse would answer the schema's defaults, which may not name the project's
# protected branches: a push or a merge is refused until it parses.
fail_closed() {
  [ -n "$CONFIG_ERROR" ] || return 0
  deny "${CONFIG_ERROR#trellis: } A push or a merge is refused until it parses again (git config -f trellis.config --list shows where)."
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
  command -v gh >/dev/null 2>&1 || return 0
  if ! gh_as_owner "$dir" "$(gh_owner "$dir")" issue view "$issue" --json state --jq .state; then
    hold_message "trellis guard-git: the state of issue $issue could not be read as $GH_AS_ACCOUNT (${GH_AS_ERR:-gh failed}), so the open-issue check of this switch was skipped."
    return 0
  fi
  state="$GH_AS_OUT"
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

# Whether a word of `gh pr merge` is the -R / --repo flag, in any form gh reads: -R x/y, -Rx/y, -R=x/y,
# --repo x/y, --repo=x/y, and -R at the end of a group of the boolean short flags (-dR x/y, -dRx/y).
# Sets REPO_FLAG_VALUE, and REPO_FLAG_NEXT when the value is the next word.
REPO_FLAG_VALUE=''
REPO_FLAG_NEXT=false
repo_flag() {
  local w="$1" pre rest
  REPO_FLAG_VALUE=''
  REPO_FLAG_NEXT=false
  case "$w" in
    --repo) REPO_FLAG_NEXT=true; return 0 ;;
    --repo=*) REPO_FLAG_VALUE="${w#*=}"; return 0 ;;
    --*) return 1 ;;
    -*R*)
      pre="${w%%R*}"
      pre="${pre#-}"
      case "$pre" in *[!dmrs]*) return 1 ;; esac
      rest="${w#*R}"
      if [ -z "$rest" ]; then REPO_FLAG_NEXT=true; else REPO_FLAG_VALUE="${rest#=}"; fi
      return 0
      ;;
  esac
  return 1
}

# Whether a word of `gh pr merge` is a group of short flags whose value is the next word: letters are
# read left to right, the boolean ones (d m r s) take nothing, and the first of b F t A takes the rest of
# the group, or the next word when it is the group's last letter. A group with any other letter before
# that is one gh refuses, and is read as it always was. -R is repo_flag's.
short_group_takes_next() {
  local w="$1" letters c i
  case "$w" in --* | -) return 1 ;; -*) ;; *) return 1 ;; esac
  letters="${w#-}"
  for ((i = 0; i < ${#letters}; i++)); do
    c="${letters:i:1}"
    case "$c" in
      [dmrs]) ;;
      [bFtA]) [ $((i + 1)) -eq ${#letters} ]; return ;;
      *) return 1 ;;
    esac
  done
  return 1
}

guard_gh_merge() {
  [ "${1:-}" = 'pr' ] && [ "${2:-}" = 'merge' ] || return 0
  fail_closed
  local dir="$DIR" target='' repo='' word base allowed
  if [ -n "${CLAUDE_CODE_REMOTE:-}" ]; then
    deny 'A cloud session never merges a pull request: the run that writes a change is not the one that merges it. A person merges.'
  fi
  shift 2
  while [ $# -gt 0 ]; do
    word="$1"
    if repo_flag "$word"; then
      if [ "$REPO_FLAG_NEXT" = true ]; then repo="${2:-}"; shift; else repo="$REPO_FLAG_VALUE"; fi
      shift
      continue
    fi
    case "$word" in
      -b | --body | -F | --body-file | -t | --subject | -A | --author-email | --match-head-commit) shift ;;
      -*)
        # A group of short flags ends in a value flag: -sb takes the next word, -sbtext took its own.
        if short_group_takes_next "$word"; then shift; fi
        ;;
      *) [ -z "$target" ] && target="$word" ;;
    esac
    shift
  done
  target="${target//[\"\']/}"
  allowed="$(printf '%s' "$MERGE_INTO" | tr '\n' ' ')"
  if [ -z "$target" ]; then
    deny "A merge names its pull request (number, URL or branch), so its base can be read first: gh pr merge <n>. The assistant merges only into: ${allowed:-nothing}."
  fi
  # The account that sees the repository is its owner's: of the URL naming the pull request, of -R,
  # or of the origin remote.
  local hint="$repo"
  case "$target" in http://* | https://*) hint="$target" ;; esac
  if [ -n "$repo" ]; then
    gh_as_owner "$dir" "$(gh_owner "$dir" "$hint")" pr view "$target" --json baseRefName --jq .baseRefName --repo "$repo"
  else
    gh_as_owner "$dir" "$(gh_owner "$dir" "$hint")" pr view "$target" --json baseRefName --jq .baseRefName
  fi
  base="${GH_AS_OUT//[[:space:]]/}"
  if [ -z "$base" ]; then
    deny "The base branch of pull request $target could not be read as $GH_AS_ACCOUNT (${GH_AS_ERR:-gh failed or answered nothing}), and a merge whose base is unknown is refused. Check the pull request and gh's session, then repeat."
  fi
  if ! in_list "$base" "$MERGE_INTO"; then
    deny "Pull request $target merges into $base, and the assistant merges only into: ${allowed:-nothing}. A merge into $base is a person's."
  fi
}

# The words of every segment of the command as the shell reads them, without running anything, in one
# quote-aware pass over the whole command: single and double quotes group and are removed ("main" and
# 'HEAD:main' are main), a backslash escapes the next character, $'...' is ANSI-C quoting (\xHH, \nnn,
# \uHHHH spell one character), $(...), backticks and <(...) stay inside their word, a comment is
# dropped, and a here-document's body is data. The operators ; & | && || ( ) { } and newline end a
# segment, and a redirection (> >> < <<< 2>&1 &> and the word after it) is not a word, even glued to
# one (main>/dev/null). A command that ends with a quote still open is judged by every word that
# whitespace splits the rest of the segment into, which fails closed.
# One record per line: "w" and the word (a newline in it is \001), "c" (the segment follows && or ||),
# "x" (the segment does not last: it is on a side of a pipe or in the background), "(" and ")" around a
# subshell, "f" and the flags of the segment's tokens (g git, h gh, k push, m merge, e a variable or
# option that redirects git or gh), "e" at the end of a segment, and "n" and a name at the end for every
# name a word could be a branch by. In node because bash 3.2 takes quadratic time over a long line.
split_segments() {
  node -e '
    const ESC = {a: "\x07", b: "\b", e: "\x1b", E: "\x1b", f: "\f", n: "\n", r: "\r", t: "\t", v: "\v", "\\": "\\", "\x27": "\x27", "\"": "\"", "?": "?"};
    const ENV = /^(GIT_DIR|GIT_WORK_TREE|GIT_COMMON_DIR|GIT_CONFIG[A-Z_0-9]*|GH_REPO)=|^--(git-dir|work-tree)(=|$)/;
    const names = new Set();
    const norm = (t) => {
      const found = [t];
      for (let part of t.split(":")) {
        part = part.replace(/^\+/, "").replace(/^refs\/heads\//, "").replace(/^heads\//, "");
        if (part) found.push(part);
      }
      return found;
    };
    const tokenize = (src, depth) => {
      const n = src.length;
      const ansi = (i) => { // src[i] is the backslash; returns [text, index of the escape last character]
        const rest = src.slice(i + 1, i + 12);
        let m;
        if (rest === "") return ["\\", i];
        if ((m = /^[0-7]{1,3}/.exec(rest))) return [String.fromCharCode(parseInt(m[0], 8) & 255), i + m[0].length];
        if ((m = /^x[0-9a-fA-F]{1,2}/.exec(rest))) return [String.fromCharCode(parseInt(m[0].slice(1), 16)), i + m[0].length];
        if ((m = /^u[0-9a-fA-F]{1,4}/.exec(rest)) || (m = /^U[0-9a-fA-F]{1,8}/.exec(rest))) {
          const point = parseInt(m[0].slice(1), 16);
          return [point <= 0x10ffff ? String.fromCodePoint(point) : "", i + m[0].length];
        }
        if (rest[0] === "c" && rest.length > 1) return [String.fromCharCode(rest.charCodeAt(1) & 31), i + 2];
        if (rest[0] in ESC) return [ESC[rest[0]], i + 1];
        return ["\\" + rest[0], i + 1];
      };
      let unterminated = false;
      // Index just after the ) that closes a $( opened before i (nested quotes, substitutions and here-documents).
      const skipSubst = (i) => {
        let depthParen = 1;
        const heredocs = [];
        while (i < n) {
          const c = src[i];
          if (c === "\\") { i += 2; continue; }
          if (c === "\x27") { const j = src.indexOf("\x27", i + 1); if (j < 0) break; i = j + 1; continue; }
          if (c === "\"") {
            i++;
            while (i < n && src[i] !== "\"") {
              if (src[i] === "\\") i += 2;
              else if (src[i] === "$" && src[i + 1] === "(") i = skipSubst(i + 2);
              else i++;
            }
            i++;
            continue;
          }
          if (c === "`") { const j = src.indexOf("`", i + 1); if (j < 0) break; i = j + 1; continue; }
          if (c === "$" && src[i + 1] === "(") { i = skipSubst(i + 2); continue; }
          if (c === "(") depthParen++;
          if (c === ")" && --depthParen === 0) return i + 1;
          if (c === "<" && src[i + 1] === "<" && src[i + 2] !== "<") {
            const m = /^<<(-?)[ \t]*(?:\x27([^\x27\n]*)\x27|"([^"\n]*)"|\\?([A-Za-z0-9_]+))/.exec(src.slice(i, i + 200));
            if (m) { heredocs.push({delim: m[2] ?? m[3] ?? m[4], strip: m[1] === "-"}); i += m[0].length; continue; }
          }
          if (c === "\n" && heredocs.length) {
            i++;
            for (const h of heredocs.splice(0)) {
              while (i < n) {
                let e = src.indexOf("\n", i);
                if (e < 0) e = n;
                const line = h.strip ? src.slice(i, e).replace(/^\t+/, "") : src.slice(i, e);
                i = Math.min(e + 1, n);
                if (line === h.delim) break;
              }
            }
            continue;
          }
          i++;
        }
        unterminated = true;
        return n;
      };
      let pos = 0;
      let seg = {words: [], atoms: [], c: false, x: false, pre: [], deep: false};
      // A substitution runs before its command, in a subshell: its segments are judged first, as a group.
      const substitute = (from, to) => {
        if (depth >= 12) { seg.deep = true; return; }
        seg.pre.push(tokenize(src.slice(from, to), depth + 1));
      };
      // One shell word from pos: its text, whether any of it was quoted, whether it holds an unquoted glob or brace.
      const readWord = () => {
        let cur = "", quoted = false, glob = false;
        while (pos < n) {
          const c = src[pos];
          if (c === " " || c === "\t" || c === "\n" || c === ";" || c === "&" || c === "|" || c === "(" || c === ")" || c === "<" || c === ">") {
            if ((c === "<" || c === ">") && src[pos + 1] === "(") { const j = skipSubst(pos + 2); substitute(pos + 2, unterminatedAt(j)); cur += src.slice(pos, j); pos = j; continue; }
            break;
          }
          if (c === "\\") {
            if (src[pos + 1] === "\n") { pos += 2; continue; }
            cur += src[pos + 1] ?? ""; pos += 2; quoted = true; continue;
          }
          if (c === "\x27") {
            const j = src.indexOf("\x27", pos + 1);
            if (j < 0) { unterminated = true; pos = n; return {text: cur, quoted: true, glob}; }
            cur += src.slice(pos + 1, j); pos = j + 1; quoted = true; continue;
          }
          if (c === "\"") {
            pos++; quoted = true;
            let closed = false;
            while (pos < n) {
              const d = src[pos];
              if (d === "\"") { closed = true; pos++; break; }
              if (d === "\\" && "$`\"\\\n".includes(src[pos + 1] ?? " ")) { if (src[pos + 1] !== "\n") cur += src[pos + 1]; pos += 2; continue; }
              if (d === "$" && src[pos + 1] === "(") { const j = skipSubst(pos + 2); substitute(pos + 2, unterminatedAt(j)); cur += src.slice(pos, j); pos = j; continue; }
              if (d === "`") { const j = src.indexOf("`", pos + 1); const e = j < 0 ? n : j + 1; substitute(pos + 1, j < 0 ? n : j); cur += src.slice(pos, e); pos = e; continue; }
              cur += d; pos++;
            }
            if (!closed) { unterminated = true; return {text: cur, quoted: true, glob}; }
            continue;
          }
          if (c === "$" && src[pos + 1] === "\x27") {
            pos += 2; quoted = true;
            let closed = false;
            while (pos < n) {
              const d = src[pos];
              if (d === "\x27") { closed = true; pos++; break; }
              if (d === "\\") { const [text, end] = ansi(pos); cur += text; pos = end + 1; continue; }
              cur += d; pos++;
            }
            if (!closed) { unterminated = true; return {text: cur, quoted: true, glob}; }
            continue;
          }
          if (c === "$" && src[pos + 1] === "(") { const j = skipSubst(pos + 2); substitute(pos + 2, unterminatedAt(j)); cur += src.slice(pos, j); pos = j; continue; }
          if (c === "$" && src[pos + 1] === "{") { const j = src.indexOf("}", pos + 2); const e = j < 0 ? n : j + 1; cur += src.slice(pos, e); pos = e; continue; }
          if (c === "`") { const j = src.indexOf("`", pos + 1); const e = j < 0 ? n : j + 1; if (j < 0) unterminated = true; substitute(pos + 1, j < 0 ? n : j); cur += src.slice(pos, e); pos = e; continue; }
          if (c === "*" || c === "?" || c === "[" || c === "{") glob = true;
          cur += c; pos++;
        }
        return {text: cur, quoted, glob};
      };
      // The end of a substitution body: the index before its closing parenthesis, or the end of the text.
      const unterminatedAt = (j) => (src[j - 1] === ")" ? j - 1 : j);
      const out = [];
      let segStart = 0, pendingC = false, pendingX = false;
      const heredocs = [];
      const emit = () => {
        let flags = "";
        for (const atom of seg.atoms) {
          for (const tok of atom.split(/[\s;&|()<>$`\x27"{}=,]+/)) {
            if (!tok) continue;
            const base = tok.replace(/^.*\//, "");
            for (const t of [tok, base]) {
              if (t === "git") flags += "g"; else if (t === "gh") flags += "h"; else if (t === "push") flags += "k"; else if (t === "merge") flags += "m";
            }
            for (const name of norm(tok)) names.add(name);
          }
          for (const name of norm(atom)) names.add(name);
          // ${NAME:-main}, ${NAME-main}, ${NAME:=main}: the word after the operator is a possible name.
          for (const m of atom.matchAll(/\$\{[A-Za-z_][A-Za-z0-9_]*:?[-=+?]([^}]*)\}/g)) for (const name of norm(m[1])) names.add(name);
        }
        for (const w of seg.words) if (ENV.test(w)) flags += "e";
        if (seg.deep) flags += "e";
        if (seg.pre.length) {
          out.push("(");
          for (const lines of seg.pre) for (const line of lines) out.push(line);
          out.push(")");
        }
        if (seg.c) out.push("c");
        if (seg.x) out.push("x");
        for (let k = 0; k < seg.words.length; k++) {
          if (seg.globs && seg.globs.has(k)) out.push("g");
          out.push("w" + seg.words[k].replace(/\n/g, "\x01"));
        }
        out.push("f" + [...new Set(flags)].join(""));
        out.push("e");
      };
      // End the segment at an operator. An empty segment is dropped and leaves the pending marks.
      const end = (op) => {
        if (seg.words.length || seg.atoms.length) {
          if (op === "|" || op === "&") seg.x = true;
          emit();
          pendingC = op === "&&" || op === "||";
          pendingX = op === "|";
        } else if (op === "&&" || op === "||") { pendingC = true; } else if (op === "|") { pendingX = true; }
        seg = {words: [], atoms: [], c: pendingC, x: pendingX, pre: [], deep: false};
        segStart = pos;
      };
      const fallback = () => { // a quote left open: whitespace words of the rest of the segment, quote marks removed
        seg.words = [];
        for (const w of src.slice(segStart).split(/[ \t\n]+/)) if (w) seg.words.push(w.replace(/[\x27"\\]/g, ""));
        seg.atoms = seg.words.slice();
        pos = n;
      };
      while (pos < n && !unterminated) {
        const c = src[pos];
        if (c === " " || c === "\t") { pos++; continue; }
        if (c === "\n") {
          pos++;
          for (const h of heredocs.splice(0)) {
            let body = "";
            while (pos < n) {
              let e = src.indexOf("\n", pos);
              if (e < 0) e = n;
              const line = src.slice(pos, e), cmp = h.strip ? line.replace(/^\t+/, "") : line;
              pos = Math.min(e + 1, n);
              if (cmp === h.delim) break;
              body += line + "\n";
            }
            seg.atoms.push(body);
          }
          end("\n");
          continue;
        }
        if (c === "#") { while (pos < n && src[pos] !== "\n") pos++; continue; }
        if (c === ";") { pos++; if (src[pos] === ";" || src[pos] === "&") pos++; end(";"); continue; }
        if (c === "&" && src[pos + 1] === "&") { pos += 2; end("&&"); continue; }
        if (c === "&" && src[pos + 1] === ">") { pos += 2; if (src[pos] === ">") pos++; while (src[pos] === " " || src[pos] === "\t") pos++; seg.atoms.push(readWord().text); continue; }
        if (c === "&") { pos++; end("&"); continue; }
        if (c === "|") { pos++; if (src[pos] === "|") { pos++; end("||"); } else { if (src[pos] === "&") pos++; end("|"); } continue; }
        if (c === "(") { pos++; end("("); out.push("("); continue; }
        if (c === ")") { pos++; end(")"); out.push(")"); continue; }
        const isSubst = (src[pos] === "<" || src[pos] === ">") && src[pos + 1] === "(";
        let m = isSubst ? null : /^\d+(?=[<>])/.exec(src.slice(pos, pos + 12));
        if (m) pos += m[0].length;
        if (!isSubst && (src[pos] === "<" || src[pos] === ">")) {
          m = /^(<<<|<<-|<<|<&|<>|<|>>|>&|>\||>)/.exec(src.slice(pos, pos + 3));
          pos += m[0].length;
          while (src[pos] === " " || src[pos] === "\t") pos++;
          const target = readWord();
          if (m[0] === "<<" || m[0] === "<<-") heredocs.push({delim: target.text, strip: m[0] === "<<-"});
          seg.atoms.push(target.text);
          continue;
        }
        if (seg.words.length === 0 && seg.atoms.length === 0) segStart = pos;
        const word = readWord();
        if (unterminated) break;
        if (!word.quoted && (word.text === "{" || word.text === "}")) { end("{"); continue; }
        if (word.text === "" && !word.quoted) { pos++; continue; }
        if (word.glob) { if (!seg.globs) seg.globs = new Set(); seg.globs.add(seg.words.length); }
        seg.words.push(word.text);
        seg.atoms.push(word.text);
      }
      if (unterminated) fallback();
      end("\n");
      return out;
    };
    const out = tokenize(require("fs").readFileSync(0, "utf8"), 0);
    for (const name of names) if (!/[\n\x01]/.test(name)) out.push("n" + name);
    process.stdout.write(out.join("\n") + "\n");
  ' <<< "$COMMAND"
}

# The next record of fd 3: SEG_KIND is "seg" (its words are in `words`, with MAY_NOT_RUN: it follows
# && or ||; PIPED: it does not last, on a side of a pipe or in the background; FLAGS), "open" or
# "close" for a subshell's parenthesis. The names at the end go to NAMES. Status 1 at the end.
next_segment() {
  local record
  words=()
  MAY_NOT_RUN=false
  PIPED=false
  FLAGS=''
  SEG_KIND=seg
  GLOBBED=','
  local glob=false
  while IFS= read -r record <&3; do
    case "$record" in
      e) return 0 ;;
      g) glob=true ;;
      c) MAY_NOT_RUN=true ;;
      x) PIPED=true ;;
      f*) FLAGS="${record#f}" ;;
      '(') SEG_KIND=open; return 0 ;;
      ')') SEG_KIND=close; return 0 ;;
      n*) NAMES="$NAMES"$'\n'"${record#n}" ;;
      w*)
        [ "$glob" = true ] && GLOBBED="$GLOBBED${#words[@]},"
        glob=false
        record="${record#w}"
        words+=("${record//$'\001'/$'\n'}")
        ;;
    esac
  done
  return 1
}

# Variables assigned literally in the command itself (`REPO=/x; cd $REPO`), as GV_<name>. A value
# that needs the shell to run something is not recorded, so the name stays unresolved.
record_assignment() {
  local name="${1%%=*}" value="${1#*=}"
  if expand_word "$value"; then printf -v "GV_$name" '%s' "$EXPANDED"; else forget "$name"; fi
}

# The name holds no known value for the rest of the command: a use of it is unresolved. HOME too: the
# shell's ~ follows it, so once it is touched the process's HOME is no longer the shell's.
forget() {
  [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 0
  unset "GV_$1"
  [ "$1" = 'HOME' ] && HOME_TOUCHED=true
  return 0
}

# HOME as the shell has it, in HV. Status 1 when it is empty, unset, or was changed in a way the
# resolver could not follow: `~` is then unresolved, never a guess.
home_value() {
  if [ -n "${GV_HOME+x}" ]; then
    HV="$GV_HOME"
  elif [ "$HOME_TOUCHED" = true ]; then
    return 1
  else
    HV="${HOME:-}"
  fi
  [ -n "$HV" ]
}
HOME_TOUCHED=false
PWD_OK=false # $PWD is the shell's directory only while the shell can stand in one

# The word with `~`, `~/x`, `$NAME` and `${NAME}` expanded from what the command assigned (and
# HOME), in EXPANDED. Status 1 when it needs the shell: `~user`, `-`, an unknown variable, `$(...)`,
# a backtick.
expand_word() {
  local w="$1" out='' name rest ref
  EXPANDED=''
  [ "$w" = '-' ] && return 1
  case "$w" in *'`'*) return 1 ;; esac
  case "$w" in
    '~') home_value || return 1; w="$HV" ;;
    '~/'*) home_value || return 1; w="$HV/${w#\~/}" ;;
    '~'*) return 1 ;;
  esac
  while [[ "$w" == *'$'* ]]; do
    out="$out${w%%\$*}"
    w="${w#*\$}"
    if [[ "$w" =~ ^\{([A-Za-z_][A-Za-z0-9_]*)\}(.*)$ ]] || [[ "$w" =~ ^([A-Za-z_][A-Za-z0-9_]*)(.*)$ ]]; then
      name="${BASH_REMATCH[1]}"
      rest="${BASH_REMATCH[2]}"
      ref="GV_$name"
      if [ -n "${!ref+x}" ]; then
        out="$out${!ref}"
      elif [ "$name" = 'HOME' ] && home_value; then
        out="$out$HV"
      elif [ "$name" = 'PWD' ] && [ "$PWD_OK" = true ]; then
        out="$out$DIR"
      else
        return 1
      fi
      w="$rest"
    else
      return 1
    fi
  done
  EXPANDED="$out$w"
}

# Where a segment runs after `cd <word>` or `git -C <word>`, from DIR. A word that cannot be expanded
# without the shell leaves the session's own directory (MOVE_UNRESOLVED): the config of the
# directories the command visited and of the session's judges it.
move_to() {
  MOVE_UNRESOLVED=false
  if expand_word "$1"; then
    case "$EXPANDED" in
      /*) DIR="$EXPANDED" ;;
      *) DIR="$DIR/$EXPANDED" ;;
    esac
  else
    DIR="$CWD"
    MOVE_UNRESOLVED=true
  fi
  add_all "$DIR"
}

# What the command stands on and what it names, for the backstop and the directory candidates.
SHELL_DIRS=("$CWD") # where the shell may stand now (a cd that may not run adds a directory)
VISITED=("$CWD")    # the session's directory and every one a cd named
ALL_DIRS=("$CWD")   # and every one `git -C` named
SUB_STACK=()        # SHELL_DIRS at each open subshell, its entries joined by \001
SUB_DEPTH=0
UNRES=false         # a cd needed the shell: the shell's directory is not known
UNJUDGED=false      # a git or gh invocation the hook did not judge
ENV_SEEN=false      # GIT_DIR, GH_REPO and kin, --git-dir, --work-tree
ANY_PUSH=false
ANY_MERGE=false
NAMES=''
WHY=''
MAX_DIRS=8

# A directory is kept once, and only up to a cap: past it the command is not judged, so a chain of
# cd cannot make the hook slow enough to time out (which runs the command unjudged).
unjudged() {
  UNJUDGED=true
  [ -n "$WHY" ] || WHY="$1"
}
add_shell() {
  local d
  for d in ${SHELL_DIRS[@]+"${SHELL_DIRS[@]}"}; do [ "$d" = "$1" ] && return 0; done
  if [ "${#SHELL_DIRS[@]}" -ge "$MAX_DIRS" ]; then unjudged 'more directories than the guard follows'; return 0; fi
  SHELL_DIRS+=("$1")
}
add_visited() {
  local d
  for d in "${VISITED[@]}"; do [ "$d" = "$1" ] && return 0; done
  if [ "${#VISITED[@]}" -ge "$MAX_DIRS" ]; then unjudged 'more directories than the guard follows'; return 0; fi
  VISITED+=("$1")
}
add_all() {
  local d
  for d in "${ALL_DIRS[@]}"; do [ "$d" = "$1" ] && return 0; done
  if [ "${#ALL_DIRS[@]}" -ge $((MAX_DIRS * 2)) ]; then unjudged 'more directories than the guard follows'; return 0; fi
  ALL_DIRS+=("$1")
}

# A directory's own config judges a segment in it. With none, the config of every directory the
# command visited and of the session's judges it, and the strictest answer wins.
candidates_do() {
  local fn="$1" d found=false
  for d in "${VISITED[@]}"; do
    if load_config "$d"; then found=true; "$fn" "$d"; fi
  done
  [ "$found" = true ]
}

# Judges the push in `words` (refspecs in `refspecs`, NO_REFSPEC, PUSH_ALL) against the config loaded
# for $1. The branch is the checkout of the directory the push runs in (BRANCH_DIR), not of the
# directory whose config judges it.
push_check() {
  local dir="$1" bd="$BRANCH_DIR" current upstream target spec
  fail_closed
  git -C "$bd" rev-parse --git-dir >/dev/null 2>&1 || bd="$dir"
  if [ "$PUSH_ALL" = true ] && [ -n "$PROTECTED" ]; then
    deny "git push --all, --mirror and --branches push every branch, protected ones among them, and that is refused for the assistant in every permission mode. Push an issue branch with an explicit refspec."
  fi
  if [ "$NO_REFSPEC" = true ]; then
    # Without a refspec git pushes the checked-out branch to its upstream: both are judged.
    current="$(git -C "$bd" branch --show-current 2>/dev/null)"
    upstream=''
    [ -n "$current" ] && upstream="$(git -C "$bd" config --get "branch.$current.merge" 2>/dev/null)"
    upstream="${upstream#refs/heads/}"
    for target in "$current" "$upstream"; do
      if [ -n "$target" ] && in_list "$target" "$PROTECTED"; then
        deny "A push without refspec pushes $current to ${upstream:-$current}, and a push to $target is refused for the assistant in every permission mode. Push an issue branch with an explicit refspec (git push origin <branch>) and open a pull request; a person pushes to $target."
      fi
    done
    return 0
  fi
  for spec in "${refspecs[@]}"; do
    if [ "${spec#+}" = ':' ] || [[ "$spec" == *'*'* ]]; then
      deny "The refspec $spec pushes every matching branch, protected ones among them, and that is refused for the assistant in every permission mode. Push an issue branch with an explicit refspec."
    fi
    target="$(refspec_target "$spec" "$bd")"
    if in_list "$target" "$PROTECTED"; then
      deny "A push to $target is refused for the assistant in every permission mode. Push an issue branch with an explicit refspec and open a pull request; a person pushes to $target."
    fi
  done
}

merge_check() {
  DIR="$1"
  guard_gh_merge "${rest[@]}"
}

# One git invocation, in the directory $1 the shell may stand in: words[ci] is `git`.
judge_git() {
  DIR="$1"
  local j=$((ci + 1)) sub spec word remote_seen=false created positional track is_switch k target has_c=false
  SEG_UNJUDGED=''
  PUSH_ALL=false
  while [ "$j" -lt "$count" ] && [[ "${words[j]}" == -* ]]; do
    case "${words[j]}" in
      -C)
        if [ $((j + 1)) -lt "$count" ]; then
          move_to "${words[j + 1]}"
          [ "$MOVE_UNRESOLVED" = true ] && SEG_UNJUDGED='a directory only the shell can resolve'
        fi
        j=$((j + 2))
        ;;
      -c) has_c=true; j=$((j + 2)) ;;
      --exec-path | --namespace) j=$((j + 2)) ;;
      --git-dir | --work-tree) SEG_UNJUDGED='--git-dir or --work-tree'; j=$((j + 2)) ;;
      --git-dir=* | --work-tree=*) SEG_UNJUDGED='--git-dir or --work-tree'; j=$((j + 1)) ;;
      *) j=$((j + 1)) ;;
    esac
  done
  [ "$j" -lt "$count" ] || return 0
  sub="${words[j]}"
  # A subcommand git does not have is an alias, or another program: a push may hide in it.
  case "$sub" in
    push | checkout | switch | add | am | apply | archive | bisect | blame | branch | bundle | cherry-pick | clean | clone | commit | config | describe | diff | fetch | format-patch | gc | grep | init | log | ls-files | ls-remote | ls-tree | merge | mv | notes | pull | rebase | reflog | remote | reset | restore | revert | rev-list | rev-parse | rm | shortlog | show | show-ref | stash | status | submodule | tag | worktree | cat-file | diff-tree | for-each-ref | symbolic-ref | update-ref | version | help | --version) ;;
    *) case "$FLAGS" in *k*) SEG_UNJUDGED='a git subcommand that may be an alias' ;; esac ;;
  esac
  [ "$sub" = 'push' ] && [ "$has_c" = true ] && SEG_UNJUDGED='git -c on a push (it can define an alias or a remote)'

  if [ "$sub" = 'push' ]; then
    j=$((j + 1))
    # After push: the first non-flag word is the remote, every further one a refspec.
    refspecs=()
    while [ "$j" -lt "$count" ]; do
      word="${words[j]}"
      if [[ "$word" == -* ]]; then
        case "$word" in
          -o | --push-option | --receive-pack | --exec) j=$((j + 2)) ;;
          --all | --mirror | --branches) PUSH_ALL=true; j=$((j + 1)) ;;
          *) j=$((j + 1)) ;;
        esac
        continue
      fi
      if [ "$remote_seen" = false ]; then
        remote_seen=true
      elif [[ "$GLOBBED" == *",$j,"* ]]; then
        SEG_UNJUDGED='a refspec with a glob or a brace list'
        refspecs+=("$word")
      else
        case "$word" in
          '$(git branch --show-current)' | '$(git rev-parse --abbrev-ref HEAD)' | '`git branch --show-current`' | '`git rev-parse --abbrev-ref HEAD`')
            # The checked-out branch, which HEAD names.
            refspecs+=('HEAD')
            ;;
          *)
            if expand_word "$word"; then
              refspecs+=("$EXPANDED")
            else
              SEG_UNJUDGED='a refspec only the shell can resolve'
              refspecs+=("$word")
            fi
            ;;
        esac
      fi
      j=$((j + 1))
    done
    NO_REFSPEC=false
    [ "${#refspecs[@]}" -eq 0 ] && NO_REFSPEC=true
    BRANCH_DIR="$DIR"
    if load_config "$DIR"; then
      push_check "$DIR"
    else
      DENY_NOTE=" ($DIR has no trellis.config, so the config of the session or of a directory the command visited judged it.)"
      candidates_do push_check || true
      DENY_NOTE=''
    fi
    return 0
  fi

  load_config "$DIR" || return 0
  # A branch switch: checkout or switch without `--` and not `checkout .` (those restore paths).
  # The target is the name after -b/-B/-c/-C when a branch is created; with -t/--track and no name,
  # the remote-tracking branch's name without its remote, which is what git creates.
  if [ "$sub" = 'checkout' ] || [ "$sub" = 'switch' ]; then
    is_switch=true
    created=''
    positional=''
    track=false
    k=$((j + 1))
    while [ "$k" -lt "$count" ]; do
      word="${words[k]}"
      if [ "$word" = '--' ] || [ "$word" = '.' ]; then
        is_switch=false
        break
      fi
      case "$word" in
        -b | -B | -c | -C | --create | --force-create)
          [ $((k + 1)) -lt "$count" ] && [ -z "$created" ] && created="${words[k + 1]}"
          k=$((k + 1))
          ;;
        -t | --track | --track=*) track=true ;;
        -*) ;;
        *) [ -z "$positional" ] && positional="$word" ;;
      esac
      k=$((k + 1))
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
  fi
  return 0
}

# One gh invocation, in the directory $1 the shell may stand in: words[ci] is `gh`.
judge_gh() {
  DIR="$1"
  rest=("${words[@]:ci+1}")
  [ "${#rest[@]}" -gt 0 ] || return 0
  local word
  if [ "${rest[0]}" = 'pr' ] && [ "${rest[1]:-}" = 'merge' ]; then
    if load_config "$DIR"; then
      guard_gh_merge "${rest[@]}"
    elif DENY_NOTE=" ($DIR has no trellis.config, so the config of the session or of a directory the command visited judged it.)"; ! candidates_do merge_check; then
      DENY_NOTE=''
      # Nothing here or in the session has a config, and gh reaches a repository by name.
      for word in "${rest[@]}"; do
        if repo_flag "$word"; then
          deny 'A merge into a repository named by -R, with no trellis.config in the session or the directories it visited, cannot be judged. Run it from the repository, without -R: cd <repo> && gh pr merge <n>.'
        fi
      done
      [ "$ENV_SEEN" = true ] && deny 'A merge with GH_REPO set, and no trellis.config in the session or the directories it visited, cannot be judged. Run it from the repository: cd <repo> && gh pr merge <n>.'
    fi
    return 0
  fi
  load_config "$DIR" || return 0
  guard_gh_issue "${rest[@]}"
}

# One trellis invocation, in the directory $1 the shell may stand in: words[ci] is `trellis`.
judge_trellis() {
  DIR="$1"
  load_config "$DIR" || return 0
  guard_gh_issue "${words[@]:ci+1}"
}

# Whether a git or gh invocation hides in a segment: its command is not git or gh itself, and its
# words mention git, gh, push or merge. Programs that only print or move text do not count.
INERT=' echo printf cat tee grep egrep fgrep rg head tail wc ls cp mv rm mkdir touch diff cmp sort uniq tr cut basename dirname test [ true false : pwd realpath stat file tree date sleep which type '
INTERPRETERS=' sh bash zsh dash ksh eval source . '

# A command that names branches and pushes, or merges, is refused unless every git and gh invocation
# in it was judged. It runs after the segments are judged one by one.
backstop() {
  [ "$UNJUDGED" = true ] || return 0
  local d protected_union='' hit=false name any_config=false
  for d in "${ALL_DIRS[@]}"; do
    if load_config "$d"; then any_config=true; protected_union="$protected_union"$'\n'"$PROTECTED"; fi
  done
  [ "$any_config" = true ] || return 0
  if [ "$ANY_PUSH" = true ]; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      case "$NAMES" in *$'\n'"$name"$'\n'* | *$'\n'"$name") hit=true; break ;; esac
    done <<< "$protected_union"
  fi
  [ "$ANY_MERGE" = true ] && hit=true
  [ "$hit" = true ] || return 0
  deny "This command names a protected branch next to push, or holds a gh merge, and the guard could not judge it: ${WHY:-a form it does not parse}. What it cannot judge it refuses. Write it plainly, one invocation per command: git push origin <branch>, gh pr merge <n>."
}

# One tool call can chain several commands; every segment is judged on its own.
while next_segment; do
  case "$SEG_KIND" in
    open)
      SUB_STACK+=("$(IFS=$'\001'; printf '%s' "${SHELL_DIRS[*]}")")
      SUB_DEPTH=$((SUB_DEPTH + 1))
      continue
      ;;
    close)
      if [ "$SUB_DEPTH" -gt 0 ]; then
        last=$((${#SUB_STACK[@]} - 1))
        IFS=$'\001' read -r -a SHELL_DIRS <<< "${SUB_STACK[last]}"
        unset "SUB_STACK[$last]"
        SUB_DEPTH=$((SUB_DEPTH - 1))
      fi
      continue
      ;;
  esac
  count=${#words[@]}
  [ "$count" -gt 0 ] || continue
  case "$FLAGS" in *k*) ANY_PUSH=true ;; esac
  [[ "$FLAGS" == *h* && "$FLAGS" == *m* ]] && ANY_MERGE=true
  case "$FLAGS" in *e*) ENV_SEEN=true; unjudged 'GIT_DIR, GIT_WORK_TREE, --git-dir, GH_REPO or a like variable' ;; esac
  PWD_OK=false
  if [ "${#SHELL_DIRS[@]}" -eq 1 ]; then PWD_OK=true; DIR="${SHELL_DIRS[0]}"; fi
  # Reserved words before the command.
  s=0
  while [ "$s" -lt "$count" ]; do
    case "${words[s]}" in '!' | if | then | else | elif | do | while | until | time) s=$((s + 1)) ;; *) break ;; esac
  done
  i=$s
  while [ "$i" -lt "$count" ] && [[ "${words[i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*\+?= ]]; do
    i=$((i + 1))
  done
  # Assignments alone set the variable for the next segments, when the segment runs and lasts. In
  # front of a command they belong to that command only. Whatever else the resolver cannot follow
  # (`NAME+=`, a value from a command, a segment after && || or a pipe or in a subshell, read,
  # printf -v, for, declare and its kin) leaves the name unresolved, never holding an old value.
  k=$s
  while [ "$k" -lt "$i" ]; do
    name="${words[k]%%=*}"
    if [[ "$name" == *+ ]]; then
      forget "${name%+}"
    elif [ "$i" -eq "$count" ] && [ "$MAY_NOT_RUN" = false ] && [ "$PIPED" = false ] && [ "$SUB_DEPTH" -eq 0 ]; then
      record_assignment "${words[k]}"
    elif [ "$i" -eq "$count" ] || ! expand_word "${words[k]#*=}"; then
      forget "$name"
    fi
    k=$((k + 1))
  done
  if [ "$i" -lt "$count" ]; then
    case "${words[i]}" in
      export | declare | local | typeset | readonly | unset | read)
        k=$((i + 1))
        while [ "$k" -lt "$count" ]; do
          name="${words[k]%%=*}"
          [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && forget "$name"
          k=$((k + 1))
        done
        ;;
      for | select)
        [ $((i + 1)) -lt "$count" ] && forget "${words[i + 1]}"
        ;;
      printf)
        k=$((i + 1))
        while [ "$k" -lt "$count" ]; do
          [ "${words[k]}" = '-v' ] && [ $((k + 1)) -lt "$count" ] && forget "${words[k + 1]}"
          k=$((k + 1))
        done
        ;;
    esac
  fi
  # The projects a variable or an option points git at are directories the command names.
  if [[ "$FLAGS" == *e* ]] || [ "${words[i]:-}" = 'env' ]; then
    for ((k = s; k < count; k++)); do
      v=''
      case "${words[k]}" in
        GIT_DIR=* | GIT_WORK_TREE=* | --git-dir=* | --work-tree=*) v="${words[k]#*=}" ;;
        --git-dir | --work-tree) [ $((k + 1)) -lt "$count" ] && v="${words[k + 1]}" ;;
        -C) [ "${words[i]:-}" = 'env' ] && [ $((k + 1)) -lt "$count" ] && v="${words[k + 1]}" ;;
      esac
      if [ -n "$v" ] && expand_word "$v"; then add_all "$EXPANDED"; add_all "${EXPANDED%/.git}"; fi
    done
  fi
  if [ "$i" -ge "$count" ]; then
    # Only assignments: a command string kept in a variable is not judged.
    [[ "$FLAGS" == *[ghkm]* ]] && unjudged 'a command held in a variable'
    continue
  fi
  ci=$i
  cmd="${words[ci]}"

  # `cd <dir>` moves where the later segments run; one that may not run, or does not last, adds a
  # place the shell may stand without taking the others away.
  if [ "$cmd" = 'cd' ] || [ "$cmd" = 'pushd' ]; then
    i=$((ci + 1))
    while [ "$i" -lt "$count" ] && [[ "${words[i]}" =~ ^-(-|[LPe@]+)$ ]]; do
      i=$((i + 1))
    done
    target='~'
    [ "$i" -lt "$count" ] && target="${words[i]}"
    moved=()
    for sd in "${SHELL_DIRS[@]}"; do
      DIR="$sd"
      move_to "$target"
      if [ "$MOVE_UNRESOLVED" = true ]; then UNRES=true; moved+=("$sd"); fi
      moved+=("$DIR")
      add_visited "$DIR"
    done
    if [ "$PIPED" = true ]; then
      :
    elif [ "$MAY_NOT_RUN" = true ] || [ "$UNRES" = true ]; then
      for d in "${moved[@]}"; do add_shell "$d"; done
    else
      SHELL_DIRS=()
      for d in "${moved[@]}"; do add_shell "$d"; done
    fi
    continue
  fi
  if [ "$cmd" = 'popd' ]; then
    UNRES=true
    continue
  fi

  SEG_UNJUDGED=''
  NO_REFSPEC=false
  refspecs=()
  case "$cmd" in
    git)
      for sd in "${SHELL_DIRS[@]}"; do
        judge_git "$sd"
        if [ -n "$SEG_UNJUDGED" ]; then why="$SEG_UNJUDGED"; fi
      done
      [ -n "${why:-}" ] && { unjudged "$why"; why=''; }
      [ "$UNRES" = true ] && unjudged 'a directory only the shell can resolve'
      ;;
    gh)
      for sd in "${SHELL_DIRS[@]}"; do judge_gh "$sd"; done
      if [[ "$FLAGS" == *m* ]]; then
        case "${words[ci + 1]:-} ${words[ci + 2]:-}" in
          'pr merge') ;;
          'pr view' | 'pr list' | 'pr create' | 'pr edit' | 'pr comment' | 'pr diff' | 'pr checks' | 'pr close' | 'pr reopen' | 'pr ready' | 'pr review' | 'pr status' | 'pr checkout' | 'issue '*) ;;
          *) unjudged 'a gh form it does not parse (gh api, an alias)' ;;
        esac
        [ "$UNRES" = true ] && unjudged 'a directory only the shell can resolve'
      fi
      ;;
    trellis | */trellis)
      # Its subcommand `issue` takes the arguments of `gh issue`, whose words are data.
      for sd in "${SHELL_DIRS[@]}"; do judge_trellis "$sd"; done
      if [[ "$FLAGS" == *[ghkm]* ]] && [ "$cmd ${words[ci + 1]:-}" != 'trellis issue' ]; then
        unjudged "a wrapper or a program ($cmd) that may run git or gh"
      fi
      ;;
    *)
      if [[ "$INTERPRETERS" == *" $cmd "* ]]; then
        operands=0
        for ((k = ci + 1; k < count; k++)); do [[ "${words[k]}" == -* ]] || operands=$((operands + 1)); done
        { [[ "$FLAGS" == *[ghkm]* ]] || [ "$operands" -eq 0 ]; } && unjudged "an interpreter ($cmd) that runs text"
      elif [[ "$FLAGS" == *[ghkm]* ]]; then
        # A program that only prints text runs what a substitution in its words runs.
        runs=false
        for word in "${words[@]}"; do
          case "$word" in *'$('* | *'`'* | *'<('* | *'>('*) runs=true ;; esac
        done
        { [ "$runs" = true ] || [[ "$INERT" != *" $cmd "* ]]; } && unjudged "a wrapper or a program ($cmd) that may run git or gh"
      fi
      ;;
  esac
done 3< <(split_segments)

backstop
print_held_message
exit 0
