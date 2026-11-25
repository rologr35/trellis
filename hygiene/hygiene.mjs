// trellis hygiene: the contract of the instruction files of a project, checked file by file.
//
//   trellis hygiene              the working tree, every check
//   trellis hygiene --staged     the index (what is about to be committed), every check but the
//                                aggregate limits, which are a budget shared between branches and
//                                run only in CI
//   trellis hygiene --freeze     records the measured size of every frozen file in [hygiene] frozen
//
// What is checked:
//   - the instruction files (root and nested CLAUDE.md, rules, agents, skills, TESTING.md) describe
//     the present: no phrase that narrates what the code used to be (the en list, and the es one
//     too when project.locale is es), and no tracker reference unless [hygiene] keepRef lists it
//     with its reason;
//   - every `paths:` glob of a rule matches a file; a file a rule names (extensions of
//     [hygiene] namedExt, by default those of workspace.kind) loads that rule, unless
//     [hygiene] namedElsewhere lists it; a rule does not load what [hygiene] mustNotLoad lists;
//   - sizes in bytes: the root, each nested file and TESTING.md (whose rungs block sync rewrites,
//     so it carries the nested limit and is not frozen), each rule, each agent (4 KB, fixed) and
//     all the rules together under their [hygiene] limits; skills and docs/ under their
//     [hygiene] frozen size plus 2%, every one of them frozen;
//   - every package of lib/packages.mjs has its CLAUDE.md (a package at the root, `.`, is the root one);
//   - the orientation block lists every nested file and every rule;
//   - every generated block matches what `trellis sync` generates, the root is there and carries the
//     method block, the deny of .claude/settings.json keeps every entry sync generates, and its hooks
//     the ones of the copy, and .githooks/find-trellis.sh is trellis's copy;
//   - the copy of trellis is whole, as `trellis verify` says, and its files are not judged by anything
//     above: the project does not write them;
//   - in the repository of trellis, which runs from its own tree, its skills and agents under .claude/
//     are the ones `trellis sync` writes from skills/ and agents/.
//
// Prints one line per finding and exits 1 when there is any. Node only, no dependencies.

import {execFileSync} from 'node:child_process';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {
  BLOCK_FILES,
  FIND_TRELLIS_COPY,
  blocksIn,
  findTrellisSource,
  generateBlocks,
  generatedDeny,
  instructionIndex,
  missingHooks,
  rulePaths,
} from '../lib/blocks.mjs';
import {loadConfig, stagedConfig} from '../lib/config.mjs';
import {COPY_DIR, generatedFiles, hasCopy, isTrellis, ownTree, refuseOtherCheckout, verifyCopy} from '../lib/copy.mjs';
import {globToRegExp} from '../lib/glob.mjs';
import {localeOf} from '../lib/locale.mjs';
import {inPackage, packagesOf} from '../lib/packages.mjs';
import {projectTree, topLevel} from '../lib/tree.mjs';

export const AGENT_LIMIT_BYTES = 4 * 1024;
export const FROZEN_SLACK = 1.02;

/**
 * Phrases that narrate what the code used to be instead of what it is, per locale. A project is
 * checked with the list of its project.locale and always with the en one, because code comments
 * are English.
 */
export const NARRATIVE = {
  en: [
    /\bused to\b/iu,
    /\bthe old\s/iu,
    /\bretired with\b/iu,
    /\bwas replaced\b/iu,
    /\bno longer\b/iu,
    /\bany ?more\b/iu,
    /\b(?:is|are) gone\b/iu,
    /\b(?:since|before|until) #\d/iu,
  ],
  es: [
    /(?<![\p{L}])ya no(?![\p{L}])/iu,
    /(?<![\p{L}])sol[ií]a(?:n)?(?![\p{L}])/iu,
    /(?<![\p{L}])antes (?:era|eran|se|hab[ií]a|estaba|usaba)(?![\p{L}])/iu,
    // `antes <word> <verb>`, the word not a function word (`antes qué había`, `antes si estaba` ask).
    /(?<![\p{L}])antes (?!(?:de|que|qu[eé]|si|lo|la|los|las)(?![\p{L}]))\p{L}+ (?:era|eran|hab[ií]a|estaba|usaba)(?![\p{L}])/iu,
    // `ahora` only as the contrast: a line that also holds `antes`, or `y ahora` / `pero ahora`.
    /(?<![\p{L}])antes(?![\p{L}]).*(?<![\p{L}])ahora(?![\p{L}])/iu,
    /(?<![\p{L}])(?:y|pero) ahora(?![\p{L}])/iu,
    /(?<![\p{L}])(?:se reemplaz[oó]|fue reemplazad[oa]|fueron reemplazad[oa]s)(?![\p{L}])/iu,
    /(?<![\p{L}])dej[oó] de(?![\p{L}])/iu,
    /(?<![\p{L}])(?:desde|hasta|a partir de) #\d/iu,
    /(?<![\p{L}])(?:anteriormente|en su momento)(?![\p{L}])/iu,
  ],
};

/** The narrative phrases a project of this locale is checked with. */
export const narrativeFor = locale => (locale === 'en' ? NARRATIVE.en : [...NARRATIVE.en, ...NARRATIVE[locale]]);

/** A tracker reference, not an HTML entity, a path or a color. */
export const TRACKER_REF = /(?<![\w&/])#\d+\b/gu;

/** The extensions a rule names files by, per workspace.kind. */
const NAMED_EXT = {flutter: ['dart'], dart: ['dart'], node: ['ts', 'tsx', 'js', 'jsx', 'mjs', 'cjs']};

/** `<left>: <right> | <reason>` entries of an allowlist, as a set of `<left>: <right>`. */
const allowlist = values => new Set(values.map(v => v.split('|')[0].trim()));

export function hygiene(root, {staged = false} = {}) {
  const whole = projectTree(root, {staged});
  const tree = ownTree(whole);
  const config = staged ? stagedConfig(tree) : loadConfig({cwd: root});

  const findings = [];
  const fail = (file, message) => findings.push(`${file}: ${message}`);
  const {nested, rules} = instructionIndex(tree);
  const agents = tree.files.filter(f => /^\.claude\/agents\/[^/]+\.md$/.test(f));
  const skills = tree.files.filter(f => /^\.claude\/skills\/[^/]+\/SKILL\.md$/.test(f));
  const docs = tree.files.filter(f => /^docs\/.*\.md$/.test(f));
  const rootFile = tree.has('CLAUDE.md') ? ['CLAUDE.md'] : [];
  if (rootFile.length === 0) fail('CLAUDE.md', 'is not there, and the method is always loaded from it: write it from the template CLAUDE.root.md');
  const testing = tree.has('TESTING.md') ? ['TESTING.md'] : [];
  const instructions = [...rootFile, ...nested, ...rules, ...agents, ...skills, ...testing];

  // The present tense, and no tracker references.
  const keepRef = allowlist(config.all('hygiene.keepRef'));
  const narrative = narrativeFor(localeOf(config));
  for (const file of instructions) {
    const text = tree.read(file);
    text.split('\n').forEach((line, i) => {
      for (const phrase of narrative) {
        if (phrase.test(line)) fail(file, `line ${i + 1} narrates history (${phrase.source}): rewrite the paragraph to its current state; the history stays in the commit`);
      }
    });
    const refs = [...text.matchAll(TRACKER_REF)].map(m => m[0]).filter(ref => !keepRef.has(`${file}: ${ref}`));
    if (refs.length) fail(file, `cites ${[...new Set(refs)].join(', ')}: name the concept, not the issue (or list it in [hygiene] keepRef with its reason)`);
  }

  // Rules load where they speak.
  const kind = config.get('workspace.kind');
  const extensions = config.all('hygiene.namedExt').length ? config.all('hygiene.namedExt') : NAMED_EXT[kind] ?? [];
  for (const value of config.all('workspace.manifest')) {
    if (/[/*?[\]{}]/u.test(value)) fail('trellis.config', `[workspace] manifest: ${value} is not the name of a file, so it finds no package`);
  }
  let packages = [];
  try {
    packages = packagesOf(tree, config);
  } catch (error) {
    fail('trellis.config', `[workspace] notPackage: ${error.message}`);
  }
  const namedElsewhere = allowlist(config.all('hygiene.namedElsewhere'));
  const globsOf = new Map();
  for (const rule of rules) {
    const text = tree.read(rule);
    const globs = [];
    for (const glob of rulePaths(text)) {
      try {
        const re = globToRegExp(glob);
        globs.push(re);
        if (!tree.files.some(f => re.test(f))) fail(rule, `the glob ${glob} matches no file, so the rule never loads through it`);
      } catch (error) {
        fail(rule, error.message);
      }
    }
    globsOf.set(rule, globs);
    if (extensions.length === 0 || globs.length === 0) continue;
    const named = new Set();
    const token = new RegExp(`\`([^\`\\s]+\\.(?:${extensions.join('|')}))\``, 'gu');
    for (const [, name] of text.matchAll(token)) {
      const hit = [name, ...packages.map(p => inPackage(p, name))].find(c => tree.has(c));
      if (hit) named.add(hit);
    }
    const name = path.posix.basename(rule);
    for (const file of named) {
      if (namedElsewhere.has(`${name}: ${file}`)) continue;
      if (!globs.some(re => re.test(file))) fail(rule, `names ${file}, which does not load it: add a glob, name the symbol instead, or list it in [hygiene] namedElsewhere`);
    }
  }
  for (const entry of config.all('hygiene.mustNotLoad')) {
    const [pair, reason = ''] = entry.split('|').map(s => s.trim());
    const [rule, file] = pair.split(': ');
    const rulePath = `.claude/rules/${rule}`;
    if (!tree.has(rulePath)) {
      fail('trellis.config', `[hygiene] mustNotLoad names the rule ${rule}, which does not exist`);
      continue;
    }
    if (!tree.has(file)) {
      fail('trellis.config', `[hygiene] mustNotLoad names ${file}, which must exist for the check to mean something`);
      continue;
    }
    if ((globsOf.get(rulePath) ?? []).some(re => re.test(file))) fail(rulePath, `loads ${file}, which it must not: ${reason}`);
  }

  // Sizes.
  const limit = key => Number(config.get(`hygiene.${key}`));
  const over = (file, max, advice) => {
    const size = tree.size(file);
    if (size > max) fail(file, `${size} bytes, over its limit of ${max}: ${advice}`);
  };
  for (const file of rootFile) over(file, limit('rootLimit'), 'move a domain to a nested CLAUDE.md or a rule with paths:');
  for (const file of [...nested, ...testing]) over(file, limit('nestedLimit'), 'move a section to a rule with paths:');
  for (const file of rules) over(file, limit('ruleLimit'), 'split it by subdomain, each half with the globs of its own files');
  for (const file of agents) over(file, AGENT_LIMIT_BYTES, 'a subagent does one check; what it needs is in the files it reads');
  if (!staged) {
    const total = rules.reduce((sum, rule) => sum + tree.size(rule), 0);
    if (total > limit('rulesTotalLimit')) fail('.claude/rules', `the rules add up to ${total} bytes, over ${limit('rulesTotalLimit')}: rewrite what grew to its current state before adding`);
  }
  const frozen = new Map(config.all('hygiene.frozen').map(v => v.trim().split(/\s+/)).map(([file, size]) => [file, Number(size)]));
  for (const file of [...skills, ...docs]) {
    if (!frozen.has(file)) {
      fail(file, 'has no frozen size: trellis hygiene --freeze records it in [hygiene] frozen');
      continue;
    }
    over(file, Math.round(frozen.get(file) * FROZEN_SLACK), 'rewrite what grew to its current state');
  }

  // Packages, orientation and generated content.
  for (const pkg of packages) {
    if (!tree.has(inPackage(pkg, 'CLAUDE.md'))) fail(pkg || '.', 'is a [workspace] package without its CLAUDE.md (the scaffold skill drafts one; notPackage takes out an example or a fixture, with its reason)');
  }
  const generated = generateBlocks(tree, config);
  for (const [file, ids] of Object.entries(BLOCK_FILES)) {
    if (!tree.has(file)) continue;
    const present = blocksIn(tree.read(file));
    for (const id of ids) {
      if (!(id in present) || !(id in generated)) continue;
      if (present[id] !== generated[id]) fail(file, `the block ${id} does not match its source: run trellis sync`);
    }
    if (file === 'CLAUDE.md' && 'method' in generated && !('method' in present)) {
      fail(file, 'has no <!-- trellis:method --> block: the method is always loaded from there');
    }
    if (file === 'CLAUDE.md' && 'orientation' in present) {
      for (const listed of [...nested, ...rules]) {
        if (!present.orientation.includes(`\`${listed}\``)) fail(file, `the orientation table does not list ${listed}: run trellis sync`);
      }
    }
  }
  const settingsText = tree.read('.claude/settings.json');
  const copy = hasCopy(whole);
  if (settingsText === null) {
    if (copy) fail('.claude/settings.json', 'is not there, and it loads the hooks of the copy: run trellis sync');
  } else {
    let settings = null;
    try {
      settings = JSON.parse(settingsText);
    } catch {
      fail('.claude/settings.json', 'does not parse as JSON');
    }
    if (settings) {
      const deny = settings.permissions?.deny ?? [];
      for (const entry of generatedDeny(config, {copy})) {
        if (!deny.includes(entry)) fail('.claude/settings.json', `permissions.deny lacks ${entry}: run trellis sync`);
      }
      for (const {event, group} of copy ? missingHooks(settings) : []) {
        fail('.claude/settings.json', `hooks.${event} lacks ${group.hooks[0].command}: run trellis sync`);
      }
    }
  }
  if (tree.files.some(f => f.startsWith('.githooks/')) && tree.read(FIND_TRELLIS_COPY) !== findTrellisSource()) {
    fail(FIND_TRELLIS_COPY, 'is not trellis\'s lib/find-trellis.sh: run trellis sync');
  }
  if (isTrellis(tree)) {
    const {expected, leftOver} = generatedFiles(tree);
    const bytes = tree.bytes([...expected.keys()]);
    for (const [file, {source, bytes: theirs}] of expected) {
      if (!bytes.get(file)) fail(file, `is not there: trellis sync writes it from ${source}`);
      else if (!bytes.get(file).equals(theirs)) fail(file, `is not what sync writes from ${source}: run trellis sync`);
    }
    for (const file of leftOver) fail(file, 'has no source in skills/ or agents/: run trellis sync');
  }
  // The settings that load the copy's hooks need it there.
  if (copy || (settingsText ?? '').includes(`${COPY_DIR}/`)) findings.push(...verifyCopy(whole));

  return findings;
}

/** Records the size of every frozen file in [hygiene] frozen; returns the lines that rose. */
export function freeze(root) {
  const tree = ownTree(projectTree(root));
  const config = loadConfig({cwd: root});
  const was = new Map(config.all('hygiene.frozen').map(v => v.trim().split(/\s+/)).map(([file, size]) => [file, Number(size)]));
  const files = tree.files.filter(f => /^\.claude\/skills\/[^/]+\/SKILL\.md$/.test(f) || /^docs\/.*\.md$/.test(f));
  const file = path.join(root, 'trellis.config');
  const git = (...args) => execFileSync('git', ['config', '-f', file, ...args], {stdio: ['ignore', 'pipe', 'ignore']});
  try {
    git('--unset-all', 'hygiene.frozen');
  } catch {
    // Nothing frozen yet.
  }
  const rose = [];
  for (const f of files) {
    const size = tree.size(f);
    git('--add', 'hygiene.frozen', `${f} ${size}`);
    if (was.has(f) && size > was.get(f)) rose.push(`${f}: ${was.get(f)} -> ${size} (the ratchet asks for the escape)`);
  }
  return {files, rose};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  const unknown = args.filter(a => a !== '--staged' && a !== '--freeze');
  if (unknown.length) {
    console.error('usage: trellis hygiene [--staged] [--freeze]');
    process.exit(2);
  }
  const root = topLevel();
  refuseOtherCheckout(root, 'hygiene');
  if (args.includes('--freeze')) {
    const {files, rose} = freeze(root);
    console.log(`hygiene: froze ${files.length} file(s) in [hygiene] frozen`);
    for (const line of rose) console.log(`  rose ${line}`);
  }
  const findings = hygiene(root, {staged: args.includes('--staged')});
  for (const line of findings) console.log(`  FAIL  ${line}`);
  console.log(findings.length ? `\nhygiene: ${findings.length} finding(s)` : 'hygiene: ok');
  process.exit(findings.length ? 1 : 0);
}
