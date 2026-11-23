// The node side of lib/config.sh: the effective config as `trellis config list` prints it, so the
// schema and its defaults have one reader. Used by hygiene/, scripts/ratchet.mjs and lib/blocks.mjs.

import {execFileSync} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

export const TRELLIS_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

/**
 * The effective config.
 * @param {{file?: string, cwd?: string}} options - file overrides the config path (TRELLIS_CONFIG);
 *   a file that does not exist yields the defaults
 */
export function loadConfig({file, cwd} = {}) {
  const env = {...process.env};
  if (file) env.TRELLIS_CONFIG = file;
  const out = execFileSync('bash', [path.join(TRELLIS_ROOT, 'bin', 'trellis'), 'config', 'list'], {
    cwd,
    env,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
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
