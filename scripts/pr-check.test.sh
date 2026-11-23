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
body 'Closes #12' '' '**Resumen**' 'Algo.' '' '**Verificación**' '- pruebas en verde'
tl_eq 'a good body passes' '0' "$(status_of --body body.md)"
body 'Closes #12' '' '**Resumen**' "Algo $(printf '\342\200\224') otro." '' '**Verificación**' 'ok'
tl_eq 'long dash fails' '1' "$(status_of --body body.md)"
body 'Closes #12' '' '## Resumen' 'Algo.' '' '## Verificación' 'ok' '' 'Generated with Claude Code'
tl_eq 'attribution fails' '1' "$(status_of --body body.md)"
body 'Closes #12' '' '**Resumen**' 'Ver el paso #3.' '' '**Verificación**' 'ok'
tl_eq 'a bare #N fails' '1' "$(status_of --body body.md)"
tl_has 'and is named' 'bare #3' "$(cat out.txt)"
body 'Closes #12' '' '**Resumen**' 'Refs #3, también `#4` y (#5).' '' '**Verificación**' 'ok'
tl_eq 'keyword, backticks and parentheses pass' '0' "$(status_of --body body.md)"
body 'Closes #12' '' '**Resumen**' 'Algo.'
tl_eq 'a missing section fails' '1' "$(status_of --body body.md)"
tl_has 'and is named' 'Verificación' "$(cat out.txt)"
printf '[project]\n\tlocale = en\n' > trellis.config
body 'Closes #12' '' '**Summary**' 'Thing.' '' '**Verification**' 'ok'
tl_eq 'the sections follow project.locale' '0' "$(status_of --body body.md)"
rm trellis.config

printf '\nsetback\n'
git config branch.12-thing.ratchet-loosened true
body 'Closes #12' '' '**Resumen**' 'Algo.' '' '**Verificación**' 'ok'
tl_eq 'a loosened branch needs Retroceso' '1' "$(status_of --body body.md)"
body 'Closes #12' '' '**Resumen**' 'Algo.' '' '**Verificación**' 'ok' '' '**Retroceso**' 'nada'
tl_eq 'Retroceso nada does not count' '1' "$(status_of --body body.md)"
tl_eq 'has-setback says no' '1' "$(status_of --has-setback --body body.md)"
body 'Closes #12' '' '**Resumen**' 'Algo.' '' '**Verificación**' 'ok' '' '**Retroceso**' '- Un ignore en main.dart; coste: el aviso queda; se acepta por el SDK.'
tl_eq 'a written Retroceso passes' '0' "$(status_of --body body.md)"
tl_eq 'has-setback says yes' '0' "$(status_of --has-setback --body body.md)"
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
