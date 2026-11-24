// The files of a project as git sees them, read from the working tree or from the index, so the
// hygiene of `--staged` judges exactly what is about to be committed. Used by hygiene/ and sync.

import {execFileSync} from 'node:child_process';
import {existsSync, readFileSync, realpathSync, statSync} from 'node:fs';
import path from 'node:path';

const run = (cwd, args) =>
  execFileSync('git', args, {cwd, encoding: 'utf8', maxBuffer: 256 << 20, stdio: ['ignore', 'pipe', 'ignore']});

/** Paths never part of the project's instructions: other sessions' worktrees. */
const IGNORED = /^\.claude\/worktrees\//;

/**
 * @param {string} root - the project's top level
 * @param {{staged?: boolean}} options - staged reads the index instead of the working tree
 * @returns {{root: string, files: string[], has(file: string): boolean, read(file: string): string|null, size(file: string): number, bytes(files: string[]): Map<string, Buffer|null>}}
 */
export function projectTree(root, {staged = false} = {}) {
  const listed = staged
    ? run(root, ['ls-files', '-z', '--cached'])
    : run(root, ['ls-files', '-z', '--cached', '--others', '--exclude-standard']);
  const files = [...new Set(listed.split('\0').filter(Boolean))]
    .filter(f => !IGNORED.test(f))
    .filter(f => staged || (existsSync(path.join(root, f)) && statSync(path.join(root, f)).isFile()))
    .sort();
  const set = new Set(files);
  const cache = new Map();
  const read = file => {
    if (!set.has(file)) return null;
    if (!cache.has(file)) {
      cache.set(file, staged ? run(root, ['show', `:${file}`]) : readFileSync(path.join(root, file), 'utf8'));
    }
    return cache.get(file);
  };
  return {
    root,
    files,
    has: file => set.has(file),
    read,
    size: file => Buffer.byteLength(read(file) ?? ''),
    /** The bytes of each file, null for one that is not there or is reached through a symbolic link. */
    bytes: wanted => (staged ? stagedBytes(root, wanted.filter(f => set.has(f))) : new Map(wanted.map(f => [f, set.has(f) ? plainBytes(root, f) : null]))),
  };
}

function plainBytes(root, file) {
  const full = path.join(root, file);
  return realpathSync(full) === path.join(realpathSync(root), file) ? readFileSync(full) : null;
}

/** One `git cat-file` for all of them: a process per file is what a pre-commit would feel. */
function stagedBytes(root, files) {
  const regular = new Set(run(root, ['ls-files', '-s', '-z']).split('\0').filter(l => l.startsWith('100')).map(l => l.slice(l.indexOf('\t') + 1)));
  const wanted = files.filter(f => regular.has(f));
  const out = execFileSync('git', ['cat-file', '--batch'], {cwd: root, input: wanted.map(f => `:${f}\n`).join(''), maxBuffer: 256 << 20, stdio: ['pipe', 'pipe', 'ignore']});
  const found = new Map();
  let at = 0;
  for (const file of wanted) {
    const eol = out.indexOf('\n', at);
    const size = Number(/ blob (\d+)$/.exec(out.toString('utf8', at, eol))?.[1]);
    found.set(file, out.subarray(eol + 1, eol + 1 + size));
    at = eol + 1 + size + 1;
  }
  return found;
}

/** The top level of the git repository that holds cwd. */
export function topLevel(cwd = process.cwd()) {
  return run(cwd, ['rev-parse', '--show-toplevel']).trim();
}
