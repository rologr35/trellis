// The packages of a project, each of which has its CLAUDE.md: the folders of its manifests
// (`workspace.manifest`) below the root, with the ones of `workspace.package` (a package without a
// manifest), and without the ones a glob of `workspace.notPackage` matches. Used by hygiene/.

import path from 'node:path';
import {COPY_DIR} from './copy.mjs';
import {globToRegExp} from './glob.mjs';

/**
 * A `workspace.package` value as a path from the project's root: `./x`, `x/` and `x//` are `x`, and
 * `.` (or `./`) is the root, the empty string. The one reading of the key.
 */
export function packagePath(value) {
  const normalized = path.posix.normalize(value.trim()).replace(/\/+$/u, '');
  return normalized === '.' ? '' : normalized;
}

/** A file of a package: the package at the root has its files at the root. */
export const inPackage = (pkg, file) => (pkg === '' ? file : `${pkg}/${file}`);

/**
 * The folders of the packages of a project tree, those of `workspace.package` first. A manifest of the
 * copy of trellis is none of the project's. Throws on a glob of `workspace.notPackage` it cannot read.
 */
export function packagesOf(tree, config) {
  const manifests = new Set(config.all('workspace.manifest').map(name => name.trim()));
  const out = config.all('workspace.notPackage').map(entry => globToRegExp(packagePath(entry.split('|')[0])));
  const listed = config.all('workspace.package').map(packagePath);
  const found = tree.files
    .filter(file => manifests.has(path.posix.basename(file)) && !file.startsWith(`${COPY_DIR}/`))
    .map(file => packagePath(path.posix.dirname(file)))
    .filter(folder => folder !== '');
  return [...new Set([...listed, ...found])].filter(folder => !out.some(re => re.test(folder)));
}
