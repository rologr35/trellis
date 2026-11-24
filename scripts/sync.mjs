// The writing of `trellis sync` (scripts/sync.sh holds the contract).

import {existsSync, readFileSync, writeFileSync} from 'node:fs';
import path from 'node:path';
import {BLOCK_FILES, FIND_TRELLIS_COPY, findTrellisSource, generateBlocks, generatedDeny, pushDenyBranch, replaceBlocks} from '../lib/blocks.mjs';
import {loadConfig} from '../lib/config.mjs';
import {ownTree} from '../lib/copy.mjs';
import {projectTree, topLevel} from '../lib/tree.mjs';

const root = topLevel();
const config = loadConfig({cwd: root});
const tree = ownTree(projectTree(root));
const blocks = generateBlocks(tree, config);
const changed = [];

const write = (file, text) => {
  const full = path.join(root, file);
  const was = existsSync(full) ? readFileSync(full, 'utf8') : null;
  if (was === text) return;
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
if (existsSync(path.join(root, settingsFile))) {
  const settings = JSON.parse(readFileSync(path.join(root, settingsFile), 'utf8'));
  settings.permissions ??= {};
  const protectedBranches = new Set(config.all('git.protected'));
  const kept = (settings.permissions.deny ?? []).filter(entry => {
    const branch = pushDenyBranch(entry);
    return branch === null || protectedBranches.has(branch);
  });
  settings.permissions.deny = [...new Set([...kept, ...generatedDeny(config)])];
  write(settingsFile, `${JSON.stringify(settings, null, 2)}\n`);
}

if (existsSync(path.join(root, '.githooks'))) write(FIND_TRELLIS_COPY, findTrellisSource());

for (const file of changed) console.log(`sync: wrote ${file}`);
if (changed.length === 0) console.log('sync: nothing to change');
