#!/usr/bin/env bash
#
# secret-scan-ci: the secret scan of the consumer CI. Runs [command "<name>"] ci (or run, when there
# is no ci form) of the command [command] secretScan names, after making sure the scanner exists:
#   - gitleaks is installed at the version and sha256 pinned below, from its official release;
#   - any other scanner is installed by its [command "<name>"] ciInstall, and without one the job
#     fails saying how to declare it, so a scanner that is not there never reads as a red finding.
# Nothing configured passes with a line that says so (trellis doctor warns about it).
#
#   bash scripts/secret-scan-ci.sh      from the project root, in CI (linux x64)

set -uo pipefail

TRELLIS_ROOT="${TRELLIS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TRELLIS="$TRELLIS_ROOT/bin/trellis"

GITLEAKS_VERSION='8.21.2'
GITLEAKS_SHA256='5bc41815076e6ed6ef8fbecc9d9b75bcae31f39029ceb55da08086315316e3ba'

name="$(bash "$TRELLIS" config get command.secretScan)" || exit $?
if [ -z "$name" ]; then
  echo 'secret-scan: no [command] secretScan configured'
  exit 0
fi
run="$(bash "$TRELLIS" config get "command.$name.ci")" || exit $?
[ -n "$run" ] || run="$(bash "$TRELLIS" config get "command.$name.run")"
if [ -z "$run" ]; then
  echo "secret-scan: [command \"$name\"] has neither ci nor run" >&2
  exit 1
fi
tool="${run%% *}"

if ! command -v "$tool" >/dev/null 2>&1; then
  install="$(bash "$TRELLIS" config get "command.$name.ciInstall")"
  if [ -n "$install" ]; then
    bash -c "$install" || { echo "secret-scan: [command \"$name\"] ciInstall failed" >&2; exit 1; }
  elif [ "$tool" = 'gitleaks' ]; then
    dir="$(mktemp -d)"
    archive="$dir/gitleaks.tar.gz"
    url="https://github.com/gitleaks/gitleaks/releases/download/v$GITLEAKS_VERSION/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
    curl -fsSL -o "$archive" "$url" || { echo "secret-scan: could not download $url" >&2; exit 1; }
    actual="$( (sha256sum "$archive" 2>/dev/null || shasum -a 256 "$archive") | cut -c1-64)"
    if [ "$actual" != "$GITLEAKS_SHA256" ]; then
      echo "secret-scan: gitleaks $GITLEAKS_VERSION has sha256 $actual, expected $GITLEAKS_SHA256" >&2
      exit 1
    fi
    tar -xzf "$archive" -C "$dir" gitleaks || exit 1
    export PATH="$dir:$PATH"
  else
    echo "secret-scan: $tool is not installed in CI. Declare how: [command \"$name\"] ciInstall = <the commands that install it>" >&2
    exit 1
  fi
fi
command -v "$tool" >/dev/null 2>&1 || { echo "secret-scan: $tool still not found after its install" >&2; exit 1; }

echo "secret-scan: $run"
bash -c "$run"
