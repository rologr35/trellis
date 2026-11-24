// What the body of a pull request says about its issues and about what is left to do, read by
// scripts/pr-check.mjs before the merge and by `trellis issue close` after it.

import {PR_SECTIONS} from '../lib/locale.mjs';

const blank = text => text.replace(/[^\n]/g, ' ');

/**
 * The lines of a body, with LF line ends and composed letters: `lines` as a person reads it, without
 * comments, and `prose` with the code blanked too. Both have the same lines, so a place found in one
 * is the same place of the other.
 */
export function readBody(body) {
  const text = (body ?? '').replace(/\r\n?/g, '\n').normalize('NFC');
  let fence = '';
  let indented = false;
  let inList = false;
  let before = '';
  const blocks = text.split('\n').map(line => {
    const mark = /^[\s>]*(`{3,}(?=[^`]*$)|~{3,})/.exec(line)?.[1] ?? '';
    if (fence !== '') {
      if (mark[0] === fence[0] && mark.length >= fence.length && /^[\s>]*[`~]+\s*$/.test(line)) fence = '';
      before = line;
      return blank(line);
    }
    if (mark) {
      fence = mark;
      before = line;
      return blank(line);
    }
    // Four spaces make code after a blank line, except inside a list, where they go on with an item.
    if (line.trim() !== '') {
      const deep = /^(?: {4}| {0,3}\t)/.test(line);
      indented = deep && !inList && (indented || before.trim() === '');
      if (!deep) inList = /^\s*(?:[-*+]|\d+[.)])\s/.test(line) || (inList && /^\s/.test(line));
    }
    before = line;
    return indented ? blank(line) : line;
  }).join('\n');
  // Whichever opens first wins: a comment mark in a code span is text, and so is a backtick in a comment.
  const comments = [];
  const prose = blocks.replace(/(?<!`)(`+)(?!`)(?:(?!\n[ \t]*\n)[\s\S])*?(?<!`)\1(?!`)|<!--[\s\S]*?-->|<(pre|code)\b[\s\S]*?<\/\2>/gi, (found, ticks, tag, at) => {
    if (found.startsWith('<!--')) comments.push([at, at + found.length]);
    return blank(found);
  });
  let read = text;
  for (const [from, to] of comments) read = read.slice(0, from) + blank(read.slice(from, to)) + read.slice(to);
  return {lines: read.split('\n'), prose: prose.split('\n')};
}

/**
 * The lines of a section, or null when there is none: a heading or a bold label naming it, with its
 * content after the label or below it, up to the next heading or bold label. Its place is looked for
 * in `lines` and its content is the one of `source`.
 */
export function sectionLines(lines, name, source = lines) {
  const heading = new RegExp(`^\\s*(?:#+\\s*|\\*\\*)${name}(?:\\*\\*)?\\s*:?(?:\\*\\*)?(.*)$`, 'i');
  const start = lines.findIndex(l => heading.test(l));
  if (start === -1) return null;
  const inline = heading.exec(source[start])?.[1].trim() ?? '';
  const rest = lines.slice(start + 1);
  const end = rest.findIndex(l => /^\s*(#+\s|\*\*[^*]+\*\*\s*:?(\s|$))/.test(l));
  return [inline, ...source.slice(start + 1, end === -1 ? undefined : start + 1 + end)];
}

/** The content of a section, without blank lines, or null when there is none. */
export const sectionOf = (lines, name, source) => sectionLines(lines, name, source)?.map(l => l.trim()).filter(Boolean) ?? null;

/** A section of what is done before or after the merge: 'missing', 'none', 'list', or 'prose'. */
export function kindOf(content, none) {
  if (!content || content.length === 0) return 'missing';
  const items = content.map(l => /^(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s*)?(\S.*)$/.exec(l)?.[1]);
  if (items.some(item => item && !none.test(item))) return 'list';
  return content.every(l => none.test(l.replace(/^[-*+]\s+/, ''))) ? 'none' : 'prose';
}

/** The numbers of the issues a body closes: the ones written `#n`, and, with `repo`, the ones that name it. */
export function closedIssues(body, repo = '') {
  const closing = /(?<![\w-])(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?[ \t]+(?:(?:https:\/\/github\.com\/([\w.-]+\/[\w.-]+)\/issues\/)|([\w.-]+\/[\w.-]+)?#)(\d+)(?![\w-])/gi;
  const numbers = new Set();
  for (const [, url, named, n] of body.prose.join('\n').matchAll(closing)) {
    const other = url ?? named;
    if (other === undefined || (repo !== '' && other.toLowerCase() === repo.toLowerCase())) numbers.add(Number(n));
  }
  return [...numbers];
}

/** The content of the section of what is left after the merge, '' when nothing is. */
export function pendingActions(body, locale) {
  const {afterMerging, none} = PR_SECTIONS[locale];
  const lines = sectionLines(body.prose, afterMerging, body.lines);
  const kind = kindOf(lines?.map(l => l.trim()).filter(Boolean), none);
  return kind === 'missing' || kind === 'none' ? '' : lines.join('\n').replace(/^\s*\n/, '').trimEnd();
}
