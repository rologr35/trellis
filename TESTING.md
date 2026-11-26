# Testing

The project's test rungs, from the cheapest to the most expensive. `bin/trellis sync` writes the table from the `[rung]` sections of `trellis.config`; a "no" in the "Claude runs it" column becomes a `deny` in `.claude/settings.json`.

<!-- trellis:rungs -->
| Rung | Command | Claude runs it | On every PR | Proves | Off until |
|---|---|---|---|---|---|
| unit | `./test.sh` | yes | yes | Each script and each check of the hygiene, on repositories of their own, against no network. |  |
<!-- /trellis:rungs -->

## Base rules

- Never against production, and never against GitHub: `gh` is a stub on the PATH of the suite.
- A test touches no network that does not belong to it: external services are replaced at the edge. An upstream is a local clone.
- No quarantine for flaky tests: a flaky test is fixed, or deleted with the code it covers.
- Coverage is honest: a test that cannot fail does not count. A mutation of the guard it covers turns it red.
- Every new test is seen failing before it is seen passing.
- The tests of a rung that no pull request runs at least compile or are analyzed in the pull request's rung, and the pull request body says which rung is left waiting.

## Rungs

### unit

- What it proves: each script and each check of the hygiene, by what it prints, writes and exits with, on repositories made for the case in a temporary folder, with a `HOME` and a git identity of their own.
- What it does not prove: what GitHub answers, what Claude Code does with a hook or a setting, and that the copy of a real project passes. CI runs it on ubuntu and on macOS with `/bin/bash` 3.2.
- When a new test goes here: always, it is the only rung. `./test.sh` runs every suite, `./test.sh shell` and `./test.sh node` the ones of each kind, and `/bin/bash <suite>` one of them.

## Where does a new test go?

- A script of `scripts/`: the `*.test.sh` of its name; one that judges a branch or an issue, the suite of the subcommand.
- A function of `lib/`: the suite of the script that calls it; the reading of the config has its own.
- A check of the hygiene: `hygiene/hygiene.test.mjs`. What depends on the language: `hygiene/locale.test.mjs`.
- The guard of Claude Code: `hooks/guard-git.test.sh`. The hooks of a session without a person: `hooks/unattended.test.sh` and `hooks/waiting.test.sh`. A git hook, and which trellis it finds: `hooks/githooks.test.sh`.
- A job of `.github/workflows/`: its text, in the suite of the script it runs.
- A refusal of a private name: `scripts/private-names.test.sh`, with a list of the case. No suite reads the one of the machine.
