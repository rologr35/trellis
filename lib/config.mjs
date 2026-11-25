// The node side of lib/config.sh: the effective config as `trellis config list` prints it, so the
// schema and its defaults have one reader. Used by hygiene/, scripts/ratchet.mjs and lib/blocks.mjs.

import {execFileSync} from 'node:child_process';
import {mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

export const TRELLIS_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

export class ConfigError extends Error {}

/**
 * The effective config.
 * @param {{file?: string, cwd?: string, label?: string, throws?: boolean}} options - file overrides
 *   the config path (TRELLIS_CONFIG), and a file that does not exist yields the defaults. A file
 *   that does not parse fails closed: the error is printed and the process exits 3, or, with
 *   throws, a ConfigError is thrown for the caller to decide.
 */
export function loadConfig({file, cwd, label = 'trellis.config', throws = false} = {}) {
  const env = {...process.env};
  if (file) env.TRELLIS_CONFIG = file;
  let out;
  try {
    out = execFileSync('bash', [path.join(TRELLIS_ROOT, 'bin', 'trellis'), 'config', 'list'], {
      cwd,
      env,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (error) {
    const reason = String(error.stderr ?? error.message).trim().replace(/^trellis: trellis\.config does not parse: /, '');
    const message = `trellis: ${label} does not parse: ${reason}`;
    if (throws) throw new ConfigError(message);
    console.error(message);
    process.exit(3);
  }
  const values = new Map();
  const spelled = new Map();
  for (const line of out.split('\n')) {
    const eq = line.indexOf('=');
    if (eq <= 0) continue;
    const key = line.slice(0, eq);
    const lower = key.toLowerCase();
    if (!values.has(lower)) {
      values.set(lower, []);
      spelled.set(lower, key);
    }
    values.get(lower).push(line.slice(eq + 1));
  }
  const all = key => values.get(key.toLowerCase()) ?? [];
  return {
    all,
    get: key => all(key).at(-1) ?? '',
    /** The names of the subsections of a section, in the order the config writes them. */
    subsections(section) {
      const prefix = `${section.toLowerCase()}.`;
      const names = [];
      for (const [lower, key] of spelled) {
        if (!lower.startsWith(prefix)) continue;
        const rest = key.slice(prefix.length);
        const dot = rest.lastIndexOf('.');
        if (dot <= 0) continue;
        const name = rest.slice(0, dot);
        if (!names.includes(name)) names.push(name);
      }
      return names;
    },
  };
}

/** The effective config of the index, by the project tree that reads it (lib/tree.mjs). */
export function stagedConfig(tree) {
  const scratch = mkdtempSync(path.join(tmpdir(), 'trellis-config-'));
  const file = path.join(scratch, 'trellis.config');
  const text = tree.read('trellis.config');
  if (text !== null) writeFileSync(file, text);
  const config = loadConfig({file, cwd: tree.root, label: 'trellis.config (staged)'});
  rmSync(scratch, {recursive: true, force: true});
  return config;
}
