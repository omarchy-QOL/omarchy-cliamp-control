#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_ROOT="$(mktemp -d)"
readonly TEST_DIR TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

export CLIAMP_HYPR_CONFIG="$TEMP_ROOT/hyprland.lua"
export CLIAMP_TEST_EXPRESSION="$TEMP_ROOT/expression"
mkdir -p "$TEMP_ROOT/bin"

cat >"$CLIAMP_HYPR_CONFIG" <<'LUA'
require("default.hypr.helpers")
local rules = {}
table.insert(rules, hl.workspace_rule({ workspace = "1" }))
rules[1]:set_enabled(true)
local options = {
  mouse = true, release = true, locked = true, non_consuming = true,
  device = { inclusive = true, list = { "kbd one", 'quote"and\\slash' } },
}
o.bind("SUPER + SHIFT + ALT + M", 'My "player"',
  { tui = "cliamp", focus = true }, options)
options.release = false
hl.bind("F12", hl.dsp.exec_cmd("omarchy-launch-tui cliamp"))
hl.unbind("F12")
hl.bind("F11", hl.dsp.exec_cmd("omarchy-launch-tui cliamp"))
hl.unbind("F11")
o.bind("F11", "Player", { tui = "cliamp" },
  { repeating = false, dont_inhibit = true })
o.bind("SUPER + A", "Browser", { omarchy = "browser" })
o.bind("SUPER + F", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
o.bind("SUPER + H", "Help", "cliamp --help")
o.bind("SUPER + K", "Stop", "pkill cliamp")
o.bind("SUPER + O", "Other", "omarchy-launch-tui cliamp-other")
o.bind("SUPER + E", "Example", "echo omarchy-launch-tui cliamp")
LUA

cat >"$TEMP_ROOT/bin/hyprctl" <<'MOCK'
#!/bin/bash
set -euo pipefail
[[ ${1:-} == eval ]]
printf '%s\n' "$2" >"$CLIAMP_TEST_EXPRESSION"
MOCK
chmod +x "$TEMP_ROOT/bin/hyprctl"
export PATH="$TEMP_ROOT/bin:$PATH"

result="$("$TEST_DIR/../scripts/sync_bindings.sh")"
jq -e '. == ["F11", "SUPER+SHIFT+ALT+M"]' >/dev/null <<<"$result"

lua - "$CLIAMP_TEST_EXPRESSION" <<'LUA'
local seen, removed = {}, {}
hl = {
  unbind = function(keys) removed[keys] = true end,
  bind = function(keys, command, opts)
    assert(not seen[keys], "binding emitted twice")
    assert(removed[keys], "original action was not removed")
    assert(type(command) == "function")
    seen[keys] = opts
  end,
}
dofile(arg[1])
assert(seen.F11.repeating == false and seen.F11.dont_inhibit)
local opts = assert(seen["SUPER + SHIFT + ALT + M"])
assert(opts.description == 'My "player"')
assert(opts.mouse and opts.release and opts.locked and opts.non_consuming)
assert(opts.device.inclusive)
assert(opts.device.list[1] == "kbd one")
assert(opts.device.list[2] == 'quote"and\\slash')
assert(not seen.F12 and not seen["SUPER + H"] and not seen["SUPER + K"])
LUA

controller="$TEMP_ROOT/player's control.lua"
printf 'return {toggle = function() _G.toggled = true end}' >"$controller"
lua "$TEST_DIR/../lib/bindings.lua" "$CLIAMP_HYPR_CONFIG" "$controller" \
  | jq -r '.expression' >"$CLIAMP_TEST_EXPRESSION"
lua - "$CLIAMP_TEST_EXPRESSION" <<'LUA'
hl = {
  unbind = function() end,
  bind = function(_, callback)
    _G.toggled = false
    callback()
    assert(_G.toggled)
  end,
}
dofile(arg[1])
LUA

: >"$CLIAMP_HYPR_CONFIG"
rm "$CLIAMP_TEST_EXPRESSION"
[[ $("$TEST_DIR/../scripts/sync_bindings.sh") == '[]' ]]
[[ ! -e $CLIAMP_TEST_EXPRESSION ]]
printf 'error("broken config")\n' >"$CLIAMP_HYPR_CONFIG"
if "$TEST_DIR/../scripts/sync_bindings.sh" 2>"$TEMP_ROOT/error"; then
  printf 'invalid configuration was accepted\n' >&2
  exit 1
fi
grep -Fq 'CLIamp binding scan failed:' "$TEMP_ROOT/error"
[[ ! -e $CLIAMP_TEST_EXPRESSION ]]
printf 'ok - native CLIamp bindings and options\n'
