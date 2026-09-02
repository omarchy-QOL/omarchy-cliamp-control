#!/bin/bash

set -euo pipefail

readonly WORKSPACE="cliamp"

command -v hyprctl >/dev/null 2>&1 || {
  printf 'required command not found: hyprctl\n' >&2
  exit 1
}

hyprctl dispatch \
  "hl.dsp.workspace.toggle_special(\"$WORKSPACE\")" \
  >/dev/null
