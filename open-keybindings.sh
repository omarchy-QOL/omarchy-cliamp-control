#!/bin/bash

set -euo pipefail

readonly CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
readonly BINDINGS_FILE="${1:-$CONFIG_HOME/hypr/bindings.lua}"
readonly EDITOR_STATE="$STATE_HOME/omarchy/defaults/editor"

target_line=1
if [[ -r $BINDINGS_FILE ]]; then
  target_line=$(awk '
    {
      line = tolower($0)
      if (line ~ /^[[:space:]]*(o|hl)\.bind[[:space:]]*\(/) {
        bind_start = NR
      }
      matches_description = line ~ /music tui/
      matches_command = line ~ /(omarchy-launch-(or-focus-)?tui[[:space:]]+cliamp)/
      matches_tui = line ~ /tui[[:space:]]*=[[:space:]]*["\047]cliamp["\047]/
      if (matches_description || matches_command || matches_tui) {
        print (bind_start > 0 ? bind_start : NR)
        exit
      }
    }
  ' "$BINDINGS_FILE")

  if [[ -z $target_line ]]; then
    target_line=$(awk 'END { print NR + 1 }' "$BINDINGS_FILE")
  fi
fi

editor=nvim
if [[ -s $EDITOR_STATE ]]; then
  read -r editor <"$EDITOR_STATE" || true
fi
editor="${editor:-nvim}"
editor_name="${editor##*/}"

if command -v omarchy-notification-send >/dev/null 2>&1; then
  omarchy-notification-send -u low \
    "Editing CLIamp keybinding" "$BINDINGS_FILE:$target_line"
fi

case "$editor_name" in
  nvim|vim)
    exec omarchy-launch-editor "+$target_line" "+normal! zz" \
      "$BINDINGS_FILE"
    ;;
  nano)
    exec omarchy-launch-editor "+$target_line,1" "$BINDINGS_FILE"
    ;;
  micro)
    exec omarchy-launch-editor "+$target_line:1" "$BINDINGS_FILE"
    ;;
  hx|helix|subl|zed)
    exec omarchy-launch-editor "$BINDINGS_FILE:$target_line:1"
    ;;
  code|codium)
    exec omarchy-launch-editor --goto "$BINDINGS_FILE:$target_line:1"
    ;;
  *)
    exec omarchy-launch-config-editor "$BINDINGS_FILE"
    ;;
esac
