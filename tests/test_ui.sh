#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/.." && pwd)"
readonly TEST_DIR PLUGIN_ROOT

tooltip_source="$(
  sed -n \
    '/readonly property string tooltip:/,/^  readonly property string clampSummary:/p' \
    "$PLUGIN_ROOT/BarWidget.qml"
  sed -n \
    '/^  function leftAlignedTooltip(/,/^  }/p' \
    "$PLUGIN_ROOT/BarWidget.qml"
)"

[[ -n $tooltip_source ]]
if grep -Eq \
  '<(/|[A-Za-z]+[ >])|&(#x?[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]+);' \
  <<<"$tooltip_source"; then
  printf 'tooltip construction must stay plain text\n' >&2
  exit 1
fi

grep -Fq 'while (missing-- > 0) line += "\u00a0"' \
  "$PLUGIN_ROOT/BarWidget.qml"
grep -Fq 'return padded.join("\n")' "$PLUGIN_ROOT/BarWidget.qml"

grep -Fq '1. Alignment moves the window along the x-axis.\n' \
  "$PLUGIN_ROOT/BarWidget.qml"
grep -Fq '2. The top edge avoids reserved areas.\n' \
  "$PLUGIN_ROOT/BarWidget.qml"
grep -Fq '3. Hide shows how to restore the icon.' \
  "$PLUGIN_ROOT/BarWidget.qml"
grep -Fq 'text: root.restoreIconWarning' "$PLUGIN_ROOT/BarWidget.qml"

printf 'ok - tooltip and compact Note copy stay plain text\n'
