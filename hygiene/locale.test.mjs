// node --test hygiene/: what trellis writes into a project follows project.locale. A project built
// from the templates of each locale passes the hygiene, and the two versions of the method and of
// the templates carry the same principles and the same structure.

import {execFileSync, spawnSync} from 'node:child_process';
import {cpSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {after, test} from 'node:test';
import assert from 'node:assert/strict';
import {TRELLIS_ROOT} from '../lib/config.mjs';
import {CYCLE, ISSUE, LOCALES, PRINCIPLE_ID} from '../lib/locale.mjs';

const TRELLIS = path.join(TRELLIS_ROOT, 'bin', 'trellis');
const TEMPLATES = path.join(TRELLIS_ROOT, 'templates');
const scratch = realpathSync(mkdtempSync(path.join(tmpdir(), 'trellis-locale-test-')));
after(() => rmSync(scratch, {recursive: true, force: true}));

const env = {
  ...process.env,
  HOME: scratch,
  GIT_CONFIG_NOSYSTEM: '1',
  GIT_AUTHOR_NAME: 'test',
  GIT_AUTHOR_EMAIL: 'test@example.com',
  GIT_COMMITTER_NAME: 'test',
  GIT_COMMITTER_EMAIL: 'test@example.com',
};
delete env.TRELLIS_CONFIG;

const template = (locale, file) => readFileSync(path.join(TEMPLATES, locale, file), 'utf8');

/** A placeholder with a name (`{{package}}`, `{{project.name}}`), which init fills with a value. */
const NAMED = /\{\{([A-Za-z][\w.]*)\}\}/g;
/** Any placeholder: the named ones and the prose ones (`{{One sentence ...}}`), which init asks for. */
const ANY = /\{\{[^}]*\}\}/g;

/** The values a project gives the named placeholders: the same names in every locale. */
const VALUES = {
  name: 'x',
  package: 'app',
  command: 'true',
  'project.name': 'demo',
  'git.releaseBranch': 'main',
  'git.integrationBranch': 'develop',
  'tracker.kind': 'github',
  'workspace.kind': 'flutter',
  'workspace.package': 'app',
  'toolchain.require': 'node 22',
  'trellis.upstream': 'rologr35/trellis',
  'models.model': 'sonnet',
  'models.effortLevel': 'high',
  'models.autoCompactWindow': '200000',
};

/**
 * A template with its placeholders filled: the named ones from `values`, a prose one with `x`. A
 * named placeholder without a value stays, so the text still holds `{{`.
 */
const fill = (text, locale, values = {}) => text
  .replace(NAMED, (whole, key) => ({...VALUES, 'project.locale': locale, ...values})[key] ?? whole)
  .replace(ANY, whole => (/^\{\{[A-Za-z][\w.]*\}\}$/.test(whole) ? whole : 'x'));

/** The names of the named placeholders of a template, with how often each appears, in order. */
const namesOf = text => {
  const counts = new Map();
  for (const [, key] of text.matchAll(NAMED)) counts.set(key, (counts.get(key) ?? 0) + 1);
  return [...counts].sort(([a], [b]) => a.localeCompare(b));
};

/** A project written from the templates of a locale, the way /trellis:init leaves it. */
function initProject(locale, values = {}) {
  const root = path.join(scratch, ['init', locale, ...Object.values(values)].join('-'));
  mkdirSync(root);
  const write = (file, text) => {
    assert.ok(!text.includes('{{'), `${locale}: ${file} is written with a placeholder left unfilled`);
    mkdirSync(path.dirname(path.join(root, file)), {recursive: true});
    writeFileSync(path.join(root, file), text);
  };
  const trellis = (...args) => spawnSync('bash', [TRELLIS, ...args], {cwd: root, env, encoding: 'utf8'});
  execFileSync('git', ['init', '-q'], {cwd: root, env});
  write('trellis.config', fill(template(locale, 'trellis.config'), locale, values));
  write('CLAUDE.md', fill(template(locale, 'CLAUDE.root.md'), locale));
  write('app/CLAUDE.md', fill(template(locale, 'CLAUDE.package.md'), locale));
  write('app/lib/main.dart', 'void main() {}\n');
  write('.claude/rules/app.md', fill(template(locale, 'rule.md').replace(/\{\{glob[^}]*\}\}/, 'app/lib/**/*.dart'), locale));
  write('.claude/skills/x/SKILL.md', fill(template(locale, 'SKILL.md'), locale));
  write('TESTING.md', fill(template(locale, 'TESTING.md'), locale));
  write('.claude/settings.json', fill(readFileSync(path.join(TEMPLATES, 'settings.json'), 'utf8'), locale, {sha: '0'.repeat(40)}));
  cpSync(path.join(TEMPLATES, 'githooks'), path.join(root, '.githooks'), {recursive: true});
  for (const step of [['sync'], ['hygiene', '--freeze']]) {
    const r = trellis(...step);
    assert.equal(r.status, 0, `trellis ${step.join(' ')}:\n${r.stdout}${r.stderr}`);
  }
  return {root, trellis, read: file => readFileSync(path.join(root, file), 'utf8')};
}

const CYCLE_HEADING = {en: '### Cycle', es: '### Ciclo'};
const METHOD_HEADING = {en: '## Working method', es: '## Método de trabajo'};

for (const locale of LOCALES) {
  test(`init with ${locale} writes files that pass the hygiene`, () => {
    const p = initProject(locale);
    const r = p.trellis('hygiene');
    assert.equal(r.status, 0, `hygiene of an ${locale} project:\n${r.stdout}${r.stderr}`);
    const claude = p.read('CLAUDE.md');
    assert.ok(claude.includes(METHOD_HEADING[locale]), `the method block is the ${locale} one`);
    for (const other of LOCALES.filter(l => l !== locale)) assert.ok(!claude.includes(METHOD_HEADING[other]));
    assert.doesNotMatch(claude, /<!-- p:/, 'the principle ids stay in the plugin');
    assert.ok(claude.includes(`\n\n${CYCLE_HEADING[locale]}\n\n- `), 'the method has the Cycle section');
    assert.doesNotMatch(claude, /<!-- \/?cycle/, 'its markers stay in the plugin');
  });

  test(`an ${locale} project with tracker.kind = none has no Cycle section and passes the hygiene`, () => {
    const p = initProject(locale, {'tracker.kind': 'none'});
    const r = p.trellis('hygiene');
    assert.equal(r.status, 0, `hygiene of an ${locale} project without a tracker:\n${r.stdout}${r.stderr}`);
    const claude = p.read('CLAUDE.md');
    assert.ok(claude.includes(METHOD_HEADING[locale]));
    assert.ok(!claude.includes(CYCLE_HEADING[locale]), 'the Cycle section is out');
    assert.doesNotMatch(claude, /trellis issue|<!-- \/?cycle|\n\n\n/, 'with its content and its markers');
    assert.ok(claude.includes(`\n\n### ${{en: 'Releases', es: 'Entregas'}[locale]}\n\n`), 'the section after it stays');
  });
}

const methodOf = locale => readFileSync(path.join(TRELLIS_ROOT, 'method', `${locale}.md`), 'utf8');
const idsOf = text => [...text.matchAll(PRINCIPLE_ID)].map(m => m[1]);

test('the methods of every locale carry the same principles: the same count and the same ids', () => {
  const [first, ...rest] = LOCALES;
  const ids = idsOf(methodOf(first));
  assert.ok(ids.length > 0);
  assert.equal(new Set(ids).size, ids.length, 'every id is unique');
  for (const locale of rest) {
    assert.equal(idsOf(methodOf(locale)).length, ids.length, `${locale} has as many principles as ${first}`);
    assert.deepEqual(idsOf(methodOf(locale)), ids, `${locale} has the ids of ${first}, in order`);
  }
  for (const locale of LOCALES) {
    const text = methodOf(locale);
    const bullets = text.split('\n').filter(l => l.startsWith('- '));
    for (const bullet of bullets) assert.match(bullet, /<!-- p:[a-z0-9-]+ -->$/, `${locale}: a principle without its id: ${bullet}`);
    assert.equal(text.split('\n').filter(l => l.startsWith('### ')).length, methodOf(first).split('\n').filter(l => l.startsWith('### ')).length, `${locale} has the sections of ${first}`);
  }
});

test('the Cycle section of every method is marked once, takes at most 1.5 KB and says the same', () => {
  for (const locale of LOCALES) {
    const found = [...methodOf(locale).matchAll(CYCLE)];
    assert.equal(found.length, 1, `${locale}: one section between <!-- cycle --> and <!-- /cycle -->`);
    const [, section] = found[0];
    assert.ok(section.startsWith(`${CYCLE_HEADING[locale]}\n`));
    assert.ok(Buffer.byteLength(section.replace(PRINCIPLE_ID, '')) <= 1536, `${locale}: ${Buffer.byteLength(section.replace(PRINCIPLE_ID, ''))} bytes`);
    assert.deepEqual(idsOf(section), ['plan-in-issue', 'issue-amendment', 'issue-check', 'planless-issue']);
    for (const text of [`## ${ISSUE[locale].amendment} (`, 'trellis issue check <n>', 'trellis issue create', 'gh issue create', `templates/${locale}/issue.md`]) {
      assert.ok(section.includes(text), `${locale}: the Cycle section names ${text}`);
    }
  }
});

test('the templates of every locale are the same files with the same blocks and config keys', () => {
  const files = locale => readdirSync(path.join(TEMPLATES, locale)).sort();
  const markers = text => [...text.matchAll(/<!-- \/?trellis:[a-z]+ -->/g)].map(m => m[0]);
  const configLines = text => text.split('\n').filter(l => l.trim() && !l.trim().startsWith('#')).map(l => l.replace(ANY, '{{}}'));
  const [first, ...rest] = LOCALES;
  for (const locale of rest) {
    assert.deepEqual(files(locale), files(first));
    for (const file of files(first)) {
      assert.deepEqual(markers(template(locale, file)), markers(template(first, file)), `${locale}/${file} has the blocks of ${first}`);
    }
    assert.deepEqual(configLines(template(locale, 'trellis.config')), configLines(template(first, 'trellis.config')), `${locale}/trellis.config has the keys of ${first}`);
  }
});

test('the issue mould of every locale has the sections of its locale, in order, and its labels', () => {
  for (const locale of LOCALES) {
    const text = template(locale, 'issue.md');
    const lines = text.split('\n');
    assert.deepEqual(lines.filter(l => l.startsWith('#')), ISSUE[locale].sections.map(s => `## ${s}`), `${locale}/issue.md has the sections of lib/locale.mjs`);
    const has = re => assert.ok(lines.some(l => re.test(l)), `${locale}/issue.md has no line like ${re}`);
    const L = ISSUE[locale];
    has(new RegExp(`^${L.dependsOn}: `));
    has(new RegExp(`^${L.outOfScope}:$`));
    has(new RegExp(`^- .*\\b${L.source}: `));
    has(new RegExp(`^- \\*\\*${L.newFiles}\\*\\*: `));
    assert.equal(text.trimEnd().split('\n').at(-1), `${L.complexity}: S`, `${locale}/issue.md ends with the complexity line`);
  }
});

test('every locale defines the same issue labels, and as many sections', () => {
  const [first, ...rest] = LOCALES;
  for (const locale of rest) {
    assert.deepEqual(Object.keys(ISSUE[locale]), Object.keys(ISSUE[first]));
    assert.equal(ISSUE[locale].sections.length, ISSUE[first].sections.length);
  }
});

test('the plan-reviewer takes its report labels from one table, with a row per locale', () => {
  const agent = readFileSync(path.join(TRELLIS_ROOT, 'agents', 'plan-reviewer.md'), 'utf8');
  const rows = agent.split('\n').filter(line => /^\| (en|es) \|/.test(line)).map(line => line.split('|').slice(1, -1).map(cell => cell.trim()));
  assert.deepEqual(rows.map(row => row[0]), LOCALES, 'one row per locale, in the order of LOCALES');
  const expected = {
    en: ['Verdict', 'Errors', 'Omissions', 'Not established', 'correct', 'with errors'],
    es: ['Veredicto', 'Errores', 'Omisiones', 'No establecido', 'correcto', 'con errores'],
  };
  for (const row of rows) assert.deepEqual(row.slice(1), expected[row[0]], `labels of ${row[0]}`);
  const outside = agent.split('\n').filter(line => !line.startsWith('|')).join('\n');
  for (const word of ['Verdict', 'Errors', 'Omissions', 'Not established']) {
    assert.ok(!outside.includes(`**${word}**`), `the label ${word} is written only in the table`);
  }
});

test('the templates of every locale use the same placeholder names; only the text around them is translated', () => {
  const [first, ...rest] = LOCALES;
  for (const file of readdirSync(path.join(TEMPLATES, first))) {
    const names = namesOf(template(first, file));
    for (const locale of rest) {
      assert.deepEqual(namesOf(template(locale, file)), names, `${locale}/${file} names its placeholders as ${first}/${file} does`);
    }
    const prose = text => (text.match(ANY) ?? []).length - [...text.matchAll(NAMED)].length;
    for (const locale of rest) {
      assert.equal(prose(template(locale, file)), prose(template(first, file)), `${locale}/${file} has as many free-text placeholders as ${first}/${file}`);
    }
  }
});

test('filling the placeholders of a template leaves no {{ behind, and a name without a value is caught', () => {
  for (const locale of LOCALES) {
    for (const file of readdirSync(path.join(TEMPLATES, locale))) {
      const filled = fill(template(locale, file), locale);
      assert.ok(!filled.includes('{{'), `${locale}/${file} keeps a placeholder after filling`);
    }
  }
  const unfilled = fill('# {{package}} {{extra}}', 'en', {package: 'app'});
  assert.ok(unfilled.includes('{{'), 'a placeholder with no value is not filled');
  assert.match(fill('{{One sentence, free text.}}', 'en'), /^x$/, 'a free-text placeholder is filled with text');
});
