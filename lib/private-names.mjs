// The private names that nothing published may carry: the ones of the machine, which a person lists, and
// the ones of a project, read from it. `trellis private-names` judges with the first, `trellis lesson`
// with both.

import {execFileSync} from 'node:child_process';
import {readFileSync, realpathSync} from 'node:fs';
import {homedir} from 'node:os';
import path from 'node:path';
import {COPY_DIR, MANIFEST_FILE, copiedFiles} from './copy.mjs';
import {projectTree} from './tree.mjs';

// What may stand between two words of a term.
const BETWEEN = '[\\p{Pd}\\p{Pc}.\\s]';
const BETWEEN_ALL = new RegExp(BETWEEN, 'gu');
// Where a word ends inside a run of letters.
const CASE = '(?<=\\p{Ll})(?=\\p{Lu})|(?<=\\p{Lu})(?=\\p{Lu}\\p{Ll})';
const WORDS = new RegExp(`${BETWEEN}+|${CASE}`, 'u');
const SHORT = 6;

/** A text without accents nor invisible characters. Its lines stay. */
const fold = text => text.normalize('NFKD').replace(/[\p{M}\p{Cf}\p{Default_Ignorable_Code_Point}]|(?![\t\n\r])\p{Cc}/gu, '');

/** A folded text as it is found whatever its letter case and what is between its words. */
const squash = folded => folded.toLowerCase().replace(BETWEEN_ALL, '');

const isWord = char => char !== undefined && /[\p{L}\p{N}]/u.test(char);
const isUpper = char => char !== undefined && /\p{Lu}/u.test(char);
const isLower = char => char !== undefined && /\p{Ll}/u.test(char);

/** Whether a word ends between the characters `at - 1` and `at`. */
function boundary(text, at) {
  const [before, after] = [text[at - 1], text[at]];
  if (!isWord(before) || !isWord(after)) return true;
  if (isLower(before) && isUpper(after)) return true;
  if (isUpper(before) && isUpper(after)) return isLower(text[at + 1]);
  return isUpper(before) && isLower(after) && isUpper(text[at - 2]);
}

/**
 * The terms a text has, in any of their spellings, once per line.
 * @param {string} text
 * @param {{term: string, what?: string, whole?: boolean}[]} terms - whole takes the term only as a whole
 *   word, as one under six letters is taken
 * @returns {{term: string, what?: string, line: number}[]}
 */
export function termsIn(text, terms) {
  const folded = fold(text);
  const squashed = squash(folded);
  const found = [];
  for (const {term, what, whole = false} of terms) {
    const words = fold(term).split(WORDS).filter(Boolean);
    const letters = [...words.join('')].filter(isWord).length;
    if (letters === 0 || !squashed.includes(squash(fold(term)))) continue;
    const spelling = new RegExp(words.map(w => w.replace(/[\\^$.*+?()[\]{}|/]/g, '\\$&')).join(`${BETWEEN}*`), 'giu');
    const lines = new Set();
    for (let m; (m = spelling.exec(folded)); spelling.lastIndex = m.index + 1) {
      if ((whole || letters < SHORT) && !(boundary(folded, m.index) && boundary(folded, m.index + m[0].length))) continue;
      lines.add(folded.slice(0, m.index).split('\n').length);
    }
    for (const line of lines) found.push({term, what, line});
  }
  return found.sort((a, b) => a.line - b.line);
}

/** Whether two names are the same one, in any of their spellings. */
export const sameName = (a, b) => squash(fold(a)) !== '' && squash(fold(a)) === squash(fold(b));

/**
 * The list of the machine: one term per line, with # for a comment. `terms` is null without a list, or
 * with one that names nothing. Throws for one that cannot be read.
 */
export function machineList(env = process.env) {
  const file = path.join(env.XDG_CONFIG_HOME || path.join(env.HOME || homedir(), '.config'), 'trellis', 'private-names');
  let text;
  try {
    text = readFileSync(file, 'utf8');
  } catch (error) {
    if (error.code === 'ENOENT' || error.code === 'ENOTDIR') return {file, terms: null};
    throw new Error(`the list of private names (${file}) cannot be read: ${error.code ?? error.message}`);
  }
  const names = text.replace(/^﻿/, '').split('\n').map(line => line.replace(/(?:^|\s)#.*$/, '').trim());
  const terms = names.filter(name => /[\p{L}\p{N}]/u.test(name)).map(term => ({term, what: 'a private name of this machine'}));
  return {file, terms: terms.length > 0 ? terms : null};
}

/** The owner and the name in the URL of a remote; only the name when it is a path. */
export function remoteNames(url) {
  const scp = !url.includes('://') && /^[^/]*@[^/]*:(.*)$/.exec(url)?.[1];
  const remote = scp || /^(?!file:)[a-z][a-z0-9+.-]*:\/\/[^/]+\/(.*)$/i.exec(url)?.[1];
  const parts = (remote || url).replace(/[?#].*$/, '').replace(/\/+$/, '').replace(/\.git$/, '').split('/').filter(Boolean);
  return {owner: remote && parts.length > 1 ? parts[0] : '', name: parts.at(-1) ?? ''};
}

/** The URL of the origin of a project, or nothing. */
export function originOf(root) {
  try {
    return execFileSync('git', ['-C', root, 'remote', 'get-url', 'origin'], {encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore']}).trim();
  } catch {
    return '';
  }
}

/** The top level of a project, of its main checkout too when it is a worktree. */
function topLevels(root) {
  const common = execFileSync('git', ['-C', root, 'rev-parse', '--path-format=absolute', '--git-common-dir'], {encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore']}).trim();
  return [root, ...(path.basename(common) === '.git' ? [path.dirname(common)] : [])];
}

const realPath = file => {
  try {
    return realpathSync(file);
  } catch {
    return file;
  }
};

/**
 * The terms of a project: its name, the owner and the name of its origin (an owner that is also the one
 * of the upstream is none), where it is in this machine, and each tracked path with a folder, outside
 * what trellis writes.
 * @param {{root: string, name: string, hooksPath: string, upstream: string, env?: object}} project -
 *   upstream is the owner/repo of trellis
 */
export function projectTerms({root, name, hooksPath, upstream, env = process.env}) {
  const origin = remoteNames(originOf(root));
  const home = env.HOME || homedir();
  const tops = topLevels(root);
  const inHome = tops.filter(top => top.startsWith(`${realPath(home)}/`)).map(top => `~${top.slice(realPath(home).length)}`);
  const terms = [
    {term: name, what: 'the name of the project'},
    {term: sameName(origin.owner, upstream.split('/')[0]) ? '' : origin.owner, what: 'the owner of the project'},
    {term: origin.name, what: 'the name of the repository'},
    ...[...tops, ...tops.map(realPath), ...inHome].map(term => ({term, what: 'where the project is'})),
    ...[home, realPath(home)].map(term => ({term, what: 'the home of this machine'})),
  ];
  const tree = projectTree(root, {staged: true});
  const copied = copiedFiles(tree.read(MANIFEST_FILE));
  const hooks = ['pre-commit', 'commit-msg', 'pre-push', 'find-trellis.sh'].map(hook => `${hooksPath}/${hook}`);
  const written = new Set(['.claude/settings.json', '.github/workflows/trellis.yml', ...hooks]);
  for (const file of tree.files) {
    if (!file.includes('/') || file.startsWith(`${COPY_DIR}/`) || copied.has(file) || written.has(file)) continue;
    terms.push({term: file, what: 'a file of the project', whole: true});
  }
  const seen = new Set();
  return terms.filter(({term}) => term !== '' && !seen.has(term) && seen.add(term));
}

/**
 * The references and the URLs of a text that name another repository than the upstream, `owner/repo`, and
 * the ones of a gist of another owner.
 */
export function foreignRepositories(text, upstream) {
  const folded = fold(text);
  const found = [];
  const look = (pattern, what, own = upstream) => {
    for (const m of folded.matchAll(pattern)) {
      const named = m.slice(1).join('/').replace(/\.git$/i, '');
      if (named.toLowerCase() === own.toLowerCase()) continue;
      found.push({term: m[0].trim(), what, line: folded.slice(0, m.index).split('\n').length});
    }
  };
  look(/(?<![\w-])([\w-]+)\/([\w.-]+)#\d+/g, 'a reference to another repository');
  look(/(?<![\w.-])(?:(?:(?:www|api|codeload|raw)\.)?github|raw\.githubusercontent)\.com(?::\d+)?[/:]+(?:repos\/)?([^\s/<>()[\]"'`]+)\/([^\s/<>()[\]"'`?#,;]*[^\s/<>()[\]"'`?#,;.:])/gi, 'a URL of another repository');
  look(/(?<![\w.-])gist\.github(?:usercontent)?\.com(?::\d+)?[/:]+([^\s/<>()[\]"'`]+)(?=\/[^\s/])/gi, 'a gist of another owner', upstream.split('/')[0]);
  return found;
}
