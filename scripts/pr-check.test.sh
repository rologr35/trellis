#!/usr/bin/env bash
# Exercises scripts/pr-check.sh: style, sections by locale, the setback, the commit shape.
. "$(dirname "$0")/../lib/testlib.sh"

repo="$(tl_repo)"
cd "$repo" || exit 1
git switch -q -c 12-thing

body() { printf '%s\n' "$@" > body.md; }
commit() { printf '%s\n' "$@" > msg.txt; }
status_of() { "$TRELLIS" pr-check "$@" >out.txt 2>&1; echo $?; }

printf '\nbodies\n'
body 'Closes #12' '' '**Summary**' 'A thing.' '' '**Verification**' '- tests green'
tl_eq 'a good body passes' '0' "$(status_of --body body.md)"
body 'Closes #12' '' '**Summary**' "A thing $(printf '\342\200\224') another." '' '**Verification**' 'ok'
tl_eq 'long dash fails' '1' "$(status_of --body body.md)"
body 'Closes #12' '' '## Summary' 'A thing.' '' '## Verification' 'ok' '' 'Generated with Claude Code'
tl_eq 'attribution fails' '1' "$(status_of --body body.md)"
body 'Closes #12' '' '**Summary**' 'Follow step #3.' '' '**Verification**' 'ok'
tl_eq 'a bare #N fails' '1' "$(status_of --body body.md)"
tl_has 'and is named' 'bare #3' "$(cat out.txt)"
body 'Closes #12' '' '**Summary**' 'Refs #3, also `#4` and (#5).' '' '**Verification**' 'ok'
tl_eq 'keyword, backticks and parentheses pass' '0' "$(status_of --body body.md)"
body 'Closes #12' '' '**Summary**' 'A thing.'
tl_eq 'a missing section fails' '1' "$(status_of --body body.md)"
tl_has 'and is named' 'Verification' "$(cat out.txt)"
printf '[project]\n\tlocale = es\n' > trellis.config
body 'Closes #12' '' '**Resumen**' 'Algo.' '' '**Verificación**' 'ok'
tl_eq 'the sections follow project.locale' '0' "$(status_of --body body.md)"
body 'Closes #12' '' '**Summary**' 'A thing.' '' '**Verification**' 'ok'
tl_eq 'the en sections do not count in an es project' '1' "$(status_of --body body.md)"
rm trellis.config

printf '\nsetback\n'
git config branch.12-thing.ratchet-loosened true
body 'Closes #12' '' '**Summary**' 'A thing.' '' '**Verification**' 'ok'
tl_eq 'a loosened branch needs Setback' '1' "$(status_of --body body.md)"
body 'Closes #12' '' '**Summary**' 'A thing.' '' '**Verification**' 'ok' '' '**Setback**' 'none'
tl_eq 'Setback none does not count' '1' "$(status_of --body body.md)"
tl_eq 'has-setback says no' '1' "$(status_of --has-setback --body body.md)"
body 'Closes #12' '' '**Summary**' 'A thing.' '' '**Verification**' 'ok' '' '**Setback**' '- An ignore in main.dart; cost: the warning stays; accepted for the SDK.'
tl_eq 'a written Setback passes' '0' "$(status_of --body body.md)"
tl_eq 'has-setback says yes' '0' "$(status_of --has-setback --body body.md)"
printf '[project]\n\tlocale = es\n' > trellis.config
body 'Closes #12' '' '**Resumen**' 'Algo.' '' '**Verificación**' 'ok' '' '**Retroceso**' 'nada'
tl_eq 'es: Retroceso nada does not count' '1' "$(status_of --body body.md)"
body 'Closes #12' '' '**Resumen**' 'Algo.' '' '**Verificación**' 'ok' '' '**Retroceso**' '- Un ignore en main.dart; coste: el aviso queda; se acepta por el SDK.'
tl_eq 'es: a written Retroceso passes' '0' "$(status_of --body body.md)"
rm trellis.config
git config --unset branch.12-thing.ratchet-loosened

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
