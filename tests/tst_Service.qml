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

    function create(path, properties) {
      var component = Qt.createComponent("file://" + path)
      if (component.status !== Component.Ready) console.error(component.errorString())
      compare(component.status, Component.Ready, component.errorString())
      return component.createObject(testCase, properties || {})
    }

    function init() {
      host = create(Quickshell.env("OMARCHY_PATH")
        + "/shell/services/PluginShellApi.qml", {
          pluginId: "io.github.ilyazar.cliamp"
        })
      host.barConfig = {layout: {right: [{
        id: "io.github.ilyazar.cliamp", alignment: "Right",
        windowWidth: 850, windowHeight: 425
      }]}}
      service = create(Quickshell.env("CLIAMP_SOURCE") + "/Service.qml")
      service.shell = host
    }

    function cleanup() {
      if (qtest_results.failed) console.error("Failed:", qtest_results.functionName)
      service.destroy()
      host.destroy()
    }

    function test_postCreationSettingsAndChanges() {
      compare(service.settings.windowWidth, 850)
      compare(service.settings.alignment, "Right")
      service.applyWorkspace()
      service.applyWorkspace()
      host.barConfig = {layout: {left: [{
        id: "io.github.ilyazar.cliamp", windowWidth: 700
      }]}}
      compare(service.settings.windowWidth, 700)
      tryVerify(function() {
        return service.lastGeometry !== null
          && service.lastGeometry.requested.width === 700
      })
    }

    function test_independentErrorRecovery() {
      service.acceptResult(1, "", "workspace failed")
      service.acceptBindingResult(1, "", "binding failed")
      compare(service.lastError, "workspace failed\nbinding failed")
      service.acceptBindingResult(0, '["SUPER+M"]', "")
      compare(service.lastError, "workspace failed")
      compare(service.bindingLabel, "SUPER+M")
      service.acceptResult(0, '{"status":"unchanged"}', "")
      compare(service.lastError, "")

      service.acceptBindingResult(1, "", "binding failed")
      service.acceptResult(0, '{"status":"applied"}', "")
      compare(service.lastError, "binding failed")
      service.acceptBindingResult(0, '[]', "")
      compare(service.lastError, "")
      compare(service.bindingLabel, "Unbound")
    }

    function test_widgetPersistence() {
      var bar = create(Quickshell.env("OMARCHY_PATH")
        + "/shell/Ui/PluginBarApi.qml", {
          pluginId: host.pluginId, moduleName: host.pluginId, shell: host
        })
      host._serviceLookup = function(id) { return service }
      var widget = create(Quickshell.env("CLIAMP_SOURCE") + "/BarWidget.qml")
      widget.bar = bar
      widget.settings = host.barConfig.layout.right[0]
      host._updateSettings = function(id, entry) {
        host.barConfig = {layout: {right: [entry]}}
        widget.settings = entry
        return true
      }
      compare(widget.geometryService, service)
      verify(widget.implicitWidth > 0)
      widget.cycleAlignment()
      compare(service.settings.alignment, "Left")
      widget.persistDimension("windowWidth", 700)
      compare(service.settings.windowWidth, 700)
      compare(widget.leftAlignedTooltip(["a", "abc"]), "a\u00a0\u00a0\nabc")
      widget.destroy()
      bar.destroy()
    }

    function test_invalidResultsAndDestruction() {
      service.acceptBindingResult(0, '{}', "")
      verify(service.bindingsError !== "")
      service.acceptResult(0, 'null', "")
      verify(service.workspaceError !== "")
      service.teardown()
      service.acceptResult(0, '{"status":"applied"}', "")
      verify(service.workspaceError !== "")
      service.scheduleApply()
      verify(service.tearingDown)
    }
  }
}
