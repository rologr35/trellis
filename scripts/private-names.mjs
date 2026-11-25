// The judgment of `trellis private-names` (scripts/private-names.sh holds the contract).
//   node private-names.mjs (--staged | --file <file> | --text <text>)...

import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {loadConfig} from '../lib/config.mjs';
import {machineList, termsIn} from '../lib/private-names.mjs';
import {projectTree, topLevel} from '../lib/tree.mjs';

const args = process.argv.slice(2);
if (loadConfig().get('project.public') !== 'true') process.exit(0);

function stop(message) {
  console.error(`private-names: ${message}`);
  process.exit(1);
}

let list;
try {
  list = machineList();
} catch (error) {
  stop(`${error.message}, and nothing can be judged without it`);
}
if (list.terms === null) {
  console.error(`private-names: no list of private names (${list.file}): nothing was judged against it`);
  process.exit(0);
}

const findings = [];
const judge = (text, where) => findings.push(...termsIn(text, list.terms).map(found => ({where: where(found.line), term: found.term})));

/** The added lines of the index, by file, each hunk as one text. */
function* addedLines(root) {
  const diff = execFileSync('git', ['-C', root, '-c', 'core.quotePath=false', 'diff', '--cached', '-U0', '--inter-hunk-context=0', '-M', '--no-color', '--no-ext-diff', '--no-textconv', '--no-relative', '--src-prefix=a/', '--dst-prefix=b/'], {encoding: 'utf8', maxBuffer: 256 << 20, stdio: ['ignore', 'pipe', 'pipe']});
  let file = '';
  let left = 0;
  let hunk = null;
  for (const line of diff.split('\n')) {
    if (left > 0 && /^[+-]/.test(line)) {
      left--;
      if (line.startsWith('+')) hunk.lines.push(line.slice(1));
      if (left === 0) yield hunk;
      continue;
    }
    const at = /^@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/.exec(line);
    if (at) {
      left = Number(at[1] ?? 1) + Number(at[3] ?? 1);
      hunk = {file, first: Number(at[2]), lines: []};
    } else if (line.startsWith('+++ ')) {
      file = line.slice(4).replace(/^b\//, '').replace(/\t$/, '');
    }
  }
}

for (let i = 0; i < args.length; i++) {
  try {
    if (args[i] === '--staged') {
      const root = topLevel();
      for (const {file, first, lines} of addedLines(root)) judge(lines.join('\n'), line => `${file}:${first + line - 1}`);
      for (const file of projectTree(root, {staged: true}).files) judge(file, () => `the path ${file}`);
    } else if (args[i] === '--file') {
      const file = args[++i];
      judge(readFileSync(file, 'utf8'), line => `${file}:${line}`);
    } else {
      judge(args[++i], line => `the text, line ${line}`);
    }
  } catch (error) {
    stop(`${args[i]} could not be read: ${String(error.stderr ?? error.message).trim()}`);
  }
}

for (const {where, term} of findings) console.error(`private-names: ${where}: "${term}" is in the list of private names of this machine, and this project is public`);
process.exit(findings.length > 0 ? 1 : 0);
