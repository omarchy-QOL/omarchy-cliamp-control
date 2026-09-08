import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "logic/Settings.js" as Settings
import "logic/Paths.js" as Paths
import "logic/Commands.js" as Commands

Item {
  id: root

  property QtObject shell: null
  property QtObject compositor: Hyprland
  property var settings: Settings.normalize({})
  property var lastGeometry: null
  property string geometryError: ""
  property string bindingsError: ""
  property string bindingLabel: "..."
  property bool bindingRerunPending: false
  property bool persistPending: false
  property bool persisting: false
  property bool tearingDown: false
  property bool ready: false
  property int revision: 0

  readonly property string pluginId: "io.github.ilyazar.cliamp"
  readonly property string managedClass: "org.omarchy.cliamp.quake"
  readonly property string pluginDir: Paths.localPath(Qt.resolvedUrl("."))
  readonly property string epoch: Date.now() + "-" + Math.random()
  readonly property string lastError: [geometryError, bindingsError]
    .filter(function(error) { return error !== "" }).join("\n")
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
    "hyprctl reload config-only >/dev/null 2>&1 || true",
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


  function dispatch(method, args) {
    if (!tearingDown)
      compositor.dispatch(Commands.call(pluginDir + "lib/client.lua", method, args))
  }

  function geometryArgs() {
    return [epoch, revision, settings.alignment,
      settings.windowWidth, settings.windowHeight]
  }

  function receiveSettings(entry) {
    if (persistPending || persisting || tearingDown) return
    var next = Settings.normalize(entry)
    if (JSON.stringify(next) === JSON.stringify(settings)) return
    settings = next
    revision++
    if (ready) dispatch("configure", geometryArgs())
  }

  function setSetting(name, value) {
    var next = Object.assign({}, settings)
    next[name] = value
    next = Settings.normalize(next)
    if (JSON.stringify(next) === JSON.stringify(settings)) return
    settings = next
    revision++
    if (ready) dispatch("configure", geometryArgs())
    persistPending = true
    Qt.callLater(persistSettings)
  }

  function persistSettings() {
    if (!persistPending || !shell) return
    persistPending = false
    persisting = true
    shell.updateEntryInline(pluginId, Object.assign({id: pluginId}, settings))
    persisting = false
  }

  function install() {
    if (!shell || tearingDown) return
    var args = geometryArgs()
    args.splice(1, 0, pluginDir + "scripts/launch_cliamp.sh")
    dispatch("install", args)
    ready = true
    syncBindings()
  }

  function contextFor(screen) {
    var monitor = compositor.monitorFor(screen)
    return monitor && monitor.activeWorkspace
      ? {monitor: monitor.name, workspace: monitor.activeWorkspace.id} : null
  }

  function togglePlayer(context) {
    if (ready && context) dispatch("toggle", [context.monitor, context.workspace])
  }

  function acceptGeometry(data) {
    if (tearingDown) return
    var fields = data.split(",")
    if (fields[0] !== "cliamp" || fields[1] !== epoch
        || Number(fields[2]) !== revision) return
    if (fields[3] === "error") {
      geometryError = fields.slice(4).join(",")
      return
    }
    geometryError = ""
    if (fields[3] === "absent") {
      lastGeometry = null
      return
    }
    var values = fields.slice(4).map(Number)
    if (fields[3] !== "geometry" || values.length !== 8
        || !values.every(Number.isFinite)) {
      geometryError = "Invalid CLIamp geometry result"
      return
    }
    lastGeometry = {
      requested: {width: settings.windowWidth, height: settings.windowHeight},
      actual: {x: values[4], y: values[5], width: values[6], height: values[7]}
    }
    if (values.slice(0, 4).some(function(value, index) {
      return value !== values[index + 4]
    })) geometryError = "Hyprland did not accept the requested geometry"
  }

  function syncBindings() {
    if (tearingDown) return
    if (bindingProcess.running) bindingRerunPending = true
    else bindingProcess.running = true
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
      Qt.callLater(syncBindings)
    }
  }

  function teardown() {
    if (tearingDown) return
    persistSettings()
    dispatch("stop", [epoch])
    tearingDown = true
    if (bindingProcess.running) bindingProcess.running = false
    Quickshell.execDetached(["bash", "-c", teardownCommand, "cliamp-teardown",
      pluginDir, pluginId, managedClass, "100", "0.05", "10", "0.1"])
  }

  onShellChanged: if (shell) {
    receiveSettings(Settings.findEntry(shell.barConfig, pluginId))
    install()
  }

  Connections {
    target: root.compositor
    function onRawEvent(event) {
      if (event.name === "custom") root.acceptGeometry(event.data)
      else if (event.name === "configreloaded") root.install()
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

  Component.onDestruction: root.teardown()
}
