// node --test hygiene/: every rule of the contract fails on its violation, on a project built the
// way /trellis:init leaves it (templates filled, `trellis sync` run, sizes frozen).

import {execFileSync, spawnSync} from 'node:child_process';
import {mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {after, test} from 'node:test';
import assert from 'node:assert/strict';
import {TRELLIS_ROOT} from '../lib/config.mjs';

const TRELLIS = path.join(TRELLIS_ROOT, 'bin', 'trellis');
const scratch = realpathSync(mkdtempSync(path.join(tmpdir(), 'trellis-hygiene-test-')));
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

let count = 0;

/** A project that passes the hygiene: config, root with every block, one package, one rule. */
function project() {
  const root = path.join(scratch, `p${++count}`);
  mkdirSync(root);
  const write = (file, text) => {
    mkdirSync(path.dirname(path.join(root, file)), {recursive: true});
    writeFileSync(path.join(root, file), text);
  };
  const git = (...args) => execFileSync('git', args, {cwd: root, env, stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8'});
  const trellis = (...args) => spawnSync('bash', [TRELLIS, ...args], {cwd: root, env, encoding: 'utf8'});
  git('init', '-q');
  write('trellis.config', '[workspace]\n\tkind = flutter\n\tpackage = app\n[git]\n\tprotected = main\n');
  write('CLAUDE.md', [
    '# Project',
    '',
    '<!-- trellis:method -->',
    '<!-- /trellis:method -->',
    '',
    '<!-- trellis:orientation -->',
    '<!-- /trellis:orientation -->',
    '',
    '<!-- trellis:commands -->',
    '<!-- /trellis:commands -->',
    '',
    '<!-- trellis:gates -->',
    '<!-- /trellis:gates -->',
    '',
  ].join('\n'));
  write('app/CLAUDE.md', '# App\n\nThe package.\n');
  write('app/lib/main.dart', 'void main() {}\n');
  write('.claude/rules/app.md', '---\npaths:\n  - "app/lib/**/*.dart"\n---\n\n# App code\n\n`app/lib/main.dart` starts it.\n');
  write('.claude/settings.json', '{"permissions": {"deny": []}}\n');
  write('TESTING.md', '# Testing\n\n<!-- trellis:rungs -->\n<!-- /trellis:rungs -->\n');
  const p = {
    root,
    write,
    git,
    trellis,
    read: file => readFileSync(path.join(root, file), 'utf8'),
    hygiene: (...args) => trellis('hygiene', ...args),
  };
  assert.equal(trellis('sync').status, 0);
  assert.equal(trellis('hygiene', '--freeze').status, 0);
  return p;
}

const fails = (p, needle, ...args) => {
  const r = p.hygiene(...args);
  assert.equal(r.status, 1, `expected a FAIL with "${needle}":\n${r.stdout}${r.stderr}`);
  assert.match(r.stdout, new RegExp(needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
};
const passes = (p, ...args) => {
  const r = p.hygiene(...args);
  assert.equal(r.status, 0, `expected a pass:\n${r.stdout}${r.stderr}`);
};

test('the project /trellis:init leaves passes', () => {
  const p = project();
  passes(p);
  assert.match(p.read('CLAUDE.md'), /## Método de trabajo/);
});

test('the root template with the method block passes and fits its limit', () => {
  const p = project();
  p.write('CLAUDE.md', readFileSync(path.join(TRELLIS_ROOT, 'templates', 'CLAUDE.root.md'), 'utf8'));
  p.trellis('sync');
  passes(p);
});

test('narrative in Spanish fails', () => {
  const p = project();
  p.write('app/CLAUDE.md', '# App\n\nEl servicio ya no usa la caché.\n');
  fails(p, 'app/CLAUDE.md: line 3 narrates history');
});

test('narrative in English fails', () => {
  const p = project();
  p.write('.claude/rules/app.md', `${p.read('.claude/rules/app.md')}\nThe cache is no longer used.\n`);
  fails(p, '.claude/rules/app.md: line 10 narrates history');
});

test('a tracker reference fails unless keepRef lists it', () => {
  const p = project();
  p.write('app/CLAUDE.md', '# App\n\nSee #12 for the reason.\n');
  fails(p, 'app/CLAUDE.md: cites #12');
  p.git('config', '-f', 'trellis.config', '--add', 'hygiene.keepRef', 'app/CLAUDE.md: #12 | the decision lives there');
  passes(p);
});

test('a glob that matches nothing fails', () => {
  const p = project();
  p.write('.claude/rules/dead.md', '---\npaths:\n  - "nothing/**/*.dart"\n---\n\n# Dead\n');
  p.trellis('sync');
  fails(p, 'the glob nothing/**/*.dart matches no file');
});

test('a named file that does not load the rule fails unless namedElsewhere lists it', () => {
  const p = project();
  p.write('app/test/main_test.dart', 'void main() {}\n');
  p.write('.claude/rules/app.md', `${p.read('.claude/rules/app.md')}\n\`app/test/main_test.dart\` covers it.\n`);
  fails(p, 'names app/test/main_test.dart, which does not load it');
  p.git('config', '-f', 'trellis.config', '--add', 'hygiene.namedElsewhere', 'app.md: app/test/main_test.dart | the test rule covers it');
  passes(p);
});

test('a rule that loads what mustNotLoad lists fails', () => {
  const p = project();
  p.git('config', '-f', 'trellis.config', '--add', 'hygiene.mustNotLoad', 'app.md: app/lib/main.dart | narrow on purpose');
  fails(p, '.claude/rules/app.md: loads app/lib/main.dart, which it must not: narrow on purpose');
});

test('the root, a nested file, a rule and an agent over their limits fail', () => {
  const p = project();
  p.git('config', '-f', 'trellis.config', 'hygiene.nestedLimit', '10');
  fails(p, 'app/CLAUDE.md: 20 bytes, over its limit of 10');
  const q = project();
  q.git('config', '-f', 'trellis.config', 'hygiene.rootLimit', '100');
  fails(q, 'CLAUDE.md:');
  const r = project();
  r.git('config', '-f', 'trellis.config', 'hygiene.ruleLimit', '50');
  fails(r, '.claude/rules/app.md:');
  const s = project();
  s.write('.claude/agents/big.md', `# Big\n\n${'x'.repeat(5000)}\n`);
  fails(s, '.claude/agents/big.md:');
});

test('the rules together over their limit fail in full mode and not with --staged', () => {
  const p = project();
  p.git('config', '-f', 'trellis.config', 'hygiene.rulesTotalLimit', '50');
  fails(p, 'the rules add up to');
  p.git('add', '-A');
  passes(p, '--staged');
});

test('a skill without a frozen size fails, one over it fails, --freeze records it', () => {
  const p = project();
  p.write('.claude/skills/deploy/SKILL.md', '# Deploy\n\nSteps.\n');
  fails(p, '.claude/skills/deploy/SKILL.md: has no frozen size');
  assert.equal(p.hygiene('--freeze').status, 0);
  assert.match(p.read('trellis.config'), /frozen = \.claude\/skills\/deploy\/SKILL\.md 17/);
  p.write('.claude/skills/deploy/SKILL.md', '# Deploy\n\nSteps, and many more steps.\n');
  fails(p, '.claude/skills/deploy/SKILL.md: 38 bytes, over its limit of 17');
});

test('a docs file joins the frozen ones', () => {
  const p = project();
  p.write('docs/domain.md', '# Domain\n');
  fails(p, 'docs/domain.md: has no frozen size');
});

test('a package without CLAUDE.md fails', () => {
  const p = project();
  p.git('config', '-f', 'trellis.config', '--add', 'workspace.package', 'core');
  p.write('core/lib/core.dart', '\n');
  fails(p, 'core: is a [workspace] package without its CLAUDE.md');
});

test('the orientation must list every nested file and rule', () => {
  const p = project();
  p.write('core/CLAUDE.md', '# Core\n');
  fails(p, 'the orientation table does not list core/CLAUDE.md');
  p.trellis('sync');
  passes(p);
});

test('a generated block that drifted from its source fails', () => {
  const p = project();
  p.git('config', '-f', 'trellis.config', 'command.analyze.run', 'flutter analyze');
  fails(p, 'the block commands does not match its source');
  p.trellis('sync');
  passes(p);
});

test('a root without the method block fails', () => {
  const p = project();
  p.write('CLAUDE.md', p.read('CLAUDE.md').replace(/<!-- trellis:method -->[\s\S]*<!-- \/trellis:method -->/, ''));
  fails(p, 'has no <!-- trellis:method --> block');
});

test('a deny that lost a generated entry fails', () => {
  const p = project();
  p.write('.claude/settings.json', '{"permissions": {"deny": []}}\n');
  fails(p, 'permissions.deny lacks Bash(git push * main)');
});

test('the copy of find-trellis.sh must match', () => {
  const p = project();
  p.write('.githooks/pre-commit', '#!/bin/sh\n');
  fails(p, '.githooks/find-trellis.sh: is not the plugin');
  p.trellis('sync');
  passes(p);
});

test('--staged judges the index, not the working tree', () => {
  const p = project();
  p.git('add', '-A');
  p.write('app/CLAUDE.md', '# App\n\nIt used to be slow.\n');
  passes(p, '--staged');
  p.git('add', 'app/CLAUDE.md');
  fails(p, 'app/CLAUDE.md: line 3 narrates history', '--staged');
});
