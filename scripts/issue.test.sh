#!/usr/bin/env bash
# Exercises scripts/issue.sh with a fake gh on the PATH: the check of a body, the check of an issue
# with its amendments and dependencies, and the creation.
. "$(dirname "$0")/../lib/testlib.sh"

# A project whose origin/develop holds lib/a.sh, docs/guide.md and README.md.
remote="$(mktemp -d "$TL_TMP/remote.XXXXXX")"
git init -q --bare "$remote"
repo="$(tl_repo)"
cd "$repo" || exit 1
mkdir -p lib docs
echo a > lib/a.sh
echo g > docs/guide.md
echo r > README.md
cat > trellis.config <<'CFG'
[git]
	integrationBranch = develop
CFG
git add -A && git commit -q -m 'chore: files'
git remote add origin "$remote"
git push -q origin HEAD:refs/heads/develop
git fetch -q origin

# A good body in en; each case changes one thing of it with sed.
cat > "$TL_TMP/good.md" <<'MD'
## Context

A thing is broken: see rologr35/x#4.

Depends on: rologr35/x#7, `#8`, the tag v2

## Approved plan

1. `lib/a.sh` gains a flag, read as `project.locale`.

Out of scope:
- The other flag. Source: rologr35/x#5.
- A third one,
  on two lines. Source: the person, 2026-11-24.

## Layers and files

- `lib/a.sh` (`a_function`), `README.md:3`, `docs/` and `tracker.kind`
- **New**: `lib/b.sh`,
  `scripts/new.sh`

## Risks

Gates: none.

## Verification

- `lib/a.test.sh` is green.

Complexity: M
MD
cat > "$TL_TMP/good-es.md" <<'MD'
## Contexto

Algo falla.

Depende de: #7

## Plan aprobado

1. `lib/a.sh` gana una opción.

Fuera de alcance:
- La otra opción. Fuente: rologr35/x#5.

## Capas y ficheros

- `lib/a.sh`
- **Nuevos**: `lib/b.sh`

## Riesgos

Gates: ninguno.

## Verificación

- `lib/a.test.sh` en verde.

Complejidad: L
MD
status_of() { "$TRELLIS" issue "$@" >"$TL_TMP/out.txt" 2>&1; echo $?; }
out() { cat "$TL_TMP/out.txt"; }
# case_of <sed script>: the good body changed, checked; prints the exit status.
case_of() { sed "$1" "$TL_TMP/good.md" > "$TL_TMP/case.md"; status_of check --body "$TL_TMP/case.md"; }
fails() { tl_eq "$1" '1' "$(case_of "$2")"; tl_has '  and is named' "$3" "$(out)"; }

printf '\na body\n'
tl_eq 'a good body passes' '0' "$(status_of check --body "$TL_TMP/good.md")"
tl_eq '  and says so' 'issue check: ok (M)' "$(out)"
tr -d '\r' < "$TL_TMP/good.md" | sed 's/$/'"$(printf '\r')"'/' > "$TL_TMP/crlf.md"
tl_eq 'with CRLF line ends too' '0' "$(status_of check --body "$TL_TMP/crlf.md")"
tl_eq 'an es body fails in an en project' '1' "$(status_of check --body "$TL_TMP/good-es.md")"
git config -f trellis.config project.locale es
tl_eq 'a good es body passes in an es project' '0' "$(status_of check --body "$TL_TMP/good-es.md")"
tl_eq 'an en body fails in an es project' '1' "$(status_of check --body "$TL_TMP/good.md")"
tl_has '  and names the es section' 'Plan aprobado' "$(out)"
sed '/^Fuera/,/Fuente/s/ Fuente: .*//' "$TL_TMP/good-es.md" > "$TL_TMP/case.md"
tl_eq 'es: an item of Fuera de alcance without Fuente fails' '1' "$(status_of check --body "$TL_TMP/case.md")"
tl_has '  and is named' 'Fuera de alcance: "La otra opción."' "$(out)"
git config -f trellis.config --unset project.locale
for locale in en es; do
  git config -f trellis.config project.locale "$locale"
  tl_eq "the $locale mould unfilled fails" '1' "$(status_of check --body "$TRELLIS_ROOT/templates/$locale/issue.md")"
done
tl_has '  with its placeholder sections empty' 'section Contexto is empty' "$(out)"
git config -f trellis.config --unset project.locale

printf '\nsections\n'
for name in 'Context' 'Approved plan' 'Layers and files' 'Risks' 'Verification'; do
  fails "without $name" "/^## $name\$/d" "no section \`## $name\`"
done
fails 'an empty Risks' 's/^Gates: none\.$//' 'section Risks is empty'
fails 'a Risks that is only a comment' 's/^Gates: none\.$/<!-- later -->/' 'section Risks is empty'
fails 'a Context with only a Depends on line' '/^A thing is broken/d' 'section Context is empty'
fails 'a plan with only Out of scope' '/gains a flag/d' 'section Approved plan is empty'
fails 'a Verification with only the complexity line' '/a\.test\.sh/d' 'section Verification is empty'
fails 'Risks and Layers swapped' 's/^## Risks$/## X/; s/^## Layers and files$/## Risks/; s/^## X$/## Layers and files/' 'sections are not in order'
fails 'a section twice' 's/^Gates: none\.$/x\
## Context\
y/' 'section Context appears 2 times'
fails 'a heading inside a code fence is not a section' 's/^## Risks$/```\
## Risks\
```/' 'no section `## Risks`'
fails 'a bold label is not a section' 's/^## Risks$/**Risks**/' 'no section `## Risks`'

printf '\nout of scope\n'
tl_eq 'without Out of scope' '0' "$(case_of '/^Out of scope/,/^## Layers/{/^## Layers/!d;}')"
fails 'an item without Source' 's/ Source: rologr35.*//' 'Out of scope: "The other flag."'
fails 'a two-line item without Source' 's/ Source: the person.*//' 'Out of scope: "A third one,'
fails 'a Source that says nothing' 's/ Source: rologr35.*/ Source: /' 'Out of scope: "The other flag.'
fails 'a Source that is the placeholder' 's/ Source: rologr35.*/ Source: {{where}}/' 'Out of scope: "The other flag.'
fails 'written on the label line, without Source' 's/^Out of scope:$/Out of scope: everything else\./' 'Out of scope: "everything else."'
fails 'as a heading, without Source' 's/^Out of scope:$/### Out of scope/; s/ Source: rologr35.*//' 'Out of scope: "The other flag."'
fails 'bold, without Source' 's/^Out of scope:$/**Out of scope**:/; s/ Source: rologr35.*//' 'Out of scope: "The other flag."'

printf '\ncomplexity\n'
fails 'no complexity line' '/^Complexity/d' 'last line is not `Complexity: S`, M or L'
fails 'a wrong class' 's/^Complexity: M/Complexity: XL/' 'last line is not `Complexity: S`, M or L'
fails 'a lower-case class' 's/^Complexity: M/Complexity: m/' 'last line is not `Complexity: S`, M or L'
fails 'a line after it' 's/^Complexity: M/Complexity: M\
One more thing./' 'last line is not `Complexity: S`, M or L'

printf '\npaths\n'
fails 'a path that does not exist' 's|docs/`|docs/`, `lib/nope.sh`|' 'Layers and files: `lib/nope.sh` is not in origin/develop'
fails 'a file at the root that does not exist' 's|docs/`|docs/`, `NOPE.md`|' '`NOPE.md` is not in origin/develop'
fails 'a path under New and outside it' 's|docs/`|docs/`, `lib/b.sh`|' '`lib/b.sh` is not in origin/develop'
fails 'a path after the New list' 's|^  `scripts/new.sh`$|  `scripts/new.sh`\
- `lib/after.sh`|' '`lib/after.sh` is not in origin/develop'
tl_eq 'a New list as bullets below its label' '0' "$(case_of 's|^- \*\*New\*\*: `lib/b.sh`,|\
New:\
- `lib/b.sh`|; s|^  `scripts/new.sh`|- `scripts/new.sh`|')"
tl_eq 'a New heading with its list' '0' "$(case_of 's|^- \*\*New\*\*: `lib/b.sh`,|\
### New\
- `lib/b.sh`|; s|^  `scripts/new.sh`|- `scripts/new.sh`|')"
tl_eq 'a command, a glob and a placeholder are not paths' '0' "$(case_of 's|docs/`|docs/`, `bash lib/nope.sh`, `lib/**`, `templates/<locale>/x.md`, `a/{b,c}.md`, `~/x/y`, `/etc/x`|')"
tl_eq 'a path of another section is not judged' '0' "$(case_of 's|^Gates: none|`lib/nope.sh`. Gates: none|')"
echo late > lib/late.sh
git add -A && git commit -q -m 'chore: late'
fails 'a path only in the working tree' 's|docs/`|docs/`, `lib/late.sh`|' '`lib/late.sh` is not in origin/develop'
other="$TL_TMP/other-clone"
git clone -q -b develop "$remote" "$other"
echo n > "$other/lib/newer.sh"
git -C "$other" add -A && git -C "$other" commit -q -m 'chore: newer' && git -C "$other" push -q origin develop
tl_eq 'a path merged since the last fetch passes' '0' "$(case_of 's|docs/`|docs/`, `lib/newer.sh`|')"
git config -f trellis.config git.integrationBranch nowhere
fails 'an integration branch that is not known' 's/x/x/' 'origin/nowhere is not known here'
git config -f trellis.config git.integrationBranch develop

printf '\nstyle\n'
fails 'a long dash' "s/^Gates: none/Gates $(printf '\342\200\224') none/" 'long dash'
fails 'an attribution' 's/^Gates: none/Generated with a tool/' 'attribution'
fails 'a bare #N' 's/^Gates: none/As #3 says/' 'bare #3'
fails 'a bare #N on the Depends on line of another section is judged as text' 's/^Gates: none/It depends on the thing in #3/' 'bare #3'
tl_eq 'a #N on the Depends on line is a reference' '0' "$(case_of 's/^Depends on: .*/Depends on: #7, #8 and rologr35\/x#9/')"

printf '\nusage\n'
tl_eq 'no arguments' '2' "$(status_of)"
tl_eq 'a body that does not exist' '2' "$(status_of check --body "$TL_TMP/none.md")"
tl_eq 'an issue that is not a number' '2' "$(status_of check abc)"
tl_has 'the usage of trellis lists issue' 'trellis issue check' "$("$TRELLIS" help 2>&1)"
tl_has 'and still its last line' 'trellis check ' "$("$TRELLIS" help 2>&1)"
git config -f trellis.config tracker.kind none
tl_eq 'tracker.kind = none exits 2' '2' "$(status_of check --body "$TL_TMP/good.md")"
tl_has '  and says the module is off' 'tracker.kind = none' "$(out)"
git config -f trellis.config --unset tracker.kind

tl_done
