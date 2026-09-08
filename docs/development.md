# Development

`BarWidget.qml` owns the bar button and popup. Its two dimension fields share
one component. `Service.qml` owns settings, binding discovery, and compositor
requests once per plugin, including when the bar appears on several monitors.

`lib/client.lua` owns the runtime window rules, event subscriptions, launch
guard, and geometry for `org.omarchy.cliamp.quake`. It sizes the window against
its own monitor, including rotation, scaling, and reserved space. Ordinary
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

Validated runtime: Omarchy 4.0.2, Quickshell 0.3.1, Qt 6.11.2, and Hyprland
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
Dynamic host properties and Quickshell's exit-status metadata produce known
lint warnings. Imports alone do not establish runtime correctness.

Live checks cover typed and stepped dimensions, alignment, repeated toggles,
workspace changes, rotated/scaled monitors, popup dismissal, reloads, and
disable/removal. Preserve the user's configuration and keep interactive tests
on the dedicated test host.
