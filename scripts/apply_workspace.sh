#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PLUGIN_ROOT
readonly WORKSPACE="cliamp"
readonly LAUNCH_SCRIPT="$PLUGIN_ROOT/scripts/launch_cliamp.sh"

# shellcheck source=lib/workspace.sh
source "$PLUGIN_ROOT/lib/workspace.sh"

alignment="${1:-}"
requested_width="${2:-}"
requested_height="${3:-}"

case "$alignment" in
  Left | Center | Right) ;;
  *)
    printf 'invalid alignment: %s\n' "$alignment" >&2
    exit 2
    ;;
esac

if [[ ! $requested_width =~ ^[1-9][0-9]*$ ]] ||
  [[ ! $requested_height =~ ^[1-9][0-9]*$ ]]; then
  printf 'width and height must be positive integers\n' >&2
  exit 2
fi

monitors_json="$(hyprctl monitors -j)"
workspace_json="$(
  cliamp_workspace_json \
    "$monitors_json" \
    "$alignment" \
    "$requested_width" \
    "$requested_height"
)"

IFS=$'\t' read -r top right bottom left < <(
  jq -r '[.gaps.top, .gaps.right, .gaps.bottom, .gaps.left] | @tsv' \
    <<<"$workspace_json"
)
printf -v launch_path '%q' "$LAUNCH_SCRIPT"
seed="[workspace special:$WORKSPACE silent] bash $launch_path"
seed_lua="$(printf '%s' "$seed" | lua -e \
  'io.write(string.format("%q", io.read("*a")))')"

rules_json="$(hyprctl workspacerules -j)"
rule_matches="$(jq -r \
  --arg workspace "special:$WORKSPACE" \
  --arg seed "$seed" \
  --argjson top "$top" \
  --argjson right "$right" \
  --argjson bottom "$bottom" \
  --argjson left "$left" '
    if type != "array" then error("invalid workspace rules") end
    | any(.[];
      .workspaceString == $workspace
      and .enabled == true
      and .gapsIn == [0, 0, 0, 0]
      and .gapsOut == [$top, $right, $bottom, $left]
      and .border == false
      and .onCreatedEmpty == $seed
    )
  ' <<<"$rules_json")"

status="unchanged"
if [[ $rule_matches != true ]]; then
  printf -v expression \
    'hl.workspace_rule({ workspace = "special:%s", gaps_in = 0, gaps_out = { top = %d, right = %d, bottom = %d, left = %d }, no_border = true, on_created_empty = %s })' \
    "$WORKSPACE" "$top" "$right" "$bottom" "$left" "$seed_lua"
  hyprctl eval "$expression" >/dev/null
  status="applied"
fi

jq -c --arg status "$status" '. + {status: $status}' <<<"$workspace_json"
