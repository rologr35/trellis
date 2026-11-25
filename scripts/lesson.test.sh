#!/usr/bin/env bash
# Exercises scripts/lesson.sh with a fake gh on the PATH: what a lesson is, the private names it may not
# have, the proposal and its digest, and what is published in the upstream.
. "$(dirname "$0")/../lib/testlib.sh"

# gh answers only `api`, from files: <owner>_<repo>/issue-<n>.json, `labels`, and `repo.json` for what
# GitHub says of a repository. Each call is logged with the token it ran with, each write with its fields
# in writes.log and its body in `body`. A file <what>-fails makes that write fail.
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
    fields[key] = value;
  } else if (a === '--paginate') continue;
  else if (a.startsWith('-')) stop(`unknown flag: ${a}`);
  else endpoint = a;
}
method ||= Object.keys(fields).length ? 'POST' : 'GET';
const refused = (code, text) => { console.log(JSON.stringify({message: text})); stop(`gh: ${text} (HTTP ${code})`); };
const print = value => { console.log(String(value)); process.exit(0); };
const failing = what => { if (read(`${what}-fails`) !== null) refused(403, `no ${what} for you`); };
const [path] = endpoint.split('?');
if (path === 'search/issues') {
  failing('search');
  if (fields.q !== 'repo:trellis-org/trellis is:issue guard push') stop(`unexpected search: ${fields.q}`);
  const items = JSON.parse(read('search.json') ?? '[]');
  print([`${items.length} match(es)`, ...items.map(i => `#${i.number} ${i.state} ${i.title}`)].join('\n'));
}
const [, repo, rest = ''] = /^repos\/([^/]+\/[^/]+)(?:\/(.*))?$/.exec(path) || [];
if (!repo) stop(`unexpected call: ${endpoint}`);
const at = `${repo.replace('/', '_')}`;
if (method === 'GET' && rest === '' && jq === '.private') {
  const text = read(`${at}/repo.json`);
  if (text === null) refused(404, 'Not Found');
  print(JSON.parse(text).private);
}
if (repo !== 'trellis-org/trellis') stop(`unexpected call: ${method} ${endpoint}`);
if (method !== 'GET') {
  const shown = Object.keys(fields).map(k => k === 'body' ? 'body' : `${k}=${fields[k]}`).join(' ');
  fs.appendFileSync(`${dir}/writes.log`, `${method} ${rest} ${shown}\n`);
  if (fields.body !== undefined) fs.writeFileSync(`${dir}/body`, fields.body);
}
let m;
if (method === 'GET' && rest === 'labels') {
  failing('labels');
  print((read(`${at}/labels`) ?? '').trim());
}
if (method === 'POST' && rest === 'labels') { failing('label'); fs.appendFileSync(`${dir}/${at}/labels`, `${fields.name}\n`); print('{}'); }
if (method === 'POST' && rest === 'issues') {
  failing('create');
  print(`${read('drops-labels') === null ? 'labeled' : 'unlabeled'} https://github.com/trellis-org/trellis/issues/12`);
}
if ((m = /^issues\/(\d+)$/.exec(rest))) {
  const text = read(`${at}/issue-${m[1]}.json`);
  if (text === null) refused(404, 'Not Found');
  const issue = JSON.parse(text);
  if (method === 'PATCH') { failing('reopen'); print('{}'); }
  print(`${issue.state} ${issue.pull_request ? 'pull' : 'issue'} ${issue.title}`);
}
if (method === 'POST' && (m = /^issues\/(\d+)\/comments$/.exec(rest))) {
  failing('comment');
  print(`https://github.com/trellis-org/trellis/issues/${m[1]}#issuecomment-1`);
}
stop(`unexpected call: ${method} ${endpoint}`);
GH
chmod +x "$stubs/gh"
PATH="$stubs:$PATH"
export GH_FIXTURES="$TL_TMP/gh"
there="$GH_FIXTURES/trellis-org_trellis"
mkdir -p "$there" "$GH_FIXTURES/zephyr-co_ledger"
printf 'tok-there' > "$GH_FIXTURES/token-trellis-org"
printf 'tok-here' > "$GH_FIXTURES/token-zephyr-co"
printf '{"private": false}' > "$GH_FIXTURES/zephyr-co_ledger/repo.json"
printf 'bug\n' > "$there/labels"
printf '{"state": "open", "title": "The guard reads -R"}' > "$there/issue-7.json"
printf '{"state": "closed", "title": "The guard reads -C"}' > "$there/issue-8.json"
printf '{"state": "open", "title": "A change", "pull_request": {}}' > "$there/issue-9.json"

# The folder of the project is a name of its own, so it is not the one of a word of the lesson.
mkdir -p "$HOME/code" && git clone -q "$(tl_repo)" "$HOME/code/zephyr-app" 2>/dev/null
cd "$HOME/code/zephyr-app" || exit 1
git remote set-url origin https://github.com/zephyr-co/ledger.git
mkdir -p src/billing docs && printf 'x\n' > src/billing/invoice.ts && printf 'x\n' > docs/a.md && printf 'x\n' > Makefile
mkdir -p .githooks && printf 'x\n' > .githooks/pre-push
cat > trellis.config <<'CFG'
[project]
	name = Tienda Azul
[trellis]
	upstream = trellis-org/trellis
CFG
git add -A && git commit -qm 'chore: start (#1)'
list="$HOME/.config/trellis/private-names"

body="$TL_TMP/body.md"
good() {
  cat > "$body" <<'MD'
Kind: defect

## Incident

The guard let this one through:

```
git push -o x origin
```

## What must stop happening

A push with an option is judged as one without.
MD
}
good
title='guard: a push with an option is not judged'
lesson() { bash "$TRELLIS" lesson "$@" > "$TL_TMP/out.txt" 2>&1; echo $?; }
propose() { lesson --title "$title" --body-file "$body" --search 'guard push' "$@"; }
out() { cat "$TL_TMP/out.txt"; }
writes() { cat "$GH_FIXTURES/writes.log" 2>/dev/null; rm -f "$GH_FIXTURES/writes.log"; }
digest() { propose "$@" > /dev/null; sed -n 's/^Digest: //p' "$TL_TMP/out.txt"; }
# refused <name> <text of the miss>: the body of now is refused with it and nothing is asked.
refused() {
  tl_eq "$1" '1' "$(rm -f "$GH_FIXTURES/calls.log"; propose)"
  tl_has '  saying it' "$2" "$(out)"
  tl_lacks '  and GitHub is not asked' 'search/issues' "$(cat "$GH_FIXTURES/calls.log" 2>/dev/null)"
}
# with <text>: the good body with the text at its end.
with() { good; printf '\n%s\n' "$1" >> "$body"; }

printf '\nits use\n'
tl_eq 'no title' '2' "$(lesson --body-file "$body" --search x)"
tl_eq 'no search' '2' "$(lesson --title x --body-file "$body")"
tl_eq 'a file that is not there' '2' "$(lesson --title x --body-file nowhere.md --search x)"
tl_eq '--reopen without --issue' '2' "$(propose --reopen)"
tl_eq 'an issue that is no number' '2' "$(propose --issue 7x)"
tl_eq 'an unknown flag' '2' "$(propose --force)"

printf '\nwhat a lesson is\n'
sed -i.bak 's/^Kind: defect$//' "$body"; refused 'no kind' 'Kind: defect or Kind: rule'
good; sed -i.bak 's/^Kind: defect$/Kind: idea/' "$body"; refused 'another kind' 'Kind: defect or Kind: rule'
with 'Kind: rule'; refused 'two kinds' 'Kind: defect or Kind: rule'
good; sed -i.bak 's/^Kind: defect$/`Kind: defect`/' "$body"; refused 'one in code' 'Kind: defect or Kind: rule'
good; sed -i.bak '/^## Incident/,/^```$/d' "$body"; refused 'no incident' 'the section **Incident** is missing or empty'
good; sed -i.bak '/^A push with/d' "$body"; refused 'an empty section' 'the section **What must stop happening** is missing or empty'
good; sed -i.bak 's/^A push with.*/<!-- to write -->/' "$body"; refused 'one with a comment only' 'the section **What must stop happening** is missing or empty'
good; sed -i.bak '/^```$/d' "$body"; refused 'a defect without its case' 'a defect brings its case in **Incident**'
good; sed -i.bak -e '/^```$/,/^```$/d' "$body"; printf '\n```\nsomewhere else\n```\n' >> "$body"; refused 'or with it elsewhere' 'a defect brings its case in **Incident**'
good; sed -i.bak -e '/^```$/,/^```$/d' -e 's/^Kind: defect/Kind: rule/' "$body"
tl_eq 'a rule needs none' '4' "$(propose)"
good; sed -i.bak 's/judged as/judged — as/' "$body"; refused 'the style of the body' 'has a long dash'
with 'The one of #41.'; refused 'a bare reference' 'bare #41'
git config -f trellis.config style.bareReference allow
refused '  also in a project with bare references' 'bare #41'
git config -f trellis.config --unset style.bareReference
good; title='guard — a push'; refused 'the style of the title' 'title: has a long dash'
title='guard: a push with an option is not judged'

printf '\nthe private names of the project\n'
for term in 'Tienda Azul' 'tienda-azul' 'TIENDAAZUL' 'zephyr-co' 'ZephyrCo' 'zephyr_co' 'ledger' 'Ledger' 'src/billing/invoice.ts' 'SRC/billing/invoice.ts' 'docs/a.md' "$HOME" "$(pwd)" '~/code/zephyr-app'; do
  with "It was in $term there."
  refused "$term" 'line 15: "'
done
with 'It was in the Makefile, in .githooks/pre-push and in trellis.config.'
tl_eq 'a file with no folder and what trellis writes are none' '4' "$(propose)"
with 'See zephyr-labs/engine#4.'; refused 'a reference to another repository' 'line 15: "zephyr-labs/engine#4"'
with 'See https://github.com/zephyr-labs/engine/pull/4.'; refused 'the URL of one' 'line 15: "github.com/zephyr-labs/engine"'
with 'See https://raw.githubusercontent.com/zephyr-labs/engine/main/a.md.'; refused 'the one of a file of it' 'line 15: "raw.githubusercontent.com/zephyr-labs/engine"'
with 'See ssh://git@ssh.github.com:443/zephyr-labs/engine.git.'; refused 'the one of ssh by its other port' 'line 15: "ssh.github.com:443/zephyr-labs/engine'
for host in gist.github.com gist.githubusercontent.com; do
  with "See https://$host/zephyr-labs/0123abcd."; refused "a gist of another owner, in $host" "line 15: \"$host/zephyr-labs\" is a gist of another owner"
done
with 'See https://gist.github.com/Trellis-Org/0123abcd and https://raw.githubusercontent.com/trellis-org/trellis/main/a.md.'
tl_eq 'the ones of the upstream are none, in those too' '4' "$(propose)"
with 'See https://raw.githubusercontent.com/trellis-org/other/main/a.md.'; refused 'another repository of its owner is one' 'trellis-org/other'
with 'See trellis-org/trellis#4 and https://github.com/trellis-org/trellis/issues/4.'
tl_eq 'the ones of the upstream are none' '4' "$(propose)"
good; title='guard: a push of tienda azul'
refused 'one in the title' 'title: "Tienda Azul" is the name of the project'
title='guard: a push with an option is not judged'
good; printf '\nOf ledger.\nOf zephyr-co.\n' >> "$body"; refused 'each one is named with its line' 'line 15: "ledger"'
tl_has '  the other too' 'line 16: "zephyr-co"' "$(out)"
git remote set-url origin https://github.com/trellis-org/ledger.git
mkdir -p "$GH_FIXTURES/trellis-org_ledger" && printf '{"private": false}' > "$GH_FIXTURES/trellis-org_ledger/repo.json"
with 'The trellis-org of it.'
tl_eq 'an owner shared with the upstream is none' '4' "$(propose)"
with 'The ledger of it.'
tl_eq '  and the name of the repository still is' '1' "$(propose)"
git remote set-url origin https://github.com/zephyr-co/ledger.git

printf '\nthe ones of the machine\n'
mkdir -p "$(dirname "$list")" && printf 'acme\n' > "$list"
with 'As Acme did.'; refused 'a term of the list' 'line 15: "acme" is a private name of this machine'
tl_eq '  in a project that is not public' '' "$(git config -f trellis.config project.public)"
rm "$list" && mkdir "$list"
good; refused 'a list that cannot be read' 'cannot be read'
rmdir "$list"

printf '\na private repository\n'
good
tl_eq 'a public one publishes with no list' '4' "$(propose)"
for answer in '{"private": true}' '{"private": null}' ''; do
  printf '%s' "$answer" > "$GH_FIXTURES/zephyr-co_ledger/repo.json"
  [ -n "$answer" ] || rm "$GH_FIXTURES/zephyr-co_ledger/repo.json"
  what="${answer:-one that cannot be asked}"
  rm -f "$list"
  refused "$what, with no list" 'has neither the name of the project (Tienda Azul) nor the one of its repository (ledger)'
  printf 'acme\n' > "$list"
  refused "$what, with one that does not name it" 'has neither the name of the project'
  printf 'acme\ntienda-azul\n' > "$list"
  tl_eq "$what, with one that has its name" '4' "$(propose)"
  printf 'Ledger\n' > "$list"
  tl_eq "$what, with one that has the one of its repository" '4' "$(propose)"
done
rm -f "$list"
git remote set-url origin "$TL_TMP/zephyr-co/ledger"
printf '{"private": false}' > "$GH_FIXTURES/zephyr-co_ledger/repo.json"
refused 'an origin that is a path cannot be asked' 'has neither the name of the project'
git remote set-url origin zephyr-co/ledger
refused '  nor one that looks like a repository' 'has neither the name of the project'
GH_REPO=zephyr-co/ledger
export GH_REPO
refused '  and GH_REPO does not stand in for it' 'has neither the name of the project'
unset GH_REPO
git remote set-url origin git@work:zephyr-co/ledger.git
refused 'nor can an alias of ssh' 'has neither the name of the project'
git remote remove origin
refused 'nor can a project with no origin' 'has neither the name of the project'
git remote add origin https://github.com/zephyr-co/ledger.git

printf '\nthe upstream\n'
git remote set-url origin git@github.com:Trellis-Org/Trellis.git
refused 'its own repository' 'trellis issue follow-up'
git remote set-url origin git@work:trellis-org/trellis.git
refused '  by an alias of ssh too' 'trellis issue follow-up'
git config -f trellis.config trellis.upstream Trellis-Org/Trellis
refused '  and in another letter case' 'trellis issue follow-up'
git config -f trellis.config trellis.upstream trellis-org/trellis
git remote set-url origin https://github.com/zephyr-co/ledger.git
git config -f trellis.config trellis.upstream "$TL_TMP/upstream/trellis"
refused 'one that is a path' 'is not a repository of GitHub'
git config -f trellis.config trellis.upstream https://github.com/trellis-org/trellis.git
tl_eq 'a URL is the same one' '4' "$(propose)"
git config -f trellis.config trellis.upstream trellis-org/trellis
touch "$GH_FIXTURES/search-fails"
tl_eq 'a search that fails' '1' "$(propose)"
tl_has '  says who asked and why' "could not be searched as the owner's account (trellis-org): gh: no search for you" "$(out)"
rm "$GH_FIXTURES/search-fails"
tl_eq '  and writes nothing' '' "$(writes)"

printf '\nthe proposal\n'
printf '[{"number": 8, "state": "closed", "title": "The guard reads -C"}]' > "$GH_FIXTURES/search.json"
for level in '' careful balanced autonomous; do
  [ -z "$level" ] || git config -f trellis.config autonomy.level "$level"
  tl_eq "nothing is published at autonomy.level ${level:-unset}" '4' "$(propose)"
  tl_eq '  and nothing is written' '' "$(writes)"
done
tl_has 'what the search finds' '#8 closed The guard reads -C' "$(out)"
tl_has 'where it goes' 'Where: a new issue of trellis-org/trellis, with the label lesson' "$(out)"
tl_has 'its title' "Title: $title" "$(out)"
tl_has 'its text' "$(cat "$body")" "$(out)"
tl_eq 'and its digest' '64' "$(digest | tr -d '\n' | wc -c | tr -d ' ')"
tl_has 'the upstream is asked as its owner' 'search/issues' "$(grep tok-there "$GH_FIXTURES/calls.log")"
tl_has '  and the repository of the project as its own' 'repos/zephyr-co/ledger' "$(grep tok-here "$GH_FIXTURES/calls.log")"

printf '\nthe digest\n'
ok="$(digest)"
tl_eq 'another digest is refused' '1' "$(propose --approved "${ok%?}x")"
tl_has '  saying it' 'is not the digest of this lesson' "$(out)"
tl_eq 'a part of it too' '1' "$(propose --approved "${ok%?}")"
tl_eq 'an empty one is a wrong use' '2' "$(propose --approved '')"
printf '\n' >> "$body"
tl_eq 'the one of another text' '1' "$(propose --approved "$ok")"
good
tl_eq 'of another title' '1' "$(title='guard: another'; propose --approved "$ok")"
tl_eq 'of another search' '1' "$(lesson --title "$title" --body-file "$body" --search 'guard' --approved "$ok")"
tl_eq 'of an issue' '1' "$(propose --issue 7 --approved "$ok")"
git config -f trellis.config trellis.upstream trellis-org/other
tl_eq 'of another destination' '1' "$(propose --approved "$ok")"
tl_has '  saying it' 'is not the digest of this lesson' "$(out)"
git config -f trellis.config trellis.upstream https://github.acme.test/trellis-org/trellis
tl_eq 'of another host' '1' "$(propose --approved "$ok")"
tl_has '  saying it' 'is not the digest of this lesson' "$(out)"
git config -f trellis.config trellis.upstream trellis-org/trellis
tl_eq 'and the one of a case without --reopen' '1' "$(one="$(digest --issue 8)"; propose --issue 8 --reopen --approved "$one")"
tl_eq 'or of another issue' '1' "$(one="$(digest --issue 8)"; propose --issue 7 --approved "$one")"
tl_eq 'a run without a person' '1' "$(CLAUDE_CODE_REMOTE=true propose --approved "$ok")"
tl_has '  saying it' 'CLAUDE_CODE_REMOTE' "$(out)"
tl_eq '  still proposes' '4' "$(CLAUDE_CODE_REMOTE=true propose)"
tl_eq 'and none of it is written' '' "$(writes)"

printf '\na new issue\n'
tl_eq 'its digest publishes' '0' "$(propose --approved "$ok")"
tl_has 'and prints its URL' 'https://github.com/trellis-org/trellis/issues/12' "$(out)"
tl_eq 'the label is created, and the issue' "POST labels name=lesson color=BFD4F2 description=What a project learned
POST issues title=$title body labels[]=lesson" "$(writes)"
tl_eq 'with the text as it was' "$(cat "$body")" "$(cat "$GH_FIXTURES/body")"
tl_eq 'a label that is there is not created' '0' "$(propose --approved "$ok")"
tl_eq '  only the issue' "POST issues title=$title body labels[]=lesson" "$(writes)"
tl_lacks '  and says nothing of it' 'without the label' "$(out)"
touch "$GH_FIXTURES/drops-labels"
tl_eq 'an account that cannot label publishes' '0' "$(propose --approved "$ok")"
tl_has '  saying that the label is missing' "lesson: published without the label lesson, which the owner's account (trellis-org) cannot put on an issue of trellis-org/trellis" "$(out)"
tl_has '  and prints its URL' 'https://github.com/trellis-org/trellis/issues/12' "$(out)"
rm "$GH_FIXTURES/drops-labels"; writes > /dev/null
touch "$GH_FIXTURES/create-fails"
tl_eq 'a failure is one' '1' "$(propose --approved "$ok")"
tl_has '  with who asked and why' "could not be published as the owner's account (trellis-org): gh: no create for you" "$(out)"
rm "$GH_FIXTURES/create-fails"
printf 'bug\n' > "$there/labels"; touch "$GH_FIXTURES/label-fails"; writes > /dev/null
tl_eq 'and so is the one of the label' '1' "$(propose --approved "$ok")"
tl_lacks '  which opens no issue' 'POST issues' "$(writes)"
rm "$GH_FIXTURES/label-fails"; touch "$GH_FIXTURES/labels-fails"
tl_eq 'and of reading the labels' '1' "$(propose --approved "$ok")"
rm "$GH_FIXTURES/labels-fails"

printf '\nanother case\n'
tl_eq 'it is proposed' '4' "$(propose --issue 7)"
tl_has '  on its issue' 'Where: a comment on issue 7 of trellis-org/trellis, open: The guard reads -R' "$(out)"
tl_lacks '  with no title, which a comment has not' 'Title:' "$(out)"
one="$(digest --issue 7)"
tl_eq 'its digest publishes' '0' "$(propose --issue 7 --approved "$one")"
tl_eq '  the comment and nothing else' 'POST issues/7/comments body' "$(writes)"
tl_eq '  with the text as it was' "$(cat "$body")" "$(cat "$GH_FIXTURES/body")"
tl_eq 'on a closed one' '4' "$(propose --issue 8)"
tl_has '  it is named as closed' 'a comment on issue 8 of trellis-org/trellis, closed (--reopen opens it): The guard reads -C' "$(out)"
one="$(digest --issue 8)"
tl_eq '  and stays closed' '0' "$(propose --issue 8 --approved "$one")"
tl_eq '  with its comment' 'POST issues/8/comments body' "$(writes)"
tl_eq '--reopen' '4' "$(propose --issue 8 --reopen)"
tl_has '  says it' 'closed, which is opened: The guard reads -C' "$(out)"
one="$(digest --issue 8 --reopen)"
tl_eq '  and opens it' '0' "$(propose --issue 8 --reopen --approved "$one")"
tl_eq '  before the comment' 'PATCH issues/8 state=open
POST issues/8/comments body' "$(writes)"
touch "$GH_FIXTURES/reopen-fails"
tl_eq 'one that cannot be opened' '1' "$(propose --issue 8 --reopen --approved "$one")"
tl_eq '  gets no comment' 'PATCH issues/8 state=open' "$(writes)"
rm "$GH_FIXTURES/reopen-fails"
one="$(digest --issue 7 --reopen)"
tl_eq 'an open one is not opened' '0' "$(propose --issue 7 --reopen --approved "$one")"
tl_eq '  only its comment' 'POST issues/7/comments body' "$(writes)"
touch "$GH_FIXTURES/comment-fails"
one="$(digest --issue 7)"
tl_eq 'a comment that fails' '1' "$(propose --issue 7 --approved "$one")"
tl_has '  says it' 'no comment for you' "$(out)"
rm "$GH_FIXTURES/comment-fails"
tl_eq 'a pull request is no issue' '1' "$(propose --issue 9)"
tl_has '  saying it' '9 is a pull request' "$(out)"
tl_eq 'nor is one that is not there' '1' "$(propose --issue 70)"
tl_has '  saying it' 'could not be read' "$(out)"

tl_done
