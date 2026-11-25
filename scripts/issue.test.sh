#!/usr/bin/env bash
# Exercises scripts/issue.sh with a fake gh on the PATH: the check of a body, the check of an issue
# with its amendments and dependencies, the creation, and the close after a merge.
. "$(dirname "$0")/../lib/testlib.sh"

# gh answers only `api`, as in a cloud session, where the rest is refused with the text below. It keeps
# GitHub in files: <owner>_<repo>/issue-<n>.json, comments-<n>.json and pr-<n>.json, in the shape of REST,
# and `labels`. {owner}/{repo} is rologr35/fixture. Each call is logged with the token it ran with (fake
# values), each write with its fields, and `auth token -u <user>` prints token-<user> or fails, as gh does
# for an account not signed in. A file <what>-fails makes that write fail, and `race` holds who else is
# assigned at the same time.
stubs="$TL_TMP/stubs"
mkdir -p "$stubs"
cat > "$stubs/gh" <<'GH'
#!/usr/bin/env node
const fs = require('fs');
const dir = process.env.GH_FIXTURES;
const args = process.argv.slice(2);
fs.appendFileSync(`${dir}/calls.log`, `${args.join('|')}| token=${process.env.GH_TOKEN || 'none'}\n`);
const stop = text => { console.error(text); process.exit(1); };
const read = file => fs.existsSync(`${dir}/${file}`) ? fs.readFileSync(`${dir}/${file}`, 'utf8') : null;
if (args[0] === 'auth') {
  const token = read(`token-${args[args.indexOf('-u') + 1]}`);
  if (token === null) process.exit(1);
  process.stdout.write(token);
  process.exit(0);
}
if (args[0] !== 'api') stop('GitHub GraphQL is not available from Claude Code sessions; use the REST API');

let endpoint = '', method = '', jq = '';
const fields = {};
for (let i = 1; i < args.length; i++) {
  const a = args[i];
  if (a === '-X' || a === '--method') method = args[++i];
  else if (a === '--jq') jq = args[++i];
  else if (a === '--hostname') i++;
  else if (a === '-f' || a === '-F') {
    const at = args[++i].indexOf('=');
    const key = args[i].slice(0, at);
    let value = args[i].slice(at + 1);
    if (a === '-F' && value.startsWith('@')) value = fs.readFileSync(value.slice(1), 'utf8');
    if (key.endsWith('[]')) (fields[key.slice(0, -2)] ||= []).push(value);
    else fields[key] = value;
  } else if (a === '--paginate') continue;
  else if (a.startsWith('-')) stop(`unknown flag: ${a}`);
  else endpoint = a;
}
method ||= Object.keys(fields).length ? 'POST' : 'GET';
const refused = (code, text) => { console.log(JSON.stringify({message: text, status: String(code)})); stop(`gh: ${text} (HTTP ${code})`); };
const answer = value => {
  const filter = {'': v => [v], '.state': v => [v.state], '.html_url': v => [v.html_url], '.[]': v => v, '.[].name': v => v.map(x => x.name), '.login': v => [v.login]}[jq];
  if (!filter) stop(`unexpected filter: ${jq}`);
  for (const v of filter(value)) console.log(typeof v === 'string' ? v : JSON.stringify(v));
  process.exit(0);
};
const [path] = endpoint.split('?');
const [, named, rest] = /^repos\/([^/]+\/[^/]+)\/(.*)$/.exec(path) || [];
const repo = named === '{owner}/{repo}' ? 'rologr35/fixture' : named;
const at = file => `${(repo || '').replace('/', '_')}/${file}`;
const load = file => { const text = read(file); return text === null ? refused(404, 'Not Found') : JSON.parse(text); };
const save = (file, value) => fs.writeFileSync(`${dir}/${file}`, JSON.stringify(value));
const failing = what => { if (read(`${what}-fails`) !== null) refused(403, `no ${what} for you`); };
if (method !== 'GET') {
  const shown = Object.keys(fields).map(k => k === 'body' ? 'body' : `${k}=${fields[k]}`).join(' ');
  fs.appendFileSync(`${dir}/writes.log`, `${method} ${rest || path}${shown && ' '}${shown}\n`);
}
const is = re => re.exec(rest || '');
let m;
if (method === 'GET') {
  if (path === 'user') answer({login: 'rologr35'});
  if ((m = is(/^issues\/(\d+)$/))) answer(load(at(`issue-${m[1]}.json`)));
  if ((m = is(/^issues\/(\d+)\/comments$/))) answer(load(at(`comments-${m[1]}.json`)));
  if ((m = is(/^pulls\/(\d+)$/))) answer(load(at(`pr-${m[1]}.json`)));
  if (is(/^labels$/)) {
    const labels = read('labels');
    if (labels === null) refused(404, 'no labels');
    answer(labels.split('\n').filter(Boolean).map(name => ({name})));
  }
}
if (method === 'POST' && is(/^labels$/)) {
  failing('label');
  fs.appendFileSync(`${dir}/labels`, `${fields.name}\n`);
  answer({name: fields.name});
}
if (method === 'POST' && is(/^issues$/)) {
  failing('create');
  fs.writeFileSync(`${dir}/created-body`, fields.body);
  save('created.json', fields);
  answer({number: 12, html_url: 'https://github.com/rologr35/fixture/issues/12'});
}
if ((m = is(/^issues\/(\d+)(\/.*)?$/))) {
  const file = at(`issue-${m[1]}.json`);
  const issue = load(file);
  const sub = m[2] || '';
  if (method === 'PATCH' && sub === '') {
    failing('close');
    Object.assign(issue, fields);
  } else if (method === 'POST' && sub === '/comments') {
    failing('comment');
    const all = load(at(`comments-${m[1]}.json`));
    all.push({user: {login: 'x'}, author_association: 'OWNER', created_at: '2026-01-09T00:00:00Z', body: fields.body});
    save(at(`comments-${m[1]}.json`), all);
  } else if (method === 'POST' && sub === '/assignees') {
    failing('assign');
    issue.assignees ||= [];
    const also = read('race');
    const who = read('assign-ignored') === null ? fields.assignees : [];
    for (const login of [...(also === null ? [] : [also.trim()]), ...who]) if (!issue.assignees.some(a => a.login === login)) issue.assignees.push({login});
  } else if (method === 'DELETE' && sub === '/assignees') {
    failing('unassign');
    issue.assignees = issue.assignees.filter(a => !fields.assignees.includes(a.login));
  } else if (method === 'POST' && sub === '/labels') {
    failing('edit');
    for (const name of fields.labels) if (!issue.labels.some(l => l.name === name)) issue.labels.push({name});
  } else if (method === 'DELETE' && sub.startsWith('/labels/')) {
    failing('edit');
    const name = decodeURIComponent(sub.slice(8)).toLowerCase();
    if (!issue.labels.some(l => l.name.toLowerCase() === name)) refused(404, 'Label does not exist');
    issue.labels = issue.labels.filter(l => l.name.toLowerCase() !== name);
  } else {
    stop(`unexpected call: ${args.join(' ')}`);
  }
  save(file, issue);
  answer(issue);
}
stop(`unexpected call: ${args.join(' ')}`);
GH
chmod +x "$stubs/gh"
export GH_FIXTURES="$TL_TMP/gh"
here="$GH_FIXTURES/rologr35_fixture"
mkdir -p "$here"
export PATH="$stubs:$PATH"
# issue_json <n> <body file> [<author association> <comment file>]...: the issue as GitHub holds it.
issue_json() {
  node -e '
    const {readFileSync, writeFileSync} = require("fs");
    const [dir, n, body, ...rest] = process.argv.slice(1);
    const comments = [];
    for (let i = 0; i < rest.length; i += 2) comments.push({user: {login: "x"}, author_association: rest[i], body: readFileSync(rest[i + 1], "utf8"), created_at: `2026-01-0${2 + i / 2}T00:00:00Z`});
    const issue = {number: Number(n), state: "open", html_url: `https://github.com/rologr35/fixture/issues/${n}`, user: {login: "rologr35"}, author_association: "OWNER", created_at: "2026-01-01T00:00:00Z", assignees: [], labels: [], body: readFileSync(body, "utf8")};
    writeFileSync(`${dir}/issue-${n}.json`, JSON.stringify(issue));
    writeFileSync(`${dir}/comments-${n}.json`, JSON.stringify(comments));
  ' "$here" "$1" "${@:2}"
}
# state_of <owner>_<repo> <n> <state>: an issue of which only the state is asked.
state_of() {
  mkdir -p "$GH_FIXTURES/$1"
  printf '{"number":%s,"state":"%s"}' "$2" "$3" > "$GH_FIXTURES/$1/issue-$2.json"
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
fails 'a list apart from a New line that has its paths' 's|^- \*\*New\*\*: `lib/b.sh`,|\
New: `lib/b.sh`\
\
- `lib/nope.sh`|' '`lib/nope.sh` is not in origin/develop'
fails 'a Depends on line does not empty the list after it' '/^A thing is broken/d; s|^Depends on: .*|Depends on: #8\
\
- A thing is broken.\
- {{}}|; s/^## Risks/## Risk/' 'no section `## Risks`'
tl_lacks '  Context is not empty' 'Context is empty' "$(out)"
tl_eq 'a New heading with its list' '0' "$(case_of 's|^- \*\*New\*\*: `lib/b.sh`,|\
### New\
- `lib/b.sh`|; s|^  `scripts/new.sh`|- `scripts/new.sh`|')"
tl_eq 'a command, a glob and a placeholder are not paths' '0' "$(case_of 's|docs/`|docs/`, `bash lib/nope.sh`, `lib/**`, `templates/<locale>/x.md`, `a/{b,c}.md`, `~/x/y`, `/etc/x`|')"
tl_eq 'a path of another section is not judged' '0' "$(case_of 's|^Gates: none|Gates: none. `lib/nope.sh`|')"
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

printf '\ngates\n'
no_gates='Risks does not open with `Gates: none`'
fails 'Risks without Gates' 's/^Gates: none\.$/It may break./' "$no_gates"
fails 'Gates that is not the first line' 's/^Gates: none\.$/It may break.\
\
Gates: none./' "$no_gates"
fails 'Gates that says nothing' 's/^Gates: none\.$/Gates:\
\
It may break./' "$no_gates"
fails 'Gates with the placeholder' 's/^Gates: none\.$/Gates: {{none}}/' "$no_gates"
tl_eq 'a text after none' '0' "$(case_of 's/^Gates: none\.$/Gates: none. It may break, in lib./')"
tl_eq 'Gates after a comment' '0' "$(case_of 's/^Gates: none\.$/<!-- a note -->\
**Gates**: none/')"
fails 'a gate that does not exist' 's/^Gates: none\.$/Gates: money/' 'Gates: there is no [gate "money"] in trellis.config'
git config -f trellis.config gate.money.paths 'lib/**'
git config -f trellis.config --add gate.money.paths 'docs/*.md'
git config -f trellis.config gate.release-notes.paths 'CHANGES.md'
fails 'a path of a gate that is not named' 's/x/x/' 'Gates: `lib/a.sh` is of the gate money, which Risks does not name'
tl_has '  and one under New' 'Gates: `lib/b.sh` is of the gate money' "$(out)"
tl_has '  and a folder that has one of its files' 'Gates: `docs` is of the gate money' "$(out)"
tl_lacks '  and no other gate' 'release-notes' "$(out)"
tl_eq 'the gate named passes' '0' "$(case_of 's/^Gates: none\.$/Gates: money/')"
tl_eq 'two gates named, with text after' '0' "$(case_of 's/^Gates: none\.$/Gates: `money`, release-notes. It may break./')"
fails 'one that exists and one that does not' 's/^Gates: none\.$/Gates: money, nothing/' 'there is no [gate "nothing"]'
fails 'none and a name' 's/^Gates: none\.$/Gates: none, money/' 'there is no [gate "none"]'
git config -f trellis.config gate.money.paths 'lib/{a,b}.sh' 'lib/'
fails 'a gate whose glob is not read' 's/x/x/' 'gate.money.paths: glob lib/{a,b}.sh uses syntax trellis does not read'
git config -f trellis.config --remove-section gate.money
git config -f trellis.config --remove-section gate.release-notes
git config -f trellis.config project.locale es
sed 's/^Gates: ninguno/Gates: none/' "$TL_TMP/good-es.md" > "$TL_TMP/case.md"
tl_eq 'es: none is not its word' '1' "$(status_of check --body "$TL_TMP/case.md")"
tl_has '  it is ninguno' 'there is no [gate "none"]' "$(out)"
git config -f trellis.config --unset project.locale

printf '\nstyle\n'
fails 'a long dash' "s/^Gates: none/Gates $(printf '\342\200\224') none/" 'long dash'
fails 'an attribution' 's/^Gates: none/Generated with a tool/' 'attribution'
fails 'a bare #N' 's/^Gates: none/As #3 says/' 'bare #3'
fails 'a bare #N on the Depends on line of another section is judged as text' 's/^Gates: none/It depends on the thing in #3/' 'bare #3'
tl_eq 'a #N on the Depends on line is a reference' '0' "$(case_of 's/^Depends on: .*/Depends on: #7, #8 and rologr35\/x#9/')"

printf '\nan issue\n'
state_of rologr35_x 7 closed
state_of rologr35_fixture 8 closed
printf 'token-of-rologr35\n' > "$GH_FIXTURES/token-rologr35"
issue_json 1 "$TL_TMP/good.md"
tl_eq 'a good issue passes' '0' "$(status_of check 1)"
tl_has '  and says so' 'issue check: ok (M)' "$(out)"
tl_has '  a dependency in free text is printed for a person' 'the tag v2' "$(out)"
tl_has '  the dependency is asked as its owner, when it is signed in' 'api|repos/rologr35/x/issues/7|--jq|.state| token=token-of-rologr35' "$(cat "$GH_FIXTURES/calls.log")"
tl_lacks '  the token is not printed' 'token-of-rologr35' "$(out)"
tl_has '  its comments are read by pages' 'api|repos/{owner}/{repo}/issues/1/comments?per_page=100|--paginate|' "$(cat "$GH_FIXTURES/calls.log")"
state_of rologr35_fixture 8 open
tl_eq 'an open dependency fails' '1' "$(status_of check 1)"
tl_has '  and is named' 'depends on #8, which is open' "$(out)"
state_of rologr35_fixture 8 closed
tl_eq 'a closed one, which a merged pull request is too, passes' '0' "$(status_of check 1)"
rm "$here/issue-8.json"
tl_eq 'a dependency that cannot be read fails' '1' "$(status_of check 1)"
tl_has '  with the error of gh' 'depends on #8, whose state could not be read as the active account: gh: Not Found (HTTP 404)' "$(out)"
state_of rologr35_fixture 8 closed
tl_eq 'a body does not ask for its dependencies' '0' "$(rm -f "$GH_FIXTURES/calls.log"; status_of check --body "$TL_TMP/good.md")"
tl_eq '  no gh call' 'none' "$([ -f "$GH_FIXTURES/calls.log" ] && echo some || echo none)"
sed 's/^Depends on: .*/Depends on:\
\
- #8\
- rologr35\/x#9/' "$TL_TMP/good.md" > "$TL_TMP/case.md"
issue_json 2 "$TL_TMP/case.md"
state_of rologr35_x 9 open
tl_eq 'a dependency in a list under the label counts' '1' "$(status_of check 2)"
tl_has '  and is named' 'depends on rologr35/x#9, which is open' "$(out)"
sed 's/^Depends on: .*/Depends on: the tag v2 and a decision/' "$TL_TMP/good.md" > "$TL_TMP/case.md"
issue_json 2 "$TL_TMP/case.md"
tl_eq 'only a free-text dependency passes' '0' "$(status_of check 2)"
sed 's/^Depends on: .*//' "$TL_TMP/good.md" > "$TL_TMP/case.md"
issue_json 2 "$TL_TMP/case.md"
tl_eq 'without Depends on' '0' "$(status_of check 2)"
tl_eq 'an issue gh cannot read fails' '1' "$(status_of check 404)"
tl_has '  with the error of gh' 'Not Found (HTTP 404)' "$(out)"
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
# opened_by <association> <n>: who opened the issue, as GitHub holds it.
opened_by() {
  node -e '
    const fs = require("fs");
    const [file, association] = process.argv.slice(1);
    const issue = {...JSON.parse(fs.readFileSync(file, "utf8")), author_association: association, user: {login: "stranger"}};
    fs.writeFileSync(file, JSON.stringify(issue));
  ' "$here/issue-$2.json" "$1"
}
for who in NONE CONTRIBUTOR ''; do
  issue_json 3 "$TL_TMP/good.md"
  opened_by "$who" 3
  tl_eq "a body with the five sections by someone outside (${who:-no association}) is not a plan" '1' "$(status_of check 3)"
  tl_has '  and the check says why' 'the body is not a plan: its author (stranger) is not an owner, a member or a collaborator' "$(out)"
  tl_has '  naming what is missing' 'no section `## Approved plan`' "$(out)"
done
tl_eq '--print of it prints no plan' '0' "$("$TRELLIS" issue check 3 --print 2>"$TL_TMP/err.txt" | grep -c .)"
tl_has '  and says why, apart from it' 'the body is not a plan' "$(cat "$TL_TMP/err.txt")"
issue_json 3 "$TL_TMP/good.md" MEMBER "$TL_TMP/plan.md"
opened_by NONE 3
tl_eq 'the same text as an amendment of a member is' '0' "$(status_of check 3)"
tl_has '  and the check says that the body is not' 'the plan is what the amendments carry' "$(out)"
{ amendment 'risks'; printf '### Risks\n\nGates: none\n'; } > "$TL_TMP/a1-only.md"
issue_json 3 "$TL_TMP/good.md" OWNER "$TL_TMP/a1-only.md"
opened_by NONE 3
tl_eq 'an amendment of one section does not make the rest of that body a plan' '1' "$(status_of check 3)"
for who in MEMBER COLLABORATOR; do
  issue_json 3 "$TL_TMP/good.md"
  opened_by "$who" 3
  tl_eq "a body of a $who is a plan" '0' "$(status_of check 3)"
done
{ printf 'A thought first.\n\n'; cat "$TL_TMP/plan.md"; } > "$TL_TMP/buried.md"
issue_json 3 "$TL_TMP/symptom.md" OWNER "$TL_TMP/buried.md"
tl_eq 'a comment that is not headed Amendment is ignored' '1' "$(status_of check 3)"
sed 's/^### Risks$/## Risks/' "$TL_TMP/plan.md" > "$TL_TMP/wrong-level.md"
issue_json 3 "$TL_TMP/symptom.md" OWNER "$TL_TMP/wrong-level.md"
tl_eq 'a section of an amendment is a ### heading' '1' "$(status_of check 3)"
{ amendment 'risks'; printf '### Risks\n\nGates: none. The first risk.\n'; } > "$TL_TMP/a1.md"
{ amendment 'risks again'; printf '### Risks\n\nGates: none. The second risk.\n\n### Notes\n\nStill risks.\n\n## Other\n\nNot risks.\n\nComplexity: L\n'; } > "$TL_TMP/a2.md"
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
# commit_at <date> <path>: a commit on the integration branch, with that date.
commit_at() {
  mkdir -p "$(dirname "$other/$2")"
  echo "$1" >> "$other/$2"
  git -C "$other" add -A
  GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -C "$other" commit -q -m "chore: $2"
  git -C "$other" push -q origin HEAD:develop
}
written_at() { { amendment 'a date'; printf 'The plan holds.\n'; } > "$TL_TMP/dated.md"; issue_json 20 "$TL_TMP/good.md" OWNER "$TL_TMP/dated.md"; }
dated() {
  node -e '
    const fs = require("fs");
    const [dir, created, amended] = process.argv.slice(1);
    const at = (file, set) => { const v = JSON.parse(fs.readFileSync(`${dir}/${file}`)); set(v); fs.writeFileSync(`${dir}/${file}`, JSON.stringify(v)); };
    at("issue-20.json", v => { v.created_at = created; });
    at("comments-20.json", v => { if (amended) v[0].created_at = amended; else v.length = 0; });
  ' "$here" "$@"
}
git -C "$other" pull -q origin develop
commit_at 2040-01-01T00:00:00Z docs/late.md
commit_at 2040-03-01T00:00:00Z lib/a.sh
commit_at 2040-03-02T00:00:00Z lib/not-of-the-plan.sh
written_at
dated 2040-01-15T00:00:00Z
tl_eq 'a path that changed after the plan was written fails nothing' '0' "$(status_of check 20)"
tl_has '  and is printed' 'issue: `lib/a.sh` changed on origin/develop since the plan was written (2040-01-15T00:00:00Z): git diff ' "$(out)"
tl_lacks '  one that changed before is not' '`docs` changed' "$(out)"
tl_lacks '  nor one that is not of the plan' 'not-of-the-plan' "$(out)"
dated 2039-12-01T00:00:00Z
tl_has '  a folder changes with its files' '`docs` changed' "$(status_of check 20; out)"
dated 2039-12-01T00:00:00Z
written_at
dated 2039-12-01T00:00:00Z 2040-02-01T00:00:00Z
status_of check 20 >/dev/null
tl_lacks 'one that changed before the last amendment is not printed' '`docs` changed' "$(out)"
tl_has '  one that changed after it is' '`lib/a.sh` changed on origin/develop since the plan was written (2040-02-01T00:00:00Z)' "$(out)"
dated 2039-12-01T00:00:00Z 2040-04-01T00:00:00Z
tl_lacks 'nor any when the amendment is the last to change' 'changed on' "$(status_of check 20; out)"
git -C "$other" switch -q -c side HEAD~2
GIT_AUTHOR_DATE=2040-01-02T00:00:00Z GIT_COMMITTER_DATE=2040-01-02T00:00:00Z bash -c 'cd "$1" && echo s > lib/b.sh && git add -A && git commit -q -m "chore: side"' _ "$other"
git -C "$other" switch -q develop
GIT_AUTHOR_DATE=2040-05-01T00:00:00Z GIT_COMMITTER_DATE=2040-05-01T00:00:00Z git -C "$other" merge -q --no-ff -m 'Merge the side' side
git -C "$other" push -q origin HEAD:develop
tl_has 'what was committed before the plan and merged after it is printed' '`lib/b.sh` changed' "$(status_of check 20; out)"
dated 1990-01-01T00:00:00Z
tl_has 'every path that is there, when the plan is older than the branch' '`README.md` changed' "$(status_of check 20; out)"
shallow="$TL_TMP/shallow"
git clone -q --depth 1 -b develop "file://$remote" "$shallow"
tl_has 'a shallow clone that does not reach the date says so' 'the clone is shallow' "$(cd "$shallow" && "$TRELLIS" issue check 20 2>&1)"

git config -f trellis.config project.locale es
sed 's/^## /### /; s/^Depende de: .*//' "$TL_TMP/good-es.md" > "$TL_TMP/case.md"
{ printf '## Enmienda (2026-11-24)\n\n'; cat "$TL_TMP/case.md"; } > "$TL_TMP/plan-es.md"
issue_json 7 "$TL_TMP/symptom.md" OWNER "$TL_TMP/plan-es.md"
tl_eq 'es: a plan in an Enmienda passes' '0' "$(status_of check 7)"
git config -f trellis.config --unset project.locale

printf '\nthe gates of a branch\n'
git fetch -q origin
git switch -q -c 21-thing origin/develop
git config -f trellis.config gate.money.paths 'lib/**'
git config -f trellis.config gate.notes.paths 'notes/*.md'
git add -A && git commit -q -m 'chore: gates'
git push -q origin HEAD:develop
git fetch -q origin
issue_json 21 "$TL_TMP/good.md"
tl_eq 'a branch with no commits touches no gate' '0' "$(status_of gates 21)"
tl_eq '  and says so' 'issue gates: ok' "$(out)"
echo z >> README.md
git commit -q -am 'docs: readme'
tl_eq 'a file of no gate' '0' "$(status_of gates 21)"
echo y >> lib/a.sh
tl_eq 'a change that is not committed is not of the branch' '0' "$(status_of gates 21)"
git commit -q -am 'feat: a'
tl_eq 'a file of a gate the plan does not name exits 1' '1' "$(status_of gates 21)"
tl_has '  and is named' '`lib/a.sh` is of the gate money, which the plan does not name' "$(out)"
tl_lacks '  without the files of no gate' 'README.md' "$(out)"
sed 's/^Gates: none\.$/Gates: money/' "$TL_TMP/good.md" > "$TL_TMP/case.md"
issue_json 22 "$TL_TMP/case.md"
tl_eq 'the gate named passes' '0' "$(status_of gates 22)"
{ amendment 'gates'; printf '### Risks\n\nGates: notes\n'; } > "$TL_TMP/a7.md"
issue_json 22 "$TL_TMP/case.md" OWNER "$TL_TMP/a7.md"
tl_eq 'the gates are the ones of the last amendment' '1' "$(status_of gates 22)"
issue_json 22 "$TL_TMP/symptom.md"
tl_eq 'an issue without a plan names none' '1' "$(status_of gates 22)"
git mv lib/a.sh moved.sh
git config -f trellis.config --remove-section gate.money
git commit -q -am 'feat: move'
tl_eq 'a file moved out of a gate, in a branch that takes the gate out' '1' "$(status_of gates 21)"
tl_has '  still answers to the gate of the integration branch' '`lib/a.sh` is of the gate money' "$(out)"
tl_eq 'no number' '2' "$(status_of gates)"
tl_eq 'two numbers' '2' "$(status_of gates 21 22)"
tl_eq 'an issue gh cannot read' '1' "$(status_of gates 404)"
git config -f trellis.config git.integrationBranch nowhere
tl_eq 'an integration branch that is not known' '1' "$(status_of gates 21)"
tl_has '  which it says' 'are not known against origin/nowhere' "$(out)"
tl_has 'the usage of trellis lists gates' 'issue gates <n>' "$("$TRELLIS" help 2>&1)"
git checkout -q -- trellis.config
git switch -q main
git branch -q -D 21-thing
git -C "$other" pull -q origin develop
git -C "$other" revert --no-edit HEAD >/dev/null
git -C "$other" push -q origin HEAD:develop
git fetch -q origin

printf '\nclaim\n'
calls() { cat "$GH_FIXTURES/calls.log" 2>/dev/null; }
writes() { cat "$GH_FIXTURES/writes.log" 2>/dev/null; }
# claim_of <n> [<flags>]: a claim with a clean log.
claim_of() { rm -f "$GH_FIXTURES"/calls.log "$GH_FIXTURES"/writes.log; status_of claim "$@"; }
# facts <n> <javascript>: changes the issue, `i`.
facts() { node -e 'const fs = require("fs"); const [f, js] = process.argv.slice(1); const i = JSON.parse(fs.readFileSync(f)); eval(js); fs.writeFileSync(f, JSON.stringify(i));' "$here/issue-$1.json" "$2"; }
assignees() { node -p 'JSON.parse(require("fs").readFileSync(process.argv[1])).assignees.map(a => a.login).join(" ")' "$here/issue-$1.json"; }
issue_json 30 "$TL_TMP/good.md"
tl_eq 'a claim of a free issue' '0' "$(claim_of 30)"
tl_eq '  assigns the account it asks as' 'rologr35' "$(assignees 30)"
tl_has '  and says so' 'issue claim: #30 is assigned to rologr35' "$(out)"
tl_eq '  with no other write' 'POST issues/30/assignees assignees=rologr35' "$(writes)"
tl_eq '  and the issue read again after it' '2' "$(calls | grep -c 'api|repos/{owner}/{repo}/issues/30|')"
tl_eq 'a claim of its own issue is refused' '1' "$(claim_of 30)"
tl_has '  which it says' 'it is assigned to rologr35' "$(out)"
tl_eq '  and writes nothing' '' "$(writes)"
tl_eq '--resume accepts it' '0' "$(claim_of 30 --resume)"
tl_eq '  and writes nothing' '' "$(writes)"
facts 30 'i.assignees = [{login: "other"}]'
for flags in '' --resume; do
  # shellcheck disable=SC2086
  tl_eq "an issue of another account is refused ($flags)" '1' "$(claim_of 30 $flags)"
  tl_has '  naming it' 'it is assigned to other' "$(out)"
done
facts 30 'i.assignees = [{login: "other"}, {login: "rologr35"}]'
tl_eq 'and one of two accounts, its own among them' '1' "$(claim_of 30 --resume)"
facts 30 'i.assignees = []; i.state = "closed"'
tl_eq 'a closed issue is refused' '1' "$(claim_of 30)"
tl_has '  which it says' 'it is closed' "$(out)"
facts 30 'i.state = "open"; i.pull_request = {}'
tl_eq 'a pull request is refused' '1' "$(claim_of 30)"
tl_has '  which it says' 'it is a pull request' "$(out)"
facts 30 'delete i.pull_request'
git push -q origin origin/develop:refs/heads/30-thing
tl_eq 'an issue with its branch on origin is refused' '1' "$(claim_of 30)"
tl_has '  naming it' 'origin has its branch: 30-thing' "$(out)"
tl_eq '--resume of a branch that is nobody'"'"'s is refused too' '1' "$(claim_of 30 --resume)"
facts 30 'i.assignees = [{login: "RoloGR35"}]'
tl_eq '--resume accepts the branch of its own issue, whatever the case of the account' '0' "$(claim_of 30 --resume)"
tl_has '  and says how it is checked out' 'its branch on origin: 30-thing (trellis worktree add 30 <slug> --resume)' "$(out)"
facts 30 'i.labels = [{name: "stopped"}]'
tl_eq 'a stopped issue is refused' '1' "$(claim_of 30)"
tl_has '  naming --resume' 'it is stopped: --resume takes it' "$(out)"
tl_eq '--resume takes it' '0' "$(claim_of 30 --resume)"
tl_eq '  and takes the label off' 'DELETE issues/30/labels/stopped' "$(writes)"
facts 30 'i.labels = [{name: "stopped"}]; i.assignees = []'
tl_eq '--resume takes a stopped issue nobody is assigned to, with its branch' '0' "$(claim_of 30 --resume)"
tl_eq '  assigning it' 'rologr35' "$(assignees 30)"
tl_has '  and with the label off' 'DELETE issues/30/labels/stopped' "$(writes)"
facts 30 'i.labels = [{name: "stopped"}]; i.assignees = [{login: "other"}]'
tl_eq 'but not a stopped issue of another account' '1' "$(claim_of 30 --resume)"
git push -q origin :refs/heads/30-thing
git push -q origin origin/develop:refs/heads/300-thing
facts 30 'i.labels = []; i.assignees = []'
tl_eq 'a branch of another number does not count' '0' "$(claim_of 30)"
git push -q origin :refs/heads/300-thing
issue_json 31 "$TL_TMP/good.md"
printf 'other\n' > "$GH_FIXTURES/race"
tl_eq 'with another assignee after the assignment it refuses' '1' "$(claim_of 31)"
tl_eq '  and takes itself off' 'other' "$(assignees 31)"
tl_has '  which it says' 'after the assignment it is of other rologr35' "$(out)"
rm "$GH_FIXTURES/race"
issue_json 31 "$TL_TMP/good.md"
touch "$GH_FIXTURES/assign-ignored"
tl_eq 'an assignment GitHub does not take refuses' '1' "$(claim_of 31)"
tl_has '  which it says' 'it is of nobody' "$(out)"
rm "$GH_FIXTURES/assign-ignored"
touch "$GH_FIXTURES/assign-fails"
tl_eq 'an assignment that fails refuses' '1' "$(claim_of 31)"
tl_has '  with the error of gh' 'no assign for you' "$(out)"
rm "$GH_FIXTURES/assign-fails"
issue_json 31 "$TL_TMP/symptom.md"
tl_eq 'a plan that does not pass the check is refused' '1' "$(claim_of 31)"
tl_has '  which it says' '#31 is not claimed: its plan does not pass the check' "$(out)"
tl_eq '  with nothing written' '' "$(writes)"
git config -f trellis.config gate.notes.paths 'notes/*.md'
sed 's/^Gates: none\.$/Gates: notes/' "$TL_TMP/good.md" > "$TL_TMP/gated.md"
issue_json 32 "$TL_TMP/gated.md"
tl_eq '--unattended refuses a plan with a gate' '1' "$(claim_of 32 --unattended)"
tl_has '  naming it' 'a run without a person cannot take it: Gates: notes' "$(out)"
tl_eq '  and assigns nobody' '' "$(assignees 32)"
tl_eq 'which a person takes' '0' "$(claim_of 32)"
git config -f trellis.config --remove-section gate.notes
for needs in 'Needs: a key of the store' '- **Needs**: a step of a person' 'Needs:\
\
- a key of the store'; do
  sed "s/^Gates: none\.\$/Gates: none.\\
\\
$needs/" "$TL_TMP/good.md" > "$TL_TMP/case.md"
  issue_json 32 "$TL_TMP/case.md"
  tl_eq "--unattended refuses a plan with Needs ($(printf '%s' "$needs" | head -n 1))" '1' "$(claim_of 32 --unattended)"
  tl_has '  naming it' 'cannot take it: Needs: ' "$(out)"
done
sed 's/^Gates: none\.$/Gates: none.\
\
Needs: none/' "$TL_TMP/good.md" > "$TL_TMP/case.md"
issue_json 32 "$TL_TMP/case.md"
tl_eq '--unattended takes a plan with none of both' '0' "$(claim_of 32 --unattended)"
tl_eq 'no number' '2' "$(claim_of --resume)"
tl_eq 'a flag it does not know' '2' "$(claim_of 32 --force)"
tl_eq 'an issue gh cannot read' '1' "$(claim_of 404)"
issue_json 33 "$TL_TMP/good.md"
git remote set-url origin "$TL_TMP/no-such-remote"
tl_eq 'an origin that does not answer is refused' '1' "$(claim_of 33)"
tl_has '  which it says' 'origin could not be asked for its branch' "$(out)"
git remote set-url origin "$remote"
tl_has 'the usage of trellis lists claim' 'issue claim <n> [--unattended] [--resume]' "$("$TRELLIS" help 2>&1)"

printf '\ncreate\n'
calls() { cat "$GH_FIXTURES/calls.log" 2>/dev/null; }
# Runs a create with a clean log.
create_of() { rm -f "$GH_FIXTURES"/calls.log "$GH_FIXTURES"/writes.log "$GH_FIXTURES"/created*; status_of create "$@"; }
writes() { cat "$GH_FIXTURES/writes.log" 2>/dev/null; }
printf 'bug\nM\n' > "$GH_FIXTURES/labels"
tl_eq 'a good body is created' '0' "$(create_of --title 'A flag for x' --body-file "$TL_TMP/good.md")"
tl_eq '  and only its URL is printed' 'https://github.com/rologr35/fixture/issues/12' "$(out)"
tl_has '  with the label of its complexity line' 'labels=M' "$(writes)"
tl_has '  and its title' 'POST issues title=A flag for x ' "$(writes)"
tl_lacks '  the label exists, so none is created' 'POST labels' "$(writes)"
tl_eq '  the body is the one of the file' '' "$(diff "$TL_TMP/good.md" "$GH_FIXTURES/created-body" 2>&1)"
for class in S L; do
  sed "s/^Complexity: M/Complexity: $class/" "$TL_TMP/good.md" > "$TL_TMP/case.md"
  tl_eq "a body of class $class is created" '0' "$(create_of --title x --body-file "$TL_TMP/case.md")"
  tl_has '  its label is created first' "POST labels name=$class color=" "$(head -n 1 "$GH_FIXTURES/writes.log")"
  tl_has '  and used' "labels=$class" "$(tail -n 1 "$GH_FIXTURES/writes.log")"
done
printf 'm\n' > "$GH_FIXTURES/labels"
tl_eq 'a label in lower case is the same label' '0' "$(create_of --title x --body-file "$TL_TMP/good.md")"
tl_lacks '  and is not created again' 'POST labels' "$(writes)"
printf 'bug\n' > "$GH_FIXTURES/labels"
(cd "$TL_TMP" && cp good.md "$repo/relative.md")
tl_eq 'a relative body file, the flags with = and in another order' '0' "$(create_of --body-file=relative.md --title='With = sign')"
tl_has '  keep the title' 'title=With = sign ' "$(writes)"
tl_eq '  and the body' '' "$(diff relative.md "$GH_FIXTURES/created-body" 2>&1)"
rm -f relative.md
sed 's/^Complexity: M//' "$TL_TMP/good.md" > "$TL_TMP/case.md"
tl_eq 'a body that fails the check is not created' '1' "$(create_of --title x --body-file "$TL_TMP/case.md")"
tl_has '  it says why' 'last line is not' "$(out)"
tl_eq '  and makes no gh call' '' "$(calls)"
printf 'bug\n' > "$GH_FIXTURES/labels"; touch "$GH_FIXTURES/label-fails"
tl_eq 'a label that cannot be created fails' '1' "$(create_of --title x --body-file "$TL_TMP/good.md")"
tl_has '  with the error of gh' 'no label for you' "$(out)"
tl_lacks '  and no issue is created' 'POST issues' "$(writes)"
rm "$GH_FIXTURES/label-fails" "$GH_FIXTURES/labels"
tl_eq 'labels that cannot be read fail' '1' "$(create_of --title x --body-file "$TL_TMP/good.md")"
tl_lacks '  and no issue is created' 'POST issues' "$(writes)"
printf 'M\n' > "$GH_FIXTURES/labels"
touch "$GH_FIXTURES/create-fails"
tl_eq 'an issue that cannot be created fails' '1' "$(create_of --title x --body-file "$TL_TMP/good.md")"
tl_has '  with the error of gh' 'no create for you' "$(out)"
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
tl_has '  and creates as its owner' 'token=token-of-rologr35' "$(calls | grep '/issues|-f|title')"
tl_has '  without origin reached, it says the last fetch judged' 'judged by the last fetch' "$(out)"
tl_lacks '  the token is not printed' 'token-of-rologr35' "$(out)"
unset GIT_ALLOW_PROTOCOL
git remote set-url origin "$remote"

printf '\nclose\n'
# pr_json <n> <state> <base> <body line>...: a pull request of rologr35/fixture as GitHub holds it.
pr_json() {
  local n="$1" state="$2" base="$3"
  shift 3
  node -e '
    const [out, n, state, base, ...lines] = process.argv.slice(1);
    const merged = state === "merged";
    require("fs").writeFileSync(out, JSON.stringify({number: Number(n), html_url: `https://github.com/rologr35/fixture/pull/${n}`, state: merged ? "closed" : state, merged, base: {ref: base}, body: lines.join("\n")}));
  ' "$here/pr-$n.json" "$n" "$state" "$base" "$@"
}
# issue_of <n> <state> [<url>] [<comments>]: an issue without labels, nor comments unless given.
issue_of() {
  printf '{"number":%s,"html_url":"%s","state":"%s","labels":[]}' "$1" \
    "${3:-https://github.com/rologr35/fixture/issues/$1}" "$2" > "$here/issue-$1.json"
  printf '%s' "${4:-[]}" > "$here/comments-$1.json"
}
close_of() { rm -f "$GH_FIXTURES/calls.log" "$GH_FIXTURES/writes.log"; status_of close "$@"; }
json_of() { node -p "const o = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); $2" "$here/$1.json"; }
state_is() { json_of "issue-$1" 'o.state'; }
labels_of() { json_of "issue-$1" 'o.labels.map(l => l.name).join()'; }
comments_of() { json_of "comments-$1" 'o.map(c => c.body).join("\n====\n")'; }
count_of() { json_of "comments-$1" 'o.length'; }
CLOSE='PATCH issues/12 state=closed'
printf 'M\n' > "$GH_FIXTURES/labels"

pr_json 40 merged develop 'Closes #12' '' '**After merging**' 'none'
issue_of 12 open
tl_eq 'merged into the integration branch' '0' "$(close_of 40)"
tl_eq '  closes the issue and writes nothing else' "$CLOSE" "$(writes)"
tl_eq '  which is closed' 'closed' "$(state_is 12)"
tl_eq 'again' '0' "$(close_of 40)"
tl_eq '  writes nothing' '' "$(writes)"
issue_of 12 open
tl_eq 'with the # of the pull request' '0' "$(close_of '#40')"
tl_eq '  closes it' 'closed' "$(state_is 12)"
pr_json 40 merged develop 'Closes #12'
issue_of 12 open
tl_eq 'a body without the section has nothing pending' '0' "$(close_of 40)"
tl_eq '  and closes it' "$CLOSE" "$(writes)"

for case in 'open develop' 'closed develop' 'merged main'; do
  # shellcheck disable=SC2086
  pr_json 40 $case 'Closes #12' '' '**After merging**' '- Tag it.'
  issue_of 12 open
  tl_eq "refuses a pull request $case" '1' "$(close_of 40)"
  tl_eq '  and writes nothing' '' "$(writes)"
  tl_eq '  nor with --done' '1' "$(close_of 40 --done)"
  tl_eq '  and writes nothing' '' "$(writes)"
done
tl_has '  it names the branch' 'develop' "$(out)"

nothing() {
  pr_json 40 merged develop "${@:2}"
  issue_of 12 open
  tl_eq "nothing to close: $1" '0' "$(close_of 40)"
  tl_eq '  and it writes nothing' '' "$(writes)"
}
nothing 'another repository' 'Closes rologr35/x#12'
nothing 'the URL of another repository' 'Closes https://github.com/rologr35/x/issues/12'
nothing 'a fence' '```' 'Closes #12' '```'
nothing 'a fence of tildes' '~~~' 'Closes #12' '~~~'
nothing 'a fence that is not closed' '```' 'Closes #12'
nothing 'an indented block' 'Text.' '' '    Closes #12'
nothing 'an inline span' 'Write `Closes #12`.'
nothing 'a comment' '<!-- Closes #12 -->'
nothing 'a reference that does not close' 'See #12'
nothing 'no body' ''
pr_json 40 merged develop 'Closes #13'
issue_of 13 open 'https://github.com/rologr35/fixture/pull/13'
tl_eq 'the number of a pull request' '0' "$(close_of 40)"
tl_eq '  is skipped' '' "$(writes)"
issue_of 13 open 'https://github.com/rologr35/x/issues/4'
tl_eq 'an issue moved to another repository' '0' "$(close_of 40)"
tl_eq '  is skipped' '' "$(writes)"
for text in 'Closes rologr35/Fixture#12' 'closes: #12' 'Fixes https://github.com/rologr35/fixture/issues/12' '- Text' ; do
  pr_json 40 merged develop "$text" '' '  - Resolved #12'
  issue_of 12 open
  tl_eq "closes: $text" '0' "$(close_of 40)"
  tl_eq '  once' "$CLOSE" "$(writes)"
done
pr_json 40 merged develop 'Closes #12, closes #14'
issue_of 12 open; issue_of 14 open
tl_eq 'two issues' '0' "$(close_of 40)"
tl_eq '  are both closed' 'closed closed' "$(state_is 12) $(state_is 14)"

PENDING=('Closes #12' '' '## After merging' '' '- [ ] Tag it.' '  - as v1 <!-- hidden -->' '- Run `trellis doctor`.' '' '## Verification' 'ok')
pr_json 40 merged develop "${PENDING[@]}"
issue_of 12 open
tl_eq 'with actions pending' '0' "$(close_of 40)"
tl_eq '  creates the label, labels, comments and closes, in that order' \
  "POST labels name=pending-actions color=D93F0B description=Merged with actions pending
POST issues/12/labels labels=pending-actions
POST issues/12/comments body
$CLOSE" "$(writes)"
tl_has '  the comment opens with the mark' '<!-- trellis:pending-actions pr=40 -->' "$(comments_of 12 | head -1)"
tl_has '  it has the actions as they are written' '  - as v1' "$(comments_of 12)"
tl_has '  and the code of them' 'Run `trellis doctor`.' "$(comments_of 12)"
tl_lacks '  not what is hidden' 'hidden' "$(comments_of 12)"
tl_lacks '  nor the next section' 'Verification' "$(comments_of 12)"
tl_eq 'again' '0' "$(close_of 40)"
tl_eq '  writes nothing' '' "$(writes)"
tl_eq '  one comment and the label remain' '1 pending-actions' "$(count_of 12) $(labels_of 12)"
printf 'M\nPending-Actions\n' > "$GH_FIXTURES/labels"
tl_eq 'done' '0' "$(close_of 40 --done)"
tl_eq '  takes the label off and writes nothing else' 'DELETE issues/12/labels/pending-actions' "$(writes)"
tl_eq 'done, before the number, again' '0' "$(close_of --done 40)"
tl_eq '  writes nothing' '' "$(writes)"
tl_eq 'a rerun after done' '0' "$(close_of 40)"
tl_eq '  does not put the label back' '' "$(writes)"
issue_of 12 closed
tl_eq 'an issue that is closed already' '0' "$(close_of 40)"
tl_eq '  gets the label and the comment' '1 pending-actions' "$(count_of 12) $(labels_of 12)"
tl_lacks '  and no close' 'PATCH' "$(writes)"
pr_json 41 merged develop "${PENDING[@]}"
tl_eq 'another pull request of the same issue' '0' "$(close_of 41)"
tl_eq '  has its own comment' '2' "$(count_of 12)"
issue_of 12 open '' '[{"user":{"login":"x"},"author_association":"NONE","body":"<!-- trellis:pending-actions pr=40 -->"},{"user":{"login":"y"},"author_association":"OWNER","body":"quoted: <!-- trellis:pending-actions pr=40 -->"}]'
tl_eq 'the mark of someone outside, or inside a text' '0' "$(close_of 40)"
tl_eq '  is not the mark' '3' "$(count_of 12)"
issue_of 12 open '' '[{"user":{"login":"github-actions[bot]"},"author_association":"NONE","body":"<!-- trellis:pending-actions pr=40 -->"}]'
tl_eq 'the mark of the workflow' '0' "$(close_of 40)"
tl_eq '  is the mark' "$CLOSE" "$(writes)"
pr_json 40 merged develop 'Closes #12' '' '**After merging**: tag it'
issue_of 12 open
tl_eq 'actions written as prose' '0' "$(close_of 40)"
tl_has '  are pending too' 'tag it' "$(comments_of 12)"

pr_json 40 merged develop "${PENDING[@]}"
for verb in edit comment; do
  issue_of 12 open
  touch "$GH_FIXTURES/$verb-fails"
  tl_eq "a failure of the $verb fails" '1' "$(close_of 40)"
  tl_eq '  and leaves it open' 'open' "$(state_is 12)"
  tl_has '  with the error of gh' "no $verb for you" "$(out)"
  rm "$GH_FIXTURES/$verb-fails"
  tl_eq '  the rerun ends it' '0' "$(close_of 40)"
  tl_eq '  with one comment and the label' 'closed 1 pending-actions' "$(state_is 12) $(count_of 12) $(labels_of 12)"
done
issue_of 12 open
touch "$GH_FIXTURES/close-fails"
tl_eq 'a failure of the close fails' '1' "$(close_of 40)"
rm "$GH_FIXTURES/close-fails"
tl_eq '  and the rerun only closes' '0' "$(close_of 40)"
tl_eq '  it' "$CLOSE" "$(writes)"
pr_json 40 merged develop 'Closes #99, closes #12'
issue_of 12 open
tl_eq 'an issue that cannot be read fails' '1' "$(close_of 40)"
tl_has '  it is named' '#99' "$(out)"
tl_eq '  and the next one is still closed' 'closed' "$(state_is 12)"
rm "$here/issue-12.json"
tl_eq 'a pull request that cannot be read fails' '1' "$(close_of 77)"
tl_has '  with the error of gh' 'Not Found (HTTP 404)' "$(out)"
echo 'x' > "$here/pr-78.json"
tl_eq 'an answer that does not parse fails' '1' "$(close_of 78)"
pr_json 40 merged develop '**After merging**' '- Tag it.'
tl_eq 'actions pending without an issue' '0' "$(close_of 40)"
tl_has '  it says where they are' 'no issue' "$(out)"
printf '[project]\n\tlocale = es\n[git]\n\tintegrationBranch = develop\n' > trellis.config
pr_json 40 merged develop 'Closes #12' '' '**Después de mezclar**' '- Poner el tag.'
issue_of 12 open
tl_eq 'es: the section of the locale' '0' "$(close_of 40)"
tl_has '  es: its actions' 'Poner el tag.' "$(comments_of 12)"
tl_has '  es: under its words' 'Pendiente tras mezclar #40' "$(comments_of 12)"
git config -f trellis.config --unset project.locale
git remote set-url origin https://github.com/rologr35/fixture.git
pr_json 40 merged develop "${PENDING[@]}"
issue_of 12 open
tl_eq 'a repository whose owner is signed in' '0' "$(close_of 40)"
tl_lacks '  asks and writes nothing as another account' 'token=none' "$(calls | grep -v '^auth')"
git remote set-url origin "$remote"
for wrong in '' 'abc' '40 41' '40 --force'; do
  # shellcheck disable=SC2086
  tl_eq "a wrong use: close $wrong" '2' "$(close_of $wrong)"
done
tl_has 'the usage of trellis lists close' 'trellis issue close <pr> [--done]' "$("$TRELLIS" help 2>&1)"
git config -f trellis.config tracker.kind none
tl_eq 'tracker.kind = none exits 2' '2' "$(close_of 40)"
tl_eq '  with no gh call' '' "$(calls)"
git config -f trellis.config --unset tracker.kind

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
