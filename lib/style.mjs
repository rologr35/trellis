// The style of every text a project publishes on GitHub: a pull request body, a commit message, an
// issue. Read by scripts/pr-check.mjs and scripts/issue-check.mjs.

// Stands for each character of code in a text of the same length.
const CODE = '\0';
const LONG_DASH = /[—–]/;
const ATTRIBUTION = /co-authored-by:|generated with|claude\.ai\/code|\u{1F916}/iu;
// The words a reference follows, the es ones included (Ver, depende de, parte de) for es bodies.
const KEYWORD = /(?:^|[\s(])(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|refs?|see|ver|issue|pr|pull request|depende de|parte de|part of)\s+$/i;

/** The line of the text that holds the character `at`. */
function lineOf(text, at) {
  const end = text.indexOf('\n', at);
  return text.slice(text.lastIndexOf('\n', at) + 1, end < 0 ? text.length : end).trim();
}

/** What the text breaks of the style, one message per miss, each starting with `what`. */
export function styleMisses(text, what) {
  const misses = [];
  if (LONG_DASH.test(text)) misses.push(`${what}: has a long dash; use a comma, a colon or parentheses`);
  if (ATTRIBUTION.test(text)) misses.push(`${what}: has an attribution (Co-Authored-By, "Generated with", a session link)`);
  // A reference is searched in the text without code, and quoted in its line of the text as written.
  const blank = (code) => CODE.repeat(code.length);
  const marked = text.replace(/```[\s\S]*?```/g, blank).replace(/`[^`\n]*`/g, blank);
  let start = 0;
  for (const part of marked.split('\n')) {
    const at = [];
    for (let i = 0; i < part.length; i++) if (part[i] !== CODE) at.push(start + i);
    start += part.length + 1;
    const line = at.map((i) => text[i]).join('');
    for (const m of line.matchAll(/(?<![\w&/])#(\d+)\b/g)) {
      const before = line.slice(0, m.index);
      const parenthesized = before.endsWith('(') && line.slice(m.index + m[0].length).startsWith(')');
      if (!parenthesized && !KEYWORD.test(before)) {
        misses.push(`${what}: bare ${m[0]} that GitHub links to an issue ("${lineOf(text, at[m.index])}"); write it after Closes/Refs/See, or in backticks`);
      }
    }
  }
  return misses;
}
