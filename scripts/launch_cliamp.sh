#!/bin/bash

set -euo pipefail

readonly MANAGED_CLASS="org.omarchy.cliamp.quake"

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

# Flags from the user's CLIamp shortcut arrive as one string. Split them on
# whitespace, as Omarchy's own TUI launcher does.
read -r -a cliamp_args <<<"${1:-}"

exec omarchy-launch-or-focus-tui "--app-id=$MANAGED_CLASS" cliamp \
  "${cliamp_args[@]}"
