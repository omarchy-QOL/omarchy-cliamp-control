import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "io.github.ilyazar.cliamp"
  ipcTarget: ""

  property int selectedIndex: 0
  property bool hideConfirmOpen: false
  property int hideConfirmIndex: 0

  readonly property var geometryService: bar && bar.shell
    ? bar.shell.serviceFor(moduleName) : null
  readonly property string alignment: validAlignment(
    setting("alignment", "Center"))
  readonly property int windowWidth: intSetting(
    "windowWidth", 1200)
  readonly property int windowHeight: intSetting(
    "windowHeight", 600)
  readonly property bool iconVisible: setting("iconVisible", true) === true
  readonly property color foreground: bar
    ? bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string toggleScript: localPath(
    Qt.resolvedUrl("scripts/toggle_cliamp.sh"))
  readonly property string keybindingsScript: localPath(
    Qt.resolvedUrl("open-keybindings.sh"))
  readonly property int keybindingIndex: 3
  readonly property int iconIndex: 4
  readonly property int settingsCount: 5
  readonly property string restoreIconWarning:
    "Run `~/.config/omarchy/plugins/io.github.ilyazar.cliamp/bin/"
      + "cliamp-widget` to restore the bar icon."
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
      + " inside " + result.monitor.name
  }

  function validAlignment(value) {
    var text = String(value || "")
    return ["Left", "Center", "Right"].indexOf(text) >= 0
      ? text : "Center"
  }

  function leftAlignedTooltip(lines) {
    var width = 0
    var padded = []
    for (var i = 0; i < lines.length; i++)
      width = Math.max(width, String(lines[i]).length)
    for (var j = 0; j < lines.length; j++) {
      var line = String(lines[j])
      var missing = width - line.length
      while (missing-- > 0) line += "\u00a0"
      padded.push(line)
    }
    return padded.join("\n")
  }

  function intSetting(name, fallback) {
    var value = Number(setting(name, fallback))
    if (!isFinite(value) || value < 1 || value > 100000
        || Math.floor(value) !== value) return fallback
    return value
  }

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.substring(7)
    return decodeURIComponent(value)
  }

  function nextAlignment() {
    var values = ["Left", "Center", "Right"]
    return values[(values.indexOf(alignment) + 1) % values.length]
  }

  function persistSetting(name, value) {
    var entry = { id: moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    entry[name] = value
    settings = entry
    if (bar && bar.shell
        && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, entry)
  }

  function syncService() {
    if (geometryService && typeof geometryService.configure === "function")
      geometryService.configure(alignment, windowWidth, windowHeight)
  }

  function persistDimension(name, value) {
    persistSetting(name, Math.max(1, Math.min(100000, Number(value))))
  }

  function launchCliamp() {
    close()
    Quickshell.execDetached(["bash", toggleScript])
  }

  function launchKeybindings() {
    close()
    Quickshell.execDetached(["bash", keybindingsScript])
  }

  function cycleAlignment() {
    persistSetting("alignment", nextAlignment())
  }

  function hideIcon() {
    close()
    persistSetting("iconVisible", false)
  }

  function requestHideIcon() {
    hideConfirmIndex = 0
    hideConfirmOpen = true
  }

  function cancelHideIcon() {
    hideConfirmOpen = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmHideIcon() {
    hideConfirmOpen = false
    hideIcon()
  }

  function activateSelected() {
    if (hideConfirmOpen) {
      if (hideConfirmIndex === 0) cancelHideIcon()
      else confirmHideIcon()
      return
    }
    if (selectedIndex === 0) cycleAlignment()
    else if (selectedIndex === 1) widthRow.focusField()
    else if (selectedIndex === 2) heightRow.focusField()
    else if (selectedIndex === keybindingIndex) launchKeybindings()
    else if (selectedIndex === iconIndex) requestHideIcon()
  }

  onSettingsChanged: syncService()
  onGeometryServiceChanged: syncService()
  onOpenedChanged: if (opened) {
    selectedIndex = 0
    hideConfirmOpen = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  visible: iconVisible
  implicitWidth: iconVisible ? button.implicitWidth : 0
  implicitHeight: iconVisible ? button.implicitHeight : 0

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: root.opened
    tooltipText: root.tooltip
    text: ""
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.launchCliamp()
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
        if (root.hideConfirmOpen) {
          if (dx !== 0 || dy !== 0)
            root.hideConfirmIndex = root.hideConfirmIndex === 0 ? 1 : 0
          return
        }
        if (dy !== 0)
          root.selectedIndex = (root.selectedIndex + dy
            + root.settingsCount) % root.settingsCount
        if (dx !== 0 && root.selectedIndex === 0) root.cycleAlignment()
      }
      onActivateRequested: root.activateSelected()
      onCloseRequested: {
        if (root.hideConfirmOpen) root.cancelHideIcon()
        else root.close()
      }
      onTabRequested: function(direction) {
        if (root.hideConfirmOpen)
          root.hideConfirmIndex = root.hideConfirmIndex === 0 ? 1 : 0
        else root.switchPanel(direction)
      }
      onTextKey: function(text) {
        var key = String(text).toLowerCase()
        if (root.hideConfirmOpen) {
          if (key === "y") root.confirmHideIcon()
          else if (key === "n") root.cancelHideIcon()
          return
        }
        if (key === "a") root.cycleAlignment()
        else if (key === "w") widthRow.focusField()
        else if (key === "h") heightRow.focusField()
        else if (key === "k") root.launchKeybindings()
        else if (key === "v") root.requestHideIcon()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        PanelHero {
          visible: !root.hideConfirmOpen
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
          visible: !root.hideConfirmOpen
          label: "Horizontal alignment"
          value: root.alignment
          hasCursor: root.selectedIndex === 0
          onHovered: function(on) { if (on) root.selectedIndex = 0 }
          onClicked: root.cycleAlignment()
        }

        DimensionRow {
          id: widthRow
          visible: !root.hideConfirmOpen
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
          visible: !root.hideConfirmOpen
          label: "Window height"
          hasCursor: root.selectedIndex === 2
          value: root.windowHeight
          onHovered: function(on) { if (on) root.selectedIndex = 2 }
          onModified: function(value) {
            root.persistDimension("windowHeight", value)
          }
        }

        MenuRow {
          visible: !root.hideConfirmOpen
          label: "Launch keybinding"
          value: root.geometryService
            ? root.geometryService.bindingLabel : "..."
          hasCursor: root.selectedIndex === root.keybindingIndex
          onHovered: function(on) {
            if (on) root.selectedIndex = root.keybindingIndex
          }
          onClicked: root.launchKeybindings()
        }

        MenuRow {
          visible: !root.hideConfirmOpen
          label: "Bar icon"
          value: "Visible"
          hasCursor: root.selectedIndex === root.iconIndex
          onHovered: function(on) {
            if (on) root.selectedIndex = root.iconIndex
          }
          onClicked: root.requestHideIcon()
        }

        Text {
          visible: !root.hideConfirmOpen && (root.clampSummary !== ""
            || (root.geometryService
              && root.geometryService.lastError !== ""))
          width: parent.width
          text: root.geometryService && root.geometryService.lastError !== ""
              ? root.geometryService.lastError : root.clampSummary
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Column {
          visible: !root.hideConfirmOpen
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
              + "2. The top edge avoids reserved areas.\n"
              + "3. Hide shows how to restore the icon."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        Column {
          visible: root.hideConfirmOpen
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            width: parent.width
            text: "HIDE BAR ICON?"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            text: root.restoreIconWarning
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          MenuRow {
            label: "Cancel"
            value: "Abort"
            hasCursor: root.hideConfirmIndex === 0
            onHovered: function(on) {
              if (on) root.hideConfirmIndex = 0
            }
            onClicked: root.cancelHideIcon()
          }

          MenuRow {
            label: "Confirm hide"
            value: "Hide"
            hasCursor: root.hideConfirmIndex === 1
            onHovered: function(on) {
              if (on) root.hideConfirmIndex = 1
            }
            onClicked: root.confirmHideIcon()
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

  Component.onCompleted: Qt.callLater(syncService)
}
