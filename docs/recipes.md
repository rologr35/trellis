# Recipes

What trellis does not do and a project may. Each one is built in the project, with its own tools; none is installed by trellis nor checked by it. Each says what it costs and what it does not prove.

## Another tracker in front of the issues

The team plans in a tracker of its own, and the issues of the repository hold the work a session takes. The item of the tracker holds the need, in the words of who asks; when it is approved, its plan is written as an issue with the mould, and the item keeps the link to it. Only one direction is automated: the merge closes the issue, and a workflow of the project, on an issue that closes, moves the item. A check of the project (`command.issueCheck`) refuses a plan that does not name its item, when the team wants that.

- Costs: the credential of the tracker in CI, a workflow to maintain, and a second place to look. Two directions cost more: each edit has to say which side wins.
- Does not prove: that the item and the issue say the same. The plan in force is the one of the issue; what is edited in the tracker after it was written changes nothing.

## A weekly review of errors

Once a week a scheduled run reads the errors of production grouped by cause, takes the few with more affected users, and searches the backlog for each one. What is known gets its new count as a comment; what is new is proposed as an issue without a plan, with the trace and the query that counts it. A person decides which ones are opened.

- Costs: one run a week, its share of the quota, and a credential that reads the error service and nothing else. Without the search first, it opens the same error every week.
- Does not prove: that what is not reported does not happen. An error that is caught and logged nowhere has no count, and a low count may be a broken report. The text of an error can carry personal data: it is summarised, not pasted.

## Untranslated texts as a ratchet

A script counts the texts a person sees that do not go through the translations, by file, and compares with a committed baseline. A number that rises fails, one that falls is written in the same change. The count runs in CI as a command of `check`, and the baseline is watched as any other list of exceptions.

- Costs: the script that tells a visible text from an identifier, with its false positives, and a line of the baseline in each change that moves texts between files.
- Does not prove: that a translation is right, nor that it fits in its place. A text that is built from parts is not seen by a search of literals.

## A preview per branch

Each pull request gets an address of its own with the branch deployed against data that is not production's, and the address is written in the pull request by the deploy. It is torn down when the pull request closes, by the same workflow, and a scheduled run removes what a failed close left.

- Costs: the deploy of each push, an environment for each open pull request, and data for it: a fixture that every migration keeps valid, or a copy with the personal data removed.
- Does not prove: that the migration is safe on the data of production, nor the load, nor what depends on a fixed address (a callback, a certificate, an allowed origin). A green preview is not a test: a person looks at it.

## CI by cost

The checks of a pull request are ordered by what they cost, and the expensive ones run only for what the change touches: formatting and types first, the units of the packages that changed and of the ones that depend on them, then what needs a device, a browser or a database. The whole suite runs on the integration branch and before a release. The rule that says what a path runs is one file, with a test of its own.

- Costs: that file, which has to be right, and the run that catches up on the integration branch. A required check that is skipped has to report as passed, or nothing merges.
- Does not prove: what the rule left out. Two pull requests that are green apart can be red together, and only the run on the integration branch says so. A path with no rule runs everything.

## Gates of migrations

A `[gate]` on the folder of migrations makes a plan that touches it name the gate, and a run without a person does not take it. The check of the project then reads the migration: it refuses the forms that lock a table or lose data, a backfill in the same step as the change of the schema, and a file that was already applied. Before the merge, the migration runs on a copy of the structure, up and down; what it leaves for after the deploy goes in **After merging**.

- Costs: a copy of the structure in CI, and a person for each migration. The list of forms that are refused is of one engine and one version of it.
- Does not prove: how long it takes on the real data, nor that the code of the previous version works with the new schema while both run. That is read in the plan, in the order of the steps.
