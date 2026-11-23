// The generated parts of a project, one definition each: the blocks between
// `<!-- trellis:<id> -->` and `<!-- /trellis:<id> -->`, the deny of .claude/settings.json and the
// copy of lib/find-trellis.sh the git hooks source. `trellis sync` writes them and `trellis hygiene`
// checks that what is written matches what this file generates.

import {existsSync, readFileSync} from 'node:fs';
import path from 'node:path';
import {TRELLIS_ROOT} from './config.mjs';

/** The files that hold blocks, and the blocks each one may hold. */
export const BLOCK_FILES = {
  'CLAUDE.md': ['method', 'orientation', 'commands', 'gates'],
  'TESTING.md': ['rungs'],
};

export const FIND_TRELLIS_COPY = '.githooks/find-trellis.sh';

const LABELS = {
  es: {
    file: 'Fichero',
    loads: 'Carga',
    covers: 'Qué cubre',
    under: dir => `al leer un fichero de \`${dir}/\``,
    always: 'siempre',
    check: names => `- \`trellis check\` corre en orden: ${names}.`,
    noCheck: '- `trellis check` no tiene comandos: `[command] check` en `trellis.config`.',
    gatesIntro: 'Antes de cambiar estos ficheros, parar y pedir la decisión a una persona:',
    noGates: 'Sin gates: `[gate "<nombre>"]` en `trellis.config` los declara.',
    rung: 'Escalón',
    command: 'Comando',
    agent: 'Lo corre Claude',
    pr: 'En cada PR',
    proves: 'Qué prueba',
    off: 'Apagado hasta',
    yes: 'sí',
    no: 'no',
    noRungs: 'Sin escalones: `[rung "<nombre>"]` en `trellis.config` los declara.',
  },
  en: {
    file: 'File',
    loads: 'Loads',
    covers: 'Covers',
    under: dir => `when a file under \`${dir}/\` is read`,
    always: 'always',
    check: names => `- \`trellis check\` runs, in order: ${names}.`,
    noCheck: '- `trellis check` has no commands: `[command] check` in `trellis.config`.',
    gatesIntro: 'Before changing these files, stop and ask a person for the decision:',
    noGates: 'No gates: `[gate "<name>"]` in `trellis.config` declares them.',
    rung: 'Rung',
    command: 'Command',
    agent: 'Claude runs it',
    pr: 'On every PR',
    proves: 'Proves',
    off: 'Off until',
    yes: 'yes',
    no: 'no',
    noRungs: 'No rungs: `[rung "<name>"]` in `trellis.config` declares them.',
  },
};

const RULES_DIR = '.claude/rules/';

/** The `paths:` globs of a rule's frontmatter, as a YAML list or a comma-separated string. */
export function rulePaths(text) {
  const front = /^---\n([\s\S]*?)\n---/.exec(text ?? '');
  if (!front) return [];
  const lines = front[1].split('\n');
  const at = lines.findIndex(l => /^paths:/.test(l));
  if (at === -1) return [];
  const inline = lines[at].replace(/^paths:\s*/, '').trim();
  const unquote = s => s.trim().replace(/^["']|["']$/g, '');
  if (inline) return inline.replace(/^\[|\]$/g, '').split(',').map(unquote).filter(Boolean);
  const globs = [];
  for (const line of lines.slice(at + 1)) {
    const item = /^\s+-\s+(.+)$/.exec(line);
    if (!item) break;
    globs.push(unquote(item[1]));
  }
  return globs;
}

const firstHeading = text => /^#\s+(.+)$/m.exec(text ?? '')?.[1].trim() ?? '';

/** The nested CLAUDE.md files and the rules of a project tree. */
export function instructionIndex(tree) {
  return {
    nested: tree.files.filter(f => f.endsWith('/CLAUDE.md')),
    rules: tree.files.filter(f => f.startsWith(RULES_DIR) && f.endsWith('.md')),
  };
}

const cell = s => s.replace(/\|/g, '\\|');

/** Every block a project can hold, generated from the plugin, the config and the tree. */
export function generateBlocks(tree, config) {
  const L = LABELS[config.get('project.locale') === 'en' ? 'en' : 'es'];
  const {nested, rules} = instructionIndex(tree);

  const orientation = [`| ${L.file} | ${L.loads} | ${L.covers} |`, '|---|---|---|'];
  for (const file of nested) {
    orientation.push(`| \`${file}\` | ${L.under(path.posix.dirname(file))} | ${cell(firstHeading(tree.read(file)))} |`);
  }
  for (const file of rules) {
    const text = tree.read(file);
    const globs = rulePaths(text);
    const loads = globs.length ? globs.map(g => `\`${cell(g)}\``).join(', ') : L.always;
    orientation.push(`| \`${file}\` | ${loads} | ${cell(firstHeading(text))} |`);
  }

  const names = config.subsections('command');
  const check = config.all('command.check');
  const commands = [check.length ? L.check(check.map(n => `\`${n}\``).join(', ')) : L.noCheck];
  for (const name of names) {
    const run = config.get(`command.${name}.run`);
    if (!run) continue;
    const description = config.get(`command.${name}.description`);
    commands.push(`- \`${name}\`: \`${run}\`${description ? `. ${description}` : ''}`);
  }

  const gateNames = config.subsections('gate');
  const gates = gateNames.length ? [L.gatesIntro] : [L.noGates];
  for (const name of gateNames) {
    const globs = config.all(`gate.${name}.paths`).map(g => `\`${g}\``).join(', ');
    const reason = config.get(`gate.${name}.reason`);
    gates.push(`- **${name}** (${globs})${reason ? `: ${reason}` : ''}`);
  }

  const rungNames = config.subsections('rung');
  const rungs = rungNames.length
    ? [`| ${L.rung} | ${L.command} | ${L.agent} | ${L.pr} | ${L.proves} | ${L.off} |`, '|---|---|---|---|---|---|']
    : [L.noRungs];
  for (const name of rungNames) {
    const command = config.get(`rung.${name}.command`);
    const run = config.get(`command.${command}.run`);
    const yes = key => (config.get(`rung.${name}.${key}`) === 'false' ? L.no : L.yes);
    rungs.push(`| ${name} | \`${cell(run || command)}\` | ${yes('agent')} | ${yes('pr')} | ${cell(config.get(`rung.${name}.proves`))} | ${config.get(`rung.${name}.offUntil`)} |`);
  }

  const method = path.join(TRELLIS_ROOT, 'method', 'base.md');
  return {
    ...(existsSync(method) ? {method: readFileSync(method, 'utf8').trim()} : {}),
    orientation: orientation.join('\n'),
    commands: commands.join('\n'),
    gates: gates.join('\n'),
    rungs: rungs.join('\n'),
  };
}

const blockRe = id => new RegExp(`(<!-- trellis:${id} -->)\\n[\\s\\S]*?\\n?(<!-- /trellis:${id} -->)`);

/** The content of each block a text holds, by id. */
export function blocksIn(text) {
  const found = {};
  for (const m of (text ?? '').matchAll(/<!-- trellis:([a-z]+) -->\n([\s\S]*?)\n?<!-- \/trellis:\1 -->/g)) {
    found[m[1]] = m[2];
  }
  return found;
}

/** The text with every block it holds rewritten from `blocks`. */
export function replaceBlocks(text, blocks) {
  let out = text;
  for (const id of Object.keys(blocksIn(text))) {
    if (!(id in blocks)) continue;
    out = out.replace(blockRe(id), (_, open, close) => `${open}\n${blocks[id]}\n${close}`);
  }
  return out;
}

/** The deny entries sync generates: each rung Claude must not run, each push to a protected branch. */
export function generatedDeny(config) {
  const deny = [];
  for (const name of config.subsections('rung')) {
    if (config.get(`rung.${name}.agent`) !== 'false') continue;
    const run = config.get(`command.${config.get(`rung.${name}.command`)}.run`);
    if (run) deny.push(`Bash(${run}*)`);
  }
  for (const branch of config.all('git.protected')) deny.push(...pushDeny(branch));
  return [...new Set(deny)];
}

function pushDeny(branch) {
  return [
    `Bash(git push * ${branch})`,
    `Bash(git push * ${branch} *)`,
    `Bash(git push *:${branch})`,
    `Bash(git push *:${branch} *)`,
    `Bash(git push *:refs/heads/${branch})`,
  ];
}

/** The branch a deny entry of the push shape names, or null for any other entry. */
export function pushDenyBranch(entry) {
  const m = /^Bash\(git push \*(?: |:(?:refs\/heads\/)?)([^\s*:]+)(?: \*)?\)$/.exec(entry);
  return m && pushDeny(m[1]).includes(entry) ? m[1] : null;
}

/** The content the copy of lib/find-trellis.sh must have. */
export const findTrellisSource = () => readFileSync(path.join(TRELLIS_ROOT, 'lib', 'find-trellis.sh'), 'utf8');
