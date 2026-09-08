#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
readonly TEST_DIR PLUGIN_ROOT TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

readonly MOCK_BIN="$TEMP_ROOT/bin"
readonly TEST_PLUGIN_DIR="$TEMP_ROOT/plugin"
readonly CALLS_FILE="$TEMP_ROOT/calls"
readonly PLUGIN_STATE_FILE="$TEMP_ROOT/plugin-state"
readonly CLIENTS_FILE="$TEMP_ROOT/clients.json"
readonly CLIENT_MODE_FILE="$TEMP_ROOT/client-mode"
readonly CLIENT_COUNT_FILE="$TEMP_ROOT/client-count"
readonly CLIENT_CLOSED_FILE="$TEMP_ROOT/client-closed"
readonly DISPATCH_FAIL_FILE="$TEMP_ROOT/dispatch-fail"

mkdir -p "$MOCK_BIN"

teardown_command="$({
  sed -n \
    '/readonly property string teardownCommand: \[/,/  ].join("\\n")/p' \
    "$PLUGIN_ROOT/Service.qml" |
    sed -n 's/^[[:space:]]*\(".*"\),\{0,1\}$/\1/p' |
    jq -Rr fromjson
})"
readonly teardown_command

[[ -n $teardown_command ]]
bash -n <<<"$teardown_command"
grep -Fq 'Component.onDestruction: root.teardown()' \
  "$PLUGIN_ROOT/Service.qml"

cat >"$MOCK_BIN/omarchy" <<'MOCK'
#!/bin/bash
set -euo pipefail

printf 'omarchy %s\n' "$*" >>"$CLIAMP_TEST_CALLS"
state="$(cat "$CLIAMP_TEST_PLUGIN_STATE")"
case "$state" in
enabled | disabled)
  enabled_value=false
  [[ $state == enabled ]] && enabled_value=true
  printf '[{"id":"io.github.ilyazar.cliamp","enabled":%s}]\n' \
    "$enabled_value"
  ;;
malformed)
  printf 'not json\n'
  ;;
fail)
  exit 1
  ;;
disappears)
  rm -rf -- "$CLIAMP_TEST_PLUGIN_DIR"
  exit 1
  ;;
*)
  exit 2
  ;;
esac
MOCK

cat >"$MOCK_BIN/hyprctl" <<'MOCK'
#!/bin/bash
set -euo pipefail

printf 'hyprctl %s\n' "$*" >>"$CLIAMP_TEST_CALLS"
case "${1:-}" in
reload)
  ;;
clients)
  count="$(cat "$CLIAMP_TEST_CLIENT_COUNT")"
  count=$((count + 1))
  printf '%d\n' "$count" >"$CLIAMP_TEST_CLIENT_COUNT"
  if [[ -e $CLIAMP_TEST_CLIENT_CLOSED ]]; then
    printf '[]\n'
  elif [[ $(cat "$CLIAMP_TEST_CLIENT_MODE") == delayed && $count -eq 1 ]]; then
    printf '[]\n'
  else
    cat "$CLIAMP_TEST_CLIENTS"
  fi
  ;;
dispatch)
  [[ ! -e $CLIAMP_TEST_DISPATCH_FAIL ]] || exit 1
  touch "$CLIAMP_TEST_CLIENT_CLOSED"
  ;;
*)
  exit 2
  ;;
esac
MOCK

chmod 0755 "$MOCK_BIN/omarchy" "$MOCK_BIN/hyprctl"

export CLIAMP_TEST_CALLS="$CALLS_FILE"
export CLIAMP_TEST_PLUGIN_STATE="$PLUGIN_STATE_FILE"
export CLIAMP_TEST_CLIENTS="$CLIENTS_FILE"
export CLIAMP_TEST_CLIENT_MODE="$CLIENT_MODE_FILE"
export CLIAMP_TEST_CLIENT_COUNT="$CLIENT_COUNT_FILE"
export CLIAMP_TEST_CLIENT_CLOSED="$CLIENT_CLOSED_FILE"
export CLIAMP_TEST_DISPATCH_FAIL="$DISPATCH_FAIL_FILE"
export CLIAMP_TEST_PLUGIN_DIR="$TEST_PLUGIN_DIR"

reset_case() {
  rm -rf -- "$TEST_PLUGIN_DIR"
  mkdir -p "$TEST_PLUGIN_DIR"
  : >"$CALLS_FILE"
  printf 'disabled\n' >"$PLUGIN_STATE_FILE"
  printf 'static\n' >"$CLIENT_MODE_FILE"
  printf '0\n' >"$CLIENT_COUNT_FILE"
  printf '[]\n' >"$CLIENTS_FILE"
  rm -f -- "$CLIENT_CLOSED_FILE" "$DISPATCH_FAIL_FILE"
}

run_teardown() {
  local poll_attempts="${1:-1}"
  local enabled_attempts="${2:-2}"

  PATH="$MOCK_BIN:$PATH" bash -c "$teardown_command" \
    cliamp-teardown \
    "$TEST_PLUGIN_DIR" \
    io.github.ilyazar.cliamp \
    org.omarchy.cliamp.quake \
    "$poll_attempts" 0 "$enabled_attempts" 0
}

assert_call_absent() {
  local pattern="$1"

  if grep -Fq "$pattern" "$CALLS_FILE"; then
    printf 'unexpected teardown call: %s\n' "$pattern" >&2
    exit 1
  fi
}

assert_restart_keeps_client() {
  reset_case
  printf 'enabled\n' >"$PLUGIN_STATE_FILE"
  printf '%s\n' \
    '[{"address":"0xaaa","class":"org.omarchy.cliamp.quake"}]' \
    >"$CLIENTS_FILE"

  run_teardown

  assert_call_absent 'hyprctl reload'
  grep -Fq 'omarchy plugin list --json' "$CALLS_FILE"
  assert_call_absent 'hyprctl clients -j'
  assert_call_absent 'hyprctl dispatch'
}

assert_unknown_state_keeps_client() {
  local state

  for state in fail malformed; do
    reset_case
    printf '%s\n' "$state" >"$PLUGIN_STATE_FILE"

    run_teardown 1 2

    [[ $(grep -Fc 'omarchy plugin list --json' "$CALLS_FILE") -eq 2 ]]
    assert_call_absent 'hyprctl reload'
    assert_call_absent 'hyprctl clients -j'
  done
}

assert_disabled_closes_only_managed_clients() {
  reset_case
  printf '%s\n' '[
    {"address":"0xaaa","class":"org.omarchy.cliamp.quake"},
    {"address":"0xbbb","class":"changed",
      "initialClass":"org.omarchy.cliamp.quake"},
    {"address":"0xccc","class":"org.omarchy.cliamp"},
    {"address":"0xddd","class":"org.example.player"},
    {"address":"invalid","class":"org.omarchy.cliamp.quake"}
  ]' >"$CLIENTS_FILE"

  run_teardown

  [[ $(grep -Fc 'hyprctl reload config-only' "$CALLS_FILE") -eq 2 ]]
  [[ $(grep -Fc 'address:0xaaa' "$CALLS_FILE") -eq 1 ]]
  [[ $(grep -Fc 'address:0xbbb' "$CALLS_FILE") -eq 1 ]]
  assert_call_absent 'address:0xccc'
  assert_call_absent 'address:0xddd'
  assert_call_absent 'address:invalid'
  [[ $(head -n 1 "$CALLS_FILE") == 'omarchy plugin list --json' ]]
  [[ $(tail -n 1 "$CALLS_FILE") == 'hyprctl reload config-only' ]]
}

assert_checkout_removal_during_state_check_closes_client() {
  reset_case
  printf 'disappears\n' >"$PLUGIN_STATE_FILE"
  printf '%s\n' \
    '[{"address":"0xab0","class":"org.omarchy.cliamp.quake"}]' \
    >"$CLIENTS_FILE"

  run_teardown

  [[ ! -e $TEST_PLUGIN_DIR ]]
  grep -Fq 'address:0xab0' "$CALLS_FILE"
  [[ $(tail -n 1 "$CALLS_FILE") == 'hyprctl reload config-only' ]]
}

assert_delayed_client_is_closed_after_checkout_removal() {
  reset_case
  rm -rf -- "$TEST_PLUGIN_DIR"
  printf 'delayed\n' >"$CLIENT_MODE_FILE"
  printf '%s\n' \
    '[{"address":"0xeee","class":"org.omarchy.cliamp.quake"}]' \
    >"$CLIENTS_FILE"

  run_teardown 3

  assert_call_absent 'omarchy plugin list --json'
  [[ $(grep -Fc 'hyprctl clients -j' "$CALLS_FILE") -eq 3 ]]
  [[ $(grep -Fc 'address:0xeee' "$CALLS_FILE") -eq 1 ]]
  [[ $(tail -n 1 "$CALLS_FILE") == 'hyprctl reload config-only' ]]
}

assert_close_failure_does_not_skip_final_reload() {
  reset_case
  rm -rf -- "$TEST_PLUGIN_DIR"
  touch "$DISPATCH_FAIL_FILE"
  printf '%s\n' \
    '[{"address":"0xfff","class":"org.omarchy.cliamp.quake"}]' \
    >"$CLIENTS_FILE"

  run_teardown

  grep -Fq 'address:0xfff' "$CALLS_FILE"
  [[ $(grep -Fc 'hyprctl reload config-only' "$CALLS_FILE") -eq 2 ]]
  [[ $(tail -n 1 "$CALLS_FILE") == 'hyprctl reload config-only' ]]
}

assert_restart_keeps_client
assert_unknown_state_keeps_client
assert_disabled_closes_only_managed_clients
assert_checkout_removal_during_state_check_closes_client
assert_delayed_client_is_closed_after_checkout_removal
assert_close_failure_does_not_skip_final_reload

printf 'ok - guarded service teardown\n'
