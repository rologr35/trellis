# trellis

A harness for Claude Code that a project commits as a copy: the working method, git guards, the hygiene of the instruction files, ratchets and templates. This repository runs from its own tree, and follows the rules it gives to others.

<!-- trellis:method -->
## Working method

`trellis sync` writes this block from trellis (`.trellis/`); it is changed in trellis, not here. It describes how Claude works in this project, on every turn.

### Before acting

- Claude studies the whole flow before touching it: who calls it, what it reads, what it writes, what tests it.
- The gaps that reading closes (code, config, history, logs) are closed before proposing. "Not established" is said only of what cannot be checked, and it is said.
- Claude proposes before acting and waits for approval. It first considers an external alternative (a library, a tool, a service) to building.
- Simple beats clever. No abstraction until two real uses. No "safe rollout" feature flags: what waits for a date ships switchable by configuration.
- The ratchet question: does this change loosen something that is prevented today? If so, it is said before doing it (see Ratchets).
- Before calling something done, the project's real typecheck and lint run (`trellis check`), not a reading of the diff.
- The report is honest: what failed is said with its output, what was not done is said, what was verified is stated plainly.

### Delivering

- Claude delivers the finished solution and escalates to a person only what needs one: a decision, an access, something irreversible.
- A question from the person mid-task is a question, not an order to change course.
- When Claude sees how to make its own work more efficient, it proposes it with data: what it costs today and what it would cost.

### Anti-duplication

- Search by files first and by lines after, before writing something that may exist.
- Every derived value has one canonical definition. A second copy is a defect even when it matches today.
- Changing the meaning of a metric sweeps all its consumers in the same change.
- The home of a new file is decided explicitly, by the layout of this `CLAUDE.md`.
- What is replaced is deleted in the same change that replaces it.
- Metrics are honest: they measure what they say they measure.

### Git

- Claude never commits on the release branch or the integration branch: each issue is worked in its worktree (`trellis worktree add <n> <slug>`).
- A push always carries an explicit refspec (`git push origin <branch>`): the guard judges a bare push by the branch of the checkout.
- Never `amend`, `reset` or `force-push` without the approval of that specific action. "Go ahead" or "continue" do not approve those actions.
- Changes in the working tree are never discarded to tidy up. An uncommitted change is not storage: work that outlives the session is committed on a branch in the same turn.

### Ratchets

- A ratchet keeps something that was cleaned up from growing back: suppressions, tests, lint rules, size limits, exception lists.
- Before loosening one, Claude objects with data: what regresses, what it costs and which alternative does not regress. Then it waits for the person. With their confirmation, `git config branch.<branch>.ratchet-loosened true`, and the pull request carries the **Setback** section.
- A new guard is measured against the merged history while planning, not when it runs: how many cases of the history it would have stopped, and how many without reason.
- A test rung that is switched off carries a return date (`offUntil`), and switching it on costs a full catch-up run.

### Worktrees

- `EnterWorktree` acts only when this text names it for the task: after `trellis worktree add`, with the path it prints.
- Leaving is with `ExitWorktree` and `keep`, never with `remove`: `trellis worktree prune` decides what is deleted.
- Inside a worktree session, Claude Code rejects Bash with git in complex form (heredocs, `$(...)`, loops, even the word in a path). Long text goes through Write and Bash runs simple lines.

### Conflicts in instruction files

A conflict in a `CLAUDE.md`, a rule or a skill is resolved from the branch's own version plus its own change, never by rebuilding the file from the integration branch.

### Memory

- Memory keeps preferences and pointers, not state. State (pending migrations, uncommitted code, the state of a template) is read again from its source when used.
- What another session did lives in its transcript (`~/.claude/projects/**/*.jsonl`), not in git. A hypothesis a cheap query can check is checked before acting on it.

### Cost

- More use of Claude is never free. A proposal that adds runs, reviews or subagents states its weight on the quota.
- The big lever is short tool output (read ranges, not whole files; filter the output), not lowering the effort.

### Plans

- Before proposing a plan, the `trellis-plan-reviewer` agent checks it in a clean context, with the request it answers: its verdict goes with the proposal, and each of its points as corrected or rejected, with the reason.
- No plan lives in a folder git ignores. Business context goes to `docs/`.
- What is learned from the code goes to the `CLAUDE.md` or the rule closest to that code, at the height of the concept.

### Cycle

- The approved plan lives in the issue, written from the mould (`.trellis/templates/en/issue.md`) and created with `trellis issue create --title <t> --body-file <file>`, which checks it and labels it with its complexity.
- The body of an issue is never edited. A change of the plan is a comment headed `## Amendment (<date>)`, with the sections it replaces, whole, as `###` headings.
- An issue is worked with `/trellis-work <n>`: at pick-up `trellis issue check <n>` passes (with `--print`, the plan in force), and the integration branch is fetched before the body is written: a claim about it is checked there.
- An issue without a plan (a symptom, a lesson) is legitimate. It is created with `gh issue create` or `gh issue new`, which a guard wants after a search of the backlog, unclassed, and gets its plan later, as an amendment with the five sections and the complexity line.
- What a piece of work leaves for another issue goes through `trellis issue follow-up`.
- A pull request opens as a draft. `trellis-plan-check` runs, then `gh pr ready`; an S that only touches Markdown skips it.
- Its body carries `Closes #<n>`, one line `Lesson:` (`none`, `local: <what>` or `framework: <what>`), **Before merging** and **After merging**, each `none` or a list.
- A merge goes through `/trellis-merge <pr>`.
- What merged work left undone: `gh issue list --state closed --label pending-actions`.

### Releases

- Every pull request is a releasable increment.
- What waits for a date ships switchable by configuration.
- A backfill never leaves an empty view between the deploy and a script.
- A test the plan names is written even when it cannot run locally, and the pull request says which rung is left waiting.
- A quality barrier reaches the release branch or does not exist. Lint goes inside the barrier: taking it out because of accumulated drift is irreversible in practice.

### Subagents

- A subagent or a routine receives the critical rules in its prompt, without being asked to read what the harness already loads for it.
- Its report carries a length cap and is a claim to verify, not a fact.
- It shares the file system: it writes with `mktemp`, and the parent uses unique names.
- A search takes a cheap model. Sibling jobs go in tabs, not in subagents.
<!-- /trellis:method -->

## Orientation

The project's instruction files and when each one loads. `bin/trellis sync` writes the table.

<!-- trellis:orientation -->
| File | Loads | Covers |
|---|---|---|
| `.claude/rules/shell.md` | `**/*.sh` | Shell scripts |
<!-- /trellis:orientation -->

## Commands

<!-- trellis:commands -->
- `trellis check` runs, in order: `test`.
- `test`: `./test.sh`. Every suite, or the ones of its argument: `./test.sh shell`, `./test.sh node`.
- `secrets`: `gitleaks protect --staged --redact`. The secret scan of the staged change, and of the history in CI.
<!-- /trellis:commands -->

## Gates

<!-- trellis:gates -->
No gates: `[gate "<name>"]` in `trellis.config` declares them.
<!-- /trellis:gates -->

## Layout

- `bin/trellis`: the command line. Each subcommand is a script of `scripts/` or `hygiene/`.
- `scripts/`: the subcommands, in bash or node, each with its `*.test.sh`.
- `hooks/`: the hooks of Claude Code, with their suites, and the suite of the git hooks.
- `hygiene/`: the contract of the instruction files, and the suites that run with `node --test`.
- `lib/`: what the scripts, the hooks and the hygiene share.
- `method/`: the working method, one file per language, with the same principles.
- `skills/`, `agents/`: their sources. `.claude/skills/trellis-*` and `.claude/agents/trellis-*` are generated from them and are not edited.
- `docs/`: what trellis does not do and a project may, with its cost.
- `templates/`: what `init` writes into a project: one folder per language, and what has no language at the root.
- `.github/workflows/`: `test.yml` and `trellis.yml` are of this repository; `consumer-*.yml` are called by the projects.
- `.claude-plugin/`: the plugin and its marketplace, which only `init` needs.

The copy of a project holds `bin/`, `hooks/`, `lib/`, `scripts/`, `hygiene/`, `method/`, `templates/` and `LICENSE`, without the tests, and its skills and agents: a file added there reaches every project.

## Anti-duplication in this project

- The keys of `trellis.config`, their defaults and their accepted values: `lib/schema`. The config is read through `lib/config.sh` and `lib/config.mjs`.
- The language of what is written into a project, the sections of a pull request and of an issue: `lib/locale.mjs`. The style of what is published: `lib/style.mjs`.
- The files of a project, of the working tree or of the index: `lib/tree.mjs`. Its packages: `lib/packages.mjs`. A glob: `lib/glob.mjs`.
- The generated blocks, the deny and the hooks of the settings: `lib/blocks.mjs`.
- What a copy holds, the names of the skills and agents in a project, and the URL of an upstream: `lib/copy.mjs`.
- A private name, and where it is found: `lib/private-names.mjs`. The check of a project: `lib/project-check.sh`.
- Which `trellis` a project runs: `lib/find-trellis.sh`, whose copy is `.githooks/find-trellis.sh`.
- A question to GitHub: `lib/gh.sh`. The isolated repositories and the assertions of a suite: `lib/testlib.sh`.
- The contract of a script: the comment at its head. `README.md` says what a person needs to use it.

## Conventions

- A lesson of a project is an issue with the label `lesson`. A defect of a guard enters with its case; a rule enters with two incidents; a person decides. The fix is tried in the project that brought it, with `trellis update <sha>` of the pushed branch, before the release.
- Every script runs with `/bin/bash` 3.2 and with the tools of macOS and of Linux.
- Node has no dependencies: there is no `package.json`.
- A new case is seen red before it is green, and the report says so. A mutation of a guard turns a case red: a guard whose suite passes without it is not tested.
- GitHub is asked through `lib/gh.sh`, as the account of the owner of the repository, with the REST interface.
- In a worktree the command is `bin/trellis` of that worktree. `sync` and `hygiene` of another checkout refuse.
- `.trellis/` in the method is the root of this repository: `.trellis/templates/en/issue.md` is `templates/en/issue.md`.

## Never

- Never commit on `main`.
- Never push without an explicit refspec.
- Never run a test rung that `TESTING.md` marks as not runnable by Claude.
- Never write the name of a private project that uses trellis, or a path, a number or a term of it, in anything that is published: the code, a commit, a branch, an issue, a pull request or a comment.
- Never run a test against GitHub: `gh` is a stub in every suite.
- Never release a version without both systems green, ubuntu and macOS.

## Before calling it done

- [ ] `bin/trellis check` green.
- [ ] `bin/trellis hygiene` green if the change touches instructions.
- [ ] New tests per the map of `TESTING.md`, seen failing before passing.
- [ ] Commit on the issue's branch, push with an explicit refspec, pull request with its `Lesson:` line, **Summary**, **Verification**, **Before merging** and **After merging**.
