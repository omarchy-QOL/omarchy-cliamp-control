import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Item {
  id: root

  property QtObject shell: null
  property string alignment: "Center"
  property int windowWidth: 1200
  property int windowHeight: 600
  property string lastStatus: "starting"
  property string lastError: ""
  property var lastGeometry: null
  property bool rerunPending: false
  property int absentRetryCount: 0
  property string processOutput: ""
  property string processError: ""
  property string bindingLabel: "..."
  property string bindingOutput: ""
  property string bindingError: ""
  property bool bindingRerunPending: false
  property bool tearingDown: false

  readonly property string pluginId: "io.github.ilyazar.cliamp"
  readonly property string managedClass: "org.omarchy.cliamp.quake"
  readonly property string pluginDir: localPath(Qt.resolvedUrl("."))
  readonly property string applyScript: localPath(
    Qt.resolvedUrl("scripts/apply_geometry.sh"))
  readonly property string bindingScript: localPath(
    Qt.resolvedUrl("scripts/sync_bindings.sh"))
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

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.substring(7)
    return decodeURIComponent(value)
  }

  function positiveInteger(value, fallback) {
    var parsed = Number(value)
    if (!isFinite(parsed) || parsed < 1 || parsed > 100000
        || Math.floor(parsed) !== parsed) return fallback
    return parsed
  }

  function validAlignment(value) {
    var text = String(value || "")
    return ["Left", "Center", "Right"].indexOf(text) >= 0
      ? text : "Center"
  }

  function configuredEntry() {
    var config = shell ? shell.shellConfig : null
    var layout = config && config.bar ? config.bar.layout : null
    var sections = ["left", "center", "right"]
    for (var s = 0; layout && s < sections.length; s++) {
      var entries = layout[sections[s]]
      if (!Array.isArray(entries)) continue
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        if (entry && String(entry.id || entry) === "io.github.ilyazar.cliamp")
          return typeof entry === "object" ? entry : { id: entry }
      }
    }
    return null
  }

  function refreshSettingsFromShell() {
    var entry = configuredEntry()
    if (!entry) return
    configure(
      validAlignment(entry.alignment),
      positiveInteger(entry.windowWidth, 1200),
      positiveInteger(entry.windowHeight, 600)
    )
  }

  function configure(nextAlignment, nextWidth, nextHeight) {
    var normalizedAlignment = validAlignment(nextAlignment)
    var normalizedWidth = positiveInteger(nextWidth, 1200)
    var normalizedHeight = positiveInteger(nextHeight, 600)
    var changed = alignment !== normalizedAlignment
      || windowWidth !== normalizedWidth
      || windowHeight !== normalizedHeight

    alignment = normalizedAlignment
    windowWidth = normalizedWidth
    windowHeight = normalizedHeight
    if (changed || lastStatus === "starting") scheduleApply(30)
  }

  function scheduleApply(delayMs) {
    if (tearingDown) return
    applyTimer.interval = Math.max(20, Number(delayMs || 120))
    applyTimer.restart()
  }

  function applyGeometry() {
    if (tearingDown) return
    if (applyProcess.running) {
      rerunPending = true
      return
    }
    processOutput = ""
    processError = ""
    applyProcess.command = [
      "bash",
      applyScript,
      alignment,
      String(windowWidth),
      String(windowHeight)
    ]
    applyProcess.running = true
  }

  function syncBindings() {
    if (tearingDown) return
    if (bindingProcess.running) {
      bindingRerunPending = true
      return
    }
    bindingOutput = ""
    bindingError = ""
    bindingProcess.command = ["bash", bindingScript]
    bindingProcess.running = true
  }

  function acceptBindingResult(exitCode) {
    if (tearingDown) return
    var parsed = null
    try {
      parsed = JSON.parse(String(bindingOutput || "").trim())
    } catch (error) {
      parsed = null
    }

    if (exitCode === 0 && parsed) {
      var labels = []
      var bindings = Array.isArray(parsed.bindings) ? parsed.bindings : []
      for (var index = 0; index < bindings.length; index++) {
        var label = String(bindings[index].label || "")
        if (label !== "") labels.push(label)
      }
      bindingLabel = labels.length > 0 ? labels.join(" / ") : "Unbound"
    } else {
      bindingLabel = "Unbound"
      lastError = String(bindingError || "").trim()
        || "CLIamp binding adapter failed"
    }

    if (bindingRerunPending) {
      bindingRerunPending = false
      bindingTimer.restart()
    }
  }

  function acceptResult(exitCode) {
    if (tearingDown) return
    var parsed = null
    var raw = String(processOutput || "").trim()
    if (raw !== "") {
      try {
        parsed = JSON.parse(raw)
      } catch (error) {
        parsed = null
      }
    }

    if (parsed) {
      lastGeometry = parsed
      lastStatus = String(parsed.status || "error")
      if (lastStatus === "absent") {
        lastError = ""
      } else if (lastStatus === "unavailable") {
        lastError = "CLIamp is not installed"
      } else if (lastStatus === "applied") {
        absentRetryCount = 0
        lastError = parsed.clientCount > 1
          ? "More than one CLIamp client exists" : ""
      } else {
        lastError = lastStatus === "mismatch"
          ? "Hyprland did not accept the exact geometry"
          : "CLIamp disappeared while geometry was applied"
      }
    } else {
      lastStatus = "error"
      lastError = String(processError || "").trim()
        || "Geometry helper failed with exit " + exitCode
    }

    if (rerunPending) {
      rerunPending = false
      scheduleApply(30)
    }
  }

  function eventName(event) {
    return String(event && event.name ? event.name : "").toLowerCase()
  }

  function handleHyprlandEvent(event) {
    if (tearingDown) return
    var name = eventName(event)
    var relevant = [
      "openwindow",
      "closewindow",
      "movewindow",
      "movewindowv2",
      "changefloatingmode",
      "workspace",
      "workspacev2",
      "focusedmon",
      "activespecial",
      "activespecialv2",
      "monitoradded",
      "monitoraddedv2",
      "monitorremoved",
      "configreloaded"
    ]
    if (relevant.indexOf(name) >= 0) scheduleApply(120)
    if (name === "configreloaded") bindingTimer.restart()
  }

  function teardown() {
    if (tearingDown) return
    tearingDown = true
    applyTimer.stop()
    bindingTimer.stop()
    absentRetryTimer.stop()
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

  onShellChanged: refreshSettingsFromShell()

  Connections {
    target: root.shell
    ignoreUnknownSignals: true
    function onShellConfigChanged() { root.refreshSettingsFromShell() }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  Timer {
    id: applyTimer
    interval: 120
    onTriggered: root.applyGeometry()
  }

  Timer {
    id: bindingTimer
    interval: 250
    onTriggered: root.syncBindings()
  }

  Timer {
    id: absentRetryTimer
    interval: Math.min(15000, 2000 * Math.pow(2,
      Math.min(root.absentRetryCount, 3)))
    running: !root.tearingDown && (root.lastStatus === "absent"
      || root.lastStatus === "unavailable")
    repeat: true
    onTriggered: {
      root.absentRetryCount++
      root.scheduleApply(30)
    }
  }

  Process {
    id: applyProcess

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.processOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.processError = text
    }
    onExited: function(exitCode) { root.acceptResult(exitCode) }
  }

  Process {
    id: bindingProcess

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.bindingOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.bindingError = text
    }
    onExited: function(exitCode) { root.acceptBindingResult(exitCode) }
  }

  Component.onCompleted: Qt.callLater(function() {
    root.refreshSettingsFromShell()
    root.scheduleApply(30)
    root.syncBindings()
  })

  Component.onDestruction: root.teardown()
}
