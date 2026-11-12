import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "kiwel.alfred"

  readonly property var alfred: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(root.moduleName) : null
  readonly property bool opened: alfred ? alfred.hudOpen === true : false
  // A replacement bar's shell facade has no service lookup, so this widget
  // never sees profileFill. The service writes the face; the tray reads it.
  readonly property string facePath: (Quickshell.env("HOME") || "") + "/.config/Hermes/alfred-face.json"
  property string faceKey: "local:default"
  property string faceShape: "cercle"
  property string faceFill: "#0a0a0c"
  property string faceExpression: "neutre"
  property int faceIdle: 0
  property real facePhase: 0
  property string faceEyes: "soft"
  property string faceLabel: "Alfred"
  property string faceMood: "idle"
  property bool faceHudOpen: false
  property bool faceBusy: false
  property bool popoutSwitchClosing: false
  property real publishedX: -99999
  property real publishedY: -99999
  readonly property string trayPath: (Quickshell.env("HOME") || "") + "/.config/Hermes/alfred-tray.json"
  // The face lives in the overlay while the HUD is open. The file covers the
  // replacement bar, which never receives the service object.
  readonly property bool blobAway: alfred ? alfred.hudOpen === true : root.faceHudOpen

  function applyFace(content) {
    var parsed = null
    try {
      parsed = JSON.parse(String(content || ""))
    } catch (e) {
      return
    }
    if (!parsed || typeof parsed !== "object") return
    root.faceKey = String(parsed.key || "local:default")
    root.faceShape = String(parsed.shape || "cercle")
    root.faceFill = String(parsed.fill || "#0a0a0c")
    root.faceExpression = String(parsed.expression || "neutre")
    root.faceIdle = Number(parsed.idle || 0)
    root.facePhase = Number(parsed.phase || 0)
    root.faceEyes = String(parsed.eyes || "soft")
    root.faceLabel = String(parsed.label || "Alfred")
    root.faceMood = String(parsed.mood || "idle")
    root.faceHudOpen = parsed.hudOpen === true
    root.faceBusy = root.faceMood === "busy" || root.faceMood === "working" || root.faceMood === "listening"
  }

  FileView {
    id: faceFile
    path: root.facePath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyFace(text())
    onFileChanged: reload()
  }

  // FileView does not attach to a path that does not exist yet, and a burst
  // of writes can drop the watch. Reloading the snapshot keeps the tray current.
  Timer {
    interval: 250
    repeat: true
    running: true
    onTriggered: {
      faceFile.reload()
      root.publishTray()
    }
  }

  FileView {
    id: trayFile
    path: root.trayPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  function publishTray() {
    if (button.width < 2 || button.height < 2) return
    var size = Style.bar.iconCanvas
    var top = button.mapToGlobal((button.width - size) / 2, (button.height - size) / 2)
    if (Math.abs(top.x - root.publishedX) < 0.5 && Math.abs(top.y - root.publishedY) < 0.5) return
    root.publishedX = top.x
    root.publishedY = top.y
    if (alfred) {
      alfred.trayX = top.x
      alfred.trayY = top.y
      alfred.trayS = size
    }
    trayFile.setText(JSON.stringify({ x: top.x, y: top.y, s: size }) + "\n")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function open() {
    root.focusHud()
  }

  function close() {
    root.hideHud()
  }

  function toggle() {
    if (root.opened && alfred && alfred.hudFocused) root.hideHud()
    else root.focusHud()
  }

  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    root.hideHud()
    Qt.callLater(function() { popoutSwitchClosing = false })
  }

  function focusHud() {
    if (alfred && typeof alfred.requestFocus === "function") alfred.requestFocus()
    else if (root.bar) root.bar.run("omarchy-shell kiwel.alfred focus")
  }

  function hideHud() {
    if (alfred && typeof alfred.requestHide === "function") alfred.requestHide()
    else if (root.bar) root.bar.run("omarchy-shell kiwel.alfred hide")
  }

  function launchDesktop() {
    if (alfred && typeof alfred.launchDesktop === "function") alfred.launchDesktop()
    else if (root.bar) root.bar.run("hermes-desktop")
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    active: root.faceBusy || root.faceMood === "error"
    tooltipText: root.faceBusy
      ? (root.faceLabel + " is working")
      : (root.faceMood === "error"
        ? (root.faceLabel + " — something needs attention")
        : (root.faceLabel + " — click to open · right-click for Desktop"))
    // The face is a sibling, not this component. `root` inside a component
    // loaded by BarIconButton resolves to the button, so the face never saw
    // a profile change.
    iconComponent: Component {
      Item {}
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchDesktop()
      else if (buttonCode === Qt.MiddleButton) root.hideHud()
      else root.focusHud()
    }
  }

  ProfileBlob {
    anchors.centerIn: button
    width: Style.bar.iconCanvas
    height: Style.bar.iconCanvas
    enabled: false
    visible: !root.blobAway
    z: 2
    agentId: root.faceKey
    slot: "tray"
    shape: root.faceShape
    fill: root.faceFill
    expression: root.faceExpression
    idleVariant: root.faceIdle
    phase: root.facePhase
    eyes: root.faceEyes
    mood: root.faceMood
    pose: (root.faceMood === "busy" || root.faceMood === "working") ? "idle" : ""
  }
}
