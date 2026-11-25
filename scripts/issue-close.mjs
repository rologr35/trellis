// What the body of a pull request says about its issues and about what is left to do, read by
// scripts/pr-check.mjs before the merge and by `trellis issue close` (scripts/issue.sh) after it:
//   node issue-close.mjs pr <json> <comment file>   judges a pull request as REST gives it, prints its
//       repository and the issues its body closes, one per line, and writes the comment with its
//       pending actions, empty without any
//   node issue-close.mjs issue <json> <comments> <owner/repo> <pr>   prints what the issue and its
//       comments, one per line, say: skip, or <state> <labelled> <commented>
// The text is data: nothing in it is run.

import {readFileSync, realpathSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {loadConfig} from '../lib/config.mjs';
import {LESSON, PR_SECTIONS, localeOf} from '../lib/locale.mjs';

const LABEL = 'pending-actions';

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
  const heading = new RegExp(`^\\s*(?:#+\\s*|\\*\\*)${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?:\\*\\*)?\\s*:?(?:\\*\\*)?(.*)$`, 'i');
  const start = lines.findIndex(l => heading.test(l));
  if (start === -1) return null;
  const inline = heading.exec(source[start])?.[1].trim() ?? '';
  const rest = lines.slice(start + 1);
  const end = rest.findIndex(l => /^\s*(#+\s|\*\*[^*]+\*\*\s*:?(\s|$))/.test(l));
  return [inline, ...source.slice(start + 1, end === -1 ? undefined : start + 1 + end)];
}

/** The content of a section, without blank lines, or null when there is none. */
export const sectionOf = (lines, name, source) => sectionLines(lines, name, source)?.map(l => l.trim()).filter(Boolean) ?? null;

/** The text of each item of a section of a body that is not inside another, without its bullet nor its check box. */
export function itemsOf(body, name) {
  const places = sectionLines(body.prose, name) ?? [];
  const texts = sectionLines(body.prose, name, body.lines) ?? [];
  const widthOf = text => text.replace(/\t/g, '    ').length;
  const items = [];
  // Where the text of the last item starts: an item from there on is inside it.
  let column = 0;
  let blankBefore = false;
  places.forEach((line, i) => {
    const bullet = /^(\s*)((?:[-*+]|\d+[.)])(?:\s{1,4}(?=\S)|\s|$))/.exec(texts[i]);
    const indent = widthOf(/^\s*/.exec(line)[0]);
    if (line.trim() === '') {
      blankBefore = true;
    } else if (bullet) {
      blankBefore = false;
      if (column > 0 && indent >= column) return;
      column = widthOf(bullet[1] + bullet[2]);
      const text = texts[i].slice(bullet[0].length).trim();
      if (text) items.push(text.replace(/^\[[ xX]\](?:\s+|$)/, ''));
    } else {
      if (blankBefore && indent < column) column = 0;
      blankBefore = false;
    }
  });
  return items;
}

/** A section of what is done before or after the merge: 'missing', 'none', 'list', or 'prose'. */
export function kindOf(content, none) {
  if (!content || content.length === 0) return 'missing';
  const items = content.map(l => /^(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s*)?(\S.*)$/.exec(l)?.[1]);
  if (items.some(item => item && !none.test(item))) return 'list';
  return content.every(l => none.test(l.replace(/^[-*+]\s+/, ''))) ? 'none' : 'prose';
}

/** The lesson lines of a body, outside code: where, the text of each one, and whether it is an answer of the locale. */
export function lessonsOf(body, locale) {
  const {label, none, local, framework} = LESSON[locale];
  const line = new RegExp(`^ {0,3}(?:\\*\\*)?${label}(?:\\*\\*)?\\s*:(?:\\*\\*)?\\s*(.*)$`, 'i');
  const answer = new RegExp(`^(?:${none}\\.?|(?:${local}|${framework})\\s*:\\s*\\S.*)$`, 'i');
  return body.prose.flatMap((prose, i) => {
    if (!line.test(prose)) return [];
    const text = body.lines[i].trim();
    return [{at: i, text, valid: answer.test(line.exec(text)?.[1].trim() ?? '')}];
  });
}

/** What empties, in the lines of a body, the ones of its lesson, which are the content of no section. */
export function withoutLessons(body, locale) {
  const lessons = new Set(lessonsOf(body, locale).map(lesson => lesson.at));
  return lines => lines.map((line, i) => (lessons.has(i) ? '' : line));
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
  const lines = sectionLines(body.prose, afterMerging, withoutLessons(body, locale)(body.lines));
  const kind = kindOf(lines?.map(l => l.trim()).filter(Boolean), none);
  return kind === 'missing' || kind === 'none' ? '' : lines.join('\n').replace(/^\s*\n/, '').trimEnd();
}

/** The first line of the comment with what a pull request left pending: one per pull request and issue. */
const markOf = pr => `<!-- trellis:pending-actions pr=${pr} -->`;

/** Whether whoever wrote an issue or a comment may write in the repository. Anyone may comment on a public one. */
export const mayWrite = ({author_association: association}) => ['OWNER', 'MEMBER', 'COLLABORATOR'].includes(association);

/** The comments of an issue, in a file with one per line. */
export const commentsOf = file => readFileSync(file, 'utf8').split('\n').filter(Boolean).map(line => JSON.parse(line));

/** A mark counts when someone with write access, or the workflow, wrote it. */
const trusted = comment => mayWrite(comment) || comment.user?.login === 'github-actions[bot]';

function pullRequest(file, commentFile) {
  const {number, html_url: url, state, merged, base, body} = JSON.parse(readFileSync(file, 'utf8'));
  const config = loadConfig();
  const locale = localeOf(config);
  const integration = config.get('git.integrationBranch');
  const repo = /^https:\/\/github\.com\/([^/]+\/[^/]+)\/pull\/\d+$/.exec(url)?.[1];
  if (!repo) throw new Error(`the pull request's URL is ${url}`);
  if (!merged || base.ref !== integration) {
    throw new Error(`#${number} is ${merged ? 'merged' : state} with base ${base.ref}; only one merged into ${integration} closes its issues`);
  }
  const read = readBody(body);
  const actions = pendingActions(read, locale);
  writeFileSync(commentFile, actions && `${markOf(number)}\n${PR_SECTIONS[locale].pending} #${number}:\n\n${actions}\n`);
  console.log([repo, ...closedIssues(read, repo)].join('\n'));
}

function issue(file, commentsFile, repo, pr) {
  const {html_url: url, state, labels} = JSON.parse(readFileSync(file, 'utf8'));
  // The number may be of a pull request, or of an issue that moved to another repository.
  if (!url.toLowerCase().startsWith(`https://github.com/${repo}/issues/`.toLowerCase())) return console.log('skip');
  const labelled = labels.some(l => l.name.toLowerCase() === LABEL);
  const commented = commentsOf(commentsFile).some(c => trusted(c) && c.body.startsWith(markOf(pr)));
  console.log(`${state} ${labelled} ${commented}`);
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [mode, ...args] = process.argv.slice(2);
  try {
    if (mode === 'pr') pullRequest(...args);
    else issue(...args);
  } catch (error) {
    console.error(`issue close: ${error.message}`);
    process.exit(1);
  }
}
