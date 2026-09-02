#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_ROOT="$(mktemp -d)"
readonly TEST_DIR TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

readonly MOCK_BIN="$TEMP_ROOT/bin"
export CLIAMP_TEST_CALLS="$TEMP_ROOT/calls"

mkdir -p "$MOCK_BIN"
: >"$CLIAMP_TEST_CALLS"

cat >"$MOCK_BIN/hyprctl" <<'MOCK'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >>"$CLIAMP_TEST_CALLS"
[[ ${1:-} == dispatch ]]
MOCK
chmod 0755 "$MOCK_BIN/hyprctl"

PATH="$MOCK_BIN:$PATH" bash "$TEST_DIR/../scripts/toggle_cliamp.sh"

[[ $(wc -l <"$CLIAMP_TEST_CALLS") -eq 1 ]]
grep -Fxq \
  'dispatch hl.dsp.workspace.toggle_special("cliamp")' \
  "$CLIAMP_TEST_CALLS"

printf 'ok - toggle only controls the CLIamp special workspace\n'
