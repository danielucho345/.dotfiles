import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Ui

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"
  readonly property string monitorHelper: home + "/.local/bin/wallpaper-monitor"

  property string currentBackground: ""
  property var monitorBackgrounds: ({})
  property int monitorVersion: 0
  property bool monitorReloadPending: false

  property string globalFromPath: ""
  property string globalDisplayPath: ""
  property string globalFinalPath: ""
  property bool globalInstant: false
  property int globalVersion: 0

  property int pendingThemeVersion: -1
  property string pendingColorsRaw: ""
  property string pendingShellRaw: ""

  function imageUrl(path) {
    return Util.fileUrl(path)
  }

  function monitorBackground(output) {
    var path = monitorBackgrounds[String(output || "")]
    return typeof path === "string" ? path : ""
  }

  function backgroundFor(output) {
    return monitorBackground(output) || currentBackground
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function reloadMonitorBackgrounds() {
    if (overrideLoadProc.running) {
      monitorReloadPending = true
      return
    }
    overrideLoadProc.running = true
  }

  function loadMonitorBackgrounds(raw) {
    var outputs = ({})
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      if (parsed && parsed.outputs && typeof parsed.outputs === "object") {
        for (var output in parsed.outputs) {
          var path = parsed.outputs[output]
          if (typeof path === "string" && path.trim()) outputs[output] = path.trim()
        }
      }
    } catch (e) {
      console.warn("daniel.background: ignoring invalid monitor state", e)
    }
    monitorBackgrounds = outputs
    monitorVersion += 1
  }

  function setMonitorBackground(output, path) {
    output = String(output || "").trim()
    path = String(path || "").trim()
    if (!output || !path) return

    var next = ({})
    for (var key in monitorBackgrounds) next[key] = monitorBackgrounds[key]
    next[output] = path
    monitorBackgrounds = next
    monitorVersion += 1
  }

  function clearMonitorBackground(output) {
    output = String(output || "").trim()
    if (!output || !monitorBackground(output)) return

    var next = ({})
    for (var key in monitorBackgrounds) {
      if (key !== output) next[key] = monitorBackgrounds[key]
    }
    monitorBackgrounds = next
    monitorVersion += 1
  }

  function setBackground(path, instant) {
    transitionBackground("", path, path, instant, false)
  }

  function transitionBackground(fromPath, path, finalPath, instant, force) {
    path = String(path || "").trim()
    finalPath = String(finalPath || path).trim()
    fromPath = String(fromPath || "").trim()
    if (!path || (!force && finalPath === currentBackground)) return

    currentBackground = finalPath
    globalFromPath = fromPath
    globalDisplayPath = path
    globalFinalPath = finalPath
    globalInstant = !!instant
    globalVersion += 1
  }

  function setPendingTheme(colorsB64, shellB64) {
    pendingColorsRaw = Util.decodeBase64(colorsB64)
    pendingShellRaw = Util.decodeBase64(shellB64)
    pendingThemeVersion = globalVersion
    pendingThemeFallbackTimer.restart()
  }

  function applyPendingTheme() {
    if (pendingThemeVersion < 0) return
    pendingThemeFallbackTimer.stop()
    Color.loadColors(pendingColorsRaw)
    Color.loadShell(pendingShellRaw)
    Style.scheduleRefresh()
    pendingThemeVersion = -1
    pendingColorsRaw = ""
    pendingShellRaw = ""
  }

  function transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64) {
    transitionBackground(fromPath, path, finalPath, false, true)
    setPendingTheme(colorsB64, shellB64)
  }

  function openSelector() {
    if (!bgSwitchProc.running) bgSwitchProc.running = true
  }

  function openThemeSwitcher() {
    if (!themeSwitchProc.running) themeSwitchProc.running = true
  }

  Process {
    id: bgSwitchProc
    command: ["bash", "-c", "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""]
    onExited: root.refreshBackground()
  }

  Process {
    id: themeSwitchProc
    command: ["bash", "-c", "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\" >/dev/null 2>&1 &"]
    onExited: root.refreshBackground()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: root.setBackground(String(text || "").trim(), false)
    }
  }

  Process {
    id: overrideLoadProc
    command: [root.monitorHelper, "dump"]
    stdout: StdioCollector {
      onStreamFinished: root.loadMonitorBackgrounds(text)
    }
    onExited: {
      if (root.monitorReloadPending) {
        root.monitorReloadPending = false
        Qt.callLater(root.reloadMonitorBackgrounds)
      }
    }
  }

  IpcHandler {
    target: "background"

    function refresh(): void {
      root.refreshBackground()
    }

    function set(path: string): void {
      root.setBackground(path, false)
    }

    function setInstant(path: string): void {
      root.setBackground(path, true)
    }

    function transition(fromPath: string, path: string): void {
      root.transitionBackground(fromPath, path, path, false, false)
    }

    function themeTransition(fromPath: string, path: string, finalPath: string, colorsB64: string, shellB64: string): void {
      root.transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64)
    }

    function setMonitor(output: string, path: string): void {
      root.setMonitorBackground(output, path)
    }

    function clearMonitor(output: string): void {
      root.clearMonitorBackground(output)
    }

    function reloadMonitors(): void {
      root.reloadMonitorBackgrounds()
    }
  }

  Timer {
    id: pendingThemeFallbackTimer
    interval: 300
    repeat: false
    onTriggered: root.applyPendingTheme()
  }

  Component.onCompleted: {
    refreshBackground()
    reloadMonitorBackgrounds()
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: !remapGuard.remapping
      anchors { top: true; bottom: true; left: true; right: true }

      ScreenMoveRemap {
        id: remapGuard
        window: panel
      }
      color: "transparent"
      updatesEnabled: true

      readonly property string outputName: modelData && modelData.name ? String(modelData.name) : ""
      property string targetBackground: ""
      property string displayedBackground: ""
      property string incomingBackground: ""
      property string oldBackground: ""
      property bool finishingTransition: false
      property bool maskReady: false
      property real revealProgress: 1
      property int transitionVersion: 0
      property int revealStartedVersion: -1

      function transitionTo(fromPath, path, finalPath, instant) {
        path = String(path || "").trim()
        finalPath = String(finalPath || path).trim()
        fromPath = String(fromPath || "").trim()
        if (!path || finalPath === targetBackground) return

        targetBackground = finalPath
        transitionVersion += 1
        revealStartedVersion = -1
        revealAnimation.stop()
        finishingTransition = false
        maskReady = false

        if (instant || !displayedBackground) {
          oldBackground = ""
          incomingBackground = ""
          displayedBackground = finalPath
          revealProgress = 1
          return
        }

        oldBackground = fromPath || displayedBackground
        incomingBackground = path
        revealProgress = 0
      }

      function syncMonitorBackground(instant) {
        var path = root.backgroundFor(outputName)
        transitionTo("", path, path, instant)
      }

      function syncGlobalBackground() {
        if (root.monitorBackground(outputName)) return
        transitionTo(root.globalFromPath, root.globalDisplayPath, root.globalFinalPath, root.globalInstant)
      }

      function maybeStartReveal() {
        if (!incomingBackground || revealProgress !== 0 || maskReady) return
        if (incomingFrame.status !== Image.Ready) return
        Qt.callLater(function() {
          if (!panel.incomingBackground || panel.revealProgress !== 0 || panel.maskReady) return
          if (incomingFrame.status !== Image.Ready) return
          panel.maskReady = true
          if (panel.revealStartedVersion === panel.transitionVersion) return
          panel.revealStartedVersion = panel.transitionVersion
          root.applyPendingTheme()
          revealAnimation.restart()
        })
      }

      WlrLayershell.namespace: "omarchy-background"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      Image {
        id: base
        anchors.fill: parent
        source: root.imageUrl(panel.displayedBackground)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        onStatusChanged: {
          if (status === Image.Ready && panel.finishingTransition) {
            panel.incomingBackground = ""
            panel.oldBackground = ""
            panel.finishingTransition = false
          }
        }
      }

      Image {
        id: oldFrame
        anchors.fill: parent
        source: root.imageUrl(panel.oldBackground)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        visible: panel.oldBackground !== "" && panel.revealProgress < 1
        onStatusChanged: panel.maybeStartReveal()
      }

      Item {
        id: incomingLayer
        anchors.fill: parent
        visible: panel.incomingBackground !== "" && incomingFrame.status === Image.Ready && (panel.revealProgress >= 1 || panel.maskReady)
        layer.enabled: panel.incomingBackground !== "" && panel.revealProgress < 1
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: revealMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 0.02
        }

        Image {
          id: incomingFrame
          anchors.fill: parent
          source: root.imageUrl(panel.incomingBackground)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          smooth: true
          mipmap: true
          onStatusChanged: panel.maybeStartReveal()
        }
      }

      Item {
        id: revealMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        readonly property real slant: -0.18
        readonly property real centerTop: width / 2 - slant * height / 2
        readonly property real centerBottom: width / 2 + slant * height / 2
        readonly property real reach: width / 2 + Math.abs(slant) * height / 2 + 4
        readonly property real spread: reach * panel.revealProgress

        Shape {
          anchors.fill: parent
          antialiasing: true
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            fillColor: "white"
            strokeColor: "transparent"
            startX: revealMask.centerTop - revealMask.spread; startY: 0
            PathLine { x: revealMask.centerTop + revealMask.spread; y: 0 }
            PathLine { x: revealMask.centerBottom + revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerBottom - revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerTop - revealMask.spread; y: 0 }
          }
        }
      }

      NumberAnimation {
        id: revealAnimation
        target: panel
        property: "revealProgress"
        from: 0
        to: 1
        duration: 420
        easing.type: Easing.InOutCubic
        onFinished: {
          if (panel.incomingBackground) {
            panel.displayedBackground = panel.targetBackground || panel.incomingBackground
            panel.finishingTransition = true
          }
          panel.revealProgress = 1
        }
      }

      Connections {
        target: root
        function onGlobalVersionChanged() { panel.syncGlobalBackground() }
        function onMonitorVersionChanged() { panel.syncMonitorBackground(false) }
      }

      Component.onCompleted: syncMonitorBackground(true)

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.openThemeSwitcher()
          else root.openSelector()
          mouse.accepted = true
        }
      }
    }
  }
}
