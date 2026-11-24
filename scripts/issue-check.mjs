// The judgment of `trellis issue` (scripts/issue.sh holds the contract).
//   node issue-check.mjs body <file>    judges a body before it is published
//   node issue-check.mjs class <file>   prints S, M or L, the class of a body that passes
// The text is data: nothing in it is run.

import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {loadConfig} from '../lib/config.mjs';
import {ISSUE, localeOf} from '../lib/locale.mjs';
import {styleMisses} from '../lib/style.mjs';

const [, , mode, file] = process.argv;
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

/** The text without what the mould leaves for the person to fill, and without comments. */
const written = text => text.replace(/<!--[\s\S]*?(?:-->|$)/g, '').replace(/\{\{[^}]*\}\}/g, '');

/**
 * The lists a label opens (`Out of scope:`, `- **New**: ...`, `### New`), each one the text after
 * the label and the lines that belong to it: the more indented ones for a bullet, the ones up to
 * the next heading of its level for a heading, and the paragraph or the list for a label alone.
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
      // key such as tracker.kind is not.
      const extension = /[^.]\.([^.]+)$/.exec(name)?.[1];
      if (!name.includes('/') && !/^\.[\p{L}]/u.test(name) && !(extension && tree?.extensions.has(extension))) continue;
      paths.push(name);
    }
  }
  return [...new Set(paths)];
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
  const order = plan.sections.map(s => L.sections.indexOf(s.name));
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

  const [, , layersName] = L.sections;
  const layers = plan.sections.find(s => s.name === layersName)?.lines ?? [];
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

  misses.push(...styleMisses(withoutReferences(lines), 'style'));
  return misses;
}

function report(misses) {
  if (misses.length === 0) return 0;
  console.error(`issue check:\n${misses.map(m => `  - ${m}`).join('\n')}`);
  return 1;
}

const text = readFileSync(file, 'utf8');
if (mode === 'body') process.exitCode = report(judge(parse(text), linesOf(text)));
if (mode === 'class') console.log(parse(text).complexity);
