// trellis verify: the project's copy of trellis is whole.
//
//   trellis verify              the working tree: every file of .trellis/MANIFEST is there with its
//                               hash, and .trellis/ has no other file
//   trellis verify --staged     the same of the index (the pre-commit)
//   trellis verify --upstream   the same, and the files are the ones the upstream has at the sha of
//                               .trellis/VERSION, so a manifest edited with its file does not pass (CI)
//
// Prints one line per finding and exits 1 when there is any. Node only, no dependencies.

import {VERSION_FILE, parseVersion, verifyCopy, verifyUpstream} from '../lib/copy.mjs';
import {loadConfig} from '../lib/config.mjs';
import {projectTree, topLevel} from '../lib/tree.mjs';

const args = process.argv.slice(2);
if (args.some(a => a !== '--staged' && a !== '--upstream')) {
  console.error('usage: trellis verify [--staged | --upstream]');
  process.exit(2);
}
const root = topLevel();
const tree = projectTree(root, {staged: args.includes('--staged')});
const findings = verifyCopy(tree);
if (args.includes('--upstream') && findings.length === 0) {
  try {
    findings.push(...(await verifyUpstream(tree, loadConfig({cwd: root}).get('trellis.upstream'))));
  } catch (error) {
    findings.push(error.message);
  }
}
for (const line of findings) console.log(`  FAIL  ${line}`);
const version = parseVersion(tree.read(VERSION_FILE));
console.log(findings.length ? `\nverify: ${findings.length} finding(s)` : `verify: trellis ${version.version} (${version.sha}), whole`);
process.exit(findings.length ? 1 : 0);
