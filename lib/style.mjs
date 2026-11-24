// The style of every text a project publishes on GitHub: a pull request body, a commit message, an
// issue. Read by scripts/pr-check.mjs and scripts/issue-check.mjs.

const LONG_DASH = /[—–]/;
const ATTRIBUTION = /co-authored-by:|generated with|claude\.ai\/code|\u{1F916}/iu;
// The words a reference follows, the es ones included (Ver, depende de, parte de) for es bodies.
const KEYWORD = /(?:^|[\s(])(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|refs?|see|ver|issue|pr|pull request|depende de|parte de|part of)\s+$/i;

/** What the text breaks of the style, one message per miss, each starting with `what`. */
export function styleMisses(text, what) {
  const misses = [];
  if (LONG_DASH.test(text)) misses.push(`${what}: has a long dash; use a comma, a colon or parentheses`);
  if (ATTRIBUTION.test(text)) misses.push(`${what}: has an attribution (Co-Authored-By, "Generated with", a session link)`);
  const prose = text.replace(/```[\s\S]*?```/g, '').replace(/`[^`\n]*`/g, '');
  for (const line of prose.split('\n')) {
    for (const m of line.matchAll(/(?<![\w&/])#(\d+)\b/g)) {
      const before = line.slice(0, m.index);
      const parenthesized = before.endsWith('(') && line.slice(m.index + m[0].length).startsWith(')');
      if (!parenthesized && !KEYWORD.test(before)) {
        misses.push(`${what}: bare ${m[0]} that GitHub links to an issue ("${line.trim()}"); write it after Closes/Refs/See, or in backticks`);
      }
    }
  }
  return misses;
}
