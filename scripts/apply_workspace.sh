#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PLUGIN_ROOT
readonly WORKSPACE="cliamp"
readonly LAUNCH_SCRIPT="$PLUGIN_ROOT/scripts/launch_cliamp.sh"

# shellcheck source=lib/clients.sh
source "$PLUGIN_ROOT/lib/clients.sh"
# shellcheck source=lib/workspace.sh
source "$PLUGIN_ROOT/lib/workspace.sh"

alignment="${1:-}"
requested_width="${2:-}"
requested_height="${3:-}"
previous_signature="${4:-}"
allow_migration="${5:-true}"

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
if [[ $allow_migration != true && $allow_migration != false ]]; then
  printf 'allow_migration must be true or false\n' >&2
  exit 2
fi

lua_quote() {
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  printf '"%s"' "$value"
}

append_expression() {
  local statement="$1"

  [[ -z $expression ]] || expression+='; '
  expression+="$statement"
}

monitors_json="$(hyprctl monitors -j)"
workspace_json="$(
  cliamp_workspace_json \
    "$monitors_json" \
    "$alignment" \
    "$requested_width" \
    "$requested_height"
)"

signature="$(jq -r '.signature' <<<"$workspace_json")"
IFS=$'\t' read -r top right bottom left < <(
  jq -r '[.gaps.top, .gaps.right, .gaps.bottom, .gaps.left] | @tsv' \
    <<<"$workspace_json"
)
printf -v launch_path '%q' "$LAUNCH_SCRIPT"
seed="[workspace special:$WORKSPACE silent] bash $launch_path"
seed_lua="$(lua_quote "$seed")"

rules_json="$(hyprctl workspacerules -j 2>/dev/null || printf '[]')"
rule_matches=false
if jq -e \
  --arg workspace "special:$WORKSPACE" \
  --arg seed "$seed" \
  --argjson top "$top" \
  --argjson right "$right" \
  --argjson bottom "$bottom" \
  --argjson left "$left" '
    any(.[];
      .workspaceString == $workspace
      and .enabled == true
      and .gapsIn == [0, 0, 0, 0]
      and .gapsOut == [$top, $right, $bottom, $left]
      and .border == false
      and .onCreatedEmpty == $seed
    )
  ' >/dev/null <<<"$rules_json"; then
  rule_matches=true
fi

rule_changed=false
expression=""

if [[ $signature != "$previous_signature" || $rule_matches != true ]]; then
  rule_changed=true
  printf -v rule_expression \
    'hl.workspace_rule({ workspace = "special:%s", gaps_in = 0, gaps_out = { top = %d, right = %d, bottom = %d, left = %d }, no_border = true, on_created_empty = %s })' \
    "$WORKSPACE" "$top" "$right" "$bottom" "$left" "$seed_lua"
  append_expression "$rule_expression"
fi

managed_clients='[]'
client_count='null'
if [[ $allow_migration == true ]]; then
  clients_json="$(hyprctl clients -j 2>/dev/null || printf '[]')"
  managed_clients="$(cliamp_managed_clients_json "$clients_json")"
  client_count="$(jq -r 'length' <<<"$managed_clients")"
fi
migrated_clients=0

while IFS=$'\t' read -r address workspace floating; do
  [[ $address =~ ^0x[0-9A-Fa-f]+$ ]] || continue
  migrated=false

  if [[ $workspace != "special:$WORKSPACE" ]]; then
    printf -v move_expression \
      'hl.dispatch(hl.dsp.window.move({ workspace = "special:%s", follow = false, window = "address:%s" }))' \
      "$WORKSPACE" "$address"
    append_expression "$move_expression"
    migrated=true
  fi

  if [[ $floating == true ]]; then
    printf -v tile_expression \
      'hl.dispatch(hl.dsp.window.float({ action = "toggle", window = "address:%s" }))' \
      "$address"
    append_expression "$tile_expression"
    migrated=true
  fi

  if [[ $migrated == true ]]; then
    migrated_clients=$((migrated_clients + 1))
  fi
done < <(
  jq -r '.[] | [.address, (.workspace.name // ""),
    (.floating == true)] | @tsv' <<<"$managed_clients"
)

status="unchanged"
if [[ -n $expression ]]; then
  hyprctl eval "$expression" >/dev/null
  status="applied"
fi

jq -c \
  --arg status "$status" \
  --argjson ruleChanged "$rule_changed" \
  --argjson clientCount "$client_count" \
  --argjson migratedClients "$migrated_clients" '
    . + {
      status: $status,
      ruleChanged: $ruleChanged,
      clientCount: $clientCount,
      migratedClients: $migratedClients
    }
  ' <<<"$workspace_json"
