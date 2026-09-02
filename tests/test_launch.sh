#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_ROOT="$(mktemp -d)"
readonly TEST_DIR TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

readonly MOCK_BIN="$TEMP_ROOT/bin"
export CLIAMP_TEST_CALLS="$TEMP_ROOT/calls"
export CLIAMP_THUNDER_ASSET="$TEMP_ROOT/thunder.webm"

mkdir -p "$MOCK_BIN"
: >"$CLIAMP_TEST_CALLS"

cat >"$MOCK_BIN/omarchy-launch-or-focus-tui" <<'MOCK'
#!/bin/bash
set -euo pipefail

printf 'launch %s\n' "$*" >>"$CLIAMP_TEST_CALLS"
MOCK
cat >"$MOCK_BIN/cliamp" <<'MOCK'
#!/bin/bash
exit 0
MOCK
cat >"$MOCK_BIN/hyprctl" <<'MOCK'
#!/bin/bash
set -euo pipefail

printf 'hyprctl %s\n' "$*" >>"$CLIAMP_TEST_CALLS"
MOCK
chmod 0755 "$MOCK_BIN/omarchy-launch-or-focus-tui" \
  "$MOCK_BIN/cliamp" "$MOCK_BIN/hyprctl"

touch "$CLIAMP_THUNDER_ASSET"
PATH="$MOCK_BIN:$PATH" bash "$TEST_DIR/../scripts/launch_cliamp.sh"
grep -Fxq \
  "launch --app-id=org.omarchy.cliamp.quake cliamp --auto-play $CLIAMP_THUNDER_ASSET" \
  "$CLIAMP_TEST_CALLS"

: >"$CLIAMP_TEST_CALLS"
rm -f -- "$CLIAMP_THUNDER_ASSET"
PATH="$MOCK_BIN:$PATH" bash "$TEST_DIR/../scripts/launch_cliamp.sh"
grep -Fxq 'launch --app-id=org.omarchy.cliamp.quake cliamp' \
  "$CLIAMP_TEST_CALLS"
if grep -Fq -- '--auto-play' "$CLIAMP_TEST_CALLS"; then
  printf 'missing thunder asset was still passed to CLIamp\n' >&2
  exit 1
fi

: >"$CLIAMP_TEST_CALLS"
rm -f -- "$MOCK_BIN/cliamp"
if PATH="$MOCK_BIN" /bin/bash "$TEST_DIR/../scripts/launch_cliamp.sh"; then
  printf 'missing CLIamp binary did not fail lazy launch\n' >&2
  exit 1
fi
grep -Fq 'CLIamp: required command not found: cliamp' "$CLIAMP_TEST_CALLS"

printf 'ok - lazy managed CLIamp launch\n'
