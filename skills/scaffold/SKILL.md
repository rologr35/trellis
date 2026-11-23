---
name: scaffold
description: Writes a CLAUDE.md per workspace package, with its layers and commands deduced from the code, for a person to review.
disable-model-invocation: true
---

# scaffold

One `CLAUDE.md` for each `workspace.package` of `trellis.config` that lacks one, from the plugin's `CLAUDE.package.md` template of the project's language (`$(cd "$(dirname "$(command -v trellis)")/.." && pwd)/templates/<locale>/`, where `<locale>` is `trellis config get project.locale`). The draft is written in that language. A package that already has one is not touched.

## What is deduced and from where

- **What the package does**: its manifest (`pubspec.yaml`, `package.json`), its entry point and its internal dependencies.
- **Layers**: the top-level folders under its source code and the direction of their imports. A layer is a folder that imports from others but not the other way around; if the imports show no direction, the draft says so instead of inventing one.
- **Commands**: the manifest's scripts and the CI ones that run in that folder, with what each one does. The ones already in `trellis check` are not repeated.
- **Rules**: the rules of `.claude/rules/` whose `paths:` cover files of the package.

## Limits

- Present tense and third person, without history or references to issues: the hygiene checks it.
- Short: it is the package's index, not its manual. The detail of a domain goes to a rule with `paths:`.
- What could not be deduced stays as an explicit question in the draft.

When done, `trellis sync` (the orientation table lists them) and `trellis hygiene`. The summary names every file written and asks a person to review it.
