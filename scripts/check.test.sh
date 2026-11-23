#!/usr/bin/env bash
# Exercises scripts/check.sh: order, fail-fast, missing commands.
. "$(dirname "$0")/../lib/testlib.sh"

repo="$(tl_repo)"
cd "$repo" || exit 1

cat > trellis.config <<'CFG'
[command "one"]
	run = echo one >> log
[command "two"]
	run = echo two >> log && false
[command "three"]
	run = echo three >> log
[command]
	check = one
	check = two
	check = three
CFG
"$TRELLIS" check >/dev/null 2>&1
tl_eq 'stops at the first failure' '1' "$?"
tl_eq 'runs in order and no further' "one
two" "$(cat log)"

git config -f trellis.config --unset-all command.check
git config -f trellis.config --add command.check one
rm -f log
out="$("$TRELLIS" check 2>&1)"
tl_eq 'passes' '0' "$?"
tl_has 'says so' 'all passed' "$out"

git config -f trellis.config --add command.check missing
out="$("$TRELLIS" check 2>&1)"
tl_eq 'a name without run fails' '1' "$?"
tl_has 'names it' '[command "missing"] has no run' "$out"

tl_done
