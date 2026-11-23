#!/usr/bin/env bash
# Exercises scripts/secret-scan-ci.sh: nothing configured, a scanner present, a scanner missing
# with and without its declared install.
. "$(dirname "$0")/../lib/testlib.sh"

SCAN="$TRELLIS_ROOT/scripts/secret-scan-ci.sh"
tools="$TL_TMP/tools"
mkdir -p "$tools"
repo="$(tl_repo)"
cd "$repo" || exit 1
scan() { PATH="$tools:$PATH" bash "$SCAN" > "$TL_TMP/out.txt" 2>&1; echo $?; }

printf '[project]\n\tname = x\n' > trellis.config
tl_eq 'nothing configured passes' '0' "$(scan)"
tl_has 'and says so' 'no [command] secretScan' "$(cat "$TL_TMP/out.txt")"

cat > trellis.config <<'CFG'
[command "scan"]
	run = fakescan --staged
	ci = fakescan --all
[command]
	secretScan = scan
CFG
tl_eq 'a missing scanner without a declared install fails' '1' "$(scan)"
tl_has 'and says how to declare it' 'ciInstall' "$(cat "$TL_TMP/out.txt")"

git config -f trellis.config command.scan.ciInstall "printf '#!/bin/sh\necho scanned \$*\n' > $tools/fakescan && chmod +x $tools/fakescan"
tl_eq 'the declared install runs and then the ci form' '0' "$(scan)"
tl_has 'with the ci arguments' 'scanned --all' "$(cat "$TL_TMP/out.txt")"

printf '#!/bin/sh\nexit 1\n' > "$tools/fakescan"
tl_eq 'a scan that finds something fails' '1' "$(scan)"

tl_done
