// The one reading of a glob of trellis: the paths of the rules (hygiene/) and those of the gates (scripts/).

/** The regular expression of a glob: `**` crosses folders, `*` stays inside one. */
export function globToRegExp(glob) {
  if (/[{}[\]?!]/u.test(glob)) throw new Error(`glob ${glob} uses syntax trellis does not read; split it into plain globs`);
  let source = '';
  for (let i = 0; i < glob.length; i++) {
    if (glob.startsWith('**/', i)) {
      source += '(?:.*/)?';
      i += 2;
    } else if (glob.startsWith('**', i)) {
      source += '.*';
      i += 1;
    } else if (glob[i] === '*') {
      source += '[^/]*';
    } else {
      source += glob[i].replace(/[.+^$()|\\]/gu, String.raw`\$&`);
    }
  }
  return new RegExp(`^${source}$`, 'u');
}
