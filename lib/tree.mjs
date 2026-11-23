// The files of a project as git sees them, read from the working tree or from the index, so the
// hygiene of `--staged` judges exactly what is about to be committed. Used by hygiene/ and sync.

import {execFileSync} from 'node:child_process';
import {existsSync, readFileSync, statSync} from 'node:fs';
import path from 'node:path';

const run = (cwd, args) =>
  execFileSync('git', args, {cwd, encoding: 'utf8', maxBuffer: 256 << 20, stdio: ['ignore', 'pipe', 'ignore']});

/** Paths never part of the project's instructions: other sessions' worktrees. */
const IGNORED = /^\.claude\/worktrees\//;

/**
 * @param {string} root - the project's top level
 * @param {{staged?: boolean}} options - staged reads the index instead of the working tree
 * @returns {{root: string, files: string[], has(file: string): boolean, read(file: string): string|null, size(file: string): number}}
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
  };
}

/** The top level of the git repository that holds cwd. */
export function topLevel(cwd = process.cwd()) {
  return run(cwd, ['rev-parse', '--show-toplevel']).trim();
}
