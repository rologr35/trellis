// The judgment of `trellis ratchet` (scripts/ratchet.sh holds the contract).
//   node ratchet.mjs <base-ref|-> <branch|-> <escaped:true|false>

import {execFileSync} from 'node:child_process';
import {mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {loadConfig} from '../lib/config.mjs';
import {PR_SECTIONS, localeOf} from '../lib/locale.mjs';

const [, , baseRef, branchArg, escaped] = process.argv;
const branch = branchArg === '-' ? '' : branchArg;

const git = (...args) => {
  try {
    return execFileSync('git', args, {encoding: 'utf8', maxBuffer: 64 << 20, stdio: ['ignore', 'pipe', 'ignore']});
  } catch {
    return null;
  }
};

let beforeRev = 'HEAD';
let afterRev = '';
let diffArgs = ['diff', '--cached', '--name-status', '-M'];
if (baseRef !== '-') {
  const base = git('merge-base', baseRef, 'HEAD')?.trim();
  if (!base) {
    console.error(`ratchet: no merge base between ${baseRef} and HEAD (a shallow clone?); fetch the full history`);
    process.exit(2);
  }
  beforeRev = base;
  afterRev = 'HEAD';
  diffArgs = ['diff', '--name-status', '-M', base, 'HEAD'];
}

const blobs = new Map();
const blob = ref => {
  if (!blobs.has(ref)) blobs.set(ref, git('show', ref));
  return blobs.get(ref);
};
const before = file => blob(`${beforeRev}:${file}`);
const after = file => blob(`${afterRev}:${file}`);

const entries = (git(...diffArgs) ?? '').split('\n').filter(Boolean).map(l => l.split('\t'));
const deleted = entries.filter(([status]) => status === 'D').map(([, file]) => file);
const changed = entries
  .filter(([status]) => status !== 'D')
  .map(e => ({file: e.at(-1), was: e[0].startsWith('R') ? e[1] : e.at(-1)}));
const staged = new Map(changed.map(c => [c.file, c.was]));

// The config on both sides, read through the one reader from temporary copies.
const scratch = mkdtempSync(path.join(tmpdir(), 'trellis-ratchet-'));
const configAt = (text, name, label) => {
  const file = path.join(scratch, name);
  if (text !== null) writeFileSync(file, text);
  try {
    return loadConfig({file, label, throws: true});
  } catch (error) {
    return error;
  }
};
// The config after the change fails closed when it does not parse. One that did not parse before
// is judged as the schema's defaults (a file that does not exist), never as the change's own
// config: the change that repairs it passes only if it loosens nothing against the defaults.
const configWas = before('trellis.config');
const newConfig = configAt(after('trellis.config'), 'after.config', `trellis.config (${afterRev ? afterRev : 'staged'})`);
let oldConfig = configAt(configWas, 'before.config', `trellis.config (${beforeRev})`);
if (newConfig instanceof Error) {
  console.error(newConfig.message);
  process.exit(3);
}
if (oldConfig instanceof Error) oldConfig = loadConfig({file: path.join(scratch, 'absent.config')});
rmSync(scratch, {recursive: true, force: true});
// The policy is the one in force before the change, so a change cannot exempt itself.
const policy = configWas === null ? newConfig : oldConfig;

const findings = [];
const add = (what, cost, alternative) => findings.push({what, cost, alternative});

// Deleted tests.
const testFile = policy.all('ratchets.testFile').map(p => new RegExp(p));
for (const file of deleted) {
  if (testFile.some(re => re.test(file))) {
    add(`deletes the test ${file}`, 'the behaviour it covered stops being checked', 'rewrite or move the test; it goes away together with the code it covers');
  }
}

// Suppressions, net over the change's code files; a line moved is not added.
const notCode = file => /\.(md|txt)$/i.test(file) || path.basename(file) === 'trellis.config';
const count = (text, re) => (text ?? '').match(re)?.length ?? 0;
for (const source of policy.all('ratchets.suppression')) {
  const re = new RegExp(source, 'g');
  let net = 0;
  const grew = [];
  for (const {file, was} of changed) {
    if (notCode(file)) continue;
    const delta = count(after(file), re) - count(before(was), re);
    net += delta;
    if (delta > 0) grew.push(file);
  }
  for (const file of deleted) if (!notCode(file)) net -= count(before(file), re);
  if (net > 0) {
    add(`adds ${net} suppression(s) /${source}/ (${grew.join(', ')})`, 'the finding stays in the code and the next one hides behind it', 'fix what the analyzer or the test reports');
  }
}

// Lint configs. Two readings: per rule, the sum of its severities over the file (a rule lowered or
// dropped), and the entries that switch something off (an analyzer error set to ignore, a rule set
// to false or off, an excluded path), of which a new one loosens even when the rule it silences is
// inherited from an include and was never written in the file.
const ESLINT_RANK = {off: 0, warn: 1, error: 2, 0: 0, 1: 1, 2: 2};
const DART_RANK = {ignore: 0, info: 1, warning: 2, error: 3, false: 0, true: 1};
const unquote = v => v.trim().replace(/^["']|["']$/g, '');
function readLint(file, text) {
  const ranks = new Map();
  const off = new Set();
  const bump = (rule, rank) => ranks.set(rule, (ranks.get(rule) ?? 0) + rank);
  if (/\.ya?ml$/.test(file)) {
    let top = '';
    let second = '';
    for (const line of (text ?? '').split('\n')) {
      if (/^\s*(#|$)/.test(line)) continue;
      const indent = line.match(/^ */)[0].length;
      const key = /^\s*([\w./:-]+):\s*(.*)$/.exec(line);
      const item = /^\s*-\s*(\S.*?)\s*$/.exec(line);
      if (indent === 0 && key) {
        top = key[1];
        second = '';
        if (top === 'include' && key[2]) bump(`include ${unquote(key[2])}`, 1);
        continue;
      }
      if (indent <= 2 && key && !key[2]) {
        second = key[1];
        continue;
      }
      const value = key ? unquote(key[2]) : '';
      if (top === 'linter' && second === 'rules') {
        if (item) bump(item[1], 1);
        else if (key) {
          bump(key[1], DART_RANK[value] ?? 1);
          if (value === 'false' || value === 'off') off.add(`rules ${key[1]}: ${value}`);
        }
      } else if (top === 'analyzer' && second === 'errors' && key) {
        bump(`errors ${key[1]}`, DART_RANK[value] ?? 0);
        if (value === 'ignore') off.add(`errors ${key[1]}: ignore`);
      } else if (top === 'analyzer' && second === 'exclude' && item) {
        off.add(`exclude ${unquote(item[1])}`);
      }
    }
    return {ranks, off};
  }
  const re = /['"]([@\w/-]+)['"]\s*:\s*\[?\s*['"]?(error|warn|off|0|1|2)['"]?(?=\s*[,\]}\n])/g;
  for (const [, rule, level] of (text ?? '').matchAll(re)) {
    bump(rule, ESLINT_RANK[level]);
    if (level === 'off' || level === '0') off.add(`${rule}: ${level}`);
  }
  const ignores = /ignores\s*:\s*\[([^\]]*)\]/g;
  for (const [, list] of (text ?? '').matchAll(ignores)) {
    for (const [, entry] of list.matchAll(/['"]([^'"]+)['"]/g)) off.add(`ignores ${entry}`);
  }
  return {ranks, off};
}
const lintNames = policy.all('ratchets.lintConfig');
for (const [file, was] of staged) {
  if (!lintNames.some(name => file === name || path.basename(file) === name)) continue;
  const old = readLint(file, before(was) ?? '');
  const now = readLint(file, after(file));
  for (const [rule, sum] of old.ranks) {
    if ((now.ranks.get(rule) ?? 0) < sum) {
      add(`${file}: lowers or drops ${rule}`, 'every file the rule covered can regress without a signal', 'fix the findings, or exclude only the files that need it, each with its reason');
    }
  }
  for (const entry of now.off) {
    if (!old.off.has(entry)) {
      add(`${file}: switches off ${entry}`, 'what it silences stops being reported, in every file it covers', 'fix the findings; an exclusion that must stay names its reason in the pull request');
    }
  }
}
for (const file of deleted) {
  if (lintNames.some(name => file === name || path.basename(file) === name)) {
    add(`deletes the lint config ${file}`, 'every rule it held stops being checked', 'keep the file and change the rules one by one');
  }
}

// Claude Code settings: the default model and the hooks.
const settings = '.claude/settings.json';
if (staged.has(settings)) {
  const parse = text => {
    try {
      return JSON.parse(text ?? '');
    } catch {
      return null;
    }
  };
  const old = parse(before(staged.get(settings)));
  const now = parse(after(settings));
  if (old && now) {
    const tier = m => (/opus/.test(m ?? '') ? 3 : /sonnet/.test(m ?? '') ? 2 : /haiku/.test(m ?? '') ? 1 : 0);
    if (tier(old.model) > 0 && tier(now.model) > tier(old.model)) {
      add(`${settings}: raises the model from ${old.model} to ${now.model}`, 'every session of the project spends more of the quota', 'raise the model for one session with /model');
    }
    const hooks = s => JSON.stringify(s.hooks ?? {}).match(/"type":"command"/g)?.length ?? 0;
    if (hooks(now) < hooks(old)) {
      add(`${settings}: drops ${hooks(old) - hooks(now)} hook(s)`, 'what the hook guarded stops being guarded in every session', 'fix the false positive of the hook instead');
    }
  }
}

// trellis.config: limits, frozen sizes, allowlists and the ratchets' own lists.
if (configWas !== null) {
  for (const key of ['hygiene.rootLimit', 'hygiene.nestedLimit', 'hygiene.ruleLimit', 'hygiene.rulesTotalLimit']) {
    const was = Number(oldConfig.get(key));
    const now = Number(newConfig.get(key));
    if (now > was) {
      add(`trellis.config: raises ${key} from ${was} to ${now}`, 'every session pays the extra bytes on every turn that loads the file', 'rewrite what grew to its current state, or move a domain to a rule with paths:');
    }
  }
  const frozen = cfg => new Map(cfg.all('hygiene.frozen').map(v => v.trim().split(/\s+/)).map(([file, size]) => [file, Number(size)]));
  const frozenNow = frozen(newConfig);
  for (const [file, size] of frozen(oldConfig)) {
    if (!frozenNow.has(file)) {
      if (after(file) !== null) {
        add(`trellis.config: unfreezes ${file}`, 'the file can grow without a limit', 'keep the entry; lower it when the file shrinks');
      }
    } else if (frozenNow.get(file) > size) {
      add(`trellis.config: raises the frozen size of ${file} from ${size} to ${frozenNow.get(file)}`, 'every reader of the file pays the extra bytes', 'rewrite what grew to its current state');
    }
  }
  for (const key of ['hygiene.keepRef', 'hygiene.namedElsewhere', 'hygiene.mustNotLoad']) {
    const was = oldConfig.all(key).length;
    const now = newConfig.all(key).length;
    if (now > was) {
      add(`trellis.config: ${key} grows from ${was} to ${now} entries`, 'the hygiene check stops seeing that case', 'fix the file so the check passes as it is');
    }
  }
  for (const key of ['ratchets.suppression', 'ratchets.testFile', 'ratchets.lintConfig']) {
    const now = new Set(newConfig.all(key));
    const gone = oldConfig.all(key).filter(v => !now.has(v));
    if (gone.length > 0) {
      add(`trellis.config: ${key} drops ${gone.join(', ')}`, 'what it matched stops being watched by the ratchet', 'keep the entry');
    }
  }
}

if (findings.length === 0) process.exit(0);
const setback = PR_SECTIONS[localeOf(newConfig)].setback;
const list = findings.map(f => `  - ${f.what}\n      cost: ${f.cost}\n      alternative: ${f.alternative}`).join('\n');
if (escaped === 'true') {
  console.error(`ratchet: warning, ${branch || 'this change'} loosens ratchets with the person's confirmation (the pull request carries **${setback}**):\n${list}`);
  process.exit(0);
}
const escape = branch ? `git config branch.${branch}.ratchet-loosened true` : 'git config branch.<branch>.ratchet-loosened true';
console.error(`ratchet: this change loosens a ratchet:
${list}
Before going on, tell the person what regresses, its cost and the alternative that does not regress, and wait.
Only with their confirmation: ${escape}, and the pull request carries a **${setback}** section.`);
process.exit(1);
