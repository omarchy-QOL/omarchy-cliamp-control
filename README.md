# CLIamp Window Control for Omarchy Quattro

A self-contained Omarchy Quattro plugin that gives CLIamp a configurable
Guake-style drop-down window. Its bar control uses the classic Winamp
lightning-bolt logo.

- Left click shows or hides the CLIamp drop-down.
- Right click opens alignment and size settings.
- Horizontal alignment is Left, Center, or Right.
- Width and height use editable numeric fields with 50 px arrow steps.
- Existing effective CLIamp bindings trigger the shipped drop-down adapter.
- Ordinary CLIamp windows launched outside those bindings stay ordinary.
- Hiding the bar icon requires explicit confirmation.
- Geometry management continues while the bar icon is hidden.

"Center" affects x only. The y coordinate starts at the top of the monitor's
usable rectangle, below any reserved screen area.

## Requirements

- Omarchy Quattro with the manifest-based shell plugin runtime
- Hyprland 0.55 or newer with the Lua provider
- `bash`, `jq`, `lua`, and `hyprctl`
- `cliamp`, which is included in a standard Omarchy installation

When readable, `~/.local/share/cliamp/thunder.webm` is passed to CLIamp with
`--auto-play`. Without that optional file, CLIamp launches normally.

The plugin does not change CLIamp's audio sources or edit Hyprland configuration
files. Its binding adapter launches the managed app ID
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

The service listens for relevant Hyprland window, workspace, special-workspace,
and monitor events. It selects only `org.omarchy.cliamp.quake`. A tiled managed
window is floated before its exact size and position are applied.

While no client exists, a fallback check backs off from two seconds to fifteen
seconds. There is no periodic polling after a client is found. If CLIamp was
removed from the preinstalled packages, the settings panel reports that it is
not installed.

Left click calls the included `scripts/toggle_cliamp.sh` adapter. It reuses an
existing managed client or launches CLIamp with the plugin-owned app ID. When
the optional thunderstorm asset exists, a new client starts playing it
immediately. The client is moved to `special:cliamp` and shown or hidden
without creating duplicates. Generic special-workspace mechanics live
separately in `lib/quake.sh`; CLIamp selection and launch details stay in the
thin adapter.

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

The helper reads `hyprctl clients -j` and `hyprctl monitors -j`. A present
client selects its reported monitor ID. Only an absent client falls back to the
focused monitor.

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

Requested dimensions are clamped to the usable rectangle. Left uses
`usable x`, Center adds half the remaining horizontal space, and Right uses the
usable right edge minus the clamped width. Every result is integral and keeps
the complete window reachable.

The runtime floats tiled clients, then applies the result with current
Hyprland Lua dispatchers through `hyprctl eval` and an exact client address. It
does not use legacy hyprlang dispatch syntax.

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
tests/test_geometry.sh
tests/test_apply_geometry.sh
tests/test_toggle.sh
tests/test_bindings.sh
tests/test_keybindings.sh
tests/test_recovery.sh
tests/test_teardown.sh
qmllint -I /usr/share/omarchy/shell Service.qml BarWidget.qml
```

The tests cover transformed and scaled monitors, reserved margins, exact
floating geometry, managed and legacy client selection, launch/show/hide
behavior, command-based effective binding consumption, ordinary CLIamp
isolation, guarded teardown, and idempotent icon recovery.

## Logo license

The unmodified classic Winamp logo is redistributed under the permission and
attribution recorded in [`assets/README.md`](assets/README.md). It is a
trademark of its respective owner. This plugin is unofficial and is not
affiliated with or endorsed by Winamp or its owner. Plugin code is MIT
licensed; the logo keeps its separately documented terms.
