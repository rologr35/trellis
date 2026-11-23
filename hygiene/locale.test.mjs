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
import {LOCALES, PRINCIPLE_ID} from '../lib/locale.mjs';

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

/** A template with its placeholders filled: the named ones from `values`, every other one with `x`. */
const fill = (text, values = {}) => text.replace(/\{\{([^}]*)\}\}/g, (_, key) => values[key] ?? 'x');

/** A project written from the templates of a locale, the way /trellis:init leaves it. */
function initProject(locale) {
  const root = path.join(scratch, `init-${locale}`);
  mkdirSync(root);
  const write = (file, text) => {
    mkdirSync(path.dirname(path.join(root, file)), {recursive: true});
    writeFileSync(path.join(root, file), text);
  };
  const trellis = (...args) => spawnSync('bash', [TRELLIS, ...args], {cwd: root, env, encoding: 'utf8'});
  execFileSync('git', ['init', '-q'], {cwd: root, env});
  write('trellis.config', fill(template(locale, 'trellis.config'), {
    'project.name': 'demo',
    'project.locale': locale,
    'git.releaseBranch': 'main',
    'git.integrationBranch': 'develop',
    'tracker.kind': 'github',
    'workspace.kind': 'flutter',
    'workspace.package': 'app',
    'toolchain.require': 'node 22',
  }));
  write('CLAUDE.md', fill(template(locale, 'CLAUDE.root.md')));
  write('app/CLAUDE.md', fill(template(locale, 'CLAUDE.package.md'), {package: 'app'}));
  write('app/lib/main.dart', 'void main() {}\n');
  write('.claude/rules/app.md', fill(template(locale, 'rule.md').replace(/\{\{glob[^}]*\}\}/, 'app/lib/**/*.dart')));
  write('.claude/skills/x/SKILL.md', fill(template(locale, 'SKILL.md')));
  write('TESTING.md', fill(template(locale, 'TESTING.md')));
  write('.claude/settings.json', fill(readFileSync(path.join(TEMPLATES, 'settings.json'), 'utf8'), {sha: '0'.repeat(40)}));
  cpSync(path.join(TEMPLATES, 'githooks'), path.join(root, '.githooks'), {recursive: true});
  for (const step of [['sync'], ['hygiene', '--freeze']]) {
    const r = trellis(...step);
    assert.equal(r.status, 0, `trellis ${step.join(' ')}:\n${r.stdout}${r.stderr}`);
  }
  return {root, trellis, read: file => readFileSync(path.join(root, file), 'utf8')};
}

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

test('the templates of every locale are the same files with the same blocks and config keys', () => {
  const files = locale => readdirSync(path.join(TEMPLATES, locale)).sort();
  const markers = text => [...text.matchAll(/<!-- \/?trellis:[a-z]+ -->/g)].map(m => m[0]);
  const configLines = text => text.split('\n').filter(l => l.trim() && !l.trim().startsWith('#')).map(l => l.replace(/\{\{[^}]*\}\}/g, '{{}}'));
  const [first, ...rest] = LOCALES;
  for (const locale of rest) {
    assert.deepEqual(files(locale), files(first));
    for (const file of files(first)) {
      assert.deepEqual(markers(template(locale, file)), markers(template(first, file)), `${locale}/${file} has the blocks of ${first}`);
    }
    assert.deepEqual(configLines(template(locale, 'trellis.config')), configLines(template(first, 'trellis.config')), `${locale}/trellis.config has the keys of ${first}`);
  }
});
