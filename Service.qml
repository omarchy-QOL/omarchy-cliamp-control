import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "logic/Settings.js" as Settings
import "logic/Paths.js" as Paths

Item {
  id: root

  property QtObject shell: null
  property var lastGeometry: null
  property string workspaceError: ""
  property string bindingsError: ""
  property string bindingLabel: "..."
  property bool rerunPending: false
  property bool bindingRerunPending: false
  property bool tearingDown: false

  readonly property string pluginId: "io.github.ilyazar.cliamp"
  readonly property string managedClass: "org.omarchy.cliamp.quake"
  readonly property string pluginDir: Paths.localPath(Qt.resolvedUrl("."))
  readonly property string lastError: [workspaceError, bindingsError]
    .filter(function(error) { return error !== "" }).join("\n")
  readonly property var settings: Settings.normalize(
    shell ? Settings.findEntry(shell.barConfig, pluginId) : {})
  readonly property string teardownCommand: [
    "plugin_dir=\"$1\"",
    "plugin_id=\"$2\"",
    "managed_class=\"$3\"",
    "client_filter='.[] | select(.class == $class'",
    "client_filter+=' or .initialClass == $class) | .address'",
    "poll_attempts=\"$4\"",
    "poll_interval=\"$5\"",
    "enabled_attempts=\"$6\"",
    "enabled_interval=\"$7\"",
    "hyprctl reload config-only >/dev/null 2>&1 || true",
    "sleep \"$enabled_interval\"",
    "plugin_state=\"absent\"",
    "if [[ -e $plugin_dir ]]; then",
    "  plugin_state=\"unknown\"",
    "  plugin_filter='[.[] | select(.id == $id)]'",
    "  plugin_filter+=' | if length != 1 then \"unknown\"'",
    "  plugin_filter+=' elif .[0].enabled == true then \"enabled\"'",
    "  plugin_filter+=' elif .[0].enabled == false then \"disabled\"'",
    "  plugin_filter+=' else \"unknown\" end'",
    "  for ((attempt = 0; attempt < enabled_attempts; attempt++)); do",
    "    plugin_json=\"\"",
    "    if plugin_json=\"$(omarchy plugin list --json 2>/dev/null)\"; then",
    "      plugin_state=\"$(jq -r --arg id \"$plugin_id\" \\",
    "        \"$plugin_filter\" <<<\"$plugin_json\" 2>/dev/null \\",
    "        || printf 'unknown')\"",
    "      [[ $plugin_state == \"enabled\" ]] && exit 0",
    "      [[ $plugin_state == \"disabled\" ]] && break",
    "    fi",
    "    sleep \"$enabled_interval\"",
    "  done",
    "  [[ $plugin_state == \"unknown\" && -e $plugin_dir ]] && exit 0",
    "fi",
    "for ((attempt = 0; attempt < poll_attempts; attempt++)); do",
    "  clients_json=\"$(hyprctl clients -j 2>/dev/null || printf '[]')\"",
    "  while IFS= read -r address; do",
    "    [[ $address =~ ^0x[0-9A-Fa-f]+$ ]] || continue",
    "    hyprctl dispatch \\",
    "      \"hl.dsp.window.close({ window = \\\"address:$address\\\" })\" \\",
    "      >/dev/null 2>&1 || true",
    "  done < <(",
    "    jq -r --arg class \"$managed_class\" \\",
    "      \"$client_filter\" <<<\"$clients_json\" 2>/dev/null || true",
    "  )",
    "  sleep \"$poll_interval\"",
    "done",
    "hyprctl reload config-only >/dev/null 2>&1 || true"
  ].join("\n")

  function scheduleApply() {
    if (shell && !tearingDown) applyTimer.restart()
  }

  function applyWorkspace() {
    if (tearingDown) return
    if (applyProcess.running) {
      rerunPending = true
      return
    }
    applyProcess.command = [
      "bash", pluginDir + "scripts/apply_workspace.sh",
      settings.alignment, String(settings.windowWidth),
      String(settings.windowHeight)
    ]
    applyProcess.running = true
  }

  function syncBindings() {
    if (tearingDown) return
    if (bindingProcess.running) {
      bindingRerunPending = true
      return
    }
    bindingProcess.running = true
  }

  function acceptBindingResult(exitCode, output, errorOutput) {
    if (tearingDown) return
    try {
      if (exitCode !== 0)
        throw new Error(errorOutput.trim() || "CLIamp binding sync failed")
      var labels = JSON.parse(output)
      if (!Array.isArray(labels) || !labels.every(function(label) {
        return typeof label === "string"
      })) throw new Error("Invalid CLIamp binding result")
      bindingLabel = labels.length ? labels.join(" / ") : "Unbound"
      bindingsError = ""
    } catch (error) {
      bindingLabel = "Unavailable"
      bindingsError = error.message
    }
    if (bindingRerunPending) {
      bindingRerunPending = false
      bindingTimer.restart()
    }
  }

  function acceptResult(exitCode, output, errorOutput) {
    if (tearingDown) return
    try {
      if (exitCode !== 0)
        throw new Error(errorOutput.trim() || "Workspace rule helper failed")
      var result = JSON.parse(output)
      if (!result || ["applied", "unchanged"].indexOf(result.status) < 0)
        throw new Error("Invalid workspace rule result")
      lastGeometry = result
      workspaceError = ""
    } catch (error) {
      workspaceError = error.message
    }
    if (rerunPending) {
      rerunPending = false
      scheduleApply()
    }
  }

  function handleHyprlandEvent(event) {
    if (tearingDown) return
    if (["focusedmon", "monitoraddedv2", "monitorremovedv2",
         "configreloaded"].indexOf(event.name) >= 0) scheduleApply()
    if (event.name === "configreloaded") bindingTimer.restart()
  }

  function teardown() {
    if (tearingDown) return
    tearingDown = true
    applyTimer.stop()
    bindingTimer.stop()
    rerunPending = false
    bindingRerunPending = false
    if (applyProcess.running) applyProcess.running = false
    if (bindingProcess.running) bindingProcess.running = false

    Quickshell.execDetached([
      "bash",
      "-c",
      teardownCommand,
      "cliamp-teardown",
      pluginDir,
      pluginId,
      managedClass,
      "100",
      "0.05",
      "10",
      "0.1"
    ])
  }

  onSettingsChanged: scheduleApply()

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  Timer {
    id: applyTimer
    interval: 120
    onTriggered: root.applyWorkspace()
  }

  Timer {
    id: bindingTimer
    interval: 250
    onTriggered: root.syncBindings()
  }

  Timer {
    interval: 5000
    running: root.shell !== null && !root.tearingDown
    repeat: true
    onTriggered: root.scheduleApply()
  }

  Process {
    id: applyProcess
    stdout: StdioCollector { id: applyOutput; waitForEnd: true }
    stderr: StdioCollector { id: applyError; waitForEnd: true }
    onExited: function(exitCode) {
      root.acceptResult(exitCode, applyOutput.text, applyError.text)
    }
  }

  Process {
    id: bindingProcess
    command: ["bash", root.pluginDir + "scripts/sync_bindings.sh"]
    stdout: StdioCollector { id: bindingOutput; waitForEnd: true }
    stderr: StdioCollector { id: bindingError; waitForEnd: true }
    onExited: function(exitCode) {
      root.acceptBindingResult(exitCode, bindingOutput.text, bindingError.text)
    }
  }

  Component.onCompleted: Qt.callLater(function() {
    root.scheduleApply()
    root.syncBindings()
  })
  Component.onDestruction: root.teardown()
}
