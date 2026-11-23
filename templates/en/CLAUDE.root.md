# {{project.name}}

{{One or two sentences: what the project is and who it is for.}}

<!-- trellis:method -->
<!-- /trellis:method -->

## Orientation

The project's instruction files and when each one loads. `trellis sync` writes the table.

<!-- trellis:orientation -->
<!-- /trellis:orientation -->

## Commands

<!-- trellis:commands -->
<!-- /trellis:commands -->

## Gates

<!-- trellis:gates -->
<!-- /trellis:gates -->

## Layout

{{Where each thing lives: one line per top-level folder or package, with what it holds and what it does not. It is the reference for deciding the home of a new file.}}

## Anti-duplication in this project

{{The canonical definitions most often duplicated here (for example: date format, HTTP client, visual theme) and the file where each one lives.}}

## Conventions

{{The conventions lint does not enforce: names, the structure of a module, error handling, visible text.}}

## Never

- Never commit on the release branch or the integration branch.
- Never push without an explicit refspec.
- Never run a test rung that `TESTING.md` marks as not runnable by Claude.
{{What is irreversible in this project, one line each: production migrations, messages to users, payments.}}

## Before calling it done

- [ ] `trellis check` green.
- [ ] `trellis hygiene` green if the change touches instructions.
- [ ] New tests per the map of `TESTING.md`, seen failing before passing.
- [ ] Commit on the issue's branch, push with an explicit refspec, pull request with **Summary** and **Verification**.
