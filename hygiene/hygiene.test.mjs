// node --test hygiene/: every rule of the contract fails on its violation, on a project built the
// way /trellis:init leaves it (templates filled, `trellis sync` run, sizes frozen).

import {execFileSync, spawnSync} from 'node:child_process';
import {cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
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

/** The repository of trellis itself, with a root of its own, run from its tree as it runs. */
function ownTree() {
  const root = path.join(scratch, `own${++count}`);
  const listed = execFileSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'], {cwd: TRELLIS_ROOT, encoding: 'utf8'});
  for (const file of listed.split('\0').filter(f => f && existsSync(path.join(TRELLIS_ROOT, f)) && !/^(?:\.claude|\.githooks)\/|^TESTING\.md$/.test(f))) {
    cpSync(path.join(TRELLIS_ROOT, file), path.join(root, file));
  }
  const write = (file, text) => {
    mkdirSync(path.dirname(path.join(root, file)), {recursive: true});
    writeFileSync(path.join(root, file), text);
  };
  const git = (...args) => execFileSync('git', args, {cwd: root, env, stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8'});
  const trellis = (...args) => spawnSync('bash', [path.join(root, 'bin', 'trellis'), ...args], {cwd: root, env, encoding: 'utf8'});
  git('init', '-q');
  write('trellis.config', '[project]\n\tname = trellis\n');
  write('CLAUDE.md', '# Project\n\n<!-- trellis:method -->\n<!-- /trellis:method -->\n');
  const sync = trellis('sync');
  assert.equal(sync.status, 0, sync.stderr);
  trellis('hygiene', '--freeze');
  return {
    root,
    write,
    git,
    trellis,
    read: file => readFileSync(path.join(root, file), 'utf8'),
    hygiene: (...args) => trellis('hygiene', ...args),
  };
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
  assert.match(p.read('CLAUDE.md'), /## Working method/);
  assert.doesNotMatch(p.read('CLAUDE.md'), /<!-- p:/);
});

/** The project with a copy, from an upstream that is this working tree. */
let upstream = '';
function withCopy(p) {
  if (!upstream) {
    upstream = path.join(scratch, 'upstream');
    mkdirSync(upstream);
    const files = execFileSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'], {cwd: TRELLIS_ROOT, encoding: 'utf8'}).split('\0').filter(f => f && existsSync(path.join(TRELLIS_ROOT, f)));
    for (const f of files) cpSync(path.join(TRELLIS_ROOT, f), path.join(upstream, f));
    const git = (...args) => execFileSync('git', args, {cwd: upstream, env, stdio: ['ignore', 'pipe', 'pipe']});
    git('init', '-q');
    git('add', '-A');
    git('-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'chore: trellis');
    git('tag', 'v1');
  }
  p.git('config', '-f', 'trellis.config', 'trellis.upstream', upstream);
  const r = p.trellis('update', 'v1');
  assert.equal(r.status, 0, r.stderr);
  return p;
}

test('the files of the copy are not judged', () => {
  const p = withCopy(project());
  passes(p);
  assert.equal(p.trellis('hygiene', '--freeze').status, 0);
  assert.doesNotMatch(p.read('trellis.config'), /frozen = .*trellis-/);
  p.git('add', '-A');
  passes(p, '--staged');
});

test('a skill with the name of a copied one is the project\'s, and judged', () => {
  const p = withCopy(project());
  p.write('.claude/skills/trellis-mine/SKILL.md', '# Mine\n');
  fails(p, '.claude/skills/trellis-mine/SKILL.md: has no frozen size');
});

test('a copy that is not whole fails', () => {
  const p = withCopy(project());
  p.write('.trellis/lib/schema', 'x\n');
  fails(p, '.trellis/lib/schema: is not the file that was copied');
  p.git('add', '-A');
  fails(p, '.trellis/lib/schema: is not the file that was copied', '--staged');
});

test('settings that lost a hook of the copy, or its deny, fail', () => {
  const p = withCopy(project());
  const settings = p.read('.claude/settings.json');
  for (const [lost, needle] of [
    ['guard-git.sh', 'hooks.PreToolUse lacks bash "$CLAUDE_PROJECT_DIR"/.trellis/hooks/guard-git.sh'],
    ['"AskUserQuestion"', 'hooks.PreToolUse lacks bash "$CLAUDE_PROJECT_DIR"/.trellis/hooks/unattended.sh'],
    ['"PermissionRequest"', 'hooks.PermissionRequest lacks bash "$CLAUDE_PROJECT_DIR"/.trellis/hooks/unattended.sh'],
    ['waiting.sh', 'hooks.Notification lacks bash "$CLAUDE_PROJECT_DIR"/.trellis/hooks/waiting.sh'],
    ['setup --quiet', 'hooks.SessionStart lacks'],
    ['Edit(/.trellis/**)', 'permissions.deny lacks Edit(/.trellis/**)'],
  ]) {
    p.write('.claude/settings.json', settings.replace(lost, lost.startsWith('"') ? '"x"' : 'x'));
    fails(p, needle);
  }
  const own = JSON.parse(settings);
  own.hooks.PostToolUse = [{matcher: 'Edit', hooks: [{type: 'command', command: 'fmt'}]}];
  p.write('.claude/settings.json', JSON.stringify(own, null, 2) + '\n');
  passes(p);
  rmSync(path.join(p.root, '.claude/settings.json'));
  fails(p, '.claude/settings.json: is not there');
});

test('the copy gone, with the settings that name it, fails', () => {
  const p = withCopy(project());
  p.write('.claude/settings.json', p.read('.claude/settings.json').replace('"deny": [', '"deny": ["Edit(/.trellis/**)",'));
  rmSync(path.join(p.root, '.trellis'), {recursive: true});
  fails(p, '.trellis/MANIFEST: is not there');
});

test('the root template with the method block passes and fits its limit', () => {
  const p = project();
  p.write('CLAUDE.md', readFileSync(path.join(TRELLIS_ROOT, 'templates', 'en', 'CLAUDE.root.md'), 'utf8'));
  p.trellis('sync');
  passes(p);
});

test('narrative in Spanish fails in an es project and passes in an en one', () => {
  const p = project();
  p.write('app/CLAUDE.md', '# App\n\nEl servicio ya no usa la caché.\n');
  passes(p);
  p.git('config', '-f', 'trellis.config', 'project.locale', 'es');
  p.trellis('sync');
  fails(p, 'app/CLAUDE.md: line 3 narrates history');
});

test('the es narrative catches a word between "antes" and the verb, and "ahora" as a contrast', () => {
  for (const line of ['Antes esto usaba Provider.', 'Antes aquello era un singleton.', 'Antes Provider estaba en core.', 'Antes esto usaba Provider, ahora usa Bloc.', 'Esto era un singleton y ahora es un servicio.', 'Usaba Provider, pero ahora usa Bloc.']) {
    const p = project();
    p.write('app/CLAUDE.md', `# App\n\n${line}\n`);
    p.git('config', '-f', 'trellis.config', 'project.locale', 'es');
    p.trellis('sync');
    fails(p, 'app/CLAUDE.md: line 3 narrates history');
  }
  const p = project();
  const legitimate = [
    'Antes de ejecutar, lee el plan.',
    'Antes de proponer algo, busca lo que existe.',
    'Ejecuta antes una alternativa barata.',
    'Por ahora el escalón está apagado.',
    'Ahora mismo no hay caché.',
    'A partir de ahora, cada PR lleva su issue.',
    'Ahora, ejecuta el análisis.',
    'Comprueba antes qué había en la rama.',
    'Mira antes si había cambios sin commit.',
    'Pregunta antes si estaba aprobado.',
    'Mira antes de la rama lo que había.',
  ];
  p.write('app/CLAUDE.md', `# App\n\n${legitimate.join('\n')}\n`);
  p.git('config', '-f', 'trellis.config', 'project.locale', 'es');
  p.trellis('sync');
  passes(p);
});

test('narrative in English fails in an en project and in an es one', () => {
  const p = project();
  p.write('.claude/rules/app.md', `${p.read('.claude/rules/app.md')}\nThe cache is no longer used.\n`);
  fails(p, '.claude/rules/app.md: line 10 narrates history');
  p.git('config', '-f', 'trellis.config', 'project.locale', 'es');
  p.trellis('sync');
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

test('TESTING.md is not frozen: a new rung needs no setback, the nested limit holds it', () => {
  const p = project();
  assert.doesNotMatch(p.read('trellis.config'), /frozen = TESTING\.md/);
  p.git('config', '-f', 'trellis.config', 'command.unit.run', 'flutter test');
  p.git('config', '-f', 'trellis.config', 'rung.unit.command', 'unit');
  p.git('config', '-f', 'trellis.config', 'rung.unit.proves', 'the logic, without widgets or network, in every package');
  p.trellis('sync');
  passes(p);
  p.git('config', '-f', 'trellis.config', 'hygiene.nestedLimit', '40');
  p.trellis('sync');
  fails(p, 'TESTING.md:');
});

test('a package without a manifest, of workspace.package, without CLAUDE.md fails', () => {
  const p = project();
  p.git('config', '-f', 'trellis.config', '--add', 'workspace.package', 'core');
  p.write('core/lib/core.dart', '\n');
  fails(p, 'core: is a [workspace] package without its CLAUDE.md');
});

test('the repository of trellis has its skills and agents as sync writes them', () => {
  const p = ownTree();
  passes(p);
  const skill = '.claude/skills/trellis-work/SKILL.md';
  const agent = '.claude/agents/trellis-plan-check.md';
  assert.ok(!existsSync(path.join(p.root, '.claude/skills/trellis-init')), 'init is not one of them');
  p.git('add', '-A');
  passes(p, '--staged');
  for (const file of [skill, agent]) {
    const was = p.read(file);
    rmSync(path.join(p.root, file));
    fails(p, `${file}: is not there`);
    p.write(file, `${was}by hand\n`);
    fails(p, `${file}: is not what sync writes from `);
    passes(p, '--staged');
    p.git('add', '-A');
    fails(p, `${file}: is not what sync writes from `, '--staged');
    p.write(file, was);
    p.git('add', '-A');
  }
  for (const file of ['.claude/skills/trellis-gone/SKILL.md', '.claude/agents/trellis-gone.md']) {
    p.write(file, '# Gone\n');
    fails(p, `${file}: has no source`);
    rmSync(path.join(p.root, file));
  }
  p.write('skills/work/SKILL.md', `${p.read('skills/work/SKILL.md')}\nOne line more.\n`);
  fails(p, `${skill}: is not what sync writes from skills/work/SKILL.md`);
  p.trellis('sync');
  passes(p);
});

test('a project that is not trellis keeps a skill with the prefix', () => {
  const p = project();
  p.write('.claude/skills/trellis-own/SKILL.md', '# Own\n');
  p.write('.claude-plugin/plugin.json', '{"name": "another"}\n');
  p.write('lib/find-trellis.sh', '');
  p.trellis('hygiene', '--freeze');
  passes(p);
});

test('the hygiene of another checkout does not judge the repository of trellis', () => {
  const p = ownTree();
  for (const args of [[], ['--staged'], ['--freeze']]) {
    const was = p.read('trellis.config');
    const r = spawnSync('bash', [TRELLIS, 'hygiene', ...args], {cwd: path.join(p.root, 'lib'), env, encoding: 'utf8'});
    assert.equal(r.status, 1, r.stdout);
    assert.match(r.stderr, /hygiene: .*run bin\/trellis/);
    assert.equal(p.read('trellis.config'), was);
  }
});

test('a project without its root CLAUDE.md fails', () => {
  const p = project();
  rmSync(path.join(p.root, 'CLAUDE.md'));
  fails(p, 'CLAUDE.md: is not there');
  p.git('add', '-A');
  fails(p, 'CLAUDE.md: is not there', '--staged');
});

const PACKAGE = 'is a [workspace] package without its CLAUDE.md';

test('a package with a manifest and no CLAUDE.md fails, without a line of workspace.package', () => {
  const p = project();
  p.write('core/pubspec.yaml', 'name: core\n');
  fails(p, `core: ${PACKAGE}`);
  p.git('add', '-A');
  fails(p, `core: ${PACKAGE}`, '--staged');
  p.write('core/CLAUDE.md', '# Core\n');
  p.trellis('sync');
  passes(p);
});

test('workspace.notPackage takes a package out, by a glob of its folder and whatever lists it', () => {
  for (const glob of ['packages/*/example', './packages/**/example/', 'packages/core/example']) {
    const p = project();
    p.write('packages/core/example/pubspec.yaml', 'name: example\n');
    fails(p, `packages/core/example: ${PACKAGE}`);
    p.git('config', '-f', 'trellis.config', '--add', 'workspace.notPackage', `${glob} | an example`);
    passes(p);
    p.git('config', '-f', 'trellis.config', '--add', 'workspace.package', 'packages/core/example');
    passes(p);
  }
  const p = project();
  p.write('packages/core/pubspec.yaml', 'name: core\n');
  p.git('config', '-f', 'trellis.config', '--add', 'workspace.notPackage', 'packages/*/example | an example');
  fails(p, `packages/core: ${PACKAGE}`);
  p.git('config', '-f', 'trellis.config', '--add', 'workspace.notPackage', 'packages/{core} | a glob');
  fails(p, 'trellis.config: [workspace] notPackage: glob packages/{core} uses syntax');
});

test('a manifest at the root, in .trellis/ or in a folder git ignores asks for nothing', () => {
  const p = project();
  p.write('pubspec.yaml', 'name: root\n');
  p.write('.gitignore', 'node_modules/\n');
  p.write('node_modules/x/package.json', '{}\n');
  passes(p);
  rmSync(path.join(p.root, 'CLAUDE.md'));
  assert.equal(p.hygiene().stdout.match(/^ {2}FAIL /gmu).length, 1, p.hygiene().stdout);
  const q = withCopy(project());
  q.write('.trellis/x/package.json', '{}\n');
  const r = q.hygiene();
  assert.match(r.stdout, /\.trellis\/x\/package\.json: is not in the manifest/);
  assert.ok(!r.stdout.includes(PACKAGE), r.stdout);
});

test('a monorepo of both manifests asks each one, and workspace.manifest changes which', () => {
  const p = project();
  p.write('package.json', '{}\n');
  p.write('web/package.json', '{}\n');
  p.write('packages/core/pubspec.yaml', 'name: core\n');
  p.write('tool/go.mod', 'module tool\n');
  const asked = () => p.hygiene().stdout.split('\n').filter(l => l.includes(PACKAGE)).map(l => l.trim().split(/\s+|:/)[1]).sort();
  assert.deepEqual(asked(), ['packages/core', 'web']);
  p.git('config', '-f', 'trellis.config', '--add', 'workspace.manifest', 'go.mod');
  assert.deepEqual(asked(), ['tool']);
  for (const value of ['*.csproj', 'web/package.json']) {
    p.git('config', '-f', 'trellis.config', '--replace-all', 'workspace.manifest', value);
    fails(p, `trellis.config: [workspace] manifest: ${value} is not the name of a file`);
  }
});

test('the rule lookup resolves a file a rule names against a package found by its manifest', () => {
  const p = project();
  p.write('core/pubspec.yaml', 'name: core\n');
  p.write('core/CLAUDE.md', '# Core\n');
  p.write('core/lib/core.dart', '\n');
  p.write('.claude/rules/app.md', `${p.read('.claude/rules/app.md')}\n\`lib/core.dart\` too.\n`);
  p.trellis('sync');
  fails(p, 'names core/lib/core.dart, which does not load it');
});

test('a package at the root is satisfied by the root CLAUDE.md', () => {
  const p = project();
  p.git('config', '-f', 'trellis.config', '--replace-all', 'workspace.package', '.');
  passes(p);
});

test('a package path is read once the same way: ., ./x and a trailing slash', () => {
  for (const spelling of ['./', './app', 'app/', './app/', 'app//']) {
    const p = project();
    p.git('config', '-f', 'trellis.config', '--replace-all', 'workspace.package', spelling);
    passes(p);
  }
  const p = project();
  p.git('config', '-f', 'trellis.config', '--replace-all', 'workspace.package', './packages/foo/');
  fails(p, 'packages/foo: is a [workspace] package without its CLAUDE.md');
  p.write('packages/foo/CLAUDE.md', '# Foo\n');
  p.trellis('sync');
  passes(p);
});

test('the rule lookup resolves a file a rule names against a package written with a slash', () => {
  const p = project();
  p.git('config', '-f', 'trellis.config', '--replace-all', 'workspace.package', './app/');
  p.write('.claude/rules/app.md', '---\npaths:\n  - "app/lib/other/*.dart"\n---\n\n# App code\n\n`lib/main.dart` starts it.\n');
  p.write('app/lib/other/x.dart', '\n');
  p.trellis('sync');
  fails(p, 'names app/lib/main.dart, which does not load it');
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
  fails(p, '.githooks/find-trellis.sh: is not trellis\'s lib');
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
