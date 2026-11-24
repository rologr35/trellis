// The judgment of `trellis pr-check` (scripts/pr-check.sh holds the contract).
//   node pr-check.mjs <body|commit> <file> <has-setback:true|false> <branch|-> <loosened:true|false>

import {readFileSync} from 'node:fs';
import {loadConfig} from '../lib/config.mjs';
import {PR_SECTIONS, localeOf} from '../lib/locale.mjs';
import {styleMisses} from '../lib/style.mjs';

const [, , mode, file, hasSetback, branchArg, loosened] = process.argv;
const branch = branchArg === '-' ? '' : branchArg;
const config = loadConfig();
const tracker = config.get('tracker.kind');
const SECTIONS = PR_SECTIONS[localeOf(config)];

const misses = [];
const style = (text, what) => misses.push(...styleMisses(text, what));

// A section is a heading or a bold label naming it, with its content after the label or below it,
// up to the next heading or bold label.
function sectionOf(lines, name) {
  const heading = new RegExp(`^\\s*(?:#+\\s*|\\*\\*)${name}(?:\\*\\*)?\\s*:?(?:\\*\\*)?(.*)$`, 'i');
  const start = lines.findIndex(l => heading.test(l));
  if (start === -1) return null;
  const inline = heading.exec(lines[start])[1].trim();
  const rest = lines.slice(start + 1);
  const end = rest.findIndex(l => /^\s*(#+\s|\*\*[^*]+\*\*\s*:?(\s|$))/.test(l));
  return [inline, ...(end === -1 ? rest : rest.slice(0, end))].map(l => l.trim()).filter(Boolean);
}

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
  for (const name of SECTIONS.required) {
    const content = sectionOf(lines, name);
    if (!content || content.length === 0) misses.push(`body: missing the section **${name}**`);
  }
  if (sectionOf(lines, SECTIONS.setback) && setback.length === 0) {
    misses.push(`body: **${SECTIONS.setback}** is empty; it says what regresses, its cost and why it was accepted`);
  }
  if (loosened === 'true' && setback.length === 0) {
    misses.push(`body: the branch loosens a ratchet (ratchet-loosened): **${SECTIONS.setback}** says what regresses, its cost and why it was accepted`);
  }
  style(text, 'body');
}

if (misses.length === 0) process.exit(0);
console.error(`pr-check:\n${misses.map(m => `  - ${m}`).join('\n')}`);
process.exit(1);
