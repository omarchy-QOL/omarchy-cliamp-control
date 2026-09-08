# CLIamp interaction and architecture review

Investigated on 2026-09-08 against `dev` at `22043ef`. The installed plugin is
linked to this checkout. Runtime: Omarchy `4.0.0.r2071.ga703092`, Quickshell
`0.3.1`, Qt `6.11.2`, and Hyprland `0.56.2`.

This is a diagnosis and design comparison. The temporary tracing was removed;
no runtime implementation change is included in this report. The shell was
restarted and the saved settings restored to Center, 850 x 625. The player and
settings popup were hidden after testing to release their screen effects.

## Findings

### The service sometimes receives the previous settings

The alignment cycle itself is still `Left, Center, Right`, as in the initial
version. Rapid input completed the expected number of cycles in the observed
bursts. The geometry service, however, sometimes retained a previous selection
while the widget and saved configuration showed the new selection.

Temporary IPC instrumentation in the real service recorded:

| Action           | Saved/widget value | Service API value | Applied command |
| ---------------- | ------------------ | ----------------- | --------------- |
| Left to Center   | Center             | Left              | Left            |
| Right to Left    | Left               | Right             | Right           |
| Width increment  | 900                | 850               | previous width  |
| Width increment  | 950                | 900               | previous width  |

The service's input snapshot was already wrong before it constructed the
helper command. This rules out output parsing as the cause of those cases.
A six-key alignment burst also finished with Center saved and Left in the
service. This directly explains a window at the previous position while the
menu shows the next position.

The installed host publishes plugin API snapshots from its
`onShellConfigChanged` handler, through `pluginsChanged`, `syncPluginApis`, and
`publicBarConfig`. The last function reads the derived `barConfig` property.
Its binding can still contain the previous value during the source property's
change handler.

A small Qt 6.11.2 reproduction of that exact dependency pattern produced
`1/0`, `2/1`, `3/2`, `4/3`, and `5/4` for new configuration/published snapshot:

```qml
QtObject {
  id: host
  property var shellConfig: ({bar: {value: 0}})
  readonly property var barConfig: shellConfig.bar
  property var snapshot: ({})
  onShellConfigChanged: snapshot = JSON.parse(JSON.stringify(barConfig))
}
```

After assigning `host.shellConfig = {bar: {value: 1}}`, the snapshot contained
zero while a later read of `host.barConfig.value` returned one. The host has
other notification paths, which explains why some real updates succeed.

Relevant installed host locations, using `$shell` for
`/usr/share/omarchy/shell`:

- `$shell/shell.qml`: `onShellConfigChanged`, `persistShellConfig`,
  `publicBarConfig`, `syncPluginApis`, and `updateEntryInline`.
- `$shell/plugins/bar/Bar.qml`: `applySettingsDelta` updates widget settings.
- `$shell/services/PluginShellApi.qml`: the service receives a copied
  `barConfig` through this facade.

Commit `be53c49` made this host snapshot the sole geometry input. Before that,
the widget also sent its current settings directly through
`geometryService.configure(...)`. That direct route bypassed the stale host
snapshot. Removing it exposed a real integration bug; the mocked QML test
updated the facade synchronously and therefore could not catch it.

### Workspace gaps are calculated for the wrong monitor

Commit `324ce62` replaced client-addressed floating-window geometry with a
single dynamic rule for a tiled `special:cliamp` workspace. It also changed
monitor selection from the client's monitor to whichever monitor has focus.

Those monitors can differ. With CLIamp on the portrait VGA-1 display, moving
focus to DP-3 rewrites the rule using DP-3's dimensions while the workspace
remains on VGA-1.

Observed with Center and 1000 x 625 requested:

| State                    | Client monitor | Position | Actual size |
| ------------------------ | -------------- | -------- | ----------- |
| VGA-1 has focus          | VGA-1          | 40,26    | 1000 x 625  |
| Focus changes to DP-3    | VGA-1          | 460,26   | 160 x 1345  |

DP-3 has 1920 logical pixels of width. Its centered 1000-pixel window needs
460-pixel gaps on each side. Applying those gaps to the 1080-pixel-wide
portrait display leaves only 160 pixels. Its different usable height also
makes the player too tall.

At the start of the investigation, the same defect had reduced CLIamp to
10 x 1345 while the settings requested 850 x 625. That follows directly from
applying 1070 total horizontal gap pixels to a 1080-pixel-wide output.

The current helper reports its calculated rectangle as `actual`. It does not
read back the client rectangle. A successful rule update consequently appears
successful even when the real window is wrong. The earlier direct-window
helper read the client back and reported an exact-geometry mismatch.

### Resizing gained delay and lost a dependable immediate path

The numeric control is still the host's `NumberField`, wrapping Qt Quick
Controls `SpinBox`, with 50-pixel steps. That component wiring was already
present in the initial version. The important changes are downstream:

- Earlier widget actions assigned their local settings immediately and called
  `configure`. A changed value scheduled geometry after 30 ms.
- `be53c49` removed the local assignment and the direct service call. Every
  update now waits for the host-to-service snapshot and then a 120 ms timer.
- Normalization returns a new object for every snapshot, including identical
  values. Each notification restarts the timer. The previous `configure`
  compared the three geometry values and ignored duplicates.
- A queued rerun now also uses the 120 ms delay instead of 30 ms.

In six isolated live alignment actions after a fresh shell restart, three
reached the desired workspace rule in approximately 303-418 ms. Three had not
reached it after 1.5 seconds. These are input-to-rule observations, including
command and sampling overhead, rather than display-frame measurements.

The failed cases are stale input, not merely an animation taking longer.
Width changes reproduced the same one-step lag in the table above. Height
uses the same persistence, normalization, debounce, and helper route.

The field also retains the host SpinBox's default text-edit behavior: typed
text is committed on acceptance or loss of focus rather than on every digit.
This is distinct from clicking its step arrows, and was not introduced by the
workspace refactor. See the Qt [SpinBox live property][spinbox-live].

### Workspace and popup lifetimes are separate

Left click opens the CLIamp player workspace; right click opens the settings
popup. They have separate lifetimes and screen effects.

The settings popup has no workspace-change close handler. This was already
true in the initial plugin. With the popup open, a switch of the underlying
regular workspace left both
`omarchy-keyboard-panel` and the other monitor's
`omarchy-keyboard-panel-dismiss` mapped. Closing the popup removed them. The
host `KeyboardPanel` is transparent outside its card, but its dismissal
surfaces can still intercept input.

The dark backdrop behind the player comes from Hyprland's
`decoration:dim_special = 0.6`. The multi-monitor failure above leaves the
special workspace open on VGA-1 after focus moves to DP-3, even when the
player has shrunk to a nearly invisible sliver. That leaves a dimmed screen
with very little visible player content.

There is also a reproduced same-monitor race. The button starts a detached
Bash helper; F12 uses the same helper through a compositor exec dispatcher.
A sufficiently quick workspace switch runs before that helper reaches
`hyprctl`. The compositor hides the special workspace during the switch, then
the delayed toggle opens it again over the newly selected regular workspace.

This reproduced with actual input events on DP-3:

| Sequence                                      | After workspace switch |
| --------------------------------------------- | ---------------------- |
| Open player, wait, then Super+2                | Player hidden          |
| Open settings, wait, then Super+2              | Settings remain open   |
| Open both, wait, then Super+2                  | Only settings remain   |
| F12 immediately followed by Super+2            | Player opens afterward |
| Left-click bar button immediately, then Super+2 | Player opens afterward |

The actual left-click sequence reproduced three times out of three. The
keyboard sequence reproduced with 0, 2, and 5 ms between individual key
events; at 10 ms between key events it did not reproduce in this sample.
Those values are event-injection delays, not a measured universal threshold.

A fixed screenshot patch outside the player and popup had normalized mean
brightness 0.211710 in the undimmed baseline. It remained identical after all
three settled workspace-switch sequences, even with the settings popup still
mapped. In the rapid-toggle cases it dropped to 0.084946, approximately 40% of
the baseline, matching the configured 60% special-workspace dimming.

The screen is therefore being dimmed by a special workspace opened too late,
rather than by the settings popup. The popup's retained input surfaces and the
wrong-monitor geometry remain separate defects. Detached launching already
existed in the earlier plugin family; this test proves the current race, not
that a particular September commit first introduced it.

### Restarting helps stale runtime state, but does not repair these paths

The initial shell had been running since 2026-09-07 23:25:55. Its log contained
a Hyprland event-socket `PeerClosedError`. Restarting brought its initial
service state into agreement with the saved configuration.

Fresh processes then reproduced the stale facade values and wrong-monitor
geometry. Reloading therefore cannot be the complete fix. The socket warning
alone does not establish the cause of every missed interaction.

## Architectural stepping stones

Line counts below cover executable QML, JavaScript, Lua, shell scripts, and
`bin/` files. Tests, documentation, and assets are excluded. These are physical
source lines, not a measure of runtime cost.

| Commit    | Date       | Runtime LOC | Main change                         |
| --------- | ---------- | ----------- | ----------------------------------- |
| a17d7e4   | 2026-08-15 | 1528        | Direct floating-window geometry     |
| 2473460   | 2026-08-15 | 1550        | Recognize stock CLIamp              |
| 00e4c0e   | 2026-08-15 | 1628        | Plugin-owned app and binding route  |
| 191f96c   | 2026-08-15 | 1853        | Guarded disable/removal lifecycle   |
| 392adb1   | 2026-08-27 | 1830        | Last revision before workspace fit  |
| 324ce62   | 2026-09-02 | 1794        | Tiled workspace gaps and lazy seed  |
| 22043ef   | 2026-09-07 | 1029        | Simplified runtime and bar controls |

The initial version depended on the desktop overlay's quake launcher. The
August 15 releases progressively brought launching, binding discovery, and
managed-window ownership into the plugin. The August 27 state retained that
ownership and the original direct geometry route.

`324ce62` is the major geometry design change. `be53c49`, included in the last
row, is the major settings-delivery change. `22043ef` removed icon hiding and
the active red color; it did not introduce a different numeric control or
alignment order.

### Earlier command path, through 392adb1

```text
widget action
  -> update local settings immediately
  -> service.configure(alignment, width, height)
  -> ignore unchanged values; wait 30 ms
  -> apply_geometry.sh
  -> find managed client and its monitor
  -> calculate a clamped rectangle
  -> float, resize, and move that client by address
  -> read back client position and size
```

The compositor operations were `hl.dsp.window.float`,
`hl.dsp.window.resize`, and `hl.dsp.window.move`, dispatched for an explicit
window address. Geometry was a property of the player window. The special
workspace handled showing, hiding, dimming, and animation separately.

### Current command path, from be53c49

```text
widget action
  -> host.updateEntryInline
  -> host configuration and plugin API snapshots
  -> service normalizes the snapshot
  -> restart 120 ms timer
  -> apply_workspace.sh
  -> read focused monitor and existing workspace rules
  -> calculate gaps; update one workspace rule
  -> Hyprland's tiling layout determines the client rectangle
```

Geometry is now a property of the workspace layout. The rule's
`on_created_empty` handles lazy launch. Toggle itself is shorter and no longer
waits for a newly launched client, but geometry correctness depends on the
rule being current for the workspace's actual output.

## What the performance evidence does and does not show

An alternating helper benchmark used fixed mocked Hyprland replies, one warmup
and 15 measured runs per implementation:

| Helper design             | Median | Range        |
| ------------------------- | ------ | ------------ |
| Direct window, 392adb1     | 44.9ms | 40.7-52.3ms  |
| Workspace rule, 22043ef    | 25.1ms | 22.4-27.9ms  |

This measures subprocess/parsing overhead, excluding compositor rendering and
animations. The smaller current helper is faster in that limited comparison.
There is no evidence that more Bash work or a larger codebase explains the
regression. The current runtime is about 44% smaller than the August 27 state.

The verified problems are stale settings, an increased scheduling delay,
repeated notifications, and incorrect monitor ownership. Native tiling also
adds a layout dependency that direct client geometry did not have. A complete
live A/B comparison would be needed to quantify the rendering cost of that
layout dependency; the benchmark above must not be used as that claim.

## Recommended direction

Use the August 27 direct-window design as the reference for precise,
configurable rectangles, while retaining the current plugin-owned app ID,
native bar components, binding implementation, and removal of icon hiding.
Do not restore an old checkout wholesale or reintroduce compatibility paths.

1. Give user commands one immediate route into a service-owned desired state.
   Persist that state separately. A copied host snapshot must not be the only
   delivery mechanism for an interactive command.
2. Keep distinct values for desired settings and observed client geometry.
   An accepted workspace rule is not proof of the visible rectangle.
3. Associate geometry with the client's actual monitor. If workspace gaps are
   retained, select the workspace's monitor and handle workspace moves and
   special-workspace activation, not merely focus changes.
4. Restore a short, value-guarded geometry update cycle. Coalesce repeated
   input without waiting for the entire interaction to stop. Avoid resetting
   the apply timer for identical snapshots.
5. Close the settings popup when its workspace context changes. Route player
   toggles through one ordered path and cancel an opening request if its
   originating workspace context has changed. Avoid a detached shell job for
   a simple compositor toggle. Removing that extra hop reduces the race
   window; context-aware cancellation is the correctness requirement.
6. Correct the host snapshot publication order upstream. Read the new source
   value or publish after the derived bar configuration changes. The minimal
   Qt reproduction above provides a focused regression case.

For this feature, direct client geometry is the simpler candidate to validate:
exact width, height, and alignment map directly to window operations. A
full-width proportional console is a more natural fit for workspace gaps.
This is a design recommendation, not a measured claim that floating windows
always render faster.

## Verification gaps in the existing tests

The tests check geometry arithmetic and generated rules but do not compare a
real client's rectangle after moving focus between differently sized outputs.
The QML fixture delivers new host snapshots immediately, so it bypasses the
publication-order problem. Its settings assertions also do not exercise the
real numeric control's input and persistence sequence.

The next implementation needs acceptance checks for:

- Repeated alignment changes with matching widget, desired state, and actual
  client position, including input faster than persistence notifications.
- Width and height step arrows, held repeat, typed values, and acceptance.
- Moving focus between landscape and portrait outputs while the player stays
  open; reopening it on the other output; scaled and reserved work areas.
- Workspace changes while the player and settings popup are open, checking
  both special-workspace visibility and all popup/dismissal surfaces. Include
  a switch immediately after a left click or F12, before its toggle executes.
- Disable/re-enable, reload, and fresh launch with current settings.

Raw local evidence and temporary reproducers are under
`/tmp/cliamp-regression-qa/`. They include `latency.json`,
`latency-trace.json`, `burst.json`, `resize.json`, `helper-benchmark.json`,
`tst_HostSnapshots.qml`, and the captured runtime state and screenshots.
Temporary diagnostic IPC is absent from the restored shell.

The follow-up dimming evidence is under `/tmp/cliamp-dimming-qa/`:
`results.json`, `mouse-results.json`, input reproducers, and screenshots.
The input daemon was stopped and the original regular workspaces and focus
were restored after the experiment.

[spinbox-live]:
  https://doc.qt.io/qt-6/qml-qtquick-controls-spinbox.html#live-prop
