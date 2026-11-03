# Development

`BarWidget.qml` owns the bar button and popup. Its two dimension fields share
one component. `Service.qml` owns settings, binding discovery, and compositor
requests once per plugin, including when the bar appears on several monitors.

`lib/client.lua` owns the runtime workspace and window rules, event
subscriptions, launch guard, and geometry for `org.omarchy.cliamp.quake`. It
sizes the dedicated special workspace with gaps, following Omarchy's Quake
console design while preserving configurable edge, position, and dimensions.
It can temporarily override Hyprland's global special-workspace dim value while
visible and restores the exact previous value when hidden or stopped. Ordinary
CLIamp windows use a different app ID.

`lib/bindings.lua` evaluates the configured Lua bindings with a recording
adapter because Hyprland exposes opaque dispatcher IDs. It recognizes CLIamp
launch commands and preserves their binding options. The source configuration
is not rewritten. `scripts/launch_cliamp.sh` uses Omarchy's TUI launcher and
passes the optional thunder recording when present.

Window changes dispatch immediately. Typed values remain drafts until Enter
or focus loss. Settings are saved through Omarchy's `updateEntryInline` API;
the 250 ms save timer does not delay geometry. Empty widget snapshots during
reload must not reset saved dimensions.

Cleanup remains embedded in the service so it can run after the checkout has
been removed. It distinguishes reloads from disable/removal, restores native
bindings, and closes only the managed window, including a pending launch.
No external service, setup file, or window rule is installed on disk.

## Checks

Validated runtime: Omarchy 4.0.6, Quickshell 0.3.2, Qt 6.12.0, and Hyprland
0.56.2. Use Qt 6 tools from `/usr/lib/qt6/bin`, not the Qt 5 tools on PATH.

```bash
omarchy plugin validate .
shellcheck scripts/*.sh tests/*.sh *.sh
luac -p lib/*.lua tests/*.lua
for test in tests/test_*.sh; do
  bash "$test" || exit
done
```

`tests/test_qml.sh` supplies the host imports and runs Qt Quick and Quickshell
checks. It needs a Wayland session and `OMARCHY_PATH=/usr/share/omarchy`.
Commands and host interfaces are mocked; it does not change desktop settings.
The project lint configuration rejects scope, deprecation, import, type, and
unqualified-access errors. Host import metadata can still emit warnings that
do not affect runtime behavior. Imports alone do not establish runtime
correctness.

Live checks cover typed and stepped dimensions, every edge and position,
workspace changes, rotated/scaled monitors, popup dismissal, reloads, and
disable/removal. Preserve the user's configuration and keep interactive tests
on the dedicated test host.
