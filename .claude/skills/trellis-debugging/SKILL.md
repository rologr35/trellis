---
name: trellis-debugging
description: Method for a failure, a red test or unexpected behavior. Root cause before the fix, one hypothesis at a time, a regression test seen red and green.
---

# debugging

## 1. Reproduce

The failure is reproduced before it is explained: the exact command, input and output. A failure that does not reproduce is described as such, with what was tried, and is not "fixed".

## 2. One hypothesis at a time

- Each hypothesis is written in one sentence and checked against its record before acting on it: the logs, the transcripts of other sessions (`~/.claude/projects/**/*.jsonl`), the git history (`git log -S`, `git blame`), the real configuration.
- A hypothesis a cheap query can check is checked; it is not reasoned about.
- When a hypothesis is discarded, the reason is said, and the next one follows. Two hypotheses at once produce a fix nobody understands.

## 3. Root cause

The fix goes to the cause, not the symptom. If the cause is somewhere the change must not touch (another package, an external service, a gate), it is said and proposed, without patching around it.

## 4. Regression test

The test that shows the failure is written before the fix and seen red; with the fix it is seen green. It goes to the rung the map of `TESTING.md` points to.

## 5. Escalate

After three failed attempts on the same hypothesis, or if the failure depends on something only a person can see or decide, Claude stops and presents what was checked, what was discarded and what is missing, instead of trying further.
