# CLIamp Window Control for Omarchy Quattro

A self-contained Omarchy Quattro plugin that gives CLIamp a configurable Quake
console workspace. Its bar control uses the classic Winamp lightning-bolt logo.

- Left click shows or hides the CLIamp drop-down.
- Right click opens alignment and size settings.
- Horizontal alignment is Left, Center, or Right.
- Width and height use editable numeric fields with 50 px arrow steps.
- Existing effective CLIamp bindings toggle the managed special workspace.
- Ordinary CLIamp windows launched outside those bindings stay ordinary.

"Center" affects x only. The y coordinate starts at the top of the monitor's
usable rectangle, below any reserved screen area.

## Requirements

- Omarchy Quattro with `qconsole.lua` and the `shell.barConfig` plugin API
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

Defaults are Center, 1200 px wide, and 600 px high. Valid values are stored
inline on the widget's `shell.json` layout entry through the shell's
supported `updateEntryInline` method. The service reads the host's
`barConfig.layout` snapshot independently of the widget.

The service applies one rule to `special:cliamp`, then refits it when the
focused monitor, monitor layout, settings, or Hyprland configuration changes.
A low-frequency health check restores the dynamic rule after a configuration
reload that emits no socket event. It does not poll for a client or
continuously resize a window.

Left click calls `scripts/toggle_cliamp.sh`, which only toggles the managed
special workspace. Hyprland's `on_created_empty` rule launches CLIamp lazily
with the plugin-owned app ID. When the optional thunderstorm asset exists, the
new client starts playing it immediately. Closing CLIamp leaves an empty
workspace that is seeded again the next time it opens.

## Keybinding

Stock Omarchy binds `Super+Shift+Alt+M` to `Music TUI`. The plugin scans the
effective Lua configuration and recognizes CLIamp by its launch command, so a
user may change the key or description. Native bindings using
`omarchy-launch-tui cliamp` or `omarchy-launch-or-focus-tui cliamp` are rebound
in Hyprland's running session to the shipped toggle helper while the plugin is
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

The helper reads the focused monitor from `hyprctl monitors -j`. Until a
monitor is available, it installs a safe full-work-area rule so the workspace
is never created without its lazy seed.

Hyprland reports monitor pixel dimensions before output transform. The plugin
swaps width and height for odd transforms, divides by scale, and applies the
reserved margins in Hyprland's `[left, top, right, bottom]` order:

```text
logical width  = transformed pixel width / scale
logical height = transformed pixel height / scale
usable x       = monitor x + reserved left
usable y       = monitor y + reserved top
usable width   = logical width - reserved left - reserved right
usable height  = logical height - reserved top - reserved bottom
```

Requested dimensions are clamped to the usable rectangle. The remaining width
becomes workspace gaps on the right for Left, on both sides for Center, and on
the left for Right. The remaining height becomes the bottom gap, while the top
gap stays zero. Hyprland therefore lays out the tiled client at the requested
top-edge geometry without window move or resize dispatches.

The rule matches Omarchy's `qconsole.lua`: `gaps_in` is zero, the active border
is disabled, and `on_created_empty` owns lazy launch. It inherits Omarchy's
global dimming and directional special-workspace animation instead of
overriding them.

## Remove

Remove the plugin without leaving external setup files behind:

```bash
omarchy plugin remove io.github.ilyazar.cliamp
```

## Validate

```bash
omarchy plugin validate .
for file in lib/*.sh scripts/*.sh tests/*.sh *.sh; do
  bash -n "$file" || exit
done
shellcheck lib/*.sh scripts/*.sh tests/*.sh *.sh
luac -p lib/bindings.lua
for test in tests/test_*.sh; do
  bash "$test" || exit
done
```

The shell tests cover transformed and scaled monitors, reserved margins,
workspace gaps, lazy launch, idempotent rules, native binding discovery and
options, ordinary CLIamp isolation, and teardown.

`tests/test_qml.sh` requires a Wayland session, Quickshell, and Qt 6 development
tools under `/usr/lib/qt6/bin`. It supplies the host import path to `qmllint`,
runs pure settings tests with Qt Quick Test, and loads the actual entry points
and host facades in an isolated Quickshell test process. Helper commands are
mocked; the tests do not modify desktop rules or persisted settings. They
exercise configuration updates, overlapping requests, widget persistence, and
independent error recovery. Dynamic host properties can still produce lint
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
