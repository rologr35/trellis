// What scripts/lesson.sh, which holds the contract, asks of a lesson:
//   node lesson.mjs upstream                          prints the URL of the upstream
//   node lesson.mjs judge <title> <body> <owner/repo> exit 1 with what is wrong, else prints `listed` when
//       the list of the machine has the name of the project or the one of its origin
//   node lesson.mjs digest <body> <argument>...       prints the digest of the body and the arguments

import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {loadConfig} from '../lib/config.mjs';
import {upstreamUrl} from '../lib/copy.mjs';
import {foreignRepositories, machineList, originOf, projectTerms, remoteNames, sameName, termsIn} from '../lib/private-names.mjs';
import {styleMisses} from '../lib/style.mjs';
import {topLevel} from '../lib/tree.mjs';
import {readBody, sectionLines} from './issue-close.mjs';

const SECTIONS = ['Incident', 'What must stop happening'];
const KIND = /^ {0,3}(?:\*\*)?Kind(?:\*\*)?\s*:(?:\*\*)?\s*(.*)$/i;

const [command, ...args] = process.argv.slice(2);
const config = loadConfig();

function stop(misses) {
  for (const miss of misses) console.error(`lesson: ${miss}`);
  process.exit(1);
}

/** What a text lacks to be a lesson. */
function formMisses(text) {
  const body = readBody(text);
  const misses = [];
  const kinds = body.prose.flatMap(line => KIND.exec(line)?.slice(1) ?? []).map(kind => kind.trim().toLowerCase());
  const kind = kinds.length === 1 && ['defect', 'rule'].includes(kinds[0]) ? kinds[0] : '';
  if (kind === '') misses.push('the body has one line Kind: defect or Kind: rule, outside code');
  for (const name of SECTIONS) {
    const content = sectionLines(body.prose, name, body.lines)?.filter(line => !KIND.test(line)) ?? [];
    if (!content.some(line => /[\p{L}\p{N}]/u.test(line))) misses.push(`the section **${name}** is missing or empty`);
  }
  // A line of a code block: what is read of it is code alone, and it is not the mark of the block.
  const prose = sectionLines(body.prose, SECTIONS[0]) ?? [];
  const lines = sectionLines(body.prose, SECTIONS[0], body.lines) ?? [];
  const hasCase = prose.some((line, i) => line.trim() === '' && /[^\s>`~]/.test(lines[i].replace(/^[\s>]*(?:`{3,}|~{3,}).*$/, '')));
  if (kind === 'defect' && !hasCase) misses.push(`a defect brings its case in **${SECTIONS[0]}**, in a code block: what was run or written, and what came out`);
  return misses;
}

if (command === 'upstream') {
  console.log(upstreamUrl(config.get('trellis.upstream')));
} else if (command === 'digest') {
  const [file, ...rest] = args;
  console.log(createHash('sha256').update(JSON.stringify([readFileSync(file, 'utf8'), ...rest])).digest('hex'));
} else {
  const [title, file, upstream] = args;
  const text = readFileSync(file, 'utf8');
  let list;
  try {
    list = machineList();
  } catch (error) {
    stop([error.message]);
  }
  const root = topLevel();
  const name = config.get('project.name');
  const terms = [...projectTerms({root, name, hooksPath: config.get('git.hooksPath'), upstream}), ...(list.terms ?? [])];
  const named = (source, where) => [...termsIn(source, terms), ...foreignRepositories(source, upstream)]
    .map(({term, what, line}) => `${where(line)}: "${term}" is ${what}`);
  const misses = [
    ...formMisses(text),
    ...styleMisses(title, 'title', 'refuse'),
    ...styleMisses(text, 'body', 'refuse'),
    ...named(title, () => 'title'),
    ...named(text, line => `line ${line}`),
  ];
  if (misses.length > 0) stop(misses);
  const repository = remoteNames(originOf(root)).name;
  const listed = (list.terms ?? []).some(({term}) => sameName(term, name) || sameName(term, repository));
  console.log(listed ? 'listed' : `${list.file} has neither the name of the project (${name || 'none'}) nor the one of its repository (${repository || 'none'})`);
}
