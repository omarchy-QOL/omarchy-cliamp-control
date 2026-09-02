#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR

# shellcheck source=lib/workspace.sh
source "$TEST_DIR/../lib/workspace.sh"

assert_json() {
  local json="$1"
  local expression="$2"
  local label="$3"

  if ! jq -e "$expression" >/dev/null <<<"$json"; then
    printf 'not ok - %s\n%s\n' "$label" "$json" >&2
    exit 1
  fi
}

landscape='[
  {
    "id": 1,
    "name": "LANDSCAPE",
    "width": 1920,
    "height": 1080,
    "x": 0,
    "y": 0,
    "scale": 1,
    "transform": 0,
    "reserved": [10, 30, 20, 40],
    "focused": true,
    "disabled": false
  }
]'

left="$(cliamp_workspace_json "$landscape" Left 1200 600)"
center="$(cliamp_workspace_json "$landscape" Center 1200 600)"
right="$(cliamp_workspace_json "$landscape" Right 1200 600)"
assert_json "$left" '
  .status == "calculated"
  and .actual == {x: 10, y: 30, width: 1200, height: 600}
  and .gaps == {top: 0, right: 690, bottom: 410, left: 0}
' 'landscape left alignment uses the right workspace gap'
assert_json "$center" '
  .actual == {x: 355, y: 30, width: 1200, height: 600}
  and .gaps == {top: 0, right: 345, bottom: 410, left: 345}
' 'landscape center alignment splits the horizontal workspace gap'
assert_json "$right" '
  .actual == {x: 700, y: 30, width: 1200, height: 600}
  and .gaps == {top: 0, right: 0, bottom: 410, left: 690}
' 'landscape right alignment uses the left workspace gap'

portrait='[
  {
    "id": 4,
    "name": "PORTRAIT",
    "width": 1920,
    "height": 1080,
    "x": -1080,
    "y": 120,
    "scale": 1,
    "transform": 1,
    "reserved": [5, 26, 7, 9],
    "focused": true,
    "disabled": false
  }
]'
portrait_result="$(cliamp_workspace_json "$portrait" Center 800 900)"
assert_json "$portrait_result" '
  .monitor.logicalWidth == 1080
  and .monitor.logicalHeight == 1920
  and .usable == {x: -1075, y: 146, width: 1068, height: 1885}
  and .actual == {x: -941, y: 146, width: 800, height: 900}
  and .gaps == {top: 0, right: 134, bottom: 985, left: 134}
' 'rotated monitor geometry remains logical'

scaled='[
  {
    "id": 7,
    "name": "SCALED",
    "width": 3000,
    "height": 1800,
    "x": 100,
    "y": 200,
    "scale": 1.5,
    "transform": 0,
    "reserved": [11, 22, 33, 44],
    "focused": true,
    "disabled": false
  }
]'
oversized="$(cliamp_workspace_json "$scaled" Right 9999 9999)"
assert_json "$oversized" '
  .monitor.logicalWidth == 2000
  and .monitor.logicalHeight == 1200
  and .usable == {x: 111, y: 222, width: 1956, height: 1134}
  and .actual == {x: 111, y: 222, width: 1956, height: 1134}
  and .gaps == {top: 0, right: 0, bottom: 0, left: 0}
' 'fractional scale and oversized requests clamp to the work area'

double_scaled='[
  {
    "id": 8,
    "name": "DOUBLE",
    "width": 3840,
    "height": 2160,
    "x": 0,
    "y": 0,
    "scale": 2,
    "transform": 0,
    "reserved": [0, 40, 0, 0],
    "focused": true,
    "disabled": false
  }
]'
double_result="$(cliamp_workspace_json "$double_scaled" Center 1200 520)"
assert_json "$double_result" '
  .usable == {x: 0, y: 40, width: 1920, height: 1040}
  and .actual == {x: 360, y: 40, width: 1200, height: 520}
  and .gaps == {top: 0, right: 360, bottom: 520, left: 360}
' 'two-times scale uses logical workspace gaps'

two_monitors='[
  {
    "id": 1,
    "name": "LEFT",
    "width": 1920,
    "height": 1080,
    "x": 0,
    "y": 0,
    "scale": 1,
    "transform": 0,
    "reserved": [0, 26, 0, 0],
    "focused": true,
    "disabled": false
  },
  {
    "id": 2,
    "name": "RIGHT",
    "width": 2560,
    "height": 1440,
    "x": 1920,
    "y": -200,
    "scale": 1,
    "transform": 0,
    "reserved": [20, 40, 30, 50],
    "focused": false,
    "disabled": false
  }
]'
left_monitor="$(cliamp_workspace_json "$two_monitors" Center 1200 600)"
right_monitors="$(jq '.[0].focused = false | .[1].focused = true' \
  <<<"$two_monitors")"
right_monitor="$(cliamp_workspace_json "$right_monitors" Center 1200 600)"
assert_json "$left_monitor" '
  .monitor.name == "LEFT"
  and .gaps == {top: 0, right: 360, bottom: 454, left: 360}
' 'the focused monitor owns the rule geometry'
assert_json "$right_monitor" '
  .monitor.name == "RIGHT"
  and .actual == {x: 2595, y: -160, width: 1200, height: 600}
' 'focus changes refit the workspace rule'
if [[ $(jq -r '.signature' <<<"$left_monitor") == \
  "$(jq -r '.signature' <<<"$right_monitor")" ]]; then
  printf 'monitor focus change did not update the rule signature\n' >&2
  exit 1
fi

fallback="$(cliamp_workspace_json '[]' Center 1200 600)"
assert_json "$fallback" '
  .status == "fallback"
  and .monitorAvailable == false
  and .actual == null
  and .gaps == {top: 0, right: 0, bottom: 0, left: 0}
' 'an unavailable monitor still yields a safe full-work-area rule'

live_size='[
  {
    "id": 9,
    "name": "LIVE",
    "width": 1920,
    "height": 1200,
    "x": 1080,
    "y": 0,
    "scale": 1,
    "transform": 0,
    "reserved": [0, 26, 0, 0],
    "focused": true,
    "disabled": false
  }
]'
live_result="$(cliamp_workspace_json "$live_size" Right 850 425)"
assert_json "$live_result" '
  .actual == {x: 2150, y: 26, width: 850, height: 425}
  and .gaps == {top: 0, right: 0, bottom: 749, left: 1070}
' 'persisted 850 by 425 settings need no migration'

printf 'ok - qconsole workspace geometry cases\n'
