// The judgment of `trellis issue` (scripts/issue.sh holds the contract).
//   node issue-check.mjs body <file>    judges a body before it is published
//   node issue-check.mjs class <file>   prints S, M or L, the class of a body that passes
//   node issue-check.mjs issue <json> <comments>   judges an issue as REST gives it, with its comments,
//                                       one per line
//   node issue-check.mjs deps <json> <comments>    prints what the plan of an issue depends on, one per
//                                       line: ref<TAB><owner/repo or -><TAB><n>, or text<TAB><the line>
//   node issue-check.mjs print <json> <comments>   prints the plan of an issue, its amendments resolved
//   node issue-check.mjs issue-class <json> <comments>
//   node issue-check.mjs attended <json> <comments>   prints what a run without a person cannot take, one
//                                       per line
//   node issue-check.mjs stop <file> <comment>      judges the text of a stop and writes its comment
//   node issue-check.mjs refusal <file> <comment> [<branches>]   writes the comment of a plan a run could not
//                                       take, for the reasons of the file, one per line
//   node issue-check.mjs follow-up <file> <body> <reopen>  judges the body of a follow-up and writes it,
//                                       with the line of what reopens it when there is one
//   node issue-check.mjs gates <json> <comments>   judges the files of the branch against the gates of the plan
// The text is data: nothing in it is run.

import {execFileSync} from 'node:child_process';
import {mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {loadConfig} from '../lib/config.mjs';
import {globToRegExp} from '../lib/glob.mjs';
import {ISSUE, PR_SECTIONS, STOP, localeOf} from '../lib/locale.mjs';
import {styleMisses} from '../lib/style.mjs';
import {commentsOf, mayWrite, readBody, sectionOf as sectionNamed} from './issue-close.mjs';

const [, , mode, file, commentsFile, reopen = ''] = process.argv;
const config = loadConfig();
const L = ISSUE[localeOf(config)];
const CLASSES = ['S', 'M', 'L'];

const escape = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const indentOf = line => /^\s*/.exec(line)[0].length;
const isBullet = line => /^\s*(?:[-*+]|\d+[.)])\s/.test(line);
const isHeading = line => /^ {0,3}#{1,6}\s/.test(line);

/** The lines of a text, with LF line ends and composed letters; `code` marks the ones of a fence. */
function linesOf(text) {
  let fence = '';
  return (text ?? '').replace(/\r\n?/g, '\n').normalize('NFC').split('\n').map(line => {
    const mark = /^ {0,3}(`{3,}|~{3,})/.exec(line)?.[1] ?? '';
    if (fence === '' && mark) {
      fence = mark;
      return {text: line, code: true};
    }
    const closes = fence !== '' && mark[0] === fence[0] && mark.length >= fence.length && line.trim() === mark;
    const code = fence !== '';
    if (closes) fence = '';
    return {text: line, code};
  });
}

const textOf = lines => lines.map(l => l.text).join('\n');

const COMPLEXITY = new RegExp(`^${escape(L.complexity)}\\s*:(.*)$`);

/**
 * The complexity line, which is the last line with text: its class, '' when the line is there with
 * another value, null when the last line is not one. `rest` is the lines before it.
 */
function complexityOf(lines) {
  const at = lines.findLastIndex(l => l.text.trim() !== '');
  const m = at === -1 || lines[at].code ? null : COMPLEXITY.exec(lines[at].text.trimEnd());
  if (!m) return {value: null, rest: lines};
  const value = CLASSES.find(c => lines[at].text.trimEnd() === `${L.complexity}: ${c}`) ?? '';
  return {value, rest: lines.slice(0, at)};
}

/** The sections of the mould that a body has, in its order; each one ends at the next `#` or `##`. */
function sectionsOf(lines) {
  const found = [];
  let current = null;
  for (const line of lines) {
    if (!line.code && /^ {0,3}#{1,2}\s/.test(line.text)) {
      const name = /^ {0,3}##\s+(.*?)\s*#*\s*$/.exec(line.text)?.[1];
      current = L.sections.includes(name) ? {name, lines: []} : null;
      if (current) found.push(current);
    } else if (current) {
      current.lines.push(line);
    }
  }
  return found;
}

/** What a body says: its sections and its complexity. */
function parse(text) {
  const {value, rest} = complexityOf(linesOf(text));
  return {sections: sectionsOf(rest), complexity: value};
}

/** What a comment amends, when it is an amendment: its `###` sections of the mould, and its class. */
function amendmentOf(comment) {
  if (!mayWrite(comment)) return null;
  const {value, rest} = complexityOf(linesOf(comment.body));
  const first = rest.find(l => l.text.trim() !== '');
  if (!first || first.code || !new RegExp(`^##\\s+${escape(L.amendment)}\\s+\\([^)]+\\)`).test(first.text)) return null;
  const sections = new Map();
  let current = null;
  for (const line of rest) {
    const name = line.code ? undefined : /^ {0,3}###\s+(.*?)\s*#*\s*$/.exec(line.text)?.[1];
    if (!line.code && /^ {0,3}#{1,2}\s/.test(line.text)) {
      current = null;
    } else if (L.sections.includes(name)) {
      current = {name, lines: [], amended: true};
      sections.set(name, current);
    } else if (current) {
      current.lines.push(line);
    }
  }
  return {sections, complexity: value};
}

/**
 * The plan of an issue, with when it was last written (`since`): the body, with each section and the class of the last amendment that has it. The
 * body of someone who may not write in the repository is none: `note` says so.
 */
function resolve(issue, comments) {
  const plan = {...parse(mayWrite(issue) ? issue.body : ''), since: issue.created_at};
  if (!mayWrite(issue)) {
    plan.note = `the body is not a plan: its author (${issue.user?.login ?? 'unknown'}) is not an owner, a member or a collaborator of the repository, so the plan is what the amendments carry`;
  }
  for (const comment of [...comments].sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)))) {
    const amendment = amendmentOf(comment);
    if (!amendment) continue;
    plan.sections = [...plan.sections.filter(s => !amendment.sections.has(s.name)), ...amendment.sections.values()];
    plan.complexity = amendment.complexity ?? plan.complexity;
    plan.since = comment.created_at;
  }
  return plan;
}

/** The text of a plan, as a body of the mould. */
function render(plan) {
  const parts = L.sections.flatMap(name => plan.sections.filter(s => s.name === name).map(s => `## ${name}\n\n${textOf(s.lines).trim()}`));
  if (plan.complexity) parts.push(`${L.complexity}: ${plan.complexity}`);
  return parts.join('\n\n');
}

/** The issues the plan depends on, and the lines a person reads. */
function dependencies(plan) {
  const refs = new Map();
  const texts = [];
  for (const section of plan.sections.filter(s => s.name === L.sections[0])) {
    for (const group of labelled(section.lines, L.dependsOn)) {
      const lines = group.inline === '' ? group.lines.map(l => l.text) : [group.inline];
      for (const line of lines) {
        for (const [whole, repo, n] of line.matchAll(REFERENCE)) refs.set(whole, {repo: repo ?? '-', n});
        const rest = line.replace(REFERENCE, '').replace(/(?<!\p{L})(?:and|y|e)(?!\p{L})/gu, '');
        if (/[\p{L}\p{N}]/u.test(rest)) texts.push(line.trim().replace(/\t/g, ' '));
      }
    }
  }
  return {refs: [...refs.values()], texts};
}

/** The text without what the mould leaves for the person to fill, and without comments. */
const written = text => text.replace(/<!--[\s\S]*?(?:-->|$)/g, '').replace(/\{\{[^}]*\}\}/g, '');

/**
 * The lists a label opens (`Out of scope:`, `- **New**: ...`, `### New`), each one the text after
 * the label and the lines that belong to it: the more indented ones for a bullet, the ones up to
 * the next heading of its level for a heading, the rest of the paragraph for a label with text, and
 * the paragraph or the list that follows for a label alone.
 */
function labelled(lines, label) {
  const name = escape(label);
  const inlineLabel = new RegExp(`^(\\s*)((?:[-*+]|\\d+[.)])\\s+)?(?:(?:\\*\\*|__)${name}(?:\\*\\*|__)\\s*:|(?:\\*\\*|__)${name}\\s*:(?:\\*\\*|__)|${name}\\s*:)\\s*(.*)$`);
  const headingLabel = new RegExp(`^ {0,3}(#{2,6})\\s+${name}\\s*:?\\s*#*\\s*$`);
  const groups = [];
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].code) continue;
    const heading = headingLabel.exec(lines[i].text);
    const inline = heading ? null : inlineLabel.exec(lines[i].text);
    if (!heading && !inline) continue;
    const group = {start: i, inline: inline?.[3] ?? '', lines: []};
    let seen = group.inline !== '';
    let blank = false;
    let j = i + 1;
    for (; j < lines.length; j++) {
      const {text, code} = lines[j];
      const empty = text.trim() === '';
      if (heading) {
        const level = code ? null : /^ {0,3}(#{1,6})\s/.exec(text)?.[1].length;
        if (level && level <= heading[1].length) break;
      } else if (!code && !empty) {
        if (isHeading(text)) break;
        if (inline[2]) {
          if (indentOf(text) <= inline[1].length) break;
        } else if (indentOf(text) === 0 && blank && group.inline !== '') {
          break;
        } else if (indentOf(text) === 0 && !isBullet(text) && ((blank && seen) || /^(?:\*\*|__)[^*_]+(?:\*\*\s*:|:\*\*|__\s*:|:__)/.test(text))) {
          break;
        }
      }
      if (!empty) seen = true;
      blank = empty;
      group.lines.push(lines[j]);
    }
    group.end = j;
    groups.push(group);
    i = j - 1;
  }
  return groups;
}

/** The items of a list: one per bullet of the least indent, and the text before the first one. */
function itemsOf(group) {
  const bullets = group.lines.filter(l => !l.code && isBullet(l.text)).map(l => indentOf(l.text));
  const least = bullets.length ? Math.min(...bullets) : 0;
  const items = [[group.inline]];
  for (const line of group.lines) {
    if (!line.code && isBullet(line.text) && indentOf(line.text) === least) items.push([line.text.replace(/^\s*(?:[-*+]|\d+[.)])\s+/, '')]);
    else items.at(-1).push(line.text);
  }
  return items.map(item => item.join('\n').trim()).filter(Boolean);
}

/** Whether a section says nothing: only blanks, comments, placeholders, a label or the list it opens. */
function isEmpty(lines) {
  const dropped = new Set();
  for (const label of [L.dependsOn, L.outOfScope]) {
    for (const group of labelled(lines, label)) for (let i = group.start; i < group.end; i++) dropped.add(i);
  }
  const label = new RegExp(`(?:\\*\\*|__)?${escape(L.newFiles)}(?:\\*\\*|__)?\\s*:`, 'g');
  return !/[\p{L}`]/u.test(written(textOf(lines.filter((_, i) => !dropped.has(i)))).replace(label, ''));
}

/** The paths in backticks of some lines, as paths from the root of the repository. */
function pathsOf(lines, tree) {
  const paths = [];
  for (const line of lines) {
    if (line.code) continue;
    for (const [, token] of line.text.matchAll(/`([^`]+)`/g)) {
      const name = token.trim().replace(/:\d+(?:-\d+)?$/, '').replace(/^\.\//, '').replace(/\/+$/, '');
      // A command, a glob, a placeholder, a URL and a path outside the repository are not judged.
      if (!/^[\p{L}\p{N}_.@+()[\]/-]+$/u.test(name) || /^[-/]|\/\//.test(name)) continue;
      // A name without a folder is a file when some file has its extension: README.md is one, and a
      // key such as tracker.kind is not. One that ends in / is a folder, when it is there.
      const extension = /[^.]\.([^.]+)$/.exec(name)?.[1];
      if (!name.includes('/') && !/^\.[\p{L}]/u.test(name) && !(extension && tree?.extensions.has(extension)) && !(/\/\s*$/.test(token) && tree?.entries.has(name))) continue;
      paths.push(name);
    }
  }
  return [...new Set(paths)];
}

const sectionOf = (plan, name) => plan.sections.find(s => s.name === name)?.lines ?? [];

/** The gates the Risks of a plan open with: their names, [] for none, null without the line. */
function gatesOf(plan) {
  const first = written(textOf(sectionOf(plan, L.sections[3]))).split('\n').find(line => line.trim() !== '') ?? '';
  const value = new RegExp(`^\\s*(?:[-*+]\\s+)?(?:\\*\\*|__)?${escape(L.gates)}(?:(?:\\*\\*|__)\\s*:|\\s*:(?:\\*\\*|__)?)(.*)$`).exec(first)?.[1];
  if (value === undefined) return null;
  const names = value.split(/\.(?:\s|$)/)[0].split(/,|\s(?:and|y|e)\s/).map(s => s.trim().replace(/^`(.*)`$/, '$1')).filter(Boolean);
  if (names.length === 0) return null;
  return names.length === 1 && names[0].toLowerCase() === L.noGates ? [] : names;
}

/** The patterns of a gate, or the misses of the ones that are not plain globs. */
function patternsOf(gate, from = config) {
  const patterns = [];
  const misses = [];
  for (const glob of from.all(`gate.${gate}.paths`)) {
    try {
      patterns.push(globToRegExp(glob));
    } catch (error) {
      misses.push(`gate.${gate}.paths: ${error.message}`);
    }
  }
  return {patterns, misses};
}

/** What the Gates line of a plan lacks, given the paths of its Layers and files. */
function judgeGates(plan, paths, tree) {
  const named = gatesOf(plan);
  if (named === null) return [`${L.sections[3]} does not open with \`${L.gates}: ${L.noGates}\`, or the names of the gates the plan touches`];
  const known = config.subsections('gate');
  const misses = named.filter(name => !known.includes(name)).map(name => `${L.gates}: there is no [gate "${name}"] in trellis.config`);
  for (const gate of known.filter(name => !named.includes(name))) {
    const {patterns, misses: bad} = patternsOf(gate);
    misses.push(...bad);
    for (const name of paths) {
      // A folder stands for its files.
      const files = [name, `${name}/`, ...[...(tree?.entries ?? [])].filter(entry => entry.startsWith(`${name}/`))];
      if (patterns.some(re => files.some(file => re.test(file)))) misses.push(`${L.gates}: \`${name}\` is of the gate ${gate}, which ${L.sections[3]} does not name`);
    }
  }
  return misses;
}

const git = (...args) => execFileSync('git', args, {encoding: 'utf8', maxBuffer: 1 << 28, stdio: ['ignore', 'pipe', 'ignore']}).trim();

/**
 * The files of the branch that match a gate the plan does not name. The gates are the ones of the
 * integration branch too: a branch that takes a gate out of trellis.config still answers to it.
 */
function judgeBranch(plan) {
  const branch = `origin/${config.get('git.integrationBranch')}`;
  let files;
  const configs = [config];
  try {
    const base = git('merge-base', `refs/remotes/${branch}`, 'HEAD');
    files = git('diff', '--name-only', '--no-renames', '-z', base, 'HEAD').normalize('NFC').split('\0').filter(Boolean);
  } catch {
    return [`the files of the branch are not known against ${branch} (git fetch origin)`];
  }
  const scratch = mkdtempSync(path.join(tmpdir(), 'trellis-gates-'));
  try {
    const file = path.join(scratch, 'trellis.config');
    writeFileSync(file, git('show', `refs/remotes/${branch}:trellis.config`));
    configs.push(loadConfig({file, label: `trellis.config of ${branch}`}));
  } catch {
    // The integration branch has no trellis.config.
  } finally {
    rmSync(scratch, {recursive: true, force: true});
  }
  const named = gatesOf(plan) ?? [];
  const misses = [];
  for (const from of configs) {
    for (const gate of from.subsections('gate').filter(name => !named.includes(name))) {
      const {patterns, misses: bad} = patternsOf(gate, from);
      misses.push(...bad);
      for (const name of files.filter(f => patterns.some(re => re.test(f)))) misses.push(`\`${name}\` is of the gate ${gate}, which the plan does not name`);
    }
  }
  return [...new Set(misses)];
}

/** What a run without a person cannot take of a plan: its gates and what it needs. */
function attended(plan) {
  const gates = gatesOf(plan) ?? [];
  const needs = labelled(plan.sections.flatMap(s => s.lines), L.needs)
    .map(group => [group.inline, ...group.lines.map(l => l.text.trim())].filter(Boolean).join(' '))
    .filter(text => !L.none.test(text));
  return [...(gates.length ? [`${L.gates}: ${gates.join(', ')}`] : []), ...needs.map(text => `${L.needs}: ${text}`)];
}

/** Prints each path of a plan that changed on the integration branch since the plan was written. */
function printChanged(plan) {
  const branch = `origin/${config.get('git.integrationBranch')}`;
  const ref = `refs/remotes/${branch}`;
  const layers = sectionOf(plan, L.sections[2]);
  const paths = pathsOf(layers, integrationTree(ref));
  if (paths.length === 0) return;
  try {
    const root = git('rev-parse', '--show-toplevel');
    let base = git('rev-list', '-1', '--first-parent', `--before=${plan.since}`, ref);
    if (base === '') {
      if (git('rev-parse', '--is-shallow-repository') === 'true') {
        console.log(`issue: what changed on ${branch} since ${plan.since} is not known: the clone is shallow and does not reach that date`);
        return;
      }
      base = git('hash-object', '-t', 'tree', '/dev/null');
    }
    for (const name of paths) {
      if (git('--literal-pathspecs', '-C', root, 'diff', '--name-only', base, ref, '--', name) === '') continue;
      console.log(`issue: \`${name}\` changed on ${branch} since the plan was written (${plan.since}): git diff ${base.slice(0, 12)} ${branch} -- ${name}`);
    }
  } catch {
    // Without the branch the check has said so.
  }
}

/** The files, folders and extensions of origin/<integration>, or null when that branch is not known. */
function integrationTree(ref) {
  let out;
  try {
    out = execFileSync('git', ['ls-tree', '-r', '-z', '--full-tree', '--name-only', ref], {encoding: 'utf8', maxBuffer: 1 << 28, stdio: ['ignore', 'pipe', 'ignore']});
  } catch {
    return null;
  }
  const entries = new Set();
  const extensions = new Set();
  for (const name of out.normalize('NFC').split('\0').filter(Boolean)) {
    for (let p = name; p !== '.'; p = p.includes('/') ? p.slice(0, p.lastIndexOf('/')) : '.') entries.add(p);
    const extension = /[^./]\.([^./]+)$/.exec(name)?.[1];
    if (extension) extensions.add(extension);
  }
  return {entries, extensions};
}

/** The issues a `Depends on` line names, which are references and not bare numbers. */
const REFERENCE = /(?<![\w./&-])(?:([\w.-]+\/[\w.-]+))?#(\d+)\b/g;

/** The text whose style is judged: the `Depends on` lines without their references. */
function withoutReferences(lines) {
  const out = lines.map(l => l.text);
  for (const group of labelled(lines, L.dependsOn)) {
    const end = group.inline === '' ? group.end : group.start + 1;
    for (let i = group.start; i < end; i++) out[i] = out[i].replace(REFERENCE, '');
  }
  return out.join('\n');
}

/** What the plan lacks: one message per miss. */
function judge(plan, lines) {
  const misses = [];
  for (const name of L.sections) {
    const all = plan.sections.filter(s => s.name === name);
    if (all.length === 0) misses.push(`no section \`## ${name}\``);
    else if (all.length > 1) misses.push(`section ${name} appears ${all.length} times`);
    else if (isEmpty(all[0].lines)) misses.push(`section ${name} is empty`);
  }
  const order = plan.sections.filter(s => !s.amended).map(s => L.sections.indexOf(s.name));
  if (order.some((n, i) => i > 0 && n < order[i - 1])) misses.push(`the sections are not in order: ${L.sections.join(', ')}`);

  const source = new RegExp(`(?:^|[^\\p{L}])${escape(L.source)}(?:\\*\\*|__)?\\s*:(?:\\*\\*|__)?\\s*[^\\s.]`, 'u');
  for (const group of labelled(lines, L.outOfScope)) {
    for (const item of itemsOf(group)) {
      if (!source.test(written(item))) misses.push(`${L.outOfScope}: "${item.split('\n')[0]}" has no ${L.source}`);
    }
  }

  if (plan.complexity === null || plan.complexity === '') {
    misses.push(`the last line is not \`${L.complexity}: S\`, M or L`);
  }

  const [, , layersName, risksName] = L.sections;
  const layers = sectionOf(plan, layersName);
  const added = new Set();
  for (const group of labelled(layers, L.newFiles)) {
    for (let i = group.start; i < group.end; i++) added.add(i);
  }
  const ref = `origin/${config.get('git.integrationBranch')}`;
  const tree = integrationTree(`refs/remotes/${ref}`);
  const paths = pathsOf(layers.filter((_, i) => !added.has(i)), tree);
  if (!tree) {
    if (paths.length > 0) misses.push(`${layersName}: ${ref} is not known here, so its paths cannot be checked (git fetch origin)`);
  } else {
    for (const name of paths) {
      if (!tree.entries.has(name)) misses.push(`${layersName}: \`${name}\` is not in ${ref}; a file the change adds goes under ${L.newFiles}`);
    }
  }

  const risks = plan.sections.filter(s => s.name === risksName);
  if (risks.length === 1) {
    const left = /\{\{[^}]*\}\}/.exec(risks[0].lines.filter(l => !l.code).map(l => l.text.replace(/`[^`]*`/g, '')).join('\n').replace(/<!--[\s\S]*?(?:-->|$)/g, ''));
    if (left && gatesOf(plan)) misses.push(`${risksName} has a placeholder of the mould: ${left[0]}`);
  }
  if (risks.length === 1 && !isEmpty(risks[0].lines)) misses.push(...judgeGates(plan, pathsOf(layers, tree), tree));

  misses.push(...styleMisses(withoutReferences(lines), 'style'));
  return misses;
}

function report(misses, what = 'issue check') {
  if (misses.length === 0) return 0;
  console.error(`${what}:\n${misses.map(m => `  - ${m}`).join('\n')}`);
  return 1;
}

/** The first line of the comment of a stop. */
const STOP_MARK = '<!-- trellis:stopped -->';

/** What the text of a stop lacks: one message per miss. */
function judgeStop(text) {
  const {lines, prose} = readBody(text);
  return STOP[localeOf(config)].sections.flatMap(name => {
    const content = sectionNamed(prose, name, lines);
    if (!content) return [`missing the section **${name}**`];
    return content.some(l => /[\p{L}\p{N}]/u.test(l)) ? [] : [`**${name}** is empty; write \`${PR_SECTIONS[localeOf(config)].noneWord}\` when there is nothing`];
  });
}

/** The text of the stop of a plan that was refused. */
function refusal(reasons, branches) {
  const {sections: [done, missing, needs], notStarted, started, rest} = STOP[localeOf(config)];
  const items = reasons.split('\n').map(l => l.trim()).filter(Boolean).map(l => `- ${l.replace(/^- /, '')}`);
  const [has, lacks] = branches ? [started(branches), rest] : [PR_SECTIONS[localeOf(config)].noneWord, notStarted];
  return `**${done}**: ${has}\n\n**${missing}**: ${lacks}\n\n**${needs}**:\n\n${items.join('\n')}\n`;
}

const text = readFileSync(file, 'utf8');
if (mode === 'body') process.exitCode = report(judge(parse(text), linesOf(text)));
if (mode === 'class') console.log(parse(text).complexity);
if (mode === 'stop') {
  process.exitCode = report(judgeStop(text), 'issue stop');
  if (process.exitCode === 0) writeFileSync(commentsFile, `${STOP_MARK}\n${text}`);
}
if (mode === 'follow-up') {
  process.exitCode = report(text.replace(/<!--[\s\S]*?(?:-->|$)/g, '').trim() ? [] : ['the body is empty'], 'issue follow-up');
  const fact = reopen.trim().replace(/\s+/g, ' ');
  if (process.exitCode === 0) writeFileSync(commentsFile, `${fact ? `${L.reopen}: ${fact}\n\n` : ''}${text}`);
}
if (mode === 'refusal') writeFileSync(commentsFile, `${STOP_MARK}\n${refusal(text, process.argv[5])}`);
if (!['body', 'class', 'stop', 'refusal', 'follow-up'].includes(mode)) {
  const plan = resolve(JSON.parse(text), commentsOf(commentsFile));
  if (plan.note && ['issue', 'print'].includes(mode)) console.error(`issue: ${plan.note}`);
  if (mode === 'issue') {
    process.exitCode = report(judge(plan, linesOf(render(plan))));
    printChanged(plan);
  }
  if (mode === 'attended') for (const line of attended(plan)) console.log(line);
  if (mode === 'gates') process.exitCode = report(judgeBranch(plan), 'issue gates');
  if (mode === 'issue-class') console.log(plan.complexity);
  if (mode === 'print') console.log(render(plan));
  if (mode === 'deps') {
    const {refs, texts} = dependencies(plan);
    for (const {repo, n} of refs) console.log(`ref\t${repo}\t${n}`);
    for (const line of texts) console.log(`text\t${line}`);
  }
}
