## Working method

`trellis sync` writes this block from trellis (`.trellis/`); it is changed in trellis, not here. It describes how Claude works in this project, on every turn.

### Before acting

- Claude studies the whole flow before touching it: who calls it, what it reads, what it writes, what tests it. <!-- p:study-flow -->
- The gaps that reading closes (code, config, history, logs) are closed before proposing. "Not established" is said only of what cannot be checked, and it is said. <!-- p:close-gaps -->
- Claude proposes before acting and waits for approval. It first considers an external alternative (a library, a tool, a service) to building. <!-- p:propose-first -->
- Simple beats clever. No abstraction until two real uses. No "safe rollout" feature flags: what waits for a date ships switchable by configuration. <!-- p:simple -->
- The ratchet question: does this change loosen something that is prevented today? If so, it is said before doing it (see Ratchets). <!-- p:ratchet-question -->
- Before calling something done, the project's real typecheck and lint run (`trellis check`), not a reading of the diff. <!-- p:real-check -->
- The report is honest: what failed is said with its output, what was not done is said, what was verified is stated plainly. <!-- p:honest-report -->

### Delivering

- Claude delivers the finished solution and escalates to a person only what needs one: a decision, an access, something irreversible. <!-- p:finished-solution -->
- A question from the person mid-task is a question, not an order to change course. <!-- p:question-not-order -->
- When Claude sees how to make its own work more efficient, it proposes it with data: what it costs today and what it would cost. <!-- p:propose-efficiency -->

### Anti-duplication

- Search by files first and by lines after, before writing something that may exist. <!-- p:search-first -->
- Every derived value has one canonical definition. A second copy is a defect even when it matches today. <!-- p:canonical -->
- Changing the meaning of a metric sweeps all its consumers in the same change. <!-- p:metric-sweep -->
- The home of a new file is decided explicitly, by the layout of this `CLAUDE.md`. <!-- p:file-home -->
- What is replaced is deleted in the same change that replaces it. <!-- p:delete-replaced -->
- Metrics are honest: they measure what they say they measure. <!-- p:honest-metrics -->

### Git

- Claude never commits on the release branch or the integration branch: each issue is worked in its worktree (`trellis worktree add <n> <slug>`). <!-- p:no-commit-protected -->
- A push always carries an explicit refspec (`git push origin <branch>`): the guard judges a bare push by the branch of the checkout. <!-- p:explicit-refspec -->
- Never `amend`, `reset` or `force-push` without the approval of that specific action. "Go ahead" or "continue" do not approve those actions. <!-- p:no-rewrite -->
- Changes in the working tree are never discarded to tidy up. An uncommitted change is not storage: work that outlives the session is committed on a branch in the same turn. <!-- p:keep-worktree-changes -->

### Ratchets

- A ratchet keeps something that was cleaned up from growing back: suppressions, tests, lint rules, size limits, exception lists. <!-- p:ratchet-definition -->
- Before loosening one, Claude objects with data: what regresses, what it costs and which alternative does not regress. Then it waits for the person. With their confirmation, `git config branch.<branch>.ratchet-loosened true`, and the pull request carries the **Setback** section. <!-- p:ratchet-objection -->
- A new guard is measured against the merged history while planning, not when it runs: how many cases of the history it would have stopped, and how many without reason. <!-- p:guard-history -->
- A test rung that is switched off carries a return date (`offUntil`), and switching it on costs a full catch-up run. <!-- p:rung-off -->

### Worktrees

- `EnterWorktree` acts only when this text names it for the task: after `trellis worktree add`, with the path it prints. <!-- p:enter-worktree -->
- Leaving is with `ExitWorktree` and `keep`, never with `remove`: `trellis worktree prune` decides what is deleted. <!-- p:exit-keep -->
- Inside a worktree session, Claude Code rejects Bash with git in complex form (heredocs, `$(...)`, loops, even the word in a path). Long text goes through Write and Bash runs simple lines. <!-- p:worktree-bash -->

### Conflicts in instruction files

A conflict in a `CLAUDE.md`, a rule or a skill is resolved from the branch's own version plus its own change, never by rebuilding the file from the integration branch. <!-- p:instruction-conflicts -->

### Memory

- Memory keeps preferences and pointers, not state. State (pending migrations, uncommitted code, the state of a template) is read again from its source when used. <!-- p:memory-pointers -->
- What another session did lives in its transcript (`~/.claude/projects/**/*.jsonl`), not in git. A hypothesis a cheap query can check is checked before acting on it. <!-- p:other-sessions -->

### Cost

- More use of Claude is never free. A proposal that adds runs, reviews or subagents states its weight on the quota. <!-- p:cost-weight -->
- The big lever is short tool output (read ranges, not whole files; filter the output), not lowering the effort. <!-- p:short-output -->

### Plans

- Before proposing a plan, the `trellis-plan-reviewer` agent checks it in a clean context, with the request it answers: its verdict goes with the proposal, and each of its points as corrected or rejected, with the reason. <!-- p:plan-reviewer -->
- No plan lives in a folder git ignores. Business context goes to `docs/`. <!-- p:plan-tracked -->
- What is learned from the code goes to the `CLAUDE.md` or the rule closest to that code, at the height of the concept. <!-- p:learned-near-code -->

<!-- cycle -->
### Cycle

- The approved plan lives in the issue, written from the mould (`.trellis/templates/en/issue.md`) and created with `trellis issue create --title <t> --body-file <file>`, which checks it and labels it with its complexity. <!-- p:plan-in-issue -->
- The body of an issue is never edited. A change of the plan is a comment headed `## Amendment (<date>)`, with the sections it replaces, whole, as `###` headings. <!-- p:issue-amendment -->
- An issue is worked with `/trellis-work <n>`: at pick-up `trellis issue check <n>` passes (with `--print`, the plan in force), and the integration branch is fetched before the body is written: a claim about it is checked there. <!-- p:work-skill -->
- An issue without a plan (a symptom, a lesson) is legitimate. It is created with `gh issue create` or `gh issue new`, which a guard wants after a search of the backlog, unclassed, and gets its plan later, as an amendment with the five sections and the complexity line. <!-- p:planless-issue -->
- What a piece of work leaves for another issue goes through `trellis issue follow-up`. <!-- p:follow-up -->
- A pull request opens as a draft. `trellis-plan-check` runs, then `gh pr ready`; an S that only touches Markdown skips it. <!-- p:plan-check -->
- Its body carries `Closes #<n>`, one line `Lesson:` (`none`, `local: <what>` or `framework: <what>`), **Before merging** and **After merging**, each `none` or a list. <!-- p:pr-before-after -->
- A merge goes through `/trellis-merge <pr>`. <!-- p:merge-skill -->
- What merged work left undone: `gh issue list --state closed --label pending-actions`. <!-- p:pending-actions -->

<!-- /cycle -->
### Releases

- Every pull request is a releasable increment. <!-- p:releasable -->
- What waits for a date ships switchable by configuration. <!-- p:date-config -->
- A backfill never leaves an empty view between the deploy and a script. <!-- p:backfill -->
- A test the plan names is written even when it cannot run locally, and the pull request says which rung is left waiting. <!-- p:named-test -->
- A quality barrier reaches the release branch or does not exist. Lint goes inside the barrier: taking it out because of accumulated drift is irreversible in practice. <!-- p:quality-barrier -->

### Subagents

- A subagent or a routine receives the critical rules in its prompt, without being asked to read what the harness already loads for it. <!-- p:subagent-rules -->
- Its report carries a length cap and is a claim to verify, not a fact. <!-- p:subagent-report -->
- It shares the file system: it writes with `mktemp`, and the parent uses unique names. <!-- p:subagent-files -->
- A search takes a cheap model. Sibling jobs go in tabs, not in subagents. <!-- p:cheap-search -->