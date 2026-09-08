import QtQuick
import QtTest
import Quickshell

ShellRoot {
  TestCase {
    id: testCase
    name: "Service"
    onCompletedChanged: if (completed) {
      console.log("CLIAMP_QML_RESULT failures=" + qtest_results.failCount
        + " passed=" + qtest_results.passCount)
    }

    property var service
    property var host
    property var saved: []

    QtObject {
      id: compositor
      property var commands: []
      signal rawEvent(var event)
      function dispatch(request) { commands = commands.concat([request]) }
      function monitorFor(screen) {
        return {name: "TEST", activeWorkspace: {id: 2}}
      }
    }

    function create(path, properties) {
      var component = Qt.createComponent("file://" + path)
      compare(component.status, Component.Ready, component.errorString())
      return component.createObject(testCase, properties || {})
    }

    function init() {
      saved = []
      compositor.commands = []
      host = create(Quickshell.env("OMARCHY_PATH")
        + "/shell/services/PluginShellApi.qml", {
          pluginId: "io.github.ilyazar.cliamp"
        })
      host.barConfig = {layout: {right: [{
        id: host.pluginId, alignment: "Right", windowWidth: 850, windowHeight: 425
      }]}}
      host._updateSettings = function(id, entry) { saved.push(entry); return true }
      service = create(Quickshell.env("CLIAMP_SOURCE") + "/Service.qml",
        {compositor: compositor})
      service.shell = host
    }

    function cleanup() {
      if (qtest_results.failed) console.error("Failed:", qtest_results.functionName)
      service.destroy()
      host.destroy()
    }

    function result(status, values, revision) {
      return ["cliamp", service.epoch,
        revision === undefined ? service.revision : revision, status]
        .concat(values || []).join(",")
    }

    function test_immediateCommandsAndStaleSnapshots() {
      compare(service.settings.windowWidth, 850)
      var count = compositor.commands.length
      service.setSetting("windowWidth", 900)
      compare(service.settings.windowWidth, 900)
      compare(compositor.commands.length, count + 1)
      service.setSetting("windowHeight", 500)
      compare(compositor.commands.length, count + 2)
      compare(service.settings.windowHeight, 500)
      compare(saved.length, 0)
      service.receiveSettings({alignment: "Left", windowWidth: 850})
      compare(service.settings.windowWidth, 900)
      service.persistSettings()
      compare(saved.length, 1)
      compare(saved[0].windowWidth, 900)
      compare(saved[0].windowHeight, 500)
      service.receiveSettings({alignment: "Left", windowWidth: 700})
      compare(service.settings.windowWidth, 700)
      compare(service.settings.alignment, "Left")
    }

    function test_observationAndIndependentErrors() {
      service.acceptGeometry(result("error", ["geometry failed"]))
      service.acceptBindingResult(1, "", "binding failed")
      compare(service.lastError, "geometry failed\nbinding failed")
      service.acceptGeometry(result("geometry", [0,26,850,425,0,26,850,425]))
      compare(service.lastError, "binding failed")
      compare(service.lastGeometry.actual.width, 850)
      service.acceptBindingResult(0, '["F12"]', "")
      compare(service.lastError, "")
      service.setSetting("windowWidth", 900)
      service.acceptGeometry(result("error", ["stale failure"], 0))
      compare(service.lastError, "")
      service.acceptGeometry(result("geometry", [0,26,900,425,0,26,800,425]))
      verify(service.geometryError !== "")
      service.acceptGeometry(result("absent"))
      compare(service.lastGeometry, null)
      compare(service.lastError, "")
    }

    function test_widgetUsesDesiredState() {
      var bar = create(Quickshell.env("OMARCHY_PATH")
        + "/shell/Ui/PluginBarApi.qml", {
          pluginId: host.pluginId, moduleName: host.pluginId, shell: host
        })
      host._serviceLookup = function(id) { return service }
      var widget = create(Quickshell.env("CLIAMP_SOURCE") + "/BarWidget.qml")
      widget.bar = bar
      widget.settings = host.barConfig.layout.right[0]
      host._updateSettings = function(id, entry) {
        host.barConfig = {layout: {right: [widget.settings]}}
        widget.settings = entry
        saved.push(entry)
        return true
      }
      widget.cycleAlignment()
      compare(widget.alignment, "Left")
      widget.cycleAlignment()
      compare(widget.alignment, "Center")
      widget.cycleAlignment(-1)
      compare(widget.alignment, "Left")
      widget.persistDimension("windowWidth", 700)
      compare(widget.windowWidth, 700)
      service.persistSettings()
      compare(service.settings.windowWidth, 700)
      compare(host.barConfig.layout.right[0].windowWidth, 850)
      compare(saved[0].windowWidth, 700)
      widget.destroy()
      bar.destroy()
    }

    function test_teardownFlushesAndStops() {
      service.setSetting("windowHeight", 700)
      service.teardown()
      compare(saved[0].windowHeight, 700)
      verify(service.tearingDown)
      var count = compositor.commands.length
      service.togglePlayer({monitor: "TEST", workspace: 2})
      compare(compositor.commands.length, count)
    }
  }
}
