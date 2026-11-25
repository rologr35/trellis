// The copy of trellis a project commits: its runtime under .trellis/, its skills and agents under
// .claude/ with the prefix `trellis-`. One definition of what it holds (copyOf), of its manifest and
// of what makes it whole (verifyCopy). `trellis update` writes it and `trellis verify` judges it; the
// hygiene and the ratchet leave its files out. The repository of trellis runs from its own tree: it has
// no .trellis/, and its skills and agents as a copy holds them (generatedFiles).

import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, rmdirSync, statSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {TRELLIS_ROOT} from './config.mjs';
import {projectTree} from './tree.mjs';

export const COPY_DIR = '.trellis';
export const VERSION_FILE = `${COPY_DIR}/VERSION`;
export const MANIFEST_FILE = `${COPY_DIR}/MANIFEST`;

const RUNTIME = /^(?:(?:bin|hooks|lib|scripts|hygiene|method|templates)\/.+|LICENSE)$/;
const NOT_COPIED = /^hooks\/hooks\.json$|\.test\.[^/]+$|^lib\/testlib\.sh$/;
const SKILL = /^skills\/([^/]+)\/SKILL\.md$/;
const AGENT = /^agents\/([^/]+)\.md$/;
const GENERATED = /^\.claude\/(?:skills\/trellis-[^/]+\/SKILL|agents\/trellis-[^/]+)\.md$/;

/** The only paths a manifest may name: a line for any other file of the project is not a copy's. */
const COPIED = /^(?:\.trellis\/(?!MANIFEST$).+|\.claude\/skills\/trellis-[^/]+\/SKILL\.md|\.claude\/agents\/trellis-[^/]+\.md)$/;
const isCopied = file => COPIED.test(file) && !file.split('/').some(part => part === '' || part === '.' || part === '..');

const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const git = (cwd, ...args) => execFileSync('git', ['-C', cwd, ...args], {encoding: 'utf8', maxBuffer: 64 << 20, stdio: ['ignore', 'pipe', 'pipe']});

/** The text of a skill or an agent with the name it has in a project. */
function renamed(bytes, name) {
  const text = bytes.toString('utf8');
  const front = /^---\n[\s\S]*?\n---\n/.exec(text)?.[0];
  if (!front) return bytes;
  return Buffer.from(front.replace(/^name: .*$/m, `name: ${name}`) + text.slice(front.length));
}

/**
 * Where a skill or an agent of trellis goes in a project, and the name it has there; null for any
 * other file, the skill `init` included: what it writes is the copy.
 */
function inProject(file) {
  const skill = SKILL.exec(file)?.[1];
  const agent = AGENT.exec(file)?.[1];
  if (skill && skill !== 'init') return {target: `.claude/skills/trellis-${skill}/SKILL.md`, name: `trellis-${skill}`};
  return agent ? {target: `.claude/agents/trellis-${agent}.md`, name: `trellis-${agent}`} : null;
}

/**
 * The files of a copy, but its manifest, from a clone of trellis checked out at `sha`. Every version
 * has this function with this signature: `update` and `verify` call the one of the version they read.
 * @returns {Map<string, {bytes: Buffer, executable: boolean}>} by path in the project
 */
export function copyOf(source, sha) {
  const copy = new Map();
  for (const line of git(source, 'ls-tree', '-r', '-z', '--full-tree', 'HEAD').split('\0').filter(Boolean)) {
    const [meta, file] = line.split('\t');
    const mode = meta.split(' ')[0];
    if (!mode.startsWith('100') || NOT_COPIED.test(file)) continue;
    const bytes = () => readFileSync(path.join(source, file));
    const named = inProject(file);
    if (named) {
      copy.set(named.target, {bytes: renamed(bytes(), named.name), executable: false});
    } else if (RUNTIME.test(file)) {
      copy.set(`${COPY_DIR}/${file}`, {bytes: bytes(), executable: mode === '100755'});
    }
  }
  const {version} = JSON.parse(readFileSync(path.join(source, '.claude-plugin', 'plugin.json'), 'utf8'));
  copy.set(VERSION_FILE, {bytes: Buffer.from(`${version} ${sha}\n`), executable: false});
  return new Map([...copy].sort(([a], [b]) => (a < b ? -1 : 1)));
}

/** Whether a project tree is the repository of trellis, which runs from its own tree. */
export function isTrellis(tree) {
  try {
    return tree.has('lib/find-trellis.sh') && JSON.parse(tree.read('.claude-plugin/plugin.json')).name === 'trellis';
  } catch {
    return false;
  }
}

// By the folder and not by its path, which a disk that ignores the case writes in many ways.
const sameFolder = (a, b) => {
  const [one, other] = [statSync(a), statSync(b)];
  return one.dev === other.dev && one.ino === other.ino;
};

/** Stops a command of another checkout in the repository of trellis: it would judge it by other code. */
export function refuseOtherCheckout(root, command) {
  if (!isTrellis(projectTree(root)) || sameFolder(root, TRELLIS_ROOT)) return;
  console.error(`${command}: this is the trellis of ${TRELLIS_ROOT}, and the repository of trellis runs from its own tree: run bin/trellis of ${root}`);
  process.exit(1);
}

/**
 * The skills and agents the repository of trellis generates for itself.
 * @returns {{expected: Map<string, {source: string, bytes: Buffer}>, leftOver: string[]}} by path, and
 *   the ones of the tree with no source
 */
export function generatedFiles(tree) {
  const expected = new Map();
  const sources = tree.files.filter(inProject);
  const bytes = tree.bytes(sources);
  for (const source of sources) {
    const {target, name} = inProject(source);
    if (bytes.get(source)) expected.set(target, {source, bytes: renamed(bytes.get(source), name)});
  }
  return {expected, leftOver: tree.files.filter(f => GENERATED.test(f) && !expected.has(f))};
}

/** The manifest of a copy: one line per file, `<sha256>  <path>`, as `shasum -c` reads it. */
export const manifestOf = copy => [...copy].map(([file, {bytes}]) => `${sha256(bytes)}  ${file}\n`).join('');

/** The entries of a manifest, and its lines that are not one. */
export function parseManifest(text) {
  const entries = new Map();
  const invalid = [];
  for (const line of (text ?? '').split('\n').filter(Boolean)) {
    const [, hash, file] = /^([0-9a-f]{64}) {2}(.+)$/.exec(line) ?? [];
    if (file && isCopied(file) && !entries.has(file)) entries.set(file, hash);
    else invalid.push(line);
  }
  return {entries, invalid};
}

/** The version and the sha of a VERSION file, or null. */
export function parseVersion(text) {
  const m = /^(\S+) ([0-9a-f]{40})\n$/.exec(text ?? '');
  return m && {version: m[1], sha: m[2]};
}

/** The files of a copy, by its manifest: what the hygiene and the ratchet leave to `trellis verify`. */
export const copiedFiles = manifest => new Set(manifest === null ? [] : [MANIFEST_FILE, ...parseManifest(manifest).entries.keys()]);

/** A project tree without the files of its copy. */
export function ownTree(tree) {
  const copied = copiedFiles(tree.read(MANIFEST_FILE));
  return {...tree, files: tree.files.filter(f => !copied.has(f)), has: f => tree.has(f) && !copied.has(f)};
}

/** Whether a project tree has a copy, whole or not. */
export const hasCopy = tree => tree.files.some(f => f.startsWith(`${COPY_DIR}/`));

/**
 * What keeps the copy of a project tree from being whole, one line per file: every file of the
 * manifest is there with its hash, and .trellis/ has no other.
 */
export function verifyCopy(tree) {
  if (!tree.has(MANIFEST_FILE)) return [`${MANIFEST_FILE}: is not there: trellis update <tag|sha> writes the copy`];
  const findings = [];
  const {entries, invalid} = parseManifest(tree.read(MANIFEST_FILE));
  for (const line of invalid) findings.push(`${MANIFEST_FILE}: is not a line of a copy's manifest: ${line}`);
  if (!parseVersion(tree.read(VERSION_FILE))) findings.push(`${VERSION_FILE}: does not hold a version and a full sha`);
  if (!entries.has(VERSION_FILE)) findings.push(`${MANIFEST_FILE}: does not list ${VERSION_FILE}`);
  const bytes = tree.bytes([...entries.keys()]);
  for (const [file, hash] of entries) {
    if (!bytes.get(file)) findings.push(`${file}: is in the manifest and is not there`);
    else if (sha256(bytes.get(file)) !== hash) findings.push(`${file}: is not the file that was copied`);
  }
  for (const file of tree.files) {
    if (file.startsWith(`${COPY_DIR}/`) && file !== MANIFEST_FILE && !entries.has(file)) findings.push(`${file}: is not in the manifest`);
  }
  return findings;
}

/** The URL of the repository `trellis.upstream` names: an `owner/repo` is one of github.com, and a URL or a path stays as written. */
export const upstreamUrl = upstream => (/^[\w.-]+\/[\w.-]+$/.test(upstream) ? `https://github.com/${upstream}.git` : upstream);

/** The newest tag of an upstream that is a version, or null. What asks does not wait more than a minute. */
export function newestTag(upstream) {
  const listed = execFileSync('git', ['ls-remote', '--tags', '--refs', '--', upstreamUrl(upstream)], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
    timeout: 60_000,
    env: {...process.env, GIT_TERMINAL_PROMPT: '0', GIT_SSH_COMMAND: process.env.GIT_SSH_COMMAND || 'ssh -oBatchMode=yes'},
  });
  const tags = [...listed.matchAll(/\trefs\/tags\/(v?(\d+)\.(\d+)\.(\d+))$/gm)];
  tags.sort((a, b) => a[2] - b[2] || a[3] - b[3] || a[4] - b[4]);
  return tags.at(-1)?.[1] ?? null;
}

/**
 * Clones the upstream into a temporary folder, at the commit of a tag or of a sha, and hands it to
 * `use`. A branch is refused: what it names changes.
 */
export async function withUpstream(upstream, ref, use) {
  const dir = mkdtempSync(path.join(tmpdir(), 'trellis-upstream-'));
  try {
    const url = upstreamUrl(upstream);
    try {
      git(dir, '-c', 'core.autocrlf=false', 'clone', '-q', '--no-checkout', '--', url, 'trellis');
    } catch (error) {
      throw new Error(`${url} could not be cloned: ${String(error.stderr ?? error.message).trim()}`);
    }
    const source = path.join(dir, 'trellis');
    const commit = name => {
      try {
        return git(source, 'rev-parse', '--verify', '--quiet', '--end-of-options', `${name}^{commit}`).trim();
      } catch {
        return '';
      }
    };
    // A full sha is never read as a name: a tag could carry it and point at another commit.
    const tag = /^[0-9a-f]{40}$/.test(ref) ? '' : commit(`refs/tags/${ref}`);
    const short = tag === '' && /^[0-9a-f]{7,40}$/.test(ref) ? commit(ref) : '';
    const sha = tag || (short.startsWith(ref) ? short : '');
    if (!sha) throw new Error(`${ref} is neither a tag nor a sha of ${url}`);
    git(source, '-c', 'core.autocrlf=false', '-c', 'advice.detachedHead=false', 'checkout', '-q', sha);
    if (!existsSync(path.join(source, 'lib', 'copy.mjs'))) throw new Error(`${ref} of ${url} has no lib/copy.mjs: it is a version from before the copy`);
    const version = await import(pathToFileURL(path.join(source, 'lib', 'copy.mjs')).href);
    return await use({copy: version.copyOf(source, sha), sha, url});
  } finally {
    rmSync(dir, {recursive: true, force: true});
  }
}

/** What a copy that verifies differs in from the upstream at the sha of its VERSION. */
export async function verifyUpstream(tree, upstream) {
  const {sha} = parseVersion(tree.read(VERSION_FILE));
  return withUpstream(upstream, sha, ({copy, url}) => {
    const findings = [];
    const {entries} = parseManifest(tree.read(MANIFEST_FILE));
    const bytes = tree.bytes([...copy.keys()]);
    for (const [file, theirs] of copy) {
      if (!bytes.get(file)?.equals(theirs.bytes)) findings.push(`${file}: is not the one of ${url} at ${sha}`);
    }
    for (const file of entries.keys()) {
      if (!copy.has(file)) findings.push(`${file}: is in the manifest, and ${url} does not copy it at ${sha}`);
    }
    return findings;
  });
}

/** The workflow of a project that calls the ones of trellis by their sha. */
const WORKFLOW = '.github/workflows/trellis.yml';

const lstat = file => lstatSync(file, {throwIfNoEntry: false});

/** What stops `copy` from being written in the project, one line per file. */
function inTheWay(root, copy, previous) {
  const findings = [];
  const files = [...copy.keys(), MANIFEST_FILE];
  const folders = new Set(files.flatMap(file => file.split('/').slice(0, -1).map((_, i, parts) => parts.slice(0, i + 1).join('/'))));
  for (const folder of folders) {
    const stat = lstat(path.join(root, folder));
    if (stat && !stat.isDirectory()) findings.push(`${folder}: is not a folder`);
  }
  if (findings.length) return findings;
  const same = (file, bytes) => lstat(path.join(root, file)).isFile() && readFileSync(path.join(root, file)).equals(bytes);
  for (const [file, {bytes}] of copy) {
    if (!previous.has(file) && lstat(path.join(root, file)) && !same(file, bytes)) findings.push(`${file}: is a file of the project, not of a copy`);
  }
  let ignored = '';
  try {
    ignored = execFileSync('git', ['-C', root, 'check-ignore', '-z', '--stdin'], {input: files.join('\0'), encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore']});
  } catch {
    // Status 1: none is ignored.
  }
  for (const file of ignored.split('\0').filter(Boolean)) findings.push(`${file}: git ignores it (.gitignore: !/.trellis/**)`);
  return findings;
}

/**
 * Writes the copy of a tag or of a sha in the project, and removes what the previous one had and this
 * one does not. The sha of the previous copy becomes the new one in the workflow. Throws, with nothing
 * written, when the previous one was edited or a file is in the way.
 */
export async function update(root, upstream, ref) {
  const tree = projectTree(root);
  if (hasCopy(tree) && !tree.has(MANIFEST_FILE)) throw new Error(`${MANIFEST_FILE} is not there, as an interrupted update leaves it: what ${COPY_DIR}/ holds cannot be told.\nRestore it from git, or delete ${COPY_DIR}/ if it was never committed.`);
  const previous = hasCopy(tree) ? parseManifest(tree.read(MANIFEST_FILE)).entries : new Map();
  const previousSha = parseVersion(tree.read(VERSION_FILE))?.sha;
  const edited = hasCopy(tree) ? verifyCopy(tree) : [];
  if (edited.length) throw new Error(`the copy was edited by hand, and an update would lose it:\n${edited.map(l => `  ${l}`).join('\n')}\nRestore those files from git, or take the change to ${upstream} first. If ${COPY_DIR}/ was never committed, delete the whole ${COPY_DIR}/ and run the update again.`);
  return withUpstream(upstream, ref, ({copy, sha}) => {
    const blocked = inTheWay(root, copy, previous);
    if (blocked.length) throw new Error(`the copy cannot be written:\n${blocked.map(l => `  ${l}`).join('\n')}`);
    // Renamed into place: this may be the copy that is running.
    const write = (file, bytes, executable) => {
      const full = path.join(root, file);
      mkdirSync(path.dirname(full), {recursive: true});
      writeFileSync(`${full}.tmp`, bytes, {mode: executable ? 0o755 : 0o644});
      renameSync(`${full}.tmp`, full);
    };
    const removed = [...previous.keys()].filter(file => !copy.has(file));
    for (const file of removed) {
      rmSync(path.join(root, file), {force: true});
      for (let dir = path.dirname(file); ![COPY_DIR, '.claude/skills', '.claude/agents'].includes(dir); dir = path.dirname(dir)) {
        try {
          rmdirSync(path.join(root, dir));
        } catch {
          break;
        }
      }
    }
    for (const [file, {bytes, executable}] of copy) write(file, bytes, executable);
    write(MANIFEST_FILE, manifestOf(copy), false);
    const full = path.join(root, WORKFLOW);
    const calls = previousSha && lstat(full)?.isFile() ? readFileSync(full, 'latin1') : '';
    const pinned = calls.replaceAll(previousSha, sha);
    if (pinned !== calls) write(WORKFLOW, Buffer.from(pinned, 'latin1'), false);
    return {workflow: pinned !== calls ? WORKFLOW : '', version: parseVersion(copy.get(VERSION_FILE).bytes.toString()).version, sha, files: copy.size + 1, removed: removed.length};
  });
}
