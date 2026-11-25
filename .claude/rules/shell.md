---
paths:
  - "**/*.sh"
---

# Shell scripts

- `/bin/bash` 3.2 runs every script: no `mapfile`, no associative array, no `${x,,}`, no `local -n`. An empty array under `set -u` is expanded as `${a[@]+"${a[@]}"}`.
- The tools are the ones of macOS and of Linux at once: no `readlink -f`, no `sed -i`, no `grep -P`, no `date -d`, no `stat` with the flags of one of them.
- A script starts with `set -uo pipefail`, without `-e`: what can fail is checked where it can, and a check that could not be made fails closed and says so.
- The comment at the head is the contract: what it does, its usage and its exit codes. It changes with the code.
- The config is read with `tc_get` and `tc_all` of `lib/config.sh`; a key is declared in `lib/schema` first.
- GitHub is read with `gh_api` of `lib/gh.sh`, which is the REST interface: a cloud session refuses GraphQL, which `gh issue view` and `gh pr view` use. A token is neither printed nor exported.
- A file that is sourced, or copied into `.githooks/`, works alone and sets no option of the shell that sources it.
- A suite sources `lib/testlib.sh`, works in `$TL_TMP` and ends with `tl_done`.
