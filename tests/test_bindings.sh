#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_ROOT="$(mktemp -d)"
readonly TEST_DIR TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

readonly MOCK_BIN="$TEMP_ROOT/bin"
readonly CONFIG_FILE="$TEMP_ROOT/hyprland.lua"
export CLIAMP_TEST_EXPRESSION="$TEMP_ROOT/expression"

mkdir -p "$MOCK_BIN"

cat >"$CONFIG_FILE" <<'LUA'
require("default.hypr.helpers")
local monitor = hl.get_active_monitor()
if monitor and monitor.scale and monitor.scale <= 0 then
  error("invalid active monitor")
end
o.bind(
  "SUPER + SHIFT + ALT + M",
  "My renamed player",
  { tui = "cliamp", focus = true },
  {
    mouse = true,
    release = true,
    locked = true,
    non_consuming = true,
    device = { inclusive = true, list = { "kbd one", "kbd-two" } },
  }
)
hl.bind(
  "F12",
  hl.dsp.exec_cmd("~/.config/hypr/scripts/quake_toggle.sh music"),
  { description = "Old music drop-down" }
)
hl.unbind("F12")
hl.bind(
  "F11",
  hl.dsp.exec_cmd("~/.config/hypr/scripts/quake_toggle.sh music"),
  {
    description = "Moved music drop-down",
    repeating = false,
    dont_inhibit = true,
  }
)
hl.bind(
  "SUPER + A",
  hl.dsp.exec_cmd("omarchy-launch-browser"),
  { description = "Unrelated" }
)
hl.bind(
  "SUPER + H",
  hl.dsp.exec_cmd("cliamp --help"),
  { description = "CLIamp help" }
)
hl.bind(
  "SUPER + K",
  hl.dsp.exec_cmd("pkill cliamp"),
  { description = "Stop CLIamp" }
)
LUA

cat >"$MOCK_BIN/hyprctl" <<'MOCK'
#!/bin/bash
set -euo pipefail

[[ ${1:-} == "eval" ]]
printf '%s\n' "${2:-}" >"$CLIAMP_TEST_EXPRESSION"
MOCK
chmod 0755 "$MOCK_BIN/hyprctl"

result="$(
  CLIAMP_HYPR_CONFIG="$CONFIG_FILE" \
    PATH="$MOCK_BIN:$PATH" \
    "$TEST_DIR/../scripts/sync_bindings.sh"
)"

jq -e '
  .status == "managed"
  and (.bindings | length) == 2
  and .bindings[0].keys == "F11"
  and .bindings[1].keys == "SUPER + SHIFT + ALT + M"
  and .bindings[1].description == "My renamed player"
  and .bindings[1].options.mouse == true
  and .bindings[0].options.repeating == false
  and .bindings[0].options.dont_inhibit == true
  and .bindings[1].options.release == true
  and .bindings[1].options.locked == true
  and .bindings[1].options.non_consuming == true
  and .bindings[1].options.device == {
    inclusive: true,
    list: ["kbd one", "kbd-two"]
  }
' >/dev/null <<<"$result"

grep -Fq 'hl.unbind("F11")' "$CLIAMP_TEST_EXPRESSION"
grep -Fq 'hl.unbind("SUPER + SHIFT + ALT + M")' \
  "$CLIAMP_TEST_EXPRESSION"
grep -Fq 'scripts/toggle_cliamp.sh' "$CLIAMP_TEST_EXPRESSION"
grep -Fq 'mouse = true' "$CLIAMP_TEST_EXPRESSION"
grep -Fq 'repeating = false' "$CLIAMP_TEST_EXPRESSION"
grep -Fq 'dont_inhibit = true' "$CLIAMP_TEST_EXPRESSION"
grep -Fq 'release = true' "$CLIAMP_TEST_EXPRESSION"
grep -Fq 'locked = true' "$CLIAMP_TEST_EXPRESSION"
grep -Fq 'non_consuming = true' "$CLIAMP_TEST_EXPRESSION"
grep -Fq \
  'device = { inclusive = true, list = { "kbd one", "kbd-two" } }' \
  "$CLIAMP_TEST_EXPRESSION"
if grep -Fq 'hl.unbind("F12")' "$CLIAMP_TEST_EXPRESSION"; then
  printf 'removed binding was incorrectly restored\n' >&2
  exit 1
fi
if grep -Eq 'hl\.unbind\("SUPER \+ (H|K)"\)' \
  "$CLIAMP_TEST_EXPRESSION"; then
  printf 'non-launch CLIamp binding was incorrectly consumed\n' >&2
  exit 1
fi

printf 'ok - effective CLIamp bindings are consumed by command\n'
