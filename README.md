# CLIamp Window Control for Omarchy Quattro

A self-contained Omarchy Quattro plugin that gives CLIamp a configurable Quake
console workspace. Its bar control uses the classic Winamp lightning-bolt logo.

- Left click shows or hides the CLIamp drop-down.
- Right click opens alignment and size settings.
- Horizontal alignment is Left, Center, or Right.
- Width and height use editable numeric fields with immediate 50 px steps.
- Typed dimensions apply on Enter or when focus leaves the field.
- Existing effective CLIamp bindings toggle the managed special workspace.
- Ordinary CLIamp windows launched outside those bindings stay ordinary.

"Center" affects x only. The y coordinate starts at the top of the monitor's
usable rectangle, below any reserved screen area.

## Requirements

- Omarchy Quattro with its current plugin API and native Lua Hyprland support
- Hyprland 0.55 or newer with the Lua provider
- `bash`, `jq`, `lua`, and `hyprctl`
- `cliamp`, which is included in a standard Omarchy installation

When readable, `~/.local/share/cliamp/thunder.webm` is passed to CLIamp with
`--auto-play`. Without that optional file, CLIamp launches normally.

The plugin does not change CLIamp's audio sources or edit Hyprland
configuration files. Its lazy workspace seed launches the managed app ID
`org.omarchy.cliamp.quake` through Omarchy's native TUI launcher. Only that app
ID belongs to this plugin.

## Install

Install and enable the plugin with Omarchy's native plugin command:

```bash
omarchy plugin add \
  https://github.com/omarchy-QOL/omarchy-cliamp-control.git --enable
```

No setup hook or user-configuration change is required. Omarchy clones the
complete runtime, launcher, and assets into the plugin checkout.

For local development, link this checkout into the plugin directory and
rescan before enabling it:

```bash
ln -s "$PWD" \
  ~/.config/omarchy/plugins/io.github.ilyazar.cliamp
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.ilyazar.cliamp
```

After source edits, run `omarchy restart shell` to reload cached QML.

## Settings and behavior

Defaults are Center, 1200 px wide, and 600 px high. The service owns the desired
settings. Widget actions update that state and dispatch geometry immediately,
without a timer or a helper process. Persistence uses Omarchy's supported
`updateEntryInline` method on the widget's `shell.json` layout entry.

Step buttons apply immediately. Typing a custom dimension leaves the window
unchanged until Enter or a click elsewhere commits the field. Pending saves
are combined after 250 ms without another committed change; they never delay
geometry commands.
The settings popup closes when the workspace or focused monitor changes.

The compositor-side controller in `lib/client.lua` owns the plugin's window
rules, event subscriptions, and guarded toggle. It moves and resizes only the
managed app ID, using the monitor that actually contains that window. The
service receives the observed rectangle back through a Hyprland custom event.

Launch happens lazily when the workspace is opened without a player. Repeated
clicks during launch share one pending launch. A late window cannot steal
focus after its workspace has been hidden. The optional thunderstorm asset is
passed by `scripts/launch_cliamp.sh` when it exists.

## Keybinding

Stock Omarchy binds `Super+Shift+Alt+M` to `Music TUI`. The plugin scans the
effective Lua configuration and recognizes CLIamp by its launch command, so a
user may change the key or description. Native bindings using
`omarchy-launch-tui cliamp` or `omarchy-launch-or-focus-tui cliamp` are rebound
in Hyprland's running session to the native controller while the plugin is
enabled. Supported Hyprland binding options, including release behavior and
device filters, are preserved.

The source configuration is never rewritten. Disabling or removing the plugin
reloads the Hyprland configuration so each original action is restored. A
normal CLIamp launch still uses `org.omarchy.cliamp` and is not resized, moved,
or hidden by this plugin. This separate app ID is what makes the behavior
binding-scoped instead of class-wide.

The **Launch keybinding** row shows all consumed key combinations and opens the
personal bindings file in Omarchy's configured editor.

## Geometry

The controller reads the managed window's monitor inside Hyprland and computes
its usable rectangle. It swaps physical width and height for odd output
transforms, divides by scale, and subtracts reserved margins.

Requested dimensions are clamped to that usable rectangle. Left uses its left
edge, Center splits the remaining horizontal space, and Right uses its right
edge. The vertical position is the top usable edge. A native dispatcher batch
floats, resizes, and moves the window by its address, then reports the observed
position and size. Moving focus to another monitor cannot change its geometry.

The special workspace provides showing, hiding, and Omarchy's native dimming
and slide animation. It does not determine the player's dimensions through
tiling gaps. Bar clicks include their originating monitor and regular
workspace; a changed context cancels the request before it can reopen the
player on a different workspace.

## Remove

Remove the plugin without leaving external setup files behind:

```bash
omarchy plugin remove io.github.ilyazar.cliamp
```

## Validate

```bash
omarchy plugin validate .
for file in scripts/*.sh tests/*.sh *.sh; do
  bash -n "$file" || exit
done
shellcheck scripts/*.sh tests/*.sh *.sh
luac -p lib/*.lua tests/*.lua
for test in tests/test_*.sh; do
  bash "$test" || exit
done
```

The shell tests cover transformed and scaled monitors, reserved margins,
direct geometry, guarded toggles, a single pending launch, native binding
options, ordinary CLIamp isolation, and teardown.

`tests/test_qml.sh` requires a Wayland session, Quickshell, and Qt 6 development
tools under `/usr/lib/qt6/bin`. It supplies the host import path to `qmllint`,
runs pure settings tests with Qt Quick Test, and loads the actual entry points
with mocked host interfaces in an isolated Quickshell test process. Commands and
binding helpers are mocked; the tests do not modify desktop rules or persisted
settings. They exercise immediate updates, stale host snapshots, widget
persistence, observed geometry, and independent error recovery. Dynamic host
properties can still produce lint
warnings; successful imports alone do not prove runtime behavior.

Validated against Omarchy `4.0.0.r2071.ga703092`, Quickshell `0.3.1`,
Qt `6.11.2`, and Hyprland `0.56.2`. The plugin requires the current facade API;
unsupported hosts need updating.

The [architecture review](docs/architecture-review-2026-09-08.md) records the
geometry and settings history, reproduced regressions, and verification gaps.

## Logo license

The unmodified classic Winamp logo is redistributed under the permission and
attribution recorded in [`assets/README.md`](assets/README.md). It is a
trademark of its respective owner. This plugin is unofficial and is not
affiliated with or endorsed by Winamp or its owner. Plugin code is MIT
licensed; the logo keeps its separately documented terms.
