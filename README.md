# trellis

A replicable agentic harness for Claude Code: the always-loaded working method, git guards, hygiene of the instruction files, ratchets and project templates. A project commits a copy of a version of it, so the same files answer in every session, local or in the cloud. This repository follows the same rules, from its own tree, and is also a plugin and its marketplace, which only `/trellis:init` needs.

Base, the module of this repository, needs only git and node. The Cycle (issues, labels, review against the plan) and Autonomy (cloud routines, dispatcher, budget) modules are built on top of it. Of Cycle, this repository holds the mould of an issue's plan and its check, the check of the branch against that plan, the claim and the stop of an issue, the skill that works one until its pull request is ready, the follow-up of what it leaves, and the close of the issue when its pull request is merged; `tracker.kind = none` leaves them off.

## Install in a project

The plugin is installed only to run `/trellis:init`, which writes the copy; the project then works without it.

1. Claude Code 2.1.330 or later (the marketplace pinned by sha and the `--scope local` install need it).
2. In the project's main checkout, install the plugin at the **local** scope, pinned to a full sha of this repository (`<sha>` is the commit to adopt; `git ls-remote https://github.com/rologr35/trellis.git HEAD` prints the latest):

   ```sh
   claude plugin marketplace add rologr35/trellis@<sha> --scope local
   claude plugin install trellis@trellis --scope local
   ```

   Both write to `.claude/settings.local.json`, which git ignores, so the main checkout stays clean: `init` asks for it clean, on the integration branch.
3. `/trellis:init`: an interview, then, in a worktree, it writes the configuration, the templates and the copy, and ends with `trellis hygiene --freeze` and `trellis doctor`.
4. After the merge, remove the plugin: `claude plugin uninstall trellis@trellis --scope local`, and take `extraKnownMarketplaces.trellis` out of `.claude/settings.local.json`. With both, every hook runs twice, and `trellis doctor` warns.

The project's own linters and formatters must leave `.trellis/` out, in their own configuration: a file they rewrite is no longer the copied one, and `trellis verify` fails.

## The copy

`trellis update <tag|sha>` clones `trellis.upstream`, resolves the ref to a full sha and writes:

| Path | What it is |
|---|---|
| `.trellis/` | The runtime (`bin`, `hooks`, `lib`, `scripts`, `hygiene`, `method`, `templates`, `LICENSE`), without its tests. |
| `.trellis/VERSION` | The version and the full sha. |
| `.trellis/MANIFEST` | The sha256 of every file written, as `shasum -a 256 -c` reads it. |
| `.claude/skills/trellis-<name>/SKILL.md` | Every skill but `init`: `/trellis-work`, `/trellis-merge` and the rest. |
| `.claude/agents/trellis-<name>.md` | The agents: `trellis-plan-reviewer` and `trellis-plan-check`. |

What the previous copy had and the new one does not is removed. Nothing is written when the copy was edited by hand, when a file of the project has the name of a copied one, or when git ignores one: the files are named. A branch is refused, because what it names changes. It ends with `trellis sync` run from the new copy, which writes in `.claude/settings.json` the `PreToolUse` hook of `guard-git`, the `SessionStart` hook of `trellis setup` and the deny `Edit(/.trellis/**)`; other hooks of the project are left as they are.

`trellis verify` fails when a file of the manifest is missing or changed, or `.trellis/` has another one. `--upstream` clones the sha of `VERSION` and compares with it, so a file and its manifest line changed together fail too; `--staged` judges the index, and `--ref <sha>` requires that sha in `VERSION`. The pre-commit hook and `trellis hygiene` run the local form; the consumer CI runs `verify --upstream --ref` with the sha it is called with. The hygiene and the ratchet do not judge the files of the copy: they are not the project's.

To move to another version, in a pull request of its own: `trellis update <tag|sha>`, which also writes the new sha over the one of the previous copy in `.github/workflows/trellis.yml`, and the commit of everything. The update that runs is the one of the copy in the project: 0.6.0 does not write that file. There is nothing to install on a machine.

A project of 0.5.0 or earlier consumes the plugin. Its pull request with the first copy is written from a clone of this repository (`<clone>/bin/trellis update <tag|sha>`) and also:

- takes `extraKnownMarketplaces.trellis` and `enabledPlugins."trellis@trellis"` out of `.claude/settings.json`;
- takes `.githooks/` and `.github/workflows/trellis.yml` again from `templates/`, with the sha of `.trellis/VERSION`. From 0.5.0 on the workflow has the type `closed` and the job `closed`, without which `trellis doctor` warns that a merge made on GitHub closes no issue, and `pr-check` wants `Closes #<n>`, **Before merging** and **After merging** in the body of every pull request of an issue into the integration branch, the ones already open too;
- has as an item of **After merging** that each machine uninstalls the plugin: `claude plugin uninstall trellis@trellis --scope project`.

## Packages

Each package of a project has its `CLAUDE.md`, and `trellis hygiene` names the ones that lack it. `/trellis-scaffold` drafts them. `[workspace]` of `trellis.config` says which the packages are:

| Key | What it says |
|---|---|
| `manifest` | The files that make a folder below the root a package; `package.json` and `pubspec.yaml` by default. Written, they are the only ones. A manifest at the root, in `.trellis/` or in what git ignores asks for nothing. |
| `package` | One line per package without a manifest. |
| `notPackage` | `<glob> \| <reason>`: a folder that is no package, an example or a fixture, whatever lists it. |

The hygiene also resolves the files a rule names against the packages, and fails without a root `CLAUDE.md`. The ratchet stops a glob more in `notPackage` and one less in `manifest`. A project that moves from 0.7.1 or earlier gets one finding for each package without its file, and can get one more for a rule that names a file by its path inside a package. For the first, it writes the `CLAUDE.md`, or a line of `notPackage` with its reason, which the ratchet of the pull request of the update stops until a person confirms it.

## Language

trellis is written in English. What it writes into a project follows `project.locale`, `en` (the default) or `es`, the first question of `init`:

- the method block, from `method/en.md` or `method/es.md`;
- the templates, from `templates/en/` or `templates/es/`: `CLAUDE.root.md`, `CLAUDE.package.md`, `rule.md`, `SKILL.md`, `TESTING.md`, the mould of an issue (`issue.md`, read from `.trellis/`) and the comments of `trellis.config`; the language-neutral ones (`settings.json`, `githooks/`, `gitignore.fragment`, `workflows/`) stay in `templates/`;
- the generated blocks (`method`, `orientation`, `commands`, `gates`, `rungs`), whose labels live in `lib/blocks.mjs`;
- the pull request sections `pr-check` requires, defined in `lib/locale.mjs`: **Summary**, **Verification** and **Setback**, and **Before merging** and **After merging** in the pull request of an issue, in en; **Resumen**, **Verificación** and **Retroceso**, and **Antes de mezclar** and **Después de mezclar**, in es;
- the words of the report of `plan-check`, defined in `lib/locale.mjs`: `Verdict: satisfied`, `Verdict: changes requested` and `Not established:` in en; `Veredicto: satisfecho`, `Veredicto: cambios pedidos` and `No establecido:` in es;
- the sections and labels of an issue's plan that `trellis issue` reads, defined in `lib/locale.mjs`: **Context**, **Approved plan**, **Layers and files**, **Risks** and **Verification** in en; **Contexto**, **Plan aprobado**, **Capas y ficheros**, **Riesgos** and **Verificación** in es;
- the narrative phrases the hygiene checks: the list of the project's locale, and always the en one, because code comments are English.

Each prose template is a file per locale rather than one file with per-locale strings: a template is mostly prose, and a file per locale keeps it readable as the text it produces. The tests keep the copies aligned: each principle of the method carries an id (`<!-- p:<id> -->`, stripped from the generated block) and both methods carry the same ids in the same order; both template folders hold the same files with the same blocks, the same `trellis.config` keys and the same placeholder names (`{{name}}`, `{{package}}` and the rest are the English ones in both; only the text around them and the free-text prompts are translated); the sections of each `issue.md` are the ones of its locale, in order; and a project written from each locale's templates passes the hygiene.

## What is there

| Piece | Where | What it does |
|---|---|---|
| Method | `method/<locale>.md` | How Claude works, on every turn. `trellis sync` copies it into the `<!-- trellis:method -->` block of the root `CLAUDE.md`, and the hygiene checks that it matches: a skill loads only when invoked, the method is needed always. |
| CLI | `bin/trellis` | `config`, `doctor`, `sync`, `hygiene`, `setup`, `update`, `verify`, `worktree add\|prune`, `ratchet`, `pr-check`, `issue check\|gates\|claim\|stop\|create\|follow-up\|close`, `check`. |
| Issue plan | `templates/<locale>/issue.md`, `scripts/issue.sh` | The mould of the plan an issue holds, and its check: before publishing (`--body <file>`), at pick-up (`<n>`, with the amendments resolved and the dependencies closed, and the paths that changed since printed), and at creation, with the label of its class (S, M or L). |
| Claim and stop of an issue | `scripts/issue.sh` | `trellis issue claim <n>` takes an open issue with a plan that passes, that nobody is assigned to and whose branch is not on origin, for the account it asks as. `--resume` takes what that account already has, `--unattended` refuses a plan with a gate or with `Needs`. `trellis issue gates <n>` names the gates the branch touches and the plan does not. `trellis issue stop <n>` leaves the issue stopped: the label `stopped`, and a comment with what is done, what is missing and what it needs. |
| Follow-up | `scripts/issue.sh` | `trellis issue follow-up` searches the backlog and opens what the work leaves for another issue: at `[autonomy] level` `careful` it only proposes it until a person approves. It is refused when the problem was not seen at the head of the integration branch. |
| Close of a merge | `scripts/issue.sh`, `.github/workflows/consumer-closed.yml`, `skills/merge/` | `trellis issue close <pr>` closes the issues of a pull request merged into the integration branch and, with actions in **After merging**, leaves them in one comment with the label `pending-actions`, which `--done` takes off. The workflow runs it for a merge made on GitHub; `/trellis-merge <pr>` is the whole path. |
| Configuration | the project's `trellis.config` | git-config format, read with `git config -f`; `lib/schema` holds the keys and their defaults. |
| Guards | `hooks/guard-git.sh` | Pushes to protected branches, branch switches in the main checkout, issues without a prior search, merges outside the allowed bases. `gh issue new` and `trellis issue create` are issue creations like `gh issue create`. |
| Packages | `lib/packages.mjs` | Which the packages of a project are: see Packages. |
| Git hooks | `templates/githooks/` | The copy, ratchet, hygiene, commit message and branch name, in the clone. |
| Consumer CI | `.github/workflows/consumer-check.yml` | The copy, hygiene, ratchet, `pr-check` and the secret scanner on every open pull request. `consumer-closed.yml` is the second workflow, run when one is merged. Neither runs a rung: a rung with `pr = true` is run by the project's own CI. |
| Skills | `skills/` | `init`, `scaffold`, `debugging`, `retro`, `work`, `merge`. `/trellis-work <n>` takes an issue from its claim to a pull request ready, in a person's session or in a run without one; it never merges. |
| Agents | `agents/plan-reviewer.md`, `agents/plan-check.md` | `trellis-plan-reviewer` and `trellis-plan-check` in a project, each in a clean context: the first checks a plan against the repository, and its exclusions and steps against the request it answers, before the work (in opus), the second checks the branch of an issue against its approved plan while the pull request is a draft. |

## Where each thing runs

- The copy is in the repository, so it is in every clone and in a session hosted in the cloud, which does not add the marketplaces of `extraKnownMarketplaces`. `trellis issue`, the guards and `worktree prune` ask GitHub through REST, the interface such a session has; the whole path of `/trellis-work` there is not proven until the first real run of rologr35/trellis#3. Its hooks run from `.claude/settings.json` through `$CLAUDE_PROJECT_DIR`, the project the session started in.
- `trellis setup`, which the `SessionStart` hook runs, adds `.trellis/bin` to the PATH of the session's Bash tool through `CLAUDE_ENV_FILE`. It is not on the PATH of a person's shell nor of the git hooks: these look for trellis with `lib/find-trellis.sh`, first at `.trellis/bin/trellis` of the repository (`bin/trellis` in the one of trellis), then on the PATH, then in the `installPath` of `~/.claude/plugins/installed_plugins.json`.
- The hooks need node. Without node, `guard-git` has no opinion and `trellis doctor` gives a FAIL. The native `claude` binary does not bring node.
- The `deny` lives in the project's `settings.json`, and `trellis sync` generates it. The push `deny` is there as well as in `guard-git`, for a session where the hooks do not run.
- `git.hooksPath` of `trellis.config` (default `.githooks`) names the folder of the git hooks of a project that keeps them elsewhere: `setup` sets `core.hooksPath` to it and `doctor` checks it.

## The barriers and their limits

- **Consumer CI**: the real barrier, where the GitHub plan allows requiring checks. In a private repository on a plan without required checks it is advisory: nothing prevents merging with a red check. What is left is `guard-git` and the `deny` for Claude, the git hooks for the clone, and the person who does not merge on red. `trellis doctor` cannot know which plan the repository has.
- **Consumer CI and the visibility of trellis**: the consumer workflow clones trellis at the pinned sha with no credentials, so its repository has to be reachable anonymously: public, and with a public repository nothing else is configured. A private fork needs its own adaptation, which this repository does not build: its Actions access level set so that the project's repositories can call the reusable workflow, plus a token for the clone of trellis (a secret of every consumer).
- **The copy**: the deny `Edit(/.trellis/**)` stops the tools that edit a file. A Bash command that writes in `.trellis/` is not seen by it, so a session may edit the copy of its own guard that way; the pre-commit hook and the consumer check refuse the result. A `.trellis/hooks/guard-git.sh` that is not there is a hook error, which does not block the command: `doctor` and `verify` report it.
- **Git hooks**: a convenience, not a barrier. A clone without Claude and without `init` lacks them until someone runs `trellis setup`; the `SessionStart` hook of the copy runs it in every session. The aggregate limits (the total of the rules) run only in CI: they are a budget shared between branches.
- **Push without a refspec**: the `deny` of `settings.json` covers the forms a permission rule can express (`main`, `+main`, `refs/heads/main`, `HEAD:main`, with or without `-C`), but not a bare `git push` on a protected branch: no pattern stops it without stopping every push. There the guard is `guard-git`, which judges the current branch and its upstream; where the hooks do not run, the method asks for an explicit refspec.
- **Directory of the command**: `guard-git` judges a push or a merge with the `trellis.config` of the directory the command runs in, after its `cd` or `git -C`. It expands what needs no execution: quotes, `~`, and the variables the same command assigns literally. A variable counts only when its assignment surely ran and lasts: one after `&&`, `||` or a pipe (or on the left of one), from a command, appended with `+=`, or set by `read`, `printf -v`, `for`, `export`, `declare`, `local`, `typeset`, `readonly` or `unset` is unresolved, and so is `~` with `HOME` unset or empty. A directory that needs the shell (`~user`, `cd -`, `$(...)`, an unresolved variable, a variable set in an earlier call) is read as the session's own. A `cd` that may not run (after `&&` or `||`), or does not last (on a side of a pipe, in the background, in a subshell), adds a directory the shell may stand in without taking the others away. When the directory a push or a merge runs in has no `trellis.config`, the config of every directory the command visited with `cd` and of the session's judges it, and the strictest answer wins. With no `trellis.config` anywhere there is no opinion, and a push is left to the `deny` of `settings.json`, a merge to nothing; except that a merge naming another repository (`-R`, `GH_REPO`) is denied then, because gh reaches it without any directory.
- **What the hook cannot judge**: parsing the shell completely is not a goal, so `guard-git` fails closed instead. A command that has `push` next to the name of a protected branch (as a word, after the quotes are removed, also as the default of `${B:-main}`, in any directory the command visited or that `GIT_DIR`, `--git-dir` or `env -C` names), or that holds `gh` and `merge`, is denied unless every git and gh invocation in it was judged: the directory and every refspec resolved (a glob or a brace list is not), no wrapper (`env`, `command`, `sh -c`, `bash -lc`, `eval`, `xargs`, an absolute path to git), no `GIT_DIR`, `GIT_WORK_TREE`, `--git-dir` or `GH_REPO`, no `git -c` on a push, no command held in a variable. The bodies of `$(...)`, backticks and `<(...)` are read as a group and judged before the command that holds them, and `$(git branch --show-current)` counts as `HEAD`. `git push --all`, `--mirror`, `--branches`, the refspec `:` and any refspec with `*` are denied outright. The deny names the part it could not judge, and the price is that an unusual form of push or merge is denied rather than parsed: the session writes the command plainly, one invocation per command. The shell may stand in at most 8 directories at once and the command visits at most 8; past that it is not judged, so a chain of `cd` cannot slow the hook down. Operators (`; & | && || ( ) { }`, newline) and redirections (`main>/dev/null`) are read in the same quote-aware pass as the words, so `git push -o 'x;y' origin main` is one push.
- **Accepted limits of the backstop**: an alias in the git configuration files (`git p origin main`), `git -c push.default=matching push` (a push with no protected name in the command), an alias of `gh` (`gh alias`, or one of the shell), `curl` with a token, `source` of a script that pushes, and a script written and then run (`cat > p.sh`, `bash p.sh`) do not show in the command what they write, so the hook does not see them; the `deny` of `settings.json` and the branch protection of the host are the barriers there. `merge-upstream`, `branches/<b>/rename`, `branches/<b>/protection`, rulesets and `pulls/<n>/update-branch` (and its mutation, `updatePullRequestBranch`) by `gh api` are not judged.
- **Merge**: only `guard-git` judges the base of a pull request. A `deny` of `gh pr merge` would block every merge or none, because a permission rule does not see the base and a `deny` beats every `allow`. Where the hooks do not run, the merge has no guard. `guard-git` sees the Bash tool only, so `trellis sync` denies the GitHub MCP tools of a cloud session that merge, switch on auto-merge or write files in a branch (`mcp__github__` `merge_pull_request`, `enable_pr_auto_merge`, `push_files`, `create_or_update_file` and `delete_file`, as the tool list of such a session spells them): a server under another name, and a tool added to it later, are not seen. Opening a pull request, commenting and marking it ready stay allowed.
- **Which GitHub account is asked**: the account `gh` has active is not always the one that sees the repository. `guard-git` (the base of a merge, the state of the issue of a branch switch), `trellis worktree prune` (the merged pull request of a branch) and `trellis issue` (the issue, its dependencies, the issue and label it creates, and the pull request and issues it closes) ask GitHub as the account of the repository's owner when `gh auth token -h github.com -u <owner>` answers a token, through `gh api` (the REST interface: GraphQL, which `gh issue view` and `gh pr view` use, is refused in a cloud session), and give it to that one `gh` call only: the token is never printed, written or exported, and every call is a read except the writes of `trellis issue create` (the issue and its label), of `trellis issue claim` (the assignment, and the label `stopped` taken off), of `trellis issue stop` (the label and its comment), of `trellis issue follow-up` (the issue and its label) and of `trellis issue close` (the label, the comment and the state of the issue). The repository and its owner are those of `-R`/`--repo`, of the URL that names the pull request, or of the `origin` remote (https, `git@` or `ssh://`); for a merge, of the remote `gh` merges in when there are more (`gh repo set-default`, `upstream`). With no owner (another host, no origin, an origin that does not parse, or an ssh host alias such as `git@github-work:owner/repo`, which is common with two accounts), an owner that is not signed in, or `GH_TOKEN`, `GITHUB_TOKEN`, `GH_HOST` or `GH_REPO` already set, `gh` runs as it would without the hook. When the owner is an organisation there is no account of that name, so the active account is asked. A failure is named: the merge `deny` says which account was asked and what `gh` answered, the hook says in a message that the state of an issue could not be read, and `prune` keeps the worktree and says GitHub could not be asked. The `gh` commands the session itself writes are not touched and run as the active account: a `GH_TOKEN=$(gh auth token -u <owner>)` prefix on them is still the way to choose one, and Claude Code asks permission for that form unless a person allows it in `.claude/settings.local.json`.
- **Issue plan**: `trellis issue check` is a check a session runs, not a barrier: `gh issue create` without the mould and work started on an issue that fails are not prevented. At `<n>`, only what an owner, a member or a collaborator wrote counts: a comment of anyone else amends nothing, and the body of anyone else is not a plan, which the check says, so the plan of an issue opened from outside is the one its amendments carry. The check sees the form (sections, sources, paths of the integration branch, the gates those paths match, closed dependencies), not whether a plan was approved or whether the identifiers it names exist. It fetches the integration branch first; offline it says so and judges by the last fetch. Other text of a `Depends on` line is printed for a person, and does not fail.
- **Close of a merge**: `consumer-closed.yml` runs on the pull request of a branch of the repository; one of a fork has a read-only token and is skipped, and `trellis issue close <pr>` closes its issue by hand. It reads the body as it is when it runs. Closing keywords are read as GitHub reads them (`Closes`, `Fixes`, `Resolves` and their forms, one per reference), outside code and comments, and only for issues of the same repository. An issue is closed whatever is pending: the label and the comment are what remains. The comment is written once per pull request and issue, its first line being the mark, which counts when an owner, a member, a collaborator or the workflow wrote it. Two merged pull requests of the same issue share the label, so `--done` of one takes it off for both.
- **Plan check**: `plan-check` is a check a session runs, not a barrier: nothing prevents `gh pr ready` without it. Its runs vary, so the session verifies each finding against the code. It costs one subagent of the sonnet model per pull request.
- **Secret scanner**: an external tool chosen in `init` (gitleaks by default). With none configured, `doctor` warns; configured and missing, FAIL.

## `trellis doctor`

Read-only: it never writes or fetches. It exits 1 when there is any FAIL.

- **FAIL**: a `trellis.config` key outside the schema, a value outside the accepted ones of an enum key of `lib/schema` (`project.locale`, `autonomy.level`, `tracker.kind`, `workspace.kind`, `rung.*.agent`, `rung.*.pr`), `workspace.kind = other` without `[hygiene] namedExt` (the extensions to declare for a stack beyond flutter, dart and node), a command name without `[command "<name>"] run`, or a `trellis.config` that does not parse (the doctor reports it and goes on diagnosing; the other subcommands stop on it); a tool of `[toolchain] require` missing or older than its minimum; `core.hooksPath` unset or other than `git.hooksPath`; a copy that `trellis verify` does not pass or, without a copy and out of the repository of trellis, the plugin not installed; Claude Code below 2.1.330; node missing with hooks active; `ANTHROPIC_API_KEY` exported (the subscription stops being used and every token is billed as API usage, silently); a branch that is not the integration branch, the release branch or an issue branch; a configured `[command] secretScan` whose scanner is missing; a file of `[toolchain] envFile` missing (presence only, it is never read).
- **Warning**: a rung with `pr = true` that no file under `.github/workflows/` runs (it must contain the command's `run` text, or its `ci` text when set, as a plain substring search: a folded `run: >-`, a YAML comment or a commented-out step is misjudged and `npm test` is found inside `pnpm test`, so it is a hint and not a YAML parser: `pr = true` means the project's own CI runs the rung on every pull request, because the consumer workflow never runs rungs and does not install a stack's toolchain), a `.github/workflows/trellis.yml` that does not name `consumer-closed.yml` with `tracker.kind = github`, the plugin enabled in a project with a copy, the repository of trellis judged by the code of another checkout, no secret scanner configured, uncommitted changes, unpushed commits, worktrees of branches that are not on origin.
- **Info**: what the release is waiting for.

## What the framework does not do, and why

- **Executor subagents that reread the repository.** A subagent starts without the session's context and rebuilds it by reading, which costs quota every time. Two checks use one each, `plan-reviewer` in Base and `plan-check` in Cycle, because a clean context is exactly what they need.
- **Status comments on issues.** The state of a piece of work lives in its branch, its commits and its pull request; a status comment is a second copy that goes stale. The one exception is the actions a merge leaves pending: once the branch is gone nothing else holds them, so `trellis issue close` writes them once on the issue, and the label says whether they are still pending.
- **Reconciliation at session start.** Rereading all the state at startup pays in every session for what few of them need. State is reread from its source when it is used.
- **Closing rituals.** A fixed step at the end gets skipped when it adds nothing. `retro` proposes a lesson only when there is one, and a person applies it.

## This repository

It has no copy: it runs from its own tree, in each of its worktrees. It is recognized by `.claude-plugin/plugin.json` with the name `trellis` and `lib/find-trellis.sh` at the top level.

- `bin/trellis sync` writes there its own skills and agents, `.claude/skills/trellis-<name>/SKILL.md` and `.claude/agents/trellis-<name>.md`, with the names and the bytes a copy has them with, and removes the ones with no source. The hygiene fails when one is missing, differs or is left over.
- `sync` and `hygiene` of another checkout (the one of the main checkout, on the PATH of a session that moved to a worktree) refuse: they would write and judge the worktree by other code. The command is `bin/trellis`.
- The git hooks look for `bin/trellis` of their top level, so the ones of a worktree run its code, and `trellis setup` puts that `bin/` on the PATH of the session.
- `trellis doctor` says it runs from its tree, and asks for no plugin.
- `.github/workflows/trellis.yml` runs the hygiene, `pr-check`, the ratchet and the secret scan of the branch on its pull requests, with read permission, and closes the issue of a merged one.

## Development

```sh
./test.sh          # every suite; `./test.sh shell` or `./test.sh node` for one kind
bin/trellis check  # the same, as the pull request needs it
```

The scripts run with bash 3.2 (the macOS one): no `mapfile`, no associative arrays, and empty arrays under `set -u` are expanded with care. CI runs on ubuntu and macos, and on macos with `/bin/bash`.

## Version

`version` of `.claude-plugin/plugin.json` and a tag per version. A consumer pins the sha, not the tag: `trellis update <tag>` writes the sha the tag names.

## License

MIT, in `LICENSE`.
