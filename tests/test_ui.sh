#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/.." && pwd)"
readonly TEST_DIR PLUGIN_ROOT

grep -Fq '1. Alignment moves the window along the x-axis.\n' \
  "$PLUGIN_ROOT/BarWidget.qml"
grep -Fq '2. The top edge avoids reserved areas.\n' \
  "$PLUGIN_ROOT/BarWidget.qml"
grep -Fq '3. Hide shows how to restore the icon.' \
  "$PLUGIN_ROOT/BarWidget.qml"
grep -Fq 'text: root.restoreIconWarning' "$PLUGIN_ROOT/BarWidget.qml"

printf 'ok - compact Note copy keeps full recovery guidance\n'
