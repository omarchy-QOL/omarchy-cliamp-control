#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly CONFIG_FILE="${CLIAMP_HYPR_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua}"

result="$(lua "$SCRIPT_DIR/../lib/bindings.lua" "$CONFIG_FILE" \
  "$SCRIPT_DIR/toggle_cliamp.sh")"
expression="$(jq -r '.expression' <<<"$result")"
if [[ -n $expression ]]; then
  hyprctl eval "$expression" >/dev/null
fi
jq -c '.labels' <<<"$result"
