// trellis verify: the project's copy of trellis is whole, and lists nothing that copy.without leaves out.
//
//   trellis verify              the working tree: every file of .trellis/MANIFEST is there with its
//                               hash, and .trellis/ has no other file
//   trellis verify --staged     the same of the index, its trellis.config included (the pre-commit)
//   trellis verify --upstream   the same, and the files are the ones the upstream has at the sha of
//                               .trellis/VERSION, so a manifest edited with its file does not pass, but
//                               the ones copy.without names, which are skills or agents of it (CI)
//   trellis verify --ref <sha>  the same as the first, and the sha of VERSION is this one
//
// Prints one line per finding and exits 1 when there is any. Node only, no dependencies.

import {VERSION_FILE, parseVersion, verifyCopy, verifyUpstream, verifyWithout} from '../lib/copy.mjs';
import {loadConfig, stagedConfig} from '../lib/config.mjs';
import {projectTree, topLevel} from '../lib/tree.mjs';

const args = process.argv.slice(2);
const at = args.indexOf('--ref');
const ref = at === -1 ? null : args.splice(at, 2)[1] ?? '';
if (ref === '' || args.some(a => a !== '--staged' && a !== '--upstream')) {
  console.error('usage: trellis verify [--staged | --upstream] [--ref <sha>]');
  process.exit(2);
}
const root = topLevel();
const staged = args.includes('--staged');
const tree = projectTree(root, {staged});
const config = staged ? stagedConfig(tree) : loadConfig({cwd: root});
const without = config.all('copy.without');
const findings = [...verifyCopy(tree), ...verifyWithout(tree, without)];
const version = parseVersion(tree.read(VERSION_FILE));
if (ref !== null && version && version.sha !== ref) findings.push(`${VERSION_FILE}: holds ${version.sha}, and ${ref} is the one expected`);
// Never before the sha is the one expected: the comparison runs code of the upstream.
if (args.includes('--upstream') && findings.length === 0) {
  try {
    findings.push(...(await verifyUpstream(tree, config.get('trellis.upstream'), without)));
  } catch (error) {
    findings.push(error.message);
  }
}
for (const line of findings) console.log(`  FAIL  ${line}`);
console.log(findings.length ? `\nverify: ${findings.length} finding(s)` : `verify: trellis ${version.version} (${version.sha}), whole`);
process.exit(findings.length ? 1 : 0);
