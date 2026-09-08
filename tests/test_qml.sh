#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_ROOT="$(mktemp -d)"
readonly TEST_DIR TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT
mkdir -p "$TEMP_ROOT/bin"
ln -s "${OMARCHY_PATH:?OMARCHY_PATH is required}/shell" "$TEMP_ROOT/qs"
/usr/lib/qt6/bin/qmllint -I "$TEMP_ROOT" -I "$OMARCHY_PATH/shell" \
  "$TEST_DIR/../Service.qml" "$TEST_DIR/../BarWidget.qml"

cat >"$TEMP_ROOT/bin/bash" <<'MOCK'
#!/bin/bash
set -euo pipefail
case "$1" in
  */sync_bindings.sh) printf '["SUPER+M"]\n' ;;
  -c) exit 0 ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "$TEMP_ROOT/bin/bash"

PATH="$TEMP_ROOT/bin:$PATH" QT_QPA_PLATFORM=offscreen \
  /usr/lib/qt6/bin/qmltestrunner -import "$TEMP_ROOT" \
  -input "$TEST_DIR/tst_Settings.qml"

PATH="$TEMP_ROOT/bin:$PATH" QT_QPA_PLATFORM=wayland \
  CLIAMP_SOURCE="$(dirname "$TEST_DIR")" QML_IMPORT_PATH="$TEMP_ROOT" \
  timeout 5 qs -p "$TEST_DIR/tst_Service.qml" --no-color \
  >"$TEMP_ROOT/runtime.log" 2>&1 || {
  cat "$TEMP_ROOT/runtime.log" >&2
  exit 1
}
grep -Fq 'CLIAMP_QML_RESULT failures=0' "$TEMP_ROOT/runtime.log" || {
  cat "$TEMP_ROOT/runtime.log" >&2
  exit 1
}
printf 'ok - Quickshell service and widget behavior\n'
