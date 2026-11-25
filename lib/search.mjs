// What counts as a search of the backlog besides the two of trellis: the values of tracker.search.
// hooks/guard-git.sh asks whether a command is one, and scripts/doctor.sh why a value is none.

/**
 * What a session runs all the time, and the creations of an issue the guard judges: an expression that
 * matches one of these says nothing of a search, and a creation refused before is none for the next one.
 */
const NOT_A_SEARCH = ['', 'ls', 'git status', 'gh issue create', 'gh issue new', 'trellis issue create'];

/**
 * The regular expression of a value of tracker.search, or why it is none.
 * @returns {{expression?: RegExp, why?: string}}
 */
export function searchOf(value) {
  let expression;
  try {
    expression = new RegExp(value);
  } catch (error) {
    return {why: `does not compile: ${error.message}`};
  }
  const matched = NOT_A_SEARCH.find(text => expression.test(text));
  if (matched === undefined) return {expression};
  return {why: `matches ${matched === '' ? 'the empty string' : `the command ${matched}`}, which is no search of the backlog`};
}
