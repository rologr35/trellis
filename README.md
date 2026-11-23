# trellis

A replicable agentic harness for Claude Code: the always-loaded working method, git guards, hygiene of the instruction files, ratchets and project templates. This repository is both the plugin and its marketplace.

Base, the module of this repository, needs only git and node. The Cycle (issues, labels, review against the plan) and Autonomy (cloud routines, dispatcher, budget) modules are built on top of it.

## Install in a project

1. Claude Code 2.1.324 or later (the marketplace pinned by sha needs it).
2. In the project: `/plugin marketplace add rologr35/trellis` and `/plugin install trellis@trellis`. `enabledPlugins` in `settings.json` enables an installed plugin, it does not install it.
3. `/trellis:init`: an interview, then it writes the configuration and the templates, and ends with `trellis sync`, `trellis hygiene --freeze` and `trellis doctor`.

`init` pins the marketplace in `.claude/settings.json` with the plugin's full sha and `autoUpdate: false`, and the CI workflow with the same sha. Updating the plugin is changing that sha in both places, in a pull request of its own.

## Language

The plugin is written in English. What it writes into a project follows `project.locale`, `en` (the default) or `es`, the first question of `init`:

- the method block, from `method/en.md` or `method/es.md`;
- the templates, from `templates/en/` or `templates/es/`: `CLAUDE.root.md`, `CLAUDE.package.md`, `rule.md`, `SKILL.md`, `TESTING.md` and the comments of `trellis.config`; the language-neutral ones (`settings.json`, `githooks/`, `gitignore.fragment`, `workflows/`) stay in `templates/`;
- the generated blocks (`method`, `orientation`, `commands`, `gates`, `rungs`), whose labels live in `lib/blocks.mjs`;
- the pull request sections `pr-check` requires, defined in `lib/locale.mjs`: **Summary**, **Verification** and **Setback** in en; **Resumen**, **Verificación** and **Retroceso** in es;
- the narrative phrases the hygiene checks: the list of the project's locale, and always the en one, because code comments are English.

Each prose template is a file per locale rather than one file with per-locale strings: a template is mostly prose, and a file per locale keeps it readable as the text it produces. The tests keep the copies aligned: each principle of the method carries an id (`<!-- p:<id> -->`, stripped from the generated block) and both methods carry the same ids in the same order; both template folders hold the same files with the same blocks, the same `trellis.config` keys and the same placeholder names (`{{name}}`, `{{package}}` and the rest are the English ones in both; only the text around them and the free-text prompts are translated); and a project written from each locale's templates passes the hygiene.

## What is there

| Piece | Where | What it does |
|---|---|---|
| Method | `method/<locale>.md` | How Claude works, on every turn. `trellis sync` copies it into the `<!-- trellis:method -->` block of the root `CLAUDE.md`, and the hygiene checks that it matches: a skill loads only when invoked, the method is needed always. |
| CLI | `bin/trellis` | `config`, `doctor`, `sync`, `hygiene`, `setup`, `worktree add\|prune`, `ratchet`, `pr-check`, `check`. |
| Configuration | the project's `trellis.config` | git-config format, read with `git config -f`; `lib/schema` holds the keys and their defaults. |
| Guards | `hooks/guard-git.sh` | Pushes to protected branches, branch switches in the main checkout, issues without a prior search, merges outside the allowed bases. |
| Git hooks | `templates/githooks/` | Ratchet, hygiene, commit message and branch name, in the clone. |
| Consumer CI | `.github/workflows/consumer-check.yml` | Hygiene, ratchet, `pr-check` and the secret scanner on every pull request. |
| Skills | `skills/` | `init`, `scaffold`, `debugging`, `retro`. |
| Agent | `agents/plan-reviewer.md` | Checks a plan against the repository, in a clean context. |

## Where each thing runs

- The plugin's `bin/` joins the PATH of Claude's Bash tool, not a person's shell nor the hooks. A person or a git hook calls `trellis` by its path: `lib/find-trellis.sh` looks for it on the PATH and then in the `installPath` of `~/.claude/plugins/installed_plugins.json`, because the cache path changes with every version.
- The plugin's hooks use `${CLAUDE_PLUGIN_ROOT}` and need node. Without node, `guard-git` has no opinion and `trellis doctor` gives a FAIL. The native `claude` binary does not bring node.
- A plugin does not contribute `permissions`: the `deny` lives in the project's `settings.json`, and `trellis sync` generates it.
- A session hosted in the cloud reads the project's `settings.json` but does not add the marketplaces of `extraKnownMarketplaces`, so the plugin's hooks may not run there. That is why the push `deny` is in `settings.json` as well as in `guard-git`.

## The barriers and their limits

- **Consumer CI**: the real barrier, where the GitHub plan allows requiring checks. In a private repository on a plan without required checks it is advisory: nothing prevents merging with a red check. What is left is `guard-git` and the `deny` for Claude, the git hooks for the clone, and the person who does not merge on red. `trellis doctor` cannot know which plan the repository has.
- **Git hooks**: a convenience, not a barrier. A clone without Claude and without `init` lacks them until someone runs `trellis setup`; the plugin's `SessionStart` hook runs it in every session, in the cloud too. The aggregate limits (the total of the rules) run only in CI: they are a budget shared between branches.
- **Push without a refspec**: the `deny` of `settings.json` covers the forms a permission rule can express (`main`, `+main`, `refs/heads/main`, `HEAD:main`, with or without `-C`), but not a bare `git push` on a protected branch: no pattern stops it without stopping every push. There the guard is `guard-git`, which judges the current branch and its upstream; where the plugin does not load, the method asks for an explicit refspec.
- **Directory of the command**: `guard-git` judges a push or a merge with the `trellis.config` of the directory the command runs in, after its `cd` or `git -C`. It expands what needs no execution: quotes, `~`, and the variables the same command assigns literally. A directory that needs the shell (`~user`, `cd -`, `$(...)`, a variable set in an earlier call) is read as the session's own, so the session's repository config judges it; if the session's directory has no `trellis.config` either, there is no opinion and a push is left to the `deny` of `settings.json`, a merge to nothing.
- **Merge**: only `guard-git` judges the base of a pull request. A `deny` of `gh pr merge` would block every merge or none, because a permission rule does not see the base and a `deny` beats every `allow`. Where the plugin does not load, the merge has no guard; Base launches no cloud sessions.
- **Secret scanner**: an external tool chosen in `init` (gitleaks by default). With none configured, `doctor` warns; configured and missing, FAIL.

## `trellis doctor`

Read-only: it never writes or fetches. It exits 1 when there is any FAIL.

- **FAIL**: a `trellis.config` key outside the schema, a value outside the accepted ones of an enum key of `lib/schema` (`project.locale`, `tracker.kind`, `workspace.kind`, `rung.*.agent`, `rung.*.pr`), `workspace.kind = other` without `[hygiene] namedExt` (the extensions to declare for a stack beyond flutter, dart and node), a command name without `[command "<name>"] run`, or a `trellis.config` that does not parse (the doctor reports it and goes on diagnosing; the other subcommands stop on it); a tool of `[toolchain] require` missing or older than its minimum; `core.hooksPath` unset or other than `.githooks`; the plugin not installed or Claude Code below 2.1.324; node missing with hooks active; `ANTHROPIC_API_KEY` exported (the subscription stops being used and every token is billed as API usage, silently); a branch that is not the integration branch, the release branch or an issue branch; a configured `[command] secretScan` whose scanner is missing; a file of `[toolchain] envFile` missing (presence only, it is never read).
- **Warning**: no secret scanner configured, uncommitted changes, unpushed commits, worktrees of branches that are not on origin.
- **Info**: what the release is waiting for.

## What the framework does not do, and why

- **Executor subagents that reread the repository.** A subagent starts without the session's context and rebuilds it by reading, which costs quota every time. Base uses a single subagent, `plan-reviewer`, because a clean context is exactly what its check needs.
- **Status comments on issues.** The state of a piece of work lives in its branch, its commits and its pull request; a status comment is a second copy that goes stale.
- **Reconciliation at session start.** Rereading all the state at startup pays in every session for what few of them need. State is reread from its source when it is used.
- **Closing rituals.** A fixed step at the end gets skipped when it adds nothing. `retro` proposes a lesson only when there is one, and a person applies it.

## Development

```sh
for t in lib/*.test.sh scripts/*.test.sh hooks/*.test.sh; do /bin/bash "$t" || break; done
node --test hygiene/*.test.mjs
```

The scripts run with bash 3.2 (the macOS one): no `mapfile`, no associative arrays, and empty arrays under `set -u` are expanded with care. CI runs on ubuntu and macos, and on macos with `/bin/bash`.

## Version

`version` of `.claude-plugin/plugin.json` and a tag per version. A consumer pins the sha, not the tag.

## License

MIT, in `LICENSE`.
