# shellcheck shell=bash

# Pure workspace geometry shared by the runtime helper and tests.

cliamp_workspace_json() {
  local monitors_json="$1"
  local alignment="$2"
  local requested_width="$3"
  local requested_height="$4"

  jq -cen \
    --argjson monitors "$monitors_json" \
    --arg alignment "$alignment" \
    --argjson requestedWidth "$requested_width" \
    --argjson requestedHeight "$requested_height" '
      def number_or($fallback):
        if type == "number" then . else $fallback end;
      def clamp($minimum; $maximum):
        if . < $minimum then $minimum
        elif . > $maximum then $maximum
        else .
        end;

      ($monitors
        | map(select(.disabled != true))
        | map(select(.focused == true))[0]) as $monitor
      | {
          alignment: $alignment,
          width: $requestedWidth,
          height: $requestedHeight
        } as $requested
      | if $monitor == null then
          {
            status: "fallback",
            monitorAvailable: false,
            monitor: null,
            usable: null,
            requested: $requested,
            actual: null,
            gaps: {top: 0, right: 0, bottom: 0, left: 0},
            signature: ([0, 0, 0, 0] | @json)
          }
        else
          ($monitor.scale | number_or(1)) as $scale
          | if $scale <= 0 then
              error("monitor scale must be positive")
            else . end
          | ($monitor.transform | number_or(0) | floor) as $transform
          | ($monitor.width | number_or(0)) as $pixelWidth
          | ($monitor.height | number_or(0)) as $pixelHeight
          | (if ($transform % 2) == 1 then $pixelHeight else $pixelWidth end
              / $scale | floor) as $logicalWidth
          | (if ($transform % 2) == 1 then $pixelWidth else $pixelHeight end
              / $scale | floor) as $logicalHeight
          | ($monitor.reserved // [0, 0, 0, 0]) as $reserved
          | ($reserved[0] | number_or(0) | floor
              | if . < 0 then 0 else . end) as $reservedLeft
          | ($reserved[1] | number_or(0) | floor
              | if . < 0 then 0 else . end) as $reservedTop
          | ($reserved[2] | number_or(0) | floor
              | if . < 0 then 0 else . end) as $reservedRight
          | ($reserved[3] | number_or(0) | floor
              | if . < 0 then 0 else . end) as $reservedBottom
          | ([1, $logicalWidth - $reservedLeft - $reservedRight]
              | max | floor) as $usableWidth
          | ([1, $logicalHeight - $reservedTop - $reservedBottom]
              | max | floor) as $usableHeight
          | ($requestedWidth | floor | clamp(1; $usableWidth)) as $width
          | ($requestedHeight | floor | clamp(1; $usableHeight)) as $height
          | ($usableWidth - $width) as $freeX
          | (if $alignment == "Left" then 0
             elif $alignment == "Center" then ($freeX / 2 | floor)
             elif $alignment == "Right" then $freeX
             else error("invalid alignment")
             end) as $left
          | ($freeX - $left) as $right
          | ($usableHeight - $height) as $bottom
          | (($monitor.x | number_or(0) | floor) + $reservedLeft)
              as $usableX
          | (($monitor.y | number_or(0) | floor) + $reservedTop)
              as $usableY
          | {
              status: "calculated",
              monitorAvailable: true,
              monitor: {
                id: $monitor.id,
                name: $monitor.name,
                x: ($monitor.x | number_or(0) | floor),
                y: ($monitor.y | number_or(0) | floor),
                logicalWidth: $logicalWidth,
                logicalHeight: $logicalHeight,
                scale: $scale,
                transform: $transform,
                reserved: [
                  $reservedLeft,
                  $reservedTop,
                  $reservedRight,
                  $reservedBottom
                ]
              },
              usable: {
                x: $usableX,
                y: $usableY,
                width: $usableWidth,
                height: $usableHeight
              },
              requested: $requested,
              actual: {
                x: ($usableX + $left),
                y: $usableY,
                width: $width,
                height: $height
              },
              gaps: {
                top: 0,
                right: $right,
                bottom: $bottom,
                left: $left
              },
              signature: ([0, $right, $bottom, $left] | @json)
            }
        end
    '
}
