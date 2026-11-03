pragma ComponentBehavior: Bound

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
    property var saved: []

    QtObject {
      id: host
      readonly property string pluginId: "io.github.ilyazar.cliamp"
      property var barConfig: ({})
      property bool rejectUpdates: false
      property var widget: null
      function updateEntryInline(id, entry) {
        if (rejectUpdates) return false
        if (widget) widget.settings = entry
        testCase.saved.push(entry)
        return true
      }
      function serviceFor(id) { return testCase.service }
    }

    Component {
      id: barFixture
      QtObject {
        property QtObject shell: host
        property color barForeground: "white"
        property string fontFamily: "monospace"
      }
    }

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
      const component = Qt.createComponent("file://" + path)
      if (component.status !== Component.Ready) console.error(component.errorString())
      compare(component.status, Component.Ready, component.errorString())
      return component.createObject(testCase, properties || {})
    }

    // qmllint disable shadow
    function init() {
      saved = []
      compositor.commands = []
      host.rejectUpdates = false
      host.widget = null
      host.barConfig = {layout: {right: [{
        id: host.pluginId, edge: "Top", placement: "End",
        windowWidth: 850, windowHeight: 425
      }]}}
      service = create(Quickshell.env("CLIAMP_SOURCE") + "/Service.qml",
        {compositor: compositor})
      service.shell = host
    }

    function cleanup() {
      if (qtest_results.failed) console.error("Failed:", qtest_results.functionName)
      service.destroy()
    }
    // qmllint enable shadow

    function result(status, values, revision) {
      return ["cliamp", service.epoch,
        revision === undefined ? service.revision : revision, status]
        .concat(values || []).join(",")
    }

    function test_immediateCommandsAndStaleSnapshots() {
      compare(service.settings.windowWidth, 850)
      const count = compositor.commands.length
      service.setSetting("windowWidth", 900)
      compare(service.settings.windowWidth, 900)
      compare(compositor.commands.length, count + 1)
      service.setSetting("windowHeight", 500)
      compare(compositor.commands.length, count + 2)
      compare(service.settings.windowHeight, 500)
      compare(saved.length, 0)
      service.receiveSettings({edge: "Left", placement: "Start", windowWidth: 850})
      compare(service.settings.windowWidth, 900)
      service.persistSettings()
      compare(saved.length, 1)
      compare(saved[0].windowWidth, 900)
      compare(saved[0].windowHeight, 500)
      service.receiveSettings({})
      compare(service.settings.windowWidth, 900)
      compare(service.settings.windowHeight, 500)
      service.receiveSettings({edge: "Bottom", placement: "End", windowWidth: 700})
      compare(service.settings.windowWidth, 700)
      compare(service.settings.edge, "Bottom")
      compare(service.settings.placement, "End")
    }

    function test_observationAndIndependentErrors() {
      service.acceptGeometry(result("error", ["geometry failed"]))
      service.acceptBindingResult(1, "", "binding failed")
      compare(service.lastError, "geometry failed\nbinding failed")
      service.acceptGeometry(result("geometry", [850,425]))
      compare(service.lastError, "binding failed")
      compare(service.lastGeometry.actual.width, 850)
      service.acceptBindingResult(0, '["F12"]', "")
      compare(service.lastError, "")
      service.setSetting("windowWidth", 900)
      service.acceptGeometry(result("error", ["stale failure"], 0))
      compare(service.lastError, "")
      service.acceptGeometry(result("geometry", [800,425]))
      compare(service.lastGeometry.actual.width, 800)
      service.acceptGeometry(result("geometry", [800]))
      verify(service.geometryError !== "")
      service.acceptGeometry(result("absent"))
      compare(service.lastGeometry, null)
      compare(service.lastError, "")
    }

    function test_widgetUsesDesiredState() {
      const bar = barFixture.createObject(testCase)
      const widget = create(Quickshell.env("CLIAMP_SOURCE") + "/BarWidget.qml")
      widget.bar = bar
      widget.settings = host.barConfig.layout.right[0]
      host.widget = widget
      widget.cycleEdge()
      compare(widget.edge, "Right")
      compare(widget.positionLabel, "Bottom")
      widget.cycleEdge()
      compare(widget.edge, "Bottom")
      compare(widget.positionLabel, "Right")
      widget.cyclePlacement()
      compare(widget.placement, "Start")
      compare(widget.positionLabel, "Left")
      widget.persistDimension("windowWidth", 700)
      compare(widget.windowWidth, 700)
      service.persistSettings()
      compare(service.settings.windowWidth, 700)
      compare(host.barConfig.layout.right[0].windowWidth, 850)
      compare(saved[0].windowWidth, 700)
      widget.destroy()
      bar.destroy()
    }

    function test_keybindingLaunchHidesPlayer() {
      const count = compositor.commands.length
      service.launchKeybindings("/bin/true")
      compare(compositor.commands.length, count + 1)
      verify(compositor.commands[count].includes(".hide("))
    }

    function test_persistenceFailureRecovers() {
      host.rejectUpdates = true
      service.setSetting("windowHeight", 700)
      service.persistSettings()
      verify(service.persistPending)
      compare(service.lastError, "Could not save CLIamp settings")

      host.rejectUpdates = false
      service.persistSettings()
      verify(!service.persistPending)
      compare(service.lastError, "")
      compare(saved[0].windowHeight, 700)
    }

    function test_teardownFlushesAndStops() {
      service.setSetting("windowHeight", 700)
      service.teardown()
      compare(saved[0].windowHeight, 700)
      verify(service.tearingDown)
      const count = compositor.commands.length
      service.togglePlayer({monitor: "TEST", workspace: 2})
      compare(compositor.commands.length, count)
    }
  }
}
