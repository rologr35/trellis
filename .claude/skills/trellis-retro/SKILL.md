---
name: trellis-retro
description: When a piece of work closes, proposes in the chat the lesson it leaves and where it goes, or "no change" when there is no lesson. A person applies it.
disable-model-invocation: true
---

# retro

The proposal and any text for the project are written in the project's language (`trellis config get project.locale`); a lesson for the framework is written in English.

## 1. Is there a lesson?

A lesson is something the next session would get wrong without it: a repeated mistake, an instruction that was missing or confused, an expensive step that can be avoided. If there is none, the answer is "no change" and nothing more.

## 2. The cheapest piece that holds it

In this order, and the first one that is enough:

1. Bounded output of a tool (a flag, a filter).
2. A script.
3. A skill.
4. A hook, only with repeated evidence.
5. Short text in an instruction file, at the end, replacing before adding.

One change per metric at a time, so its effect can be attributed.

## 3. Local or framework

- **Local**: it holds for this project. Destination: the `CLAUDE.md` or the rule closest to the code it speaks about, at the height of the concept.
- **Framework**: it holds for any project (the method, a guard, the hygiene, a template). It is not written in the project: it would change only here and the others would not receive it.

## 4. Propose

In the chat: the lesson in one sentence, the incident that shows it (what happened, where it is recorded), its classification and the proposed text or change with its exact destination. Claude does not apply it: a person decides.

A framework lesson goes through `trellis lesson --title <t> --body-file <file> --search '<concept>'`, whose body has `Kind: defect` or `Kind: rule`, **Incident** and **What must stop happening**. It prints what the search finds, the text and its digest, and publishes nothing. `--approved <digest>` is added when a person has read that text; `--issue <n>` when the search found it. The project receives it with `trellis update`.
