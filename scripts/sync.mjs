// The writing of `trellis sync` (scripts/sync.sh holds the contract).

import {existsSync, lstatSync, mkdirSync, readFileSync, rmSync, rmdirSync, unlinkSync, writeFileSync} from 'node:fs';
import path from 'node:path';
import {BLOCK_FILES, FIND_TRELLIS_COPY, findTrellisSource, generateBlocks, generatedDeny, missingHooks, pushDenyBranch, replaceBlocks} from '../lib/blocks.mjs';
import {loadConfig} from '../lib/config.mjs';
import {VERSION_FILE, generatedFiles, isTrellis, ownTree, refuseOtherCheckout} from '../lib/copy.mjs';
import {projectTree, topLevel} from '../lib/tree.mjs';

const root = topLevel();
refuseOtherCheckout(root, 'sync');
const config = loadConfig({cwd: root});
const tree = ownTree(projectTree(root));
const blocks = generateBlocks(tree, config);
const changed = [];

const write = (file, text) => {
  const full = path.join(root, file);
  const was = existsSync(full) ? readFileSync(full, 'utf8') : null;
  if (was === text) return;
  mkdirSync(path.dirname(full), {recursive: true});
  writeFileSync(full, text);
  changed.push(file);
};

for (const [file, ids] of Object.entries(BLOCK_FILES)) {
  const full = path.join(root, file);
  if (!existsSync(full)) continue;
  const allowed = Object.fromEntries(ids.filter(id => id in blocks).map(id => [id, blocks[id]]));
  write(file, replaceBlocks(readFileSync(full, 'utf8'), allowed));
}

const settingsFile = '.claude/settings.json';
const hasSettings = existsSync(path.join(root, settingsFile));
const copy = existsSync(path.join(root, VERSION_FILE));
if (hasSettings || copy) {
  const settings = hasSettings ? JSON.parse(readFileSync(path.join(root, settingsFile), 'utf8')) : {};
  settings.permissions ??= {};
  const protectedBranches = new Set(config.all('git.protected'));
  const kept = (settings.permissions.deny ?? []).filter(entry => {
    const branch = pushDenyBranch(entry);
    return branch === null || protectedBranches.has(branch);
  });
  settings.permissions.deny = [...new Set([...kept, ...generatedDeny(config, {copy})])];
  if (copy) {
    for (const {event, group} of missingHooks(settings)) ((settings.hooks ??= {})[event] ??= []).push(group);
  }
  write(settingsFile, `${JSON.stringify(settings, null, 2)}\n`);
}

if (existsSync(path.join(root, '.githooks'))) write(FIND_TRELLIS_COPY, findTrellisSource());

// The repository of trellis: its skills and agents, as a copy holds them.
const removed = [];
if (isTrellis(tree)) {
  const {expected, leftOver} = generatedFiles(tree);
  const was = tree.bytes([...expected.keys()]);
  for (const [file, {bytes}] of expected) {
    if (was.get(file)?.equals(bytes)) continue;
    const full = path.join(root, file);
    const folder = path.dirname(full);
    // A symbolic link, of the file or of the folder of a skill, would write its target, the source itself maybe.
    if (lstatSync(folder, {throwIfNoEntry: false})?.isSymbolicLink()) unlinkSync(folder);
    mkdirSync(folder, {recursive: true});
    rmSync(full, {force: true});
    writeFileSync(full, bytes);
    changed.push(file);
  }
  for (const file of leftOver) {
    rmSync(path.join(root, file), {force: true});
    removed.push(file);
    try {
      rmdirSync(path.dirname(path.join(root, file)));
    } catch {
      // It holds something else.
    }
  }
}

for (const file of changed) console.log(`sync: wrote ${file}`);
for (const file of removed) console.log(`sync: removed ${file}`);
if (changed.length + removed.length === 0) console.log('sync: nothing to change');
