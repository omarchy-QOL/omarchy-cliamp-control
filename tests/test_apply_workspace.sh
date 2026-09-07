#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_ROOT="$(mktemp -d)"
readonly TEST_DIR TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

readonly MOCK_BIN="$TEMP_ROOT/bin"
export CLIAMP_TEST_STATE="$TEMP_ROOT/state"
export CLIAMP_TEST_EXPRESSION="$TEMP_ROOT/expression"
export CLIAMP_TEST_CALLS="$TEMP_ROOT/calls"
CLIAMP_TEST_SEED="[workspace special:cliamp silent] bash $(
  readlink -f "$TEST_DIR/../scripts/launch_cliamp.sh"
)"
readonly CLIAMP_TEST_SEED
export CLIAMP_TEST_SEED

mkdir -p "$MOCK_BIN"
printf 'before\n' >"$CLIAMP_TEST_STATE"
: >"$CLIAMP_TEST_CALLS"

cat >"$MOCK_BIN/hyprctl" <<'MOCK'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >>"$CLIAMP_TEST_CALLS"
case "${1:-}" in
  monitors)
    cat <<'JSON'
[
  {
    "id": 1,
    "name": "TEST",
    "width": 1920,
    "height": 1080,
    "x": 0,
    "y": 0,
    "scale": 1,
    "transform": 0,
    "reserved": [0, 26, 0, 0],
    "focused": true,
    "disabled": false
  }
]
JSON
    ;;
  workspacerules)
    if [[ $(cat "$CLIAMP_TEST_STATE") == after ]]; then
      jq -cn --arg seed "$CLIAMP_TEST_SEED" '[{
        workspaceString: "special:cliamp",
        enabled: true,
        gapsIn: [0, 0, 0, 0],
        gapsOut: [0, 360, 454, 360],
        border: false,
        onCreatedEmpty: $seed
      }]'
    else
      printf '[]\n'
    fi
    ;;
  eval)
    printf '%s\n' "${2:-}" >"$CLIAMP_TEST_EXPRESSION"
    printf 'after\n' >"$CLIAMP_TEST_STATE"
    ;;
  *)
    exit 2
    ;;
esac
MOCK
chmod 0755 "$MOCK_BIN/hyprctl"

result="$(
  PATH="$MOCK_BIN:$PATH" \
    bash "$TEST_DIR/../scripts/apply_workspace.sh" Center 1200 600
)"

jq -e '
  .status == "applied"
  and .actual == {x: 360, y: 26, width: 1200, height: 600}
  and .gaps == {top: 0, right: 360, bottom: 454, left: 360}
' >/dev/null <<<"$result"
grep -Fq 'hl.workspace_rule({ workspace = "special:cliamp"' \
  "$CLIAMP_TEST_EXPRESSION"
grep -Fq 'gaps_in = 0' "$CLIAMP_TEST_EXPRESSION"
grep -Fq \
  'gaps_out = { top = 0, right = 360, bottom = 454, left = 360 }' \
  "$CLIAMP_TEST_EXPRESSION"
grep -Fq 'no_border = true' "$CLIAMP_TEST_EXPRESSION"
grep -Fq \
  'on_created_empty = "[workspace special:cliamp silent] bash ' \
  "$CLIAMP_TEST_EXPRESSION"
grep -Fq 'scripts/launch_cliamp.sh"' "$CLIAMP_TEST_EXPRESSION"
grep -Fq 'workspace = "special:cliamp"' "$CLIAMP_TEST_EXPRESSION"
if grep -Eq 'hl\.dsp\.window|hl\.dispatch' \
  "$CLIAMP_TEST_EXPRESSION"; then
  printf 'workspace update dispatched a window action\n' >&2
  exit 1
fi
if grep -Eq 'hl\.(config|animation)' "$CLIAMP_TEST_EXPRESSION"; then
  printf 'global qconsole presentation was duplicated\n' >&2
  exit 1
fi

unchanged="$(
  PATH="$MOCK_BIN:$PATH" \
    bash "$TEST_DIR/../scripts/apply_workspace.sh" \
      Center 1200 600
)"
jq -e '
  .status == "unchanged"
' >/dev/null <<<"$unchanged"
[[ $(grep -c '^eval ' "$CLIAMP_TEST_CALLS") -eq 1 ]]

reloaded="$(
  printf 'missing\n' >"$CLIAMP_TEST_STATE"
  PATH="$MOCK_BIN:$PATH" \
    bash "$TEST_DIR/../scripts/apply_workspace.sh" \
      Center 1200 600
)"
jq -e '
  .status == "applied"
' \
  >/dev/null <<<"$reloaded"
[[ $(grep -c '^eval ' "$CLIAMP_TEST_CALLS") -eq 2 ]]

right="$(
  PATH="$MOCK_BIN:$PATH" \
    bash "$TEST_DIR/../scripts/apply_workspace.sh" \
      Right 850 425
)"
jq -e '
  .actual == {x: 1070, y: 26, width: 850, height: 425}
  and .gaps == {top: 0, right: 0, bottom: 629, left: 1070}
' >/dev/null <<<"$right"

printf 'ok - qconsole workspace rule\n'
