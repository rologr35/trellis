#!/usr/bin/env bash
# Exercises scripts/ratchet.sh: suppressions (Dart and JS), deleted tests, lint configs, settings,
# the [hygiene] numbers and lists, the escape, the merge, and --base.
. "$(dirname "$0")/../lib/testlib.sh"

repo="$(tl_repo)"
cd "$repo" || exit 1
OUT="$TL_TMP/out.txt"
git switch -q -c 7-work
mkdir -p lib test .claude
printf 'void main() {}\n' > lib/main.dart
printf 'void main() { test("a", () {}); }\n' > test/a_test.dart
printf 'linter:\n  rules:\n    - avoid_print\n    prefer_const_constructors: true\nanalyzer:\n  errors:\n    unused_import: error\n' > analysis_options.yaml
printf '{"model": "sonnet", "hooks": {"PreToolUse": [{"hooks": [{"type": "command", "command": "x"}]}]}}\n' > .claude/settings.json
printf '[hygiene]\n\trootLimit = 1000\n\tfrozen = docs/a.md 500\n' > trellis.config
mkdir docs && printf 'a\n' > docs/a.md
git add -A && git commit -q -m 'feat: base (#7)'

judge() { "$TRELLIS" ratchet >"$OUT" 2>&1; echo $?; }
reset() { git reset -q --hard; git clean -qfd; }

printf '\nsuppressions\n'
printf '// ignore: unused\nvoid main() {}\n' > lib/main.dart && git add -A
tl_eq 'a Dart // ignore: is refused' '1' "$(judge)"
tl_has 'with its cost' 'cost:' "$(cat "$OUT")"
reset
printf 'void main() { test("a", () {}, skip: true); }\n' > test/a_test.dart && git add -A
tl_eq 'a skip: true is refused' '1' "$(judge)"
reset
printf '// ignore_for_file: x\n' > lib/b.dart && git add -A
tl_eq 'an ignore_for_file in a new file is refused' '1' "$(judge)"
reset
printf '//ignore: unused\nvoid main() {}\n' > lib/main.dart && git add -A
tl_eq 'an //ignore: without a space is refused' '1' "$(judge)"
reset
printf '//ignore_for_file: x\n' > lib/b.dart && git add -A
tl_eq 'an //ignore_for_file: without a space is refused' '1' "$(judge)"
reset
printf 'void main() {}\n' > lib/b.dart && git add -A
tl_eq 'a clean change passes' '0' "$(judge)"
reset
printf '// eslint-disable-next-line\n' > x.ts && git add -A
tl_eq 'an eslint-disable is refused' '1' "$(judge)"
reset
printf 'Write // ignore: in docs\n' > notes.md && git add -A
tl_eq 'markdown is not code' '0' "$(judge)"
reset

printf '\ntests\n'
git rm -q test/a_test.dart
tl_eq 'a deleted Dart test is refused' '1' "$(judge)"
reset
git mv test/a_test.dart test/b_test.dart
tl_eq 'a renamed test passes' '0' "$(judge)"
reset

printf '\nlint\n'
printf 'linter:\n  rules:\n    prefer_const_constructors: true\nanalyzer:\n  errors:\n    unused_import: error\n' > analysis_options.yaml && git add -A
tl_eq 'a dropped Dart rule is refused' '1' "$(judge)"
reset
printf 'linter:\n  rules:\n    - avoid_print\n    prefer_const_constructors: true\nanalyzer:\n  errors:\n    unused_import: warning\n' > analysis_options.yaml && git add -A
tl_eq 'a lowered severity is refused' '1' "$(judge)"
reset
printf 'linter:\n  rules:\n    - avoid_print\n    - always_declare_return_types\n    prefer_const_constructors: true\nanalyzer:\n  errors:\n    unused_import: error\n' > analysis_options.yaml && git add -A
tl_eq 'an added rule passes' '0' "$(judge)"
reset
printf 'linter:\n  rules:\n    - avoid_print\n    prefer_const_constructors: true\nanalyzer:\n  errors:\n    unused_import: error\n    dead_code: ignore\n' > analysis_options.yaml && git add -A
tl_eq 'a new errors: <code>: ignore is refused' '1' "$(judge)"
reset
printf 'linter:\n  rules:\n    - avoid_print\n    prefer_const_constructors: true\n    inherited_rule: false\nanalyzer:\n  errors:\n    unused_import: error\n' > analysis_options.yaml && git add -A
tl_eq 'a new rules: <rule>: false for an inherited rule is refused' '1' "$(judge)"
reset
printf 'linter:\n  rules:\n    - avoid_print\n    prefer_const_constructors: true\nanalyzer:\n  exclude:\n    - lib/generated/**\n  errors:\n    unused_import: error\n' > analysis_options.yaml && git add -A
tl_eq 'a new analyzer: exclude: path is refused' '1' "$(judge)"
reset
printf 'export default [{rules: {"no-console": "error"}}];\n' > eslint.config.mjs && git add -A && git commit -q --no-verify -m 'chore: eslint (#7)'
printf 'export default [{rules: {"no-console": "error", "no-debugger": "off"}}];\n' > eslint.config.mjs && git add -A
tl_eq 'a new ESLint rule set to off is refused' '1' "$(judge)"
reset

printf '\nsettings\n'
printf '{"model": "opus", "hooks": {"PreToolUse": [{"hooks": [{"type": "command", "command": "x"}]}]}}\n' > .claude/settings.json && git add -A
tl_eq 'a raised model is refused' '1' "$(judge)"
reset
printf '{"model": "sonnet"}\n' > .claude/settings.json && git add -A
tl_eq 'a dropped hook is refused' '1' "$(judge)"
reset

printf '\nconfig\n'
git config -f trellis.config hygiene.rootLimit 2000 && git add -A
tl_eq 'a raised limit is refused' '1' "$(judge)"
reset
git config -f trellis.config hygiene.rootLimit 900 && git add -A
tl_eq 'a lowered limit passes' '0' "$(judge)"
reset
git config -f trellis.config --replace-all hygiene.frozen 'docs/a.md 600' && git add -A
tl_eq 'a raised frozen size is refused' '1' "$(judge)"
reset
git config -f trellis.config --add hygiene.frozen 'docs/b.md 900' && git add -A
tl_eq 'a size frozen for the first time passes' '0' "$(judge)"
reset
git config -f trellis.config autonomy.level balanced && git add -A
tl_eq 'a raise of autonomy.level from the default is refused' '1' "$(judge)"
tl_has 'naming both levels' 'raises autonomy.level from careful to balanced' "$(cat "$OUT")"
reset
git config -f trellis.config autonomy.level careful && git add -A
tl_eq 'the default written down passes' '0' "$(judge)"
git config -f trellis.config autonomy.level reckless && git add -A
tl_eq 'a value that is none of the levels is the lowest' '0' "$(judge)"
git config -f trellis.config autonomy.level autonomous && git add -A
git commit -q -m 'chore: level (#7)'
git config -f trellis.config autonomy.level balanced && git add -A
tl_eq 'lowering it passes' '0' "$(judge)"
git reset -q --hard HEAD~1
git config -f trellis.config autonomy.level balanced && git add -A && git commit -q -m 'chore: level (#7)'
git config -f trellis.config autonomy.level autonomous && git add -A
tl_eq 'a raise from a written level is refused' '1' "$(judge)"
tl_has 'naming them' 'raises autonomy.level from balanced to autonomous' "$(cat "$OUT")"
git reset -q --hard HEAD~1
git config -f trellis.config --add hygiene.keepRef 'CLAUDE.md: #4 | reason' && git add -A
tl_eq 'a grown allowlist is refused' '1' "$(judge)"
reset

printf '[hygiene\n' > "$TL_TMP/broken.config"
cp trellis.config "$TL_TMP/good.config"
cp "$TL_TMP/broken.config" trellis.config && git add trellis.config && cp "$TL_TMP/good.config" trellis.config
tl_eq 'a staged config that does not parse fails closed' '3' "$(judge)"
tl_has 'naming it' 'trellis.config (staged) does not parse' "$(cat "$OUT")"
reset
cp "$TL_TMP/broken.config" trellis.config && git add trellis.config && git commit -q --no-verify -m 'chore: broken (#7)'
cp "$TL_TMP/good.config" trellis.config && git add trellis.config
tl_eq 'the commit that repairs it passes' '0' "$(judge)"
git config -f trellis.config hygiene.rootLimit 999999 && git add trellis.config
tl_eq 'a repair that raises a limit over the default is refused' '1' "$(judge)"
cp "$TL_TMP/good.config" trellis.config
git config -f trellis.config ratchets.suppression nothing
printf '// ignore: x\n' >> lib/main.dart && git add -A
tl_eq 'a repair that replaces the suppressions and adds one is refused' '1' "$(judge)"
tl_has 'by the default suppressions' 'adds 1 suppression' "$(cat "$OUT")"
git checkout -q HEAD -- lib/main.dart
cp "$TL_TMP/good.config" trellis.config && git add -A
git commit -q --no-verify -m 'chore: repaired (#7)'

printf '\nthe copy of trellis\n'
upstream="$(tl_upstream)"
tl_copy "$upstream" && git add -A
tl_eq 'the copy is not judged, whatever its files hold' '0' "$(judge)"
git commit -q --no-verify -m 'chore: the copy (#7)'
mkdir -p .trellis/lib && printf '// ignore: x\n' > .trellis/lib/own.dart && git add -A
tl_eq 'a file of .trellis/ out of the manifest is' '1' "$(judge)"
reset
git rm -q test/a_test.dart
printf '%064d  test/a_test.dart\n' 0 >> .trellis/MANIFEST && git add -A
tl_eq 'a manifest does not hide a test of the project' '1' "$(judge)"
reset
mkdir -p .trellis/test && git mv test/a_test.dart .trellis/test/a_test.dart
printf '%064d  .trellis/test/a_test.dart\n' 0 >> .trellis/MANIFEST && git add -A
tl_eq 'a test moved into the copy is a test deleted' '1' "$(judge)"
tl_has 'and named' 'deletes the test test/a_test.dart' "$(cat "$OUT")"
reset
printf 'void main() {}\n' > "$upstream/lib/x_test.dart"
git -C "$upstream" add -A && git -C "$upstream" commit -q -m 'chore: x (#1)' && git -C "$upstream" tag v2
bash "$TRELLIS" update v2 >/dev/null && git add -A && git commit -q --no-verify -m 'chore: v2 (#7)'
bash "$TRELLIS" update v1 >/dev/null && git add -A
tl_eq 'a file the next copy does not have is not a test deleted' '0' "$(judge)"
reset

printf '\nescape, merge and base\n'
printf '// ignore: x\n' >> lib/main.dart && git add -A
git config branch.7-work.ratchet-loosened true
tl_eq 'the escape passes' '0' "$(judge)"
tl_has 'as a warning' 'warning' "$(cat "$OUT")"
git config --unset branch.7-work.ratchet-loosened
git commit -q --no-verify -m 'feat: loosen (#7)'
git switch -q main
git switch -q -c 8-other
printf 'x\n' > other.txt && git add -A && git commit -q -m 'feat: other (#8)'
git merge -q --no-commit --no-ff 7-work >/dev/null 2>&1
tl_eq 'a merge in progress is not judged' '0' "$(judge)"
git merge --abort
git switch -q 7-work
"$TRELLIS" ratchet --base main >"$OUT" 2>&1
tl_eq '--base judges the branch against its base' '1' "$?"
"$TRELLIS" ratchet --base main --allow-loosen >"$OUT" 2>&1
tl_eq '--allow-loosen passes' '0' "$?"

git config -f trellis.config --add ratchets.suppression 'nothing' && git add -A
git commit -q --no-verify -m 'chore: own list (#7)'
git config -f trellis.config --unset-all ratchets.suppression && git add -A
tl_eq 'a shortened ratchet list is refused' '1' "$(judge)"

tl_done
