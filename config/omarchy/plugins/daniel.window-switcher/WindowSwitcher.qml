import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui as Ui
import "WindowModel.js" as Model

Item {
  id: root
  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  readonly property string helper: Quickshell.env("HOME") + "/.local/bin/hypr-window-switcher"
  readonly property var appLibrary: shell ? shell.appLibrary : null
  property bool opened: false
  property bool loading: false
  property string errorMessage: ""
  property string activationError: ""
  property string view: "compact"
  property string query: ""
  property string selectedAddress: ""
  property var snapshot: ({monitors: [], windows: []})
  property var rows: []
  property var filtered: []
  property var displays: []
  property var targetScreen: null
  property int viewRevision: 0
  property string pendingAddress: ""
  property string lastSnapshot: ""
  property int session: 0

  function status() {
    return JSON.stringify({opened: opened, view: view, query: query, selected: selectedAddress,
      count: filtered.length, error: activationError || errorMessage, monitor: targetScreen ? targetScreen.name : ""});
  }
  function open(payload) {
    focusDelay.stop()
    pendingAddress = ""
    session++
    query = ""
    search.text = ""
    selectedAddress = ""
    errorMessage = ""
    activationError = ""
    rows = []; filtered = []; lastSnapshot = ""
    var focused = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    targetScreen = Quickshell.screens.find(function(s) { return s.name === focused; }) || Quickshell.screens[0]
    opened = true
    loading = true
    if (!stateRead.running) { stateRead.revision = viewRevision; stateRead.running = true }
    if (appLibrary) appLibrary.refreshIcons()
    refresh()
    Qt.callLater(function() { search.forceActiveFocus() })
  }
  function close() {
    opened = false
    focusDelay.stop()
    pendingAddress = ""
    session++
  }
  function refresh() {
    if (opened && !listProc.running) { listProc.session = session; listProc.running = true }
  }
  function rebuild() {
    rows = Model.windows(snapshot, DesktopEntries.applications.values || [])
    displays = Model.monitors(snapshot)
    applyFilter()
  }
  function applyFilter() {
    filtered = Model.filter(rows, query)
    selectedAddress = Model.selected(filtered, selectedAddress)
    Qt.callLater(revealSelected)
  }
  function ordered() {
    if (view === "compact") return filtered
    var orderedRows = []
    displays.forEach(function(d) { orderedRows = orderedRows.concat(filtered.filter(function(w) { return w.monitor === d.name; })) })
    return orderedRows
  }
  function selectStep(step) {
    var list = ordered()
    if (!list.length) return
    var index = list.findIndex(function(w) { return w.address === selectedAddress })
    selectedAddress = list[(index + step + list.length) % list.length].address
    revealSelected()
  }
  function selectMonitor(step) {
    var chosen = filtered.find(function(w) { return w.address === selectedAddress })
    if (!chosen) return
    var nonempty = displays.filter(function(d) { return filtered.some(function(w) { return w.monitor === d.name; }) })
    var index = nonempty.findIndex(function(d) { return d.name === chosen.monitor })
    var next = nonempty[index + step]
    if (!next) return
    selectedAddress = filtered.find(function(w) { return w.monitor === next.name }).address
    revealSelected()
  }
  function changeView(next) {
    view = next; viewRevision++
    saveTimer.restart()
    Qt.callLater(revealSelected)
    search.forceActiveFocus()
  }
  function toggleView() { changeView(view === "compact" ? "monitors" : "compact") }
  function activate(address) {
    if (!address || focusProc.running) return
    activationError = ""
    pendingAddress = address
    opened = false
    // Let the layer unmap and release exclusive keyboard focus first.
    focusDelay.restart()
  }
  function handleKey(event) {
    if (event.key === Qt.Key_Tab && (event.modifiers & Qt.AltModifier)) {
      if (!event.isAutoRepeat) toggleView()
    } else if (event.key === Qt.Key_E && (event.modifiers & Qt.MetaModifier)) {
      if (!event.isAutoRepeat) close()
    } else if (event.key === Qt.Key_Escape) close()
    else if (event.key === Qt.Key_Down) selectStep(1)
    else if (event.key === Qt.Key_Up) selectStep(-1)
    else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && search.activeFocus) activate(selectedAddress)
    else if (view === "monitors" && (!search.activeFocus || search.text.length === 0) && event.key === Qt.Key_Left) selectMonitor(-1)
    else if (view === "monitors" && (!search.activeFocus || search.text.length === 0) && event.key === Qt.Key_Right) selectMonitor(1)
    else return
    event.accepted = true
  }
  function revealSelected() {
    function visit(item) {
      if (item.windowData && item.windowData.address === selectedAddress) {
        var p = item.mapToItem(resultContent, 0, 0)
        if (p.y < scroll.contentY) scroll.contentY = p.y
        else if (p.y + item.height > scroll.contentY + scroll.height) scroll.contentY = p.y + item.height - scroll.height
        scroll.returnToBounds()
        return true
      }
      for (var i = 0; i < item.children.length; i++) if (visit(item.children[i])) return true
      return false
    }
    if (opened) visit(resultContent)
  }
  function iconFor(name) {
    return appLibrary ? appLibrary.iconSource(name) : Quickshell.iconPath(name || "application-x-executable", true)
  }

  Timer { interval: 1000; repeat: true; running: root.opened; onTriggered: root.refresh() }
  Timer {
    id: focusDelay
    interval: 120
    onTriggered: { focusProc.command = [root.helper, "focus", root.pendingAddress]; focusProc.running = true }
  }
  Timer {
    id: saveTimer
    interval: 100
    onTriggered: {
      if (stateWrite.running) { restart(); return }
      stateWrite.command = [root.helper, "view", root.view]; stateWrite.running = true
    }
  }
  Process {
    id: stateRead
    property int revision: 0
    command: [root.helper, "view"]
    stdout: StdioCollector {
      onStreamFinished: {
        var saved = text.trim()
        if (stateRead.revision === root.viewRevision && (saved === "compact" || saved === "monitors")) root.view = saved
      }
    }
  }
  Process {
    id: stateWrite
    onExited: function(code) { if (code !== 0) root.errorMessage = "Could not save view preference" }
  }
  Process {
    id: listProc
    property int session: 0
    command: [root.helper, "list", "--json"]
    stdout: StdioCollector { id: listOutput }
    onExited: function(code) {
      if (!root.opened || session !== root.session) { if (root.opened) Qt.callLater(root.refresh); return }
      root.loading = false
      if (code !== 0) { root.errorMessage = "Cannot read Hyprland windows. Retrying…"; return }
      try {
        var data = JSON.parse(listOutput.text)
        if (!Array.isArray(data.windows) || !Array.isArray(data.monitors)) throw new Error("Invalid response")
        root.errorMessage = ""
        if (listOutput.text !== root.lastSnapshot) {
          root.snapshot = data
          root.lastSnapshot = listOutput.text
          root.rebuild()
        }
      } catch (e) { root.errorMessage = "Invalid window data. Retrying…" }
    }
  }
  Process {
    id: focusProc
    stderr: StdioCollector { id: focusError }
    onExited: function(code) {
      root.pendingAddress = ""
      if (code !== 0) {
        root.opened = true
        root.activationError = focusError.text.trim() || "Could not focus that window"
        Qt.callLater(function() { search.forceActiveFocus() })
      }
    }
  }
  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { if (root.opened) root.rebuild() }
  }
  Connections {
    target: Quickshell
    function onScreensChanged() {
      if (root.opened && !Quickshell.screens.some(function(s) { return s.name === root.targetScreen.name; })) root.close()
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "daniel-window-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Ui.BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(640), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(610), panel.height - Style.gapsOut * 2)
      color: Color.menu.background
      radius: Style.cornerRadius
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      MouseArea { anchors.fill: parent; onClicked: {} }
      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.spacing.controlGap
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) { root.handleKey(event) }
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(12)
          Text { text: "󰖯"; color: Color.menu.text; font.family: Style.font.family; font.pixelSize: Style.font.display }
          ColumnLayout {
            spacing: Style.space(3)
            Text { text: "Windows"; color: Color.menu.text; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true }
            Text { text: "ALL WORKSPACES"; color: Util.alpha(Color.menu.text, 0.65); font.family: Style.font.family; font.pixelSize: Style.font.caption }
          }
          Item { Layout.fillWidth: true }
          Text { text: "Super E"; color: Color.menu.text; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        }
        RowLayout {
          Layout.fillWidth: true
          Ui.Button { text: "≡ Compact"; selected: root.view === "compact"; bordered: true; focusable: true; onClicked: root.changeView("compact") }
          Ui.Button { text: "◫ Monitors"; selected: root.view === "monitors"; bordered: true; focusable: true; onClicked: root.changeView("monitors") }
          Item { Layout.fillWidth: true }
          Ui.Button { text: "Alt + Tab ⇄"; fontSize: Style.font.bodySmall; onClicked: root.toggleView(); tooltipText: "Switch layout" }
        }
        Ui.TextField {
          id: search
          Layout.fillWidth: true
          placeholderText: "Search open windows…"
          onTextChanged: { root.query = text; root.applyFilter() }
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) { root.handleKey(event) }
        }
        Text {
          Layout.fillWidth: true
          visible: text.length > 0
          text: root.activationError || root.errorMessage || (root.loading ? "Loading windows…" : (!root.filtered.length ? (root.query ? "No matching windows" : "No windows on regular workspaces") : ""))
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.activationError || root.errorMessage ? Color.urgent : Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Flickable {
          id: scroll
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentWidth: width
          contentHeight: resultContent.height
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          Controls.ScrollBar.vertical: Controls.ScrollBar {}
          Column {
            id: resultContent
            width: scroll.width
            Loader {
              width: parent.width
              sourceComponent: root.view === "compact" ? compactView : monitorView
            }
          }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Util.alpha(Color.menu.text, 0.15) }
        RowLayout {
          Layout.fillWidth: true
          Text { text: root.view === "compact" ? "↑ ↓ Select" : "← ↑ ↓ → Select"; color: Util.alpha(Color.menu.text, 0.7); font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
          Item { Layout.fillWidth: true }
          Text { text: "↵ Switch · Esc Close"; color: Util.alpha(Color.menu.text, 0.7); font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        }
      }
    }
  }
  Component {
    id: compactView
    Column {
      Repeater {
        model: root.filtered
        WindowRow {
          required property var modelData
          width: parent.width
          windowData: modelData
          compact: true
          selected: root.selectedAddress === modelData.address
          iconSource: root.iconFor(modelData.icon)
          onActivate: function(address) { root.activate(address) }
        }
      }
    }
  }
  Component {
    id: monitorView
    Grid {
      id: board
      columns: width >= Style.space(500) && root.displays.length > 1 ? 2 : 1
      spacing: Style.spacing.panelGap
      Repeater {
        model: root.displays
        Column {
          id: monitorColumn
          required property var modelData
          width: (board.width - board.spacing * (board.columns - 1)) / board.columns
          Text { width: parent.width; text: "󰍹 " + monitorColumn.modelData.name; color: Color.menu.text; font.family: Style.font.family; font.pixelSize: Style.font.body; elide: Text.ElideRight; bottomPadding: Style.space(10) }
          Rectangle { width: parent.width; height: 1; color: Util.alpha(Color.menu.text, 0.15) }
          Repeater {
            model: Model.boardRows(root.filtered, monitorColumn.modelData.name)
            Loader {
              required property var modelData
              width: parent.width
              property var entry: modelData
              sourceComponent: modelData.header ? workspaceHeader : boardWindow
            }
          }
          Text {
            visible: !root.filtered.some(function(w) { return w.monitor === monitorColumn.modelData.name; })
            text: "No matches"; color: Util.alpha(Color.menu.text, 0.65); topPadding: Style.space(14)
            font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }
  Component {
    id: workspaceHeader
    Text {
      text: "WORKSPACE " + parent.entry.workspaceName
      textFormat: Text.PlainText
      color: Util.alpha(Color.menu.text, 0.65)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      topPadding: Style.space(14); bottomPadding: Style.space(6); leftPadding: Style.space(10)
    }
  }
  Component {
    id: boardWindow
    WindowRow {
      windowData: parent.entry
      selected: root.selectedAddress === windowData.address
      iconSource: root.iconFor(windowData.icon)
      onActivate: function(address) { root.activate(address) }
    }
  }
}
