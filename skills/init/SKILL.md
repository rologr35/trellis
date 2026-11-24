---
name: init
description: Puts a project under trellis. Interviews the person and writes trellis.config, the root CLAUDE.md with the method, a CLAUDE.md per package, TESTING.md, .claude/settings.json, the git hooks, the .gitignore, the copy of trellis and the CI workflow.
disable-model-invocation: true
---

# init

The project consumes a copy of trellis that it commits (`.trellis/`); the plugin is installed only to run this skill. The templates live in the plugin: `PLUGIN="$(cd "$(dirname "$(command -v trellis)")/.." && pwd)"`. The prose templates and `trellis.config` are in `$PLUGIN/templates/<locale>/`, one folder per `project.locale` (`en`, `es`); the language-neutral ones (`settings.json`, `githooks/`, `gitignore.fragment`, `workflows/`) are in `$PLUGIN/templates/`.

## 0. A worktree for init

The plugin is installed at the local scope (`claude plugin marketplace add <upstream>@<sha> --scope local`, then `claude plugin install trellis@trellis --scope local`; both write `.claude/settings.local.json`, which git ignores), so the main checkout has no uncommitted change. If it was installed at the project scope instead, `.claude/settings.json` has an uncommitted change there, which would collide with the merge of this branch: before anything else, the person is asked to uninstall it there and to install it at the local scope.

The main checkout stays on the integration branch, clean: as soon as `trellis.config` exists, `guard-git` prevents going back to it from an open issue branch. Since there is no config yet, the worktree is created with plain git, from the main checkout and in simple lines:

1. `<n>` is the issue that asks for adopting trellis; without a tracker, a number the person picks.
2. `printf '.claude/worktrees/\n' >> .git/info/exclude`, so the main checkout does not see the worktree before `.gitignore` says so.
3. `git fetch origin`
4. `git worktree add .claude/worktrees/<n>-trellis-init -b <n>-trellis-init origin/<integration>`
5. `EnterWorktree` with the absolute path of that worktree. Everything that follows is written there.

## 1. Read before asking

Claude deduces from the code all it can and asks only what it cannot: the stack and its version (`pubspec.yaml`, `package.json`, `.tool-versions`), the workspace packages, the branches (`git branch -a`), the remote and whether it is GitHub, the commands that already exist (scripts, Makefile, CI), and whether there is already a `CLAUDE.md`, a `.claude/settings.json` or hooks. What exists is kept and integrated; nothing is overwritten without saying so.

## 2. Interview

One question per topic, with the deduced answer as the default option. The language comes first, because every later question and every file written follow it:

1. **Language**: `en` (the default) or `es` (`project.locale`). It governs everything trellis writes into the project: the method block, the templates, the generated blocks, the narrative phrases the hygiene checks and the pull request sections (`Summary`, `Verification`, `Setback` in en; `Resumen`, `Verificación`, `Retroceso` in es). The interview continues in that language.
2. **Stack and workspace**: `workspace.kind` (flutter, dart, node), the packages (`workspace.package`: one line per package below the root; a single package in the root needs no line, its file is the root `CLAUDE.md`) and the tools with their minimum version (`toolchain.require`).
3. **Branches**: release, integration, the shape of an issue branch and the protected ones.
4. **Tracker**: `github` or `none`. With `github` the method carries the Cycle section: the approved plan of an issue lives in it, written from the mould `$PLUGIN/templates/<locale>/issue.md` (shown to the person here, and not copied into the project) and checked by `trellis issue check`. With `none` that section is left out and `trellis issue` answers that the module is off.
5. **Commands**: analysis, formatting, tests per rung, installing dependencies. For each rung: whether Claude may run it (`agent`), whether it runs on every pull request (`pr`) and what it proves. Explain `pr` when asking: `pr = true` means the project's own CI runs that rung's command on every pull request, in a file under `.github/workflows/`; the trellis workflow never runs rungs, because it does not install a stack's toolchain. Where no such CI exists, the answer is `pr = false` (or the person adds the step), and `trellis doctor` warns while a `pr = true` rung has no workflow naming its command.
6. **What is irreversible**: migrations, messages to users, payments, deploys. Each one becomes a line of the **Never** section of the root `CLAUDE.md` and, if it has its own files, a `[gate]`.
7. **Secret scanner**: gitleaks by default (`gitleaks protect --staged --redact` locally, `gitleaks git --redact` in CI with `ci =`), another one, or none (the doctor warns).
8. **Models**: the project's default `model`, `effortLevel` and `autoCompactWindow`.

## 3. Write

Every file below is written in the chosen language, from `$PLUGIN/templates/<locale>/` where the template is a prose one.

1. `trellis.config` from `trellis.config`, with the answers and `project.locale` set. No `{{...}}` left unfilled; what does not apply is deleted. `trellis config unknown` empty.
2. `CLAUDE.md` from `CLAUDE.root.md`: the layout, the anti-duplication and the conventions deduced from the code, and the **Never** section with what is irreversible. If one existed, its current content is spread over those sections.
3. The `scaffold` skill for a `CLAUDE.md` per package.
4. `TESTING.md` from its template, one section per rung.
5. `.claude/settings.json` from `$PLUGIN/templates/settings.json`, merged with the existing one: `allow` and `deny` are joined, everything else of the person's is kept. It names no plugin: `extraKnownMarketplaces.trellis` and `enabledPlugins."trellis@trellis"` of an earlier version are taken out.
6. `.githooks/` from `$PLUGIN/templates/githooks/`, executable.
7. Each line of `$PLUGIN/templates/gitignore.fragment` that `.gitignore` lacks.
8. The copy: `trellis update <sha>`, with the full sha of the installed plugin (`gitCommitSha` of `trellis@trellis` in `~/.claude/plugins/installed_plugins.json`; the file holds one entry per scope: the one with `scope: "local"` whose `projectPath` is the top level of the main checkout (`git rev-parse --show-toplevel` there), or the `user` one if that is how it was installed). It writes `.trellis/`, `.claude/skills/trellis-*` and `.claude/agents/trellis-*.md`, and ends with `trellis sync`, which writes the hooks of the copy in `.claude/settings.json`. The project's own linters and formatters leave `.trellis/` out, in their own configuration.
9. `.github/workflows/trellis.yml` from `$PLUGIN/templates/workflows/trellis.yml`, with the sha of `.trellis/VERSION`, if the remote is GitHub.

## 4. Close

In this order, with the copy (`.trellis/bin/trellis <command>`): `setup`, `sync`, `hygiene --freeze`, `hygiene`, `verify --upstream` and `doctor`. Whatever is left in FAIL is fixed, or told to the person with its cause. Then a commit on the worktree's branch (`chore(trellis): init (#n)`), the push with an explicit refspec (`git push origin <n>-trellis-init`), `ExitWorktree` with `keep`, and the summary: what was written, what was deduced and what was asked, what is left as a warning, that the package `CLAUDE.md` files wait for human review, and that after the merge the person removes the plugin from the machine: `claude plugin uninstall trellis@trellis --scope local`, and `extraKnownMarketplaces.trellis` out of `.claude/settings.local.json`.
