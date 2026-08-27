#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly STOCK_WORKSPACE="cliamp"
readonly THUNDER_ASSET="${CLIAMP_THUNDER_ASSET:-${XDG_DATA_HOME:-$HOME/.local/share}/cliamp/thunder.webm}"

# shellcheck source=lib/clients.sh
source "$SCRIPT_DIR/../lib/clients.sh"
# shellcheck source=lib/quake.sh
source "$SCRIPT_DIR/../lib/quake.sh"

notify_error() {
  hyprctl notify -1 5000 "rgb(ff5555)" "CLIamp: $*" >/dev/null 2>&1 || true
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    notify_error "required command not found: $1"
    exit 1
  }
}

first_client_json() {
  local clients_json

  clients_json="$(hyprctl clients -j)"
  cliamp_managed_clients_json "$clients_json" | jq -c '.[0] // null'
}

require_command jq
require_command hyprctl

client_json="$(first_client_json)"
if [[ $client_json == "null" ]]; then
  require_command cliamp
  require_command omarchy-launch-or-focus-tui

  launch_args=("--app-id=$CLIAMP_MANAGED_CLASS" cliamp)
  if [[ -r "$THUNDER_ASSET" ]]; then
    launch_args+=(--auto-play "$THUNDER_ASSET")
  fi
  omarchy-launch-or-focus-tui "${launch_args[@]}" >/dev/null 2>&1 &

  wait_attempts="${CLIAMP_WAIT_ATTEMPTS:-100}"
  wait_interval="${CLIAMP_WAIT_INTERVAL:-0.05}"
  if [[ ! $wait_attempts =~ ^[1-9][0-9]*$ ]]; then
    notify_error "CLIAMP_WAIT_ATTEMPTS must be a positive integer"
    exit 2
  fi

  for ((attempt = 0; attempt < wait_attempts; attempt++)); do
    sleep "$wait_interval"
    client_json="$(first_client_json)"
    [[ $client_json != "null" ]] && break
  done

  if [[ $client_json == "null" ]]; then
    notify_error "window did not appear"
    exit 1
  fi
fi

if ! quake_toggle_client "$client_json" "$STOCK_WORKSPACE"; then
  notify_error "Hyprland returned an invalid window address"
  exit 1
fi
