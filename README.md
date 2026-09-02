# CLIamp Window Control for Omarchy Quattro

A self-contained Omarchy Quattro plugin that gives CLIamp a configurable Quake
console workspace. Its bar control uses the classic Winamp lightning-bolt logo.

- Left click shows or hides the CLIamp drop-down.
- Right click opens alignment and size settings.
- Horizontal alignment is Left, Center, or Right.
- Width and height use editable numeric fields with 50 px arrow steps.
- Existing effective CLIamp bindings toggle the managed special workspace.
- Ordinary CLIamp windows launched outside those bindings stay ordinary.
- Hiding the bar icon requires explicit confirmation.
- Geometry management continues while the bar icon is hidden.

"Center" affects x only. The y coordinate starts at the top of the monitor's
usable rectangle, below any reserved screen area.

## Requirements

- Omarchy Quattro with the current `qconsole.lua` presentation
- Hyprland 0.55 or newer with the Lua provider
- `bash`, `jq`, `lua`, and `hyprctl`
- `cliamp`, which is included in a standard Omarchy installation

When readable, `~/.local/share/cliamp/thunder.webm` is passed to CLIamp with
`--auto-play`. Without that optional file, CLIamp launches normally.

The required Quake-console implementation landed after the `v4.0.2` stable
tag. Until a numbered release includes it, use a Quattro build at or after
commit `fa955bfa9d2c94339f452e4c56cb5bbfc5e1718e`.

The plugin does not change CLIamp's audio sources or edit Hyprland
configuration files. Its lazy workspace seed launches the managed app ID
`org.omarchy.cliamp.quake` through Omarchy's native TUI launcher. The ordinary
`org.omarchy.cliamp` app ID and older `org.omarchy.quake.music` windows are
deliberately excluded.

## Install

Install and enable the plugin with Omarchy's native plugin command:

```bash
omarchy plugin add \
  https://github.com/ilyaZar/omarchy-cliamp-control.git --enable
```

No setup hook or user-configuration change is required. Omarchy clones the
complete runtime, launcher, recovery helper, and assets into the plugin
checkout.

For local development, link this checkout into the plugin directory and
rescan before enabling it:

```bash
ln -s "$PWD" \
  ~/.config/omarchy/plugins/io.github.ilyazar.cliamp
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.ilyazar.cliamp
```

## Settings and behavior

Defaults are Center, 1200 px wide, 600 px high, and icon visible. Valid values
are stored inline on the widget's `shell.json` layout entry through the shell's
supported `updateEntryInline` method. The recovery helper uses `omarchy bar`
commands instead of editing `shell.json`.

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
user may change the key or description. It also recognizes the older
`quake_toggle.sh music` action. Every matching key is rebound in Hyprland's
running session to the shipped adapter while the plugin is enabled. Supported
Hyprland binding options, including release behavior and device filters, are
preserved.

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
overriding them. When upgrading with an old managed client still open, the
service moves it to `special:cliamp` and tiles it once so the workspace rule can
take over.

## Hide and recover

These states are deliberately different:

- **Hide icon** sets `iconVisible` to false. The widget consumes no bar gap and
  its enabled service keeps running.
- **Remove bar entry** removes the widget while leaving the installed plugin
  available.
- **Remove plugin** removes its checkout and shell registration.

Restore a hidden or removed bar entry with the helper inside the native plugin
checkout:

```bash
~/.config/omarchy/plugins/io.github.ilyazar.cliamp/bin/cliamp-widget
```

The helper rescans plugins, idempotently puts the widget in its default right
section when absent, and clears `iconVisible`. It also supports `show`, `hide`,
and `status` subcommands.

Remove the plugin without leaving external setup files behind:

```bash
omarchy plugin remove io.github.ilyazar.cliamp
```

## Validate

```bash
omarchy plugin validate .
bash -n bin/cliamp-widget lib/*.sh scripts/*.sh tests/*.sh *.sh
shellcheck bin/cliamp-widget lib/*.sh scripts/*.sh tests/*.sh *.sh
tests/test_workspace.sh
tests/test_apply_workspace.sh
tests/test_toggle.sh
tests/test_launch.sh
tests/test_bindings.sh
tests/test_keybindings.sh
tests/test_recovery.sh
tests/test_teardown.sh
tests/test_ui.sh
qmllint -I /usr/share/omarchy/shell Service.qml BarWidget.qml
```

The tests cover transformed and scaled monitors, reserved margins, workspace
gaps, all alignments, lazy launch, current-client migration, idempotent rule
updates, command-based effective binding consumption, ordinary CLIamp
isolation, guarded teardown, compact Note copy, and icon recovery.

## Logo license

The unmodified classic Winamp logo is redistributed under the permission and
attribution recorded in [`assets/README.md`](assets/README.md). It is a
trademark of its respective owner. This plugin is unofficial and is not
affiliated with or endorsed by Winamp or its owner. Plugin code is MIT
licensed; the logo keeps its separately documented terms.
