#!/usr/bin/env bash
# Exercises scripts/pr-check.sh: style, sections by locale, the setback, the pull request of an issue's
# branch into the integration branch, the commit shape.
. "$(dirname "$0")/../lib/testlib.sh"

repo="$(tl_repo)"
cd "$repo" || exit 1
git switch -q -c 12-thing

body() { printf '%s\n' "$@" > body.md; }
# The sections a cycle pull request carries besides, with nothing to do in them.
EN=('' '**Before merging**' 'none' '' '**After merging**' 'none')
ES=('' '**Antes de mezclar**' 'nada' '' '**Después de mezclar**' 'nada')
commit() { printf '%s\n' "$@" > msg.txt; }
status_of() { "$TRELLIS" pr-check "$@" >out.txt 2>&1; echo $?; }

printf '\nbodies\n'
body 'Closes #12' '' '**Summary**' 'A thing.' '' '**Verification**' '- tests green' "${EN[@]}"
tl_eq 'a good body passes' '0' "$(status_of --body body.md)"
body 'Closes #12' '' '**Summary**' "A thing $(printf '\342\200\224') another." '' '**Verification**' 'ok' "${EN[@]}"
tl_eq 'long dash fails' '1' "$(status_of --body body.md)"
body 'Closes #12' '' '## Summary' 'A thing.' '' '## Verification' 'ok' '' 'Generated with Claude Code' "${EN[@]}"
tl_eq 'attribution fails' '1' "$(status_of --body body.md)"
body 'Closes #12' '' '**Summary**' 'Follow step #3.' '' '**Verification**' 'ok' "${EN[@]}"
tl_eq 'a bare #N fails' '1' "$(status_of --body body.md)"
tl_has 'and is named' 'bare #3' "$(cat out.txt)"
body 'Closes #12' '' '## Summary' 'The `pick` step reads `a`, as in step #3 of `b`.' '' '## Verification' 'ok' "${EN[@]}"
tl_eq 'a bare #N next to code fails' '1' "$(status_of --body body.md)"
tl_has '  and the line is quoted as it is written' '("The `pick` step reads `a`, as in step #3 of `b`.")' "$(cat out.txt)"
body 'Closes #12' '' '## Summary' '```' 'step #4' '```' 'After `x`: step #3.' '' '## Verification' 'ok' "${EN[@]}"
tl_eq 'a bare #N after a fence fails' '1' "$(status_of --body body.md)"
tl_has '  and its own line is quoted' '("After `x`: step #3.")' "$(cat out.txt)"
tl_lacks '  and the one in the fence is not a miss' '#4' "$(cat out.txt)"
body 'Closes #12' '' '**Summary**' 'Refs #3, also `#4` and (#5).' '' '**Verification**' 'ok' "${EN[@]}"
tl_eq 'keyword, backticks and parentheses pass' '0' "$(status_of --body body.md)"
body 'Closes #12' '' '**Summary**' 'A thing.' "${EN[@]}"
tl_eq 'a missing section fails' '1' "$(status_of --body body.md)"
tl_has 'and is named' 'Verification' "$(cat out.txt)"
printf '[project]\n\tlocale = es\n' > trellis.config
body 'Closes #12' '' '**Resumen**' 'Algo.' '' '**Verificación**' 'ok' "${ES[@]}"
tl_eq 'the sections follow project.locale' '0' "$(status_of --body body.md)"
body 'Closes #12' '' '**Summary**' 'A thing.' '' '**Verification**' 'ok' "${EN[@]}"
tl_eq 'the en sections do not count in an es project' '1' "$(status_of --body body.md)"
rm trellis.config

printf '\nsetback\n'
git config branch.12-thing.ratchet-loosened true
body 'Closes #12' '' '**Summary**' 'A thing.' '' '**Verification**' 'ok' "${EN[@]}"
tl_eq 'a loosened branch needs Setback' '1' "$(status_of --body body.md)"
body 'Closes #12' '' '**Summary**' 'A thing.' '' '**Verification**' 'ok' '' '**Setback**' 'none' "${EN[@]}"
tl_eq 'Setback none does not count' '1' "$(status_of --body body.md)"
tl_eq 'has-setback says no' '1' "$(status_of --has-setback --body body.md)"
body 'Closes #12' '' '**Summary**' 'A thing.' '' '**Verification**' 'ok' '' '**Setback**' '- An ignore in main.dart; cost: the warning stays; accepted for the SDK.' "${EN[@]}"
tl_eq 'a written Setback passes' '0' "$(status_of --body body.md)"
tl_eq 'has-setback says yes' '0' "$(status_of --has-setback --body body.md)"
printf '[project]\n\tlocale = es\n' > trellis.config
body 'Closes #12' '' '**Resumen**' 'Algo.' '' '**Verificación**' 'ok' '' '**Retroceso**' 'nada' "${ES[@]}"
tl_eq 'es: Retroceso nada does not count' '1' "$(status_of --body body.md)"
body 'Closes #12' '' '**Resumen**' 'Algo.' '' '**Verificación**' 'ok' '' '**Retroceso**' '- Un ignore en main.dart; coste: el aviso queda; se acepta por el SDK.' "${ES[@]}"
tl_eq 'es: a written Retroceso passes' '0' "$(status_of --body body.md)"
rm trellis.config
git config --unset branch.12-thing.ratchet-loosened

printf '\nthe pull request of an issue\n'
GOOD=('**Summary**' 'A thing.' '' '**Verification**' 'ok')
body 'Closes #12' "${GOOD[@]}" "${EN[@]}"
tl_eq 'none in both sections passes' '0' "$(status_of --body body.md)"
body "${GOOD[@]}" "${EN[@]}"
tl_eq 'a body that closes nothing fails' '1' "$(status_of --body body.md)"
tl_has 'and the closing line is named' 'Closes #12' "$(cat out.txt)"
body 'Closes #13' "${GOOD[@]}" "${EN[@]}"
tl_eq 'a body that closes another issue fails' '1' "$(status_of --body body.md)"
body 'Refs #12' "${GOOD[@]}" "${EN[@]}"
tl_eq 'a reference that does not close fails' '1' "$(status_of --body body.md)"
for closing in 'closes #12' 'Fixes #12' 'This resolved #12.' 'Closes #13, closes #12'; do
  body "$closing" "${GOOD[@]}" "${EN[@]}"
  tl_eq "closing with: $closing" '0' "$(status_of --body body.md)"
done
for not in 'Closes rologr35/x#12' '`Closes #12`' '<!-- Closes #12 -->' 'Encloses #12' 'Closes #120'; do
  body "$not" "${GOOD[@]}" "${EN[@]}"
  tl_eq "not closing with: $not" '1' "$(status_of --body body.md)"
done
body '```' 'Closes #12' '```' "${GOOD[@]}" "${EN[@]}"
tl_eq 'not closing in a code block' '1' "$(status_of --body body.md)"
body 'Closes #12' "${GOOD[@]}" '' '**After merging**' 'none'
tl_eq 'without Before merging fails' '1' "$(status_of --body body.md)"
tl_has 'and it is named' 'missing the section **Before merging**' "$(cat out.txt)"
body 'Closes #12' "${GOOD[@]}" '' '**Before merging**' 'none'
tl_eq 'without After merging fails' '1' "$(status_of --body body.md)"
tl_has 'and it is named' 'missing the section **After merging**' "$(cat out.txt)"
body 'Closes #12' "${GOOD[@]}" '' '**Before merging**' 'none' '' '**After merging**' '<!-- what is left -->'
tl_eq 'a section with only a comment fails' '1' "$(status_of --body body.md)"
body 'Closes #12' "${GOOD[@]}" '' '**Before merging**' 'none' '' '```' '**After merging**' '- tag it' '```'
tl_eq 'a section in a code block is not one' '1' "$(status_of --body body.md)"
body 'Closes #12' "${GOOD[@]}" '' '## Before merging' '' '- [ ] Approve it.' '' '## After merging' '' '1. Tag it.' '   With the version.' '2. Announce it.'
tl_eq 'headings and lists pass' '0' "$(status_of --body body.md)"
body 'Closes #12' "${GOOD[@]}" '' '**Before merging**: none' '' '**After merging:** None.'
tl_eq 'none after the label passes' '0' "$(status_of --body body.md)"
body 'Closes #12' "${GOOD[@]}" '' '**Before merging**' '- none' '' '**After merging**' '- Tag it.'
tl_eq 'none as an item passes' '0' "$(status_of --body body.md)"
body 'Closes #12' "${GOOD[@]}" '' '**Before merging**' 'none' '' '**After merging**' 'Tag it.'
tl_eq 'prose is neither none nor a list' '1' "$(status_of --body body.md)"
tl_has 'and it says so' '**After merging** is `none` or a list' "$(cat out.txt)"
body 'Closes #12' "${GOOD[@]}" '' '**Before merging**' 'none' '' '**After merging**' '-'
tl_eq 'an empty item is not a list' '1' "$(status_of --body body.md)"
body 'Closes #12' "${GOOD[@]}" "${EN[@]}"
sed "s/\$/$(printf '\r')/" body.md > crlf.md
tl_eq 'the line ends of the web editor pass' '0' "$(status_of --body crlf.md)"
printf '[project]\n\tlocale = es\n' > trellis.config
body 'Closes #12' '**Resumen**' 'Algo.' '' '**Verificación**' 'ok' '' '## Antes de mezclar' 'nada' '' '## Después de mezclar' '- Poner el tag.'
tl_eq 'es: the names of the locale pass' '0' "$(status_of --body body.md)"
body 'Closes #12' '**Resumen**' 'Algo.' '' '**Verificación**' 'ok' "${EN[@]}"
tl_eq 'es: the en names do not count' '1' "$(status_of --body body.md)"
tl_has 'es: and the missing one is named' '**Después de mezclar**' "$(cat out.txt)"
body 'Closes #12' '**Resumen**' 'Algo.' '' '**Verificación**' 'ok' '' '**Antes de mezclar**' 'none' '' '**Después de mezclar**' 'nada'
tl_eq 'es: none is not nada' '1' "$(status_of --body body.md)"
tl_has 'es: and it says so' '**Antes de mezclar** is `nada` or a list' "$(cat out.txt)"
printf '[tracker]\n\tkind = none\n' > trellis.config
body "${GOOD[@]}"
tl_eq 'without a tracker it is judged as any other' '0' "$(status_of --body body.md)"
rm trellis.config

printf '\nthe sections and the actions of a project\n'
git config -f trellis.config --add pr.section 'Why (and for whom)'
git config -f trellis.config --add pr.section 'How it was seen'
body 'Closes #12' "${GOOD[@]}" "${EN[@]}"
tl_eq 'with pr.section the ones of the locale are not enough' '1' "$(status_of --body body.md)"
tl_has '  and each one that is missing is named' 'missing the section **How it was seen**' "$(cat out.txt)"
tl_has '  a name is not a pattern' 'missing the section **Why (and for whom)**' "$(cat out.txt)"
body 'Closes #12' '## Why (and for whom)' 'A thing.' '' '**How it was seen**: in the suite.' "${EN[@]}"
tl_eq 'the sections of the project pass, without the ones of the locale' '0' "$(status_of --body body.md)"
body 'Closes #12' '## Why (and for whom)' '' '## How it was seen' 'ok' "${EN[@]}"
tl_eq 'an empty one fails' '1' "$(status_of --body body.md)"
body 'Closes #12' '## Why (and for whom)' 'A thing.' '' '## How it was seen' 'ok' '' '**Before merging**' 'none'
tl_eq 'After merging stays of trellis' '1' "$(status_of --body body.md)"
git config branch.12-thing.ratchet-loosened true
body 'Closes #12' '## Why (and for whom)' 'A thing.' '' '## How it was seen' 'ok' "${EN[@]}"
tl_eq 'and so does Setback' '1' "$(status_of --body body.md)"
git config --unset branch.12-thing.ratchet-loosened
rm trellis.config
git config -f trellis.config --add pr.action 'Migrate'
git config -f trellis.config --add pr.action 'make deploy'
# acts <line>...: the exit of a body with those lines in After merging.
acts() { body 'Closes #12' "${GOOD[@]}" '' '**Before merging**' 'none' '' '**After merging**' '' "$@"; status_of --body body.md; }
tl_eq 'none is not an action' '0' "$(acts none)"
tl_eq 'nor is it as an item' '0' "$(acts '- none')"
tl_eq 'an item of each action' '0' "$(acts '- Migrate the store.' '* `make deploy` from main' '+ [ ] Migrate again' '1. [x] `make deploy`')"
tl_eq 'an item of no action fails' '1' "$(acts '- Migrate the store.' '- Tag it.')"
tl_has '  and is quoted with the actions' '**After merging**: "Tag it." does not start with one of the actions: Migrate, make deploy' "$(cat out.txt)"
tl_eq 'one with none beside it fails' '1' "$(acts '- none' '- Tag it.')"
tl_eq 'the action inside an item does not count' '1' "$(acts '- First, Migrate.')"
tl_eq 'an item inside another, and the text of one, are not judged' '0' "$(acts '- Migrate the store.' '  - with the key' '  and then look.')"
tl_eq 'nor is one in a fence' '0' "$(acts '- Migrate the store:' '  ```' '- not an item' '  ```')"
tl_eq 'an item one space to the right is beside the one before' '1' "$(acts '- Migrate the store.' ' - Tag it.')"
tl_eq 'an item in parentheses' '1' "$(acts '1) Tag it.')"
body 'Closes #12' "${GOOD[@]}" '' '## Before merging' '- [ ] Ask.' '' '## After merging' 'none'
tl_eq 'Before merging is judged too' '1' "$(status_of --body body.md)"
rm trellis.config
tl_eq 'without pr.action any item passes' '0' "$(acts '- Tag it.')"

printf '\nbare references\n'
body 'Closes #12' '**Summary**' 'Step #3.' '' '**Verification**' 'ok' "${EN[@]}"
git config -f trellis.config style.bareReference allow
tl_eq 'style.bareReference = allow accepts one in a body' '0' "$(status_of --body body.md)"
commit 'feat: a thing (#12)' '' 'As step #3 says.'
tl_eq 'and in a commit' '0' "$(status_of --commit msg.txt)"
commit 'feat: a thing' '' 'As step #3 says.'
tl_eq 'whose issue stays required' '1' "$(status_of --commit msg.txt)"
commit 'feat: a thing #12'
tl_eq 'in its parentheses' '1' "$(status_of --commit msg.txt)"
body 'Closes #12' '**Summary**' "Step #3 $(printf '\342\200\224') four." '' '**Verification**' 'ok' "${EN[@]}"
tl_eq 'the rest of the style stays' '1' "$(status_of --body body.md)"
commit 'feat: a thing (#12)' '' 'As step #3 says.'
for value in refuse reckless; do
  git config -f trellis.config style.bareReference "$value"
  tl_eq "style.bareReference = $value refuses it" '1' "$(status_of --commit msg.txt)"
done
rm trellis.config
body "${GOOD[@]}"

printf '\na pull request of another shape\n'
# In CI the checkout is detached and the branches come from the environment of the event.
ci_of() { GITHUB_HEAD_REF="$1" GITHUB_BASE_REF="$2" "$TRELLIS" pr-check --body body.md >out.txt 2>&1; echo $?; }
git switch -q --detach
tl_eq 'in CI, an issue branch into the integration branch is asked' '1' "$(ci_of 12-thing develop)"
tl_has 'for what it lacks' 'Closes #12' "$(cat out.txt)"
tl_eq 'in CI, a release is not' '0' "$(ci_of develop main)"
tl_eq 'in CI, a hotfix into main is not' '0' "$(ci_of 12-thing main)"
tl_eq 'in CI, a probe into the integration branch is not' '0' "$(ci_of probe/x develop)"
tl_eq 'detached, without the event, it is not' '0' "$(status_of --body body.md)"
git switch -q -c probe/x
tl_eq 'on a branch that is not of an issue, it is not' '0' "$(status_of --body body.md)"
tl_eq 'in CI, the branch of the event wins over the checkout' '1' "$(ci_of 12-thing develop)"
git config -f trellis.config git.issueBranch '^issue/[0-9]+'
git switch -q -c issue/12
body "${GOOD[@]}" "${EN[@]}"
tl_eq 'a branch shape without a leading number closes some issue' '1' "$(status_of --body body.md)"
body 'Closes #12' "${GOOD[@]}" "${EN[@]}"
tl_eq 'and any one will do' '0' "$(status_of --body body.md)"
rm trellis.config
git switch -q 12-thing

printf '\ncommits\n'
commit 'feat(api): add a thing (#12)' '' 'Body.' '# a comment git strips'
tl_eq 'a good commit passes' '0' "$(status_of --commit msg.txt)"
commit 'add a thing'
tl_eq 'a shapeless subject fails' '1' "$(status_of --commit msg.txt)"
commit 'feat: add a thing (#13)'
tl_eq 'another issue than the branch fails' '1' "$(status_of --commit msg.txt)"
commit 'fix: a thing (#12)' '' 'Co-Authored-By: Someone <a@b.c>'
tl_eq 'attribution fails' '1' "$(status_of --commit msg.txt)"
commit "Merge branch 'x' into 12-thing"
tl_eq 'a merge message is not judged' '0' "$(status_of --commit msg.txt)"
printf '[tracker]\n\tkind = none\n' > trellis.config
commit 'chore(ci): tidy'
tl_eq 'without a tracker no (#n)' '0' "$(status_of --commit msg.txt)"
rm trellis.config

tl_done
