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
git config -f trellis.config --add hygiene.keepRef 'CLAUDE.md: #4 | reason' && git add -A
tl_eq 'a grown allowlist is refused' '1' "$(judge)"
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
