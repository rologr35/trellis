#!/usr/bin/env bash
# The bash the scripts run with is the one CI expects: on macOS, 3.2, the shell a Mac runs them
# with. TRELLIS_EXPECT_BASH names the expected version; without it there is nothing to compare.
. "$(dirname "$0")/testlib.sh"

expected="${TRELLIS_EXPECT_BASH:-}"
if [ -z "$expected" ]; then
  printf '  skip  TRELLIS_EXPECT_BASH is not set\n'
  tl_done
  exit $?
fi
tl_has 'bash on the PATH' "version $expected" "$(bash --version | head -n 1)"
tl_has 'the bash of #!/usr/bin/env bash' "version $expected" "$(/usr/bin/env bash --version | head -n 1)"
tl_eq 'the bash a script runs under' "$expected" "$(bash -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"')"
tl_done
