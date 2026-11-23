#!/usr/bin/env bash
# Exercises lib/config.sh through `trellis config`: defaults, overrides, multi keys, subsections,
# case-insensitive keys and unknown keys.
. "$(dirname "$0")/testlib.sh"

repo="$(tl_repo)"
cd "$repo" || exit 1

printf '\nno config: the defaults\n'
tl_eq 'single default' 'develop' "$("$TRELLIS" config get git.integrationBranch)"
tl_eq 'multi default' "main
develop" "$("$TRELLIS" config all git.protected)"
tl_eq 'no unknown keys' '' "$("$TRELLIS" config unknown)"

cat > trellis.config <<'CFG'
# a comment
[git]
	integrationbranch = dev
	protected = release
[command "analyze"]
	run = flutter analyze
[command "Unit"]
	run = flutter test --reporter=compact
[command]
	check = analyze
	check = Unit
[rung "Unit"]
	command = Unit
	agent = false
[ratchets]
	suppression = \\bTODO\\b
[bogus]
	key = 1
CFG

printf '\nwith a config\n'
tl_eq 'override, key matched without case' 'dev' "$("$TRELLIS" config get git.integrationBranch)"
tl_eq 'a multi key replaces its defaults' 'release' "$("$TRELLIS" config all git.protected)"
tl_eq 'value with = kept whole' 'flutter test --reporter=compact' "$("$TRELLIS" config get command.Unit.run)"
tl_eq 'subsection names keep their case' "analyze
Unit" "$("$TRELLIS" config subsections command)"
tl_eq 'subsection default' 'true' "$("$TRELLIS" config get rung.Unit.pr)"
tl_eq 'subsection override' 'false' "$("$TRELLIS" config get rung.Unit.agent)"
tl_eq 'a doubled backslash reads as one' '\bTODO\b' "$("$TRELLIS" config all ratchets.suppression)"
tl_eq 'unknown key reported' 'bogus.key' "$("$TRELLIS" config unknown)"
tl_eq 'TRELLIS_CONFIG points elsewhere' 'develop' "$(TRELLIS_CONFIG="$repo/none" "$TRELLIS" config get git.integrationBranch)"

printf '\na config that does not parse fails closed\n'
printf '[git\n\tprotected = main\n' > trellis.config
out="$("$TRELLIS" config get git.integrationBranch 2>&1)"
tl_eq 'config get fails' '3' "$?"
tl_has 'and names the parse error' 'trellis.config does not parse' "$out"
tl_lacks 'instead of answering the default' 'develop' "$out"
for cmd in check 'pr-check --body body.md' hygiene ratchet sync; do
  [ "$cmd" = ratchet ] && git add trellis.config
  printf 'x\n' > body.md
  # shellcheck disable=SC2086
  out="$("$TRELLIS" $cmd 2>&1)"
  tl_eq "$cmd fails" '3' "$?"
  tl_has "$cmd names the parse error" 'trellis.config does not parse' "$out"
done
out="$(bash "$TRELLIS_ROOT/scripts/doctor.sh" 2>&1)"
tl_has 'doctor reports it' 'trellis.config does not parse' "$out"
tl_has 'and keeps diagnosing' 'billing' "$out"

tl_done
