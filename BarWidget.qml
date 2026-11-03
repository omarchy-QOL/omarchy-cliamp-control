pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
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
  readonly property string edge: config.edge
  readonly property string placement: config.placement
  readonly property bool dimBackground: config.dimBackground
  readonly property bool verticalEdge: edge === "Left" || edge === "Right"
  readonly property string positionLabel: {
    const labels = verticalEdge
      ? ["Top", "Center", "Bottom"] : ["Left", "Center", "Right"]
    return labels[["Start", "Center", "End"].indexOf(placement)]
  }
  readonly property string positionAxis: verticalEdge
    ? "Vertical position" : "Horizontal position"
  readonly property int windowWidth: config.windowWidth
  readonly property int windowHeight: config.windowHeight
  readonly property color foreground: bar
    ? bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string keybindingsScript: Paths.localPath(
    Qt.resolvedUrl("open-keybindings.sh"))
  readonly property int keybindingIndex: 5
  readonly property int settingsCount: 6
  readonly property string tooltip: actionTooltip("CLIamp", [
    ["Left click:", "toggle"],
    ["Right click:", "window settings"]
  ])
  readonly property string clampSummary: {
    const result = geometryService ? geometryService.lastGeometry : null
    if (!result || !result.actual || !result.requested) return ""
    if (result.actual.width === result.requested.width
        && result.actual.height === result.requested.height) return ""
    return "Clamped to " + result.actual.width + "x" + result.actual.height

  }

  function actionTooltip(title, rows) {
    const labelWidth = Math.max.apply(null, rows.map(function(row) {
      return row[0].length
    }))
    const valueWidth = Math.max.apply(null, rows.map(function(row) {
      return row[1].length
    }))
    const width = labelWidth + valueWidth + 2
    return [title.padEnd(width, "\u00a0")].concat(rows.map(function(row) {
      return row[0].padEnd(labelWidth, "\u00a0") + "\u00a0\u00a0"
        + row[1].padStart(valueWidth, "\u00a0")
    })).join("\n")
  }

  function nextValue(values, current, direction) {
    return values[(values.indexOf(current) + (direction || 1)
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
    if (geometryService) geometryService.launchKeybindings(keybindingsScript)
  }

  function toggleFromPanel() {
    if (geometryService) geometryService.togglePlayer(
      geometryService.contextFor(popup.screen))
  }

  function cycleEdge(direction) {
    commitFields()
    if (geometryService) geometryService.setSetting("edge",
      nextValue(["Top", "Right", "Bottom", "Left"], edge, direction))
  }

  function cyclePlacement(direction) {
    commitFields()
    if (geometryService) geometryService.setSetting("placement",
      nextValue(["Start", "Center", "End"], placement, direction))
  }

  function toggleDimming() {
    commitFields()
    if (geometryService)
      geometryService.setSetting("dimBackground", !dimBackground)
  }

  function activateSelected() {
    if (selectedIndex === 0) cycleEdge()
    else if (selectedIndex === 1) cyclePlacement()
    else if (selectedIndex === 2) widthRow.focusField()
    else if (selectedIndex === 3) heightRow.focusField()
    else if (selectedIndex === 4) toggleDimming()
    else if (selectedIndex === keybindingIndex) launchKeybindings()
  }

  onSettingsChanged: receiveSettings()
  onGeometryServiceChanged: Qt.callLater(receiveSettings)

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (["workspacev2", "focusedmon"].indexOf(event.name) >= 0)
        root.close()
      // Activating a special workspace moves keyboard focus to its window.
      else if (event.name === "activespecial" && root.opened) {
        popup.focusPrimed = false
        popup.beginFocusPrime()
      }
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
        root.pressContext = root.geometryService.contextFor(popup.screen)
    }
    onPressed: function(buttonCode) {
      const context = root.pressContext || (root.geometryService
        ? root.geometryService.contextFor(popup.screen) : null)
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
    padding: Style.spacing.lg
    contentWidth: popup.fittedContentWidth(Style.space(280))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: widthRow.fieldActive || heightRow.fieldActive
      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          root.selectedIndex = (root.selectedIndex + dy
            + root.settingsCount) % root.settingsCount
        if (dx !== 0 && root.selectedIndex === 0) root.cycleEdge(dx)
        else if (dx !== 0 && root.selectedIndex === 1)
          root.cyclePlacement(dx)
      }
      onActivateRequested: root.activateSelected()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        const key = String(text).toLowerCase()
        if (key === "e") root.cycleEdge()
        else if (key === "a") root.cyclePlacement()
        else if (key === "w") widthRow.focusField()
        else if (key === "h") heightRow.focusField()
        else if (key === "d") root.toggleDimming()
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
        spacing: Style.spacing.md

        CursorSurface {
          width: heroContent.implicitWidth
          implicitHeight: heroContent.implicitHeight
          hasCursor: heroMouse.containsMouse
          foreground: root.foreground

          Row {
            id: heroContent
            spacing: Style.space(14)

            Text {
              text: button.text
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: "CLIamp"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          MouseArea {
            id: heroMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleFromPanel()
          }

          PanelToolTip {
            visible: heroMouse.containsMouse
            text: "Show or hide CLIamp"
            fontFamily: root.fontFamily
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        MenuRow {
          label: "Screen edge"
          value: root.edge
          tooltipText: "Choose where the drop-down meets the screen."
          hasCursor: root.selectedIndex === 0
          onHovered: function(on) { if (on) root.selectedIndex = 0 }
          onClicked: root.cycleEdge()
        }

        MenuRow {
          label: root.positionAxis
          value: root.positionLabel
          tooltipText: "Position along the selected edge."
          hasCursor: root.selectedIndex === 1
          onHovered: function(on) { if (on) root.selectedIndex = 1 }
          onClicked: root.cyclePlacement()
        }

        DimensionRow {
          id: widthRow
          objectName: "widthRow"
          label: "Window width"
          hasCursor: root.selectedIndex === 2
          value: root.windowWidth
          onHovered: function(on) { if (on) root.selectedIndex = 2 }
          onModified: function(value) {
            root.persistDimension("windowWidth", value)
          }
        }

        DimensionRow {
          id: heightRow
          objectName: "heightRow"
          label: "Window height"
          hasCursor: root.selectedIndex === 3
          value: root.windowHeight
          onHovered: function(on) { if (on) root.selectedIndex = 3 }
          onModified: function(value) {
            root.persistDimension("windowHeight", value)
          }
        }

        ToggleRow {
          objectName: "dimRow"
          label: "Dim background"
          checked: root.dimBackground
          tooltipText: "Applied only while the CLIamp drop-down is visible."
          hasCursor: root.selectedIndex === 4
          onHovered: function(on) { if (on) root.selectedIndex = 4 }
          onToggled: root.toggleDimming()
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
      }
    }
  }

  component MenuRow: Item {
    id: row

    property string label: ""
    property string value: ""
    property string tooltipText: ""
    property bool hasCursor: false
    signal clicked()
    signal hovered(bool isHovered)

    width: parent ? parent.width : implicitWidth
    implicitHeight: Style.space(24)

    RowLayout {
      anchors.fill: parent
      spacing: Style.space(8)

      Text {
        text: row.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: row.hasCursor
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
      }

      CursorSurface {
        Layout.preferredWidth: Style.space(64)
        Layout.preferredHeight: Style.space(24)
        hasCursor: row.hasCursor
        foreground: root.foreground

        Text {
          anchors.centerIn: parent
          text: row.value
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: row.hovered(true)
      onExited: row.hovered(false)
      onClicked: row.clicked()
    }

    PanelToolTip {
      visible: row.tooltipText !== "" && mouse.containsMouse
      text: row.tooltipText
      fontFamily: root.fontFamily
    }
  }

  component ToggleRow: Item {
    id: row

    required property string label
    required property bool checked
    property string tooltipText: ""
    property bool hasCursor: false
    signal toggled()
    signal hovered(bool isHovered)

    width: parent ? parent.width : implicitWidth
    implicitHeight: Style.space(24)

    RowLayout {
      anchors.fill: parent
      spacing: Style.space(8)

      Text {
        text: row.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: row.hasCursor
        Layout.fillWidth: true
      }

      Item {
        Layout.preferredWidth: Style.space(64)
        Layout.preferredHeight: Style.space(24)

        ToggleSwitch {
          id: toggle
          objectName: "dimSwitch"
          anchors.centerIn: parent
          trackHeight: Style.space(16)
          checked: row.checked
          interactive: false
          cursorRing: false
          foreground: root.foreground
        }
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: row.hovered(true)
      onExited: row.hovered(false)
      onClicked: row.toggled()
    }

    PanelToolTip {
      visible: row.tooltipText !== "" && mouse.containsMouse
      text: row.tooltipText
      fontFamily: root.fontFamily
    }
  }

  component DimensionRow: Item {
    id: dimension

    required property string label
    required property int value
    property bool hasCursor: false
    readonly property var input: numberField.field.contentItem
    readonly property bool fieldActive: numberField.field.activeFocus
    readonly property bool invalid: fieldActive
      && (!input.acceptableInput || !/^[0-9]+$/.test(input.text))
    signal modified(int value)
    signal hovered(bool isHovered)

    function focusField() {
      numberField.field.forceActiveFocus()
      input.selectAll()
    }
    function containsField(item, point) {
      return numberField.field.contains(numberField.field.mapFromItem(
        item, point.x, point.y))
    }

    width: parent ? parent.width : implicitWidth
    implicitHeight: Style.space(24)

    RowLayout {
      anchors.fill: parent
      spacing: Style.space(8)

      Text {
        text: dimension.label
        color: dimension.invalid ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: dimension.hasCursor
        Layout.fillWidth: true
      }

      NumberField {
        id: numberField
        objectName: "numberField"
        Component.onCompleted: {
          field.live = false
          field.implicitHeight = Style.space(24)
        }
        Layout.preferredWidth: fieldWidth
        Layout.alignment: Qt.AlignVCenter
        fieldWidth: Style.space(64)
        from: 1
        to: 9999
        stepSize: 50
        value: dimension.value
        foreground: dimension.invalid ? root.urgent : root.foreground
        fontFamily: root.fontFamily
        hasCursor: dimension.hasCursor && !dimension.fieldActive
        onModified: function(value) { dimension.modified(value) }

        PanelToolTip {
          visible: dimension.invalid
          text: "Enter a whole number from 1 to 9,999."
          fontFamily: root.fontFamily
        }
      }
    }

    Shortcut {
      sequence: "Escape"
      context: Qt.ApplicationShortcut
      enabled: dimension.input && dimension.input.activeFocus
      onActivated: {
        dimension.input.text = String(dimension.value)
        keyCatcher.forceActiveFocus()
      }
    }

    HoverHandler {
      onHoveredChanged: dimension.hovered(hovered)
    }
  }
}
