#!/usr/bin/env bash
# Exercises scripts/issue.sh with a fake gh on the PATH: the check of a body, the check of an issue
# with its amendments and dependencies, and the creation.
. "$(dirname "$0")/../lib/testlib.sh"

# gh answers from files: issue-<n>.json for the issue of this repository, state-<owner_repo>-<n> (or
# state-here-<n>) for a dependency. Each call is logged with the token it ran with (fake values), and
# `auth token -u <user>` prints token-<user> or fails, as gh does for an account not signed in.
stubs="$TL_TMP/stubs"
mkdir -p "$stubs"
cat > "$stubs/gh" <<'GH'
#!/bin/sh
printf '%s|' "$@" >> "$GH_FIXTURES/calls.log"
printf ' token=%s\n' "${GH_TOKEN:-none}" >> "$GH_FIXTURES/calls.log"
fail() { echo "$1" >&2; exit 1; }
user=''; repo=here; fields=''; prev=''
for a in "$@"; do
  case "$prev" in
    -u) user="$a" ;;
    --repo) repo="$(echo "$a" | tr / _)" ;;
    --json) fields="$a" ;;
  esac
  prev="$a"
done
case "$1 $2" in
  'auth token') cat "$GH_FIXTURES/token-$user" 2>/dev/null || exit 1 ;;
  'issue view')
    case "$fields" in
      *body*) cat "$GH_FIXTURES/issue-$3.json" 2>/dev/null || fail "GraphQL: Could not resolve to an issue with the number of $3." ;;
      *) cat "$GH_FIXTURES/state-$repo-$3" 2>/dev/null || fail "HTTP 404: not found ($repo $3)" ;;
    esac ;;
  'label list') cat "$GH_FIXTURES/labels" 2>/dev/null || fail 'HTTP 404: no labels' ;;
  'label create') [ ! -f "$GH_FIXTURES/label-fails" ] || fail 'HTTP 403: no label for you' ;;
  'issue create')
    [ ! -f "$GH_FIXTURES/create-fails" ] || fail 'HTTP 403: no issue for you'
    prev=''
    for a in "$@"; do
      [ "$prev" = '--body-file' ] && cp "$a" "$GH_FIXTURES/created-body"
      prev="$a"
    done
    echo 'https://github.com/rologr35/fixture/issues/12' ;;
  *) fail "unexpected call: $*" ;;
esac
GH
chmod +x "$stubs/gh"
export GH_FIXTURES="$TL_TMP/gh"
mkdir -p "$GH_FIXTURES"
export PATH="$stubs:$PATH"
# issue_json <n> <body file> [<author association> <comment file>]...: the issue as gh answers it.
issue_json() {
  node -e '
    const {readFileSync, writeFileSync} = require("fs");
    const [out, body, ...rest] = process.argv.slice(1);
    const comments = [];
    for (let i = 0; i < rest.length; i += 2) comments.push({authorAssociation: rest[i], body: readFileSync(rest[i + 1], "utf8"), createdAt: `2026-01-0${1 + i / 2}T00:00:00Z`});
    writeFileSync(out, JSON.stringify({body: readFileSync(body, "utf8"), comments}));
  ' "$GH_FIXTURES/issue-$1.json" "${@:2}"
}

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

printf '\nan issue\n'
printf 'CLOSED\n' > "$GH_FIXTURES/state-rologr35_x-7"
printf 'CLOSED\n' > "$GH_FIXTURES/state-here-8"
printf 'token-of-rologr35\n' > "$GH_FIXTURES/token-rologr35"
issue_json 1 "$TL_TMP/good.md"
tl_eq 'a good issue passes' '0' "$(status_of check 1)"
tl_has '  and says so' 'issue check: ok (M)' "$(out)"
tl_has '  a dependency in free text is printed for a person' 'the tag v2' "$(out)"
tl_has '  the dependency is asked as its owner, when it is signed in' 'issue|view|7|--json|state|--jq|.state|--repo|rologr35/x| token=token-of-rologr35' "$(cat "$GH_FIXTURES/calls.log")"
tl_lacks '  the token is not printed' 'token-of-rologr35' "$(out)"
printf 'OPEN\n' > "$GH_FIXTURES/state-here-8"
tl_eq 'an open dependency fails' '1' "$(status_of check 1)"
tl_has '  and is named' 'depends on #8, which is open' "$(out)"
printf 'MERGED\n' > "$GH_FIXTURES/state-here-8"
tl_eq 'a merged pull request is closed' '0' "$(status_of check 1)"
rm "$GH_FIXTURES/state-here-8"
tl_eq 'a dependency that cannot be read fails' '1' "$(status_of check 1)"
tl_has '  with the error of gh' 'HTTP 404: not found (here 8)' "$(out)"
printf 'CLOSED\n' > "$GH_FIXTURES/state-here-8"
tl_eq 'a body does not ask for its dependencies' '0' "$(rm -f "$GH_FIXTURES/calls.log"; status_of check --body "$TL_TMP/good.md")"
tl_eq '  no gh call' 'none' "$([ -f "$GH_FIXTURES/calls.log" ] && echo some || echo none)"
sed 's/^Depends on: .*/Depends on:\
\
- #8\
- rologr35\/x#9/' "$TL_TMP/good.md" > "$TL_TMP/case.md"
issue_json 2 "$TL_TMP/case.md"
printf 'OPEN\n' > "$GH_FIXTURES/state-rologr35_x-9"
tl_eq 'a dependency in a list under the label counts' '1' "$(status_of check 2)"
tl_has '  and is named' 'depends on rologr35/x#9, which is open' "$(out)"
sed 's/^Depends on: .*/Depends on: the tag v2 and a decision/' "$TL_TMP/good.md" > "$TL_TMP/case.md"
issue_json 2 "$TL_TMP/case.md"
tl_eq 'only a free-text dependency passes' '0' "$(status_of check 2)"
sed 's/^Depends on: .*//' "$TL_TMP/good.md" > "$TL_TMP/case.md"
issue_json 2 "$TL_TMP/case.md"
tl_eq 'without Depends on' '0' "$(status_of check 2)"
tl_eq 'an issue gh cannot read fails' '1' "$(status_of check 404)"
tl_has '  with the error of gh' 'Could not resolve to an issue' "$(out)"
tl_eq '#n is the number too' '0' "$(status_of check '#2')"

printf '\nthe amendments of an issue\n'
printf 'It is slow since #3.\n\n## Verification\n\nNo idea.\n\n## Context\n\nWho knows.\n' > "$TL_TMP/symptom.md"
amendment() { printf '## Amendment (2026-11-24): %s\n\n' "$1"; }
{ amendment 'the plan'; sed 's/^## /### /; s/^Depends on: .*//' "$TL_TMP/good.md"; } > "$TL_TMP/plan.md"
issue_json 3 "$TL_TMP/symptom.md"
tl_eq 'an issue without a plan fails' '1' "$(status_of check 3)"
for who in OWNER MEMBER COLLABORATOR; do
  issue_json 3 "$TL_TMP/symptom.md" "$who" "$TL_TMP/plan.md"
  tl_eq "a plan in an amendment of $who passes, whatever the body says" '0' "$(status_of check 3)"
done
for who in NONE CONTRIBUTOR FIRST_TIME_CONTRIBUTOR ''; do
  issue_json 3 "$TL_TMP/symptom.md" "$who" "$TL_TMP/plan.md"
  tl_eq "one of an outside commenter (${who:-no association}) is ignored" '1' "$(status_of check 3)"
done
{ printf 'A thought first.\n\n'; cat "$TL_TMP/plan.md"; } > "$TL_TMP/buried.md"
issue_json 3 "$TL_TMP/symptom.md" OWNER "$TL_TMP/buried.md"
tl_eq 'a comment that is not headed Amendment is ignored' '1' "$(status_of check 3)"
sed 's/^### Risks$/## Risks/' "$TL_TMP/plan.md" > "$TL_TMP/wrong-level.md"
issue_json 3 "$TL_TMP/symptom.md" OWNER "$TL_TMP/wrong-level.md"
tl_eq 'a section of an amendment is a ### heading' '1' "$(status_of check 3)"
{ amendment 'risks'; printf '### Risks\n\nThe first risk.\n'; } > "$TL_TMP/a1.md"
{ amendment 'risks again'; printf '### Risks\n\nThe second risk.\n\n### Notes\n\nStill risks.\n\n## Other\n\nNot risks.\n\nComplexity: L\n'; } > "$TL_TMP/a2.md"
{ amendment 'nothing but words'; printf 'The plan does not change.\n'; } > "$TL_TMP/a3.md"
{ amendment 'a stranger'; printf '### Risks\n\nThe risk of a stranger.\n\nComplexity: S\n'; } > "$TL_TMP/a4.md"
sed 's/^Gates: none\.$//' "$TL_TMP/good.md" > "$TL_TMP/no-risks.md"
issue_json 4 "$TL_TMP/no-risks.md" OWNER "$TL_TMP/a1.md"
tl_eq 'a section filled by an amendment passes' '0' "$(status_of check 4)"
issue_json 4 "$TL_TMP/no-risks.md" OWNER "$TL_TMP/a1.md" MEMBER "$TL_TMP/a2.md" OWNER "$TL_TMP/a3.md" NONE "$TL_TMP/a4.md"
tl_eq 'the last amendment that has the section wins' '0' "$(status_of check 4)"
tl_has '  and the last complexity line' 'issue check: ok (L)' "$(out)"
tl_eq '--print passes' '0' "$(status_of check 4 --print)"
tl_has '  with the last Risks' 'The second risk.' "$(out)"
tl_has '  and what its section holds' 'Still risks.' "$(out)"
tl_lacks '  without the one before' 'The first risk.' "$(out)"
tl_lacks '  without what is outside a section' 'Not risks.' "$(out)"
tl_lacks '  without the one of a stranger' 'stranger' "$(out)"
tl_eq '  and with the last line the class' 'Complexity: L' "$(tail -n 1 "$TL_TMP/out.txt")"
tl_eq '  its sections are the five, in order' 'Context Approved-plan Layers-and-files Risks Verification' "$(sed -n 's/^## //p' "$TL_TMP/out.txt" | tr ' ' '-' | tr '\n' ' ' | sed 's/ $//')"
{ amendment 'emptied'; printf '### Risks\n\n### Verification\n\nRun it.\n\nComplexity: XL\n'; } > "$TL_TMP/a5.md"
issue_json 5 "$TL_TMP/good.md" OWNER "$TL_TMP/a5.md"
tl_eq 'an amendment that empties a section fails' '1' "$(status_of check 5)"
tl_has '  naming it' 'section Risks is empty' "$(out)"
tl_has '  and its wrong class' 'last line is not `Complexity: S`, M or L' "$(out)"
tl_eq '--print judges nothing' '0' "$(status_of check 5 --print)"
issue_json 5 "$TL_TMP/symptom.md"
tl_eq '--print of an issue without a plan' '0' "$(status_of check --print 5)"
{ amendment 'deps'; printf '### Context\n\nChanged.\n\nDepends on: rologr35/x#9\n'; } > "$TL_TMP/a6.md"
issue_json 6 "$TL_TMP/good.md" OWNER "$TL_TMP/a6.md"
tl_eq 'the dependencies are those of the last Context' '1' "$(status_of check 6)"
tl_has '  named' 'depends on rologr35/x#9, which is open' "$(out)"
tl_lacks '  and not those of the body' 'the tag v2' "$(out)"
git config -f trellis.config project.locale es
sed 's/^## /### /; s/^Depende de: .*//' "$TL_TMP/good-es.md" > "$TL_TMP/case.md"
{ printf '## Enmienda (2026-11-24)\n\n'; cat "$TL_TMP/case.md"; } > "$TL_TMP/plan-es.md"
issue_json 7 "$TL_TMP/symptom.md" OWNER "$TL_TMP/plan-es.md"
tl_eq 'es: a plan in an Enmienda passes' '0' "$(status_of check 7)"
git config -f trellis.config --unset project.locale

printf '\ncreate\n'
calls() { cat "$GH_FIXTURES/calls.log" 2>/dev/null; }
# Runs a create with a clean log.
create_of() { rm -f "$GH_FIXTURES/calls.log" "$GH_FIXTURES/created-body"; status_of create "$@"; }
printf 'bug\nM\n' > "$GH_FIXTURES/labels"
tl_eq 'a good body is created' '0' "$(create_of --title 'A flag for x' --body-file "$TL_TMP/good.md")"
tl_eq '  and only its URL is printed' 'https://github.com/rologr35/fixture/issues/12' "$(out)"
tl_has '  with the label of its complexity line' '--label|M|' "$(calls)"
tl_has '  and its title' '--title|A flag for x|' "$(calls)"
tl_lacks '  the label exists, so none is created' 'label|create' "$(calls)"
tl_eq '  the body is the one of the file' '' "$(diff "$TL_TMP/good.md" "$GH_FIXTURES/created-body" 2>&1)"
for class in S L; do
  sed "s/^Complexity: M/Complexity: $class/" "$TL_TMP/good.md" > "$TL_TMP/case.md"
  tl_eq "a body of class $class is created" '0' "$(create_of --title x --body-file "$TL_TMP/case.md")"
  tl_has '  its label is created first' "label|create|$class|" "$(calls)"
  tl_has '  and used' "--label|$class|" "$(calls)"
done
printf 'm\n' > "$GH_FIXTURES/labels"
tl_eq 'a label in lower case is the same label' '0' "$(create_of --title x --body-file "$TL_TMP/good.md")"
tl_lacks '  and is not created again' 'label|create' "$(calls)"
printf 'bug\n' > "$GH_FIXTURES/labels"
(cd "$TL_TMP" && cp good.md "$repo/relative.md")
tl_eq 'a relative body file, the flags with = and in another order' '0' "$(create_of --body-file=relative.md --title='With = sign')"
tl_has '  keep the title' '--title|With = sign|' "$(calls)"
tl_eq '  and the body' '' "$(diff relative.md "$GH_FIXTURES/created-body" 2>&1)"
rm -f relative.md
sed 's/^Complexity: M//' "$TL_TMP/good.md" > "$TL_TMP/case.md"
tl_eq 'a body that fails the check is not created' '1' "$(create_of --title x --body-file "$TL_TMP/case.md")"
tl_has '  it says why' 'last line is not' "$(out)"
tl_eq '  and makes no gh call' '' "$(calls)"
touch "$GH_FIXTURES/label-fails"
tl_eq 'a label that cannot be created fails' '1' "$(create_of --title x --body-file "$TL_TMP/good.md")"
tl_has '  with the error of gh' 'no label for you' "$(out)"
tl_lacks '  and no issue is created' 'issue|create' "$(calls)"
rm "$GH_FIXTURES/label-fails" "$GH_FIXTURES/labels"
tl_eq 'labels that cannot be read fail' '1' "$(create_of --title x --body-file "$TL_TMP/good.md")"
tl_lacks '  and no issue is created' 'issue|create' "$(calls)"
printf 'M\n' > "$GH_FIXTURES/labels"
touch "$GH_FIXTURES/create-fails"
tl_eq 'an issue that cannot be created fails' '1' "$(create_of --title x --body-file "$TL_TMP/good.md")"
tl_has '  with the error of gh' 'no issue for you' "$(out)"
rm "$GH_FIXTURES/create-fails"
tl_eq 'no title' '2' "$(create_of --body-file "$TL_TMP/good.md")"
tl_eq 'an empty title' '2' "$(create_of --title '' --body-file "$TL_TMP/good.md")"
tl_eq 'no body' '2' "$(create_of --title x)"
tl_eq 'a body that does not exist' '2' "$(create_of --title x --body-file "$TL_TMP/none.md")"
tl_eq 'a flag without its value' '2' "$(create_of --title x --body-file)"
tl_eq 'a flag it does not know' '2' "$(create_of --title x --body-file "$TL_TMP/good.md" --label L)"
tl_has '  which it names in the usage' 'trellis issue create' "$(out)"
tl_has 'the usage of trellis lists create' 'issue create' "$("$TRELLIS" help 2>&1)"
git config -f trellis.config tracker.kind none
tl_eq 'tracker.kind = none exits 2' '2' "$(create_of --title x --body-file "$TL_TMP/good.md")"
tl_eq '  with no gh call' '' "$(calls)"
git config -f trellis.config --unset tracker.kind
git remote set-url origin https://github.com/rologr35/fixture.git
export GIT_ALLOW_PROTOCOL=file
tl_eq 'a repository whose owner is signed in' '0' "$(create_of --title x --body-file "$TL_TMP/good.md")"
tl_lacks '  asks nothing as another account' 'token=none' "$(calls | grep -v '^auth')"
tl_has '  and creates as its owner' 'token=token-of-rologr35' "$(calls | grep '^issue|create')"
tl_has '  without origin reached, it says the last fetch judged' 'judged by the last fetch' "$(out)"
tl_lacks '  the token is not printed' 'token-of-rologr35' "$(out)"
unset GIT_ALLOW_PROTOCOL
git remote set-url origin "$remote"

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
