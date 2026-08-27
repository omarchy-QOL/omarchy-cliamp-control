#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_ROOT="$(mktemp -d)"
readonly TEST_DIR TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

readonly MOCK_BIN="$TEMP_ROOT/bin"
export CLIAMP_TEST_CALLS="$TEMP_ROOT/calls"
export CLIAMP_TEST_LAUNCHED="$TEMP_ROOT/launched"
export CLIAMP_TEST_MODE="$TEMP_ROOT/mode"
export CLIAMP_TEST_VISIBLE="$TEMP_ROOT/visible"
export CLIAMP_THUNDER_ASSET="$TEMP_ROOT/thunder.webm"

mkdir -p "$MOCK_BIN"
touch "$CLIAMP_THUNDER_ASSET"

cat >"$MOCK_BIN/hyprctl" <<'MOCK'
#!/bin/bash
set -euo pipefail

client_json() {
  local class="$1"
  local workspace="$2"

  printf '[{"address":"0xabc","class":"%s","initialClass":"%s","workspace":{"name":"%s"}}]\n' \
    "$class" "$class" "$workspace"
}

case "${1:-}" in
  clients)
    mode="$(cat "$CLIAMP_TEST_MODE")"
    if [[ ( $mode == "absent" || $mode == "stock" || $mode == "legacy" ) \
      && -e $CLIAMP_TEST_LAUNCHED ]]; then
      mode="managed"
      printf '%s\n' "$mode" >"$CLIAMP_TEST_MODE"
    fi
    case "$mode" in
      absent) printf '[]\n' ;;
      managed) client_json "org.omarchy.cliamp.quake" "3" ;;
      special) client_json "org.omarchy.cliamp.quake" "special:cliamp" ;;
      stock) client_json "org.omarchy.cliamp" "3" ;;
      legacy) client_json "org.omarchy.quake.music" "special:music" ;;
      *) exit 2 ;;
    esac
    ;;
  monitors)
    visible="$(cat "$CLIAMP_TEST_VISIBLE")"
    printf '[{"specialWorkspace":{"name":"%s"}}]\n' "$visible"
    ;;
  dispatch)
    expression="${2:-}"
    printf '%s\n' "$expression" >>"$CLIAMP_TEST_CALLS"
    if [[ $expression == *'workspace = "special:cliamp"'* ]]; then
      printf 'special\n' >"$CLIAMP_TEST_MODE"
    elif [[ $expression == *'workspace = "special:music"'* ]]; then
      printf 'legacy\n' >"$CLIAMP_TEST_MODE"
    fi
    if [[ $expression == *'toggle_special("cliamp")'* ]]; then
      if [[ $(cat "$CLIAMP_TEST_VISIBLE") == "special:cliamp" ]]; then
        : >"$CLIAMP_TEST_VISIBLE"
      else
        printf 'special:cliamp\n' >"$CLIAMP_TEST_VISIBLE"
      fi
    elif [[ $expression == *'toggle_special("music")'* ]]; then
      if [[ $(cat "$CLIAMP_TEST_VISIBLE") == "special:music" ]]; then
        : >"$CLIAMP_TEST_VISIBLE"
      else
        printf 'special:music\n' >"$CLIAMP_TEST_VISIBLE"
      fi
    fi
    ;;
  notify)
    ;;
  *)
    exit 2
    ;;
esac
MOCK

cat >"$MOCK_BIN/omarchy-launch-or-focus-tui" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >>"$CLIAMP_TEST_CALLS"
touch "$CLIAMP_TEST_LAUNCHED"
MOCK

cat >"$MOCK_BIN/cliamp" <<'MOCK'
#!/bin/bash
exit 0
MOCK

chmod 0755 "$MOCK_BIN/hyprctl" \
  "$MOCK_BIN/omarchy-launch-or-focus-tui" "$MOCK_BIN/cliamp"

reset_case() {
  local mode="$1"
  local visible="$2"

  printf '%s\n' "$mode" >"$CLIAMP_TEST_MODE"
  printf '%s\n' "$visible" >"$CLIAMP_TEST_VISIBLE"
  : >"$CLIAMP_TEST_CALLS"
  rm -f -- "$CLIAMP_TEST_LAUNCHED"
}

run_toggle() {
  CLIAMP_WAIT_ATTEMPTS=10 CLIAMP_WAIT_INTERVAL=0 \
    PATH="$MOCK_BIN:$PATH" \
    bash "$TEST_DIR/../scripts/toggle_cliamp.sh"
}

reset_case absent ""
run_toggle
grep -Fxq -- "--app-id=org.omarchy.cliamp.quake cliamp --auto-play $CLIAMP_THUNDER_ASSET" \
  "$CLIAMP_TEST_CALLS"
grep -Fq 'workspace = "special:cliamp"' "$CLIAMP_TEST_CALLS"
grep -Fq 'toggle_special("cliamp")' "$CLIAMP_TEST_CALLS"
[[ $(cat "$CLIAMP_TEST_VISIBLE") == "special:cliamp" ]]

reset_case special "special:cliamp"
run_toggle
[[ ! -e $CLIAMP_TEST_LAUNCHED ]]
[[ ! -s $CLIAMP_TEST_VISIBLE ]]
[[ $(grep -Fc 'toggle_special("cliamp")' "$CLIAMP_TEST_CALLS") -eq 1 ]]

reset_case special ""
run_toggle
[[ $(cat "$CLIAMP_TEST_VISIBLE") == "special:cliamp" ]]
[[ $(grep -Fc 'toggle_special("cliamp")' "$CLIAMP_TEST_CALLS") -eq 1 ]]

reset_case managed ""
run_toggle
grep -Fq 'workspace = "special:cliamp"' "$CLIAMP_TEST_CALLS"
[[ $(cat "$CLIAMP_TEST_VISIBLE") == "special:cliamp" ]]

reset_case stock ""
run_toggle
grep -Fxq -- "--app-id=org.omarchy.cliamp.quake cliamp --auto-play $CLIAMP_THUNDER_ASSET" \
  "$CLIAMP_TEST_CALLS"
grep -Fq 'workspace = "special:cliamp"' "$CLIAMP_TEST_CALLS"

reset_case legacy "special:music"
run_toggle
grep -Fxq -- "--app-id=org.omarchy.cliamp.quake cliamp --auto-play $CLIAMP_THUNDER_ASSET" \
  "$CLIAMP_TEST_CALLS"
grep -Fq 'workspace = "special:cliamp"' "$CLIAMP_TEST_CALLS"
grep -Fq 'toggle_special("cliamp")' "$CLIAMP_TEST_CALLS"
if grep -Fq 'special:music' "$CLIAMP_TEST_CALLS"; then
  printf 'legacy CLIamp window was incorrectly managed\n' >&2
  exit 1
fi

printf 'ok - only binding-managed CLIamp toggles\n'
