#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly CONFIG_FILE="${CLIAMP_HYPR_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua}"

# A config that loops at load time must not pin a core forever.
result="$(timeout 10 lua "$SCRIPT_DIR/../lib/bindings.lua" "$CONFIG_FILE" \
  "$SCRIPT_DIR/../lib/client.lua")"
expression="$(jq -r '.expression' <<<"$result")"
if [[ -n $expression ]]; then
  hyprctl eval "$expression" >/dev/null
fi
jq -c '.labels' <<<"$result"
