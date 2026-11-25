// The judgment of `trellis pr-check` (scripts/pr-check.sh holds the contract).
//   node pr-check.mjs <body|commit> <file> <has-setback:true|false> <branch|-> <loosened:true|false> <cycle head|-> <message file>
// The message file is written when the shape of a commit is judged: the message as git will write it.

import {readFileSync, writeFileSync} from 'node:fs';
import {loadConfig} from '../lib/config.mjs';
import {LESSON, PR_SECTIONS, localeOf} from '../lib/locale.mjs';
import {styleMisses} from '../lib/style.mjs';
import {closedIssues, itemsOf, kindOf, lessonsOf, readBody, sectionOf} from './issue-close.mjs';

const [, , mode, file, hasSetback, branchArg, loosened, cycleArg = '-', messageFile] = process.argv;
const branch = branchArg === '-' ? '' : branchArg;
const config = loadConfig();
const tracker = config.get('tracker.kind');
const SECTIONS = PR_SECTIONS[localeOf(config)];
const sections = config.all('pr.section').filter(Boolean);
const required = sections.length > 0 ? sections : SECTIONS.required;
const actions = config.all('pr.action').filter(Boolean);

const misses = [];
const style = (text, what) => misses.push(...styleMisses(text, what, config.get('style.bareReference')));

const text = readFileSync(file, 'utf8');

if (mode === 'commit') {
  const scissors = text.search(/^# -+ >8 -+$/m);
  const message = (scissors === -1 ? text : text.slice(0, scissors))
    .split('\n')
    .filter(l => !l.startsWith('#'))
    .join('\n')
    .trim();
  const subject = message.split('\n')[0] ?? '';
  if (/^(Merge |Revert "|fixup! |squash! |amend! )/.test(subject)) process.exit(0);
  writeFileSync(messageFile, `${message}\n`);
  const types = 'feat|fix|chore|docs|refactor|test|ci|perf|build|style|revert';
  const withIssue = tracker === 'github';
  const shape = new RegExp(`^(?:${types})(?:\\([\\w./-]+(?:,[\\w./-]+)*\\))?!?: .+${withIssue ? ' \\(#(\\d+)\\)' : ''}$`).exec(subject);
  if (!shape) {
    misses.push(`commit: the first line is not \`type(scope): message${withIssue ? ' (#n)' : ''}\``);
  } else if (withIssue) {
    const own = /^(\d+)-/.exec(branch)?.[1];
    if (own && shape[1] !== own) misses.push(`commit: cites #${shape[1]} and the branch ${branch} is of #${own}`);
  }
  style(message, 'commit');
} else {
  const lines = text.split('\n');
  const setback = (sectionOf(lines, SECTIONS.setback) ?? []).filter(l => !SECTIONS.none.test(l.replace(/^[-*]\s*/, '')));
  if (hasSetback === 'true') process.exit(setback.length > 0 ? 0 : 1);
  for (const name of required) {
    const content = sectionOf(lines, name);
    if (!content || content.length === 0) misses.push(`body: missing the section **${name}**`);
  }
  if (sectionOf(lines, SECTIONS.setback) && setback.length === 0) {
    misses.push(`body: **${SECTIONS.setback}** is empty; it says what regresses, its cost and why it was accepted`);
  }
  if (loosened === 'true' && setback.length === 0) {
    misses.push(`body: the branch loosens a ratchet (ratchet-loosened): **${SECTIONS.setback}** says what regresses, its cost and why it was accepted`);
  }
  const body = readBody(text);
  for (const name of actions.length > 0 ? [SECTIONS.beforeMerging, SECTIONS.afterMerging] : []) {
    for (const item of itemsOf(body, name).filter(text => !SECTIONS.none.test(text))) {
      if (actions.some(action => item.replace(/^`/, '').startsWith(action))) continue;
      misses.push(`body: **${name}**: "${item}" does not start with one of the actions: ${actions.join(', ')}`);
    }
  }
  if (cycleArg !== '-') {
    const closed = closedIssues(body);
    // A branch whose shape does not start with a number does not say which issue is its own.
    const own = /^(\d+)-/.exec(cycleArg)?.[1];
    if (own ? !closed.includes(Number(own)) : closed.length === 0) {
      misses.push(`body: does not close the issue of ${cycleArg}; write \`Closes #${own ?? '<n>'}\` outside code`);
    }
    const {label, none, local, framework} = LESSON[localeOf(config)];
    const answers = `\`${label}: ${none}\`, \`${label}: ${local}: <what>\` or \`${label}: ${framework}: <what>\``;
    const lessons = lessonsOf(body, localeOf(config));
    if (lessons.length === 0) misses.push(`body: missing the line ${answers}, outside code`);
    if (lessons.length > 1) misses.push(`body: ${lessons.length} lesson lines, and it is one`);
    for (const {text} of lessons.filter(l => !l.valid)) misses.push(`body: \`${text}\` is not ${answers}`);
    for (const name of [SECTIONS.beforeMerging, SECTIONS.afterMerging]) {
      const kind = kindOf(sectionOf(body.prose, name, body.lines), SECTIONS.none);
      if (kind === 'missing') misses.push(`body: missing the section **${name}**`);
      if (kind === 'prose') misses.push(`body: **${name}** is \`${SECTIONS.noneWord}\` or a list`);
    }
  }
  style(text, 'body');
}

if (misses.length === 0) process.exit(0);
console.error(`pr-check:\n${misses.map(m => `  - ${m}`).join('\n')}`);
process.exit(1);
