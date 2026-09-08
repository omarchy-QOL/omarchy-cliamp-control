pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "logic/Settings.js" as Settings
import "logic/Paths.js" as Paths

Panel {
  id: root

  moduleName: "io.github.ilyazar.cliamp"
  ipcTarget: ""

  property int selectedIndex: 0
  property var pressContext: null

  readonly property var geometryService: bar && bar.shell
    ? bar.shell.serviceFor(moduleName) : null
  readonly property var config: geometryService
    ? geometryService.settings : Settings.normalize(root.settings)
  readonly property string alignment: config.alignment
  readonly property int windowWidth: config.windowWidth
  readonly property int windowHeight: config.windowHeight
  readonly property color foreground: bar
    ? bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string keybindingsScript: Paths.localPath(
    Qt.resolvedUrl("open-keybindings.sh"))
  readonly property int keybindingIndex: 3
  readonly property int settingsCount: 4
  readonly property string tooltip: leftAlignedTooltip([
    "CLIamp",
    "Left click:  toggle",
    "Right click: window settings"
  ])
  readonly property string clampSummary: {
    var result = geometryService ? geometryService.lastGeometry : null
    if (!result || !result.actual || !result.requested) return ""
    if (result.actual.width === result.requested.width
        && result.actual.height === result.requested.height) return ""
    return "Clamped to " + result.actual.width + "x" + result.actual.height

  }

  function leftAlignedTooltip(lines) {
    var width = Math.max.apply(null, lines.map(function(line) {
      return line.length
    }))
    return lines.map(function(line) {
      return line.padEnd(width, "\u00a0")
    }).join("\n")
  }

  function nextAlignment(direction) {
    var values = ["Left", "Center", "Right"]
    return values[(values.indexOf(alignment) + (direction || 1)
      + values.length) % values.length]
  }

  function receiveSettings() {
    if (geometryService) geometryService.receiveSettings(settings)
  }

  function commitFields() { keyCatcher.forceActiveFocus() }

  function persistDimension(name, value) {
    if (geometryService) geometryService.setSetting(name, value)
  }

  function launchCliamp(context) {
    close()
    if (geometryService) geometryService.togglePlayer(context)
  }

  function launchKeybindings() {
    close()
    Quickshell.execDetached(["bash", keybindingsScript])
  }

  function cycleAlignment(direction) {
    commitFields()
    if (geometryService)
      geometryService.setSetting("alignment", nextAlignment(direction))
  }

  function activateSelected() {
    if (selectedIndex === 0) cycleAlignment()
    else if (selectedIndex === 1) widthRow.focusField()
    else if (selectedIndex === 2) heightRow.focusField()
    else if (selectedIndex === keybindingIndex) launchKeybindings()
  }

  onSettingsChanged: receiveSettings()
  onGeometryServiceChanged: Qt.callLater(receiveSettings)

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (["workspacev2", "focusedmon"].indexOf(event.name) >= 0)
        root.close()
    }
  }

  onOpenedChanged: if (opened) {
    selectedIndex = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.tooltip
    text: ""
    TapHandler {
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onPressedChanged: if (pressed && root.geometryService)
        root.pressContext = root.geometryService.contextFor(
          button.QsWindow.window.screen)
    }
    onPressed: function(buttonCode) {
      var context = root.pressContext || (root.geometryService
        ? root.geometryService.contextFor(button.QsWindow.window.screen) : null)
      root.pressContext = null
      if (buttonCode === Qt.LeftButton) root.launchCliamp(context)
      else if (buttonCode === Qt.RightButton) root.toggle()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(330))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: widthRow.fieldActive || heightRow.fieldActive
      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          root.selectedIndex = (root.selectedIndex + dy
            + root.settingsCount) % root.settingsCount
        if (dx !== 0 && root.selectedIndex === 0) root.cycleAlignment(dx)
      }
      onActivateRequested: root.activateSelected()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        var key = String(text).toLowerCase()
        if (key === "a") root.cycleAlignment()
        else if (key === "w") widthRow.focusField()
        else if (key === "h") heightRow.focusField()
        else if (key === "k") root.launchKeybindings()
      }

      TapHandler {
        onTapped: function(point) {
          if (!widthRow.containsField(keyCatcher, point.position)
              && !heightRow.containsField(keyCatcher, point.position))
            root.commitFields()
        }
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        PanelHero {
          width: parent.width
          title: "CLIamp"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Image {
              width: Style.font.display
              height: width
              source: Qt.resolvedUrl("assets/winamp-logo.svg")
              fillMode: Image.PreserveAspectFit
              smooth: true
            }
          }
        }

        MenuRow {
          label: "Horizontal alignment"
          value: root.alignment
          hasCursor: root.selectedIndex === 0
          onHovered: function(on) { if (on) root.selectedIndex = 0 }
          onClicked: root.cycleAlignment()
        }

        DimensionRow {
          id: widthRow
          objectName: "widthRow"
          label: "Window width"
          hasCursor: root.selectedIndex === 1
          value: root.windowWidth
          onHovered: function(on) { if (on) root.selectedIndex = 1 }
          onModified: function(value) {
            root.persistDimension("windowWidth", value)
          }
        }

        DimensionRow {
          id: heightRow
          objectName: "heightRow"
          label: "Window height"
          hasCursor: root.selectedIndex === 2
          value: root.windowHeight
          onHovered: function(on) { if (on) root.selectedIndex = 2 }
          onModified: function(value) {
            root.persistDimension("windowHeight", value)
          }
        }

        MenuRow {
          label: "Launch keybinding"
          value: root.geometryService
            ? root.geometryService.bindingLabel : "..."
          hasCursor: root.selectedIndex === root.keybindingIndex
          onHovered: function(on) {
            if (on) root.selectedIndex = root.keybindingIndex
          }
          onClicked: root.launchKeybindings()
        }

        Text {
          visible: root.clampSummary !== ""
            || (root.geometryService
              && root.geometryService.lastError !== "")
          width: parent.width
          text: root.geometryService && root.geometryService.lastError !== ""
              ? root.geometryService.lastError : root.clampSummary
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Column {
          width: parent.width
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: "Note:"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            width: parent.width
            text: "1. Alignment moves the window along the x-axis.\n"
              + "2. The top edge avoids reserved areas."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  component MenuRow: CursorSurface {
    id: row

    property string label: ""
    property string value: ""
    signal clicked()
    signal hovered(bool isHovered)

    width: parent ? parent.width : implicitWidth
    implicitHeight: Style.space(42)
    foreground: root.foreground

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      spacing: Style.space(10)

      Text {
        text: row.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: row.hasCursor
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        text: row.value
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.alignment: Qt.AlignVCenter
        Layout.maximumWidth: row.width * 0.52
        elide: Text.ElideRight
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: row.hovered(true)
      onExited: row.hovered(false)
      onClicked: row.clicked()
    }
  }

  component DimensionRow: CursorSurface {
    id: dimension

    required property string label
    required property int value
    readonly property bool fieldActive: numberField.field.activeFocus
    signal modified(int value)
    signal hovered(bool isHovered)

    function focusField() { numberField.field.forceActiveFocus() }
    function containsField(item, point) {
      return numberField.field.contains(numberField.field.mapFromItem(
        item, point.x, point.y))
    }

    width: parent ? parent.width : implicitWidth
    implicitHeight: Style.space(48)
    foreground: root.foreground

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      spacing: Style.space(8)

      Text {
        text: dimension.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: dimension.hasCursor
        Layout.fillWidth: true
      }

      NumberField {
        id: numberField
        objectName: "numberField"
        Component.onCompleted: field.live = false
        Layout.preferredWidth: fieldWidth
        Layout.alignment: Qt.AlignVCenter
        fieldWidth: Style.space(128)
        from: 1
        to: 100000
        stepSize: 50
        value: dimension.value
        foreground: root.foreground
        fontFamily: root.fontFamily
        hasCursor: dimension.hasCursor && !dimension.fieldActive
        onModified: function(value) { dimension.modified(value) }
      }
    }

    HoverHandler {
      onHoveredChanged: dimension.hovered(hovered)
    }
  }
}
