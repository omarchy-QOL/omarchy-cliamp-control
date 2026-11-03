# Changelog

## 0.2.0 - 2026-11-03

- Open the drop-down from any screen edge, at the start, center, or end of it.
- Add **Dim background**. Turned off, the desktop stays bright while CLIamp is
  open, and your Hyprland value returns when CLIamp closes or the plugin stops.
- Show or hide CLIamp from the panel header.
- Flag invalid sizes instead of applying them; sizes are capped at 9,999.
- Make the settings panel more compact, and keep keyboard control in it while
  CLIamp opens.

Known limits: Hyprland has one global special-workspace dim, so other special
workspaces opened while it is off stay undimmed too. Changing it while CLIamp
is open replays the slide-in, because Hyprland only reads the value when the
workspace opens.

## 0.1.6 - 2026-09-08

CLIamp Window Control is now **CLIamp quake**. The plugin ID stays the same.

- Resize immediately with the arrow buttons; typed sizes apply on Enter or when
  you click elsewhere in the panel.
- Keep the drop-down aligned on rotated and scaled monitors.
- Handle quick toggles and workspace changes without reopening the player on
  another workspace.
- Preserve dimensions through shell reloads and leave regular CLIamp windows
  alone.

## 0.1.3 - 2026-08-15

- Clean up plugin-owned CLIamp windows on disable or removal.
- Keep managed CLIamp alive across ordinary shell restarts.
- Preserve Hyprland binding options during interception.
- Locate renamed table-form CLIamp bindings in the editor.

## 0.1.2 - 2026-08-15

- Consume stock and user-overridden CLIamp launch bindings without editing
  Hyprland config files.
- Launch a managed app ID so ordinary CLIamp windows remain untouched.
- Restore original binding actions when the plugin is disabled or removed.

## 0.1.1 - 2026-08-15

- Support stock Omarchy CLIamp on a plain Quattro installation.
- Remove mandatory setup hooks and external recovery files.

## 0.1.0 - 2026-08-15

Initial release of CLIamp Window Control for Omarchy Quattro.
