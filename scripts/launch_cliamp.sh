#!/bin/bash

set -euo pipefail

readonly MANAGED_CLASS="org.omarchy.cliamp.quake"
readonly THUNDER_ASSET="${CLIAMP_THUNDER_ASSET:-${XDG_DATA_HOME:-$HOME/.local/share}/cliamp/thunder.webm}"

notify_error() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  hyprctl notify -1 5000 "rgb(ff5555)" "CLIamp: $*" \
    >/dev/null 2>&1 || true
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    notify_error "required command not found: $1"
    exit 1
  }
}

require_command cliamp
require_command omarchy-launch-or-focus-tui

launch_args=("--app-id=$MANAGED_CLASS" cliamp)
if [[ -r $THUNDER_ASSET ]]; then
  launch_args+=(--auto-play "$THUNDER_ASSET")
fi

exec omarchy-launch-or-focus-tui "${launch_args[@]}"
