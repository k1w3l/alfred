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
  property bool faceTrayAway: false
  property bool faceBusy: false
  property bool popoutSwitchClosing: false
  property real publishedX: -99999
  property real publishedY: -99999
  readonly property string trayPath: (Quickshell.env("HOME") || "") + "/.config/Hermes/alfred-tray.json"
  // The face is away from the icon while it is on the HUD, or flying to or from
  // it. The service reads directly when this bar has it; the snapshot file
  // covers the replacement bar, which never receives the service object.
  readonly property bool blobAway: alfred ? alfred.trayAway === true : root.faceTrayAway

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
    root.faceTrayAway = parsed.trayAway === true
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
      trayFile.reload()
      root.publishTray()
    }
  }

  // Every monitor has its own bar and icon, and the HUD flies from the icon of
  // the screen it opened on. Each bar writes its own entry under its screen
  // name; the file keeps the other bars' entries and x/y/s is the last writer.
  readonly property string screenName: {
    var q = root.QsWindow
    var win = q ? q.window : null
    var scr = win ? win.screen : null
    return scr ? String(scr.name || "") : ""
  }
  // The bar's own screen, and whether the pointer is on it. Only that bar's
  // icon looks at the pointer, so one face follows the cursor at a time.
  readonly property var barScreen: {
    var q = root.QsWindow
    var win = q ? q.window : null
    return win ? win.screen : null
  }
  readonly property bool cursorHere: {
    var scr = root.barScreen
    var x = root.alfred ? root.alfred.cursorX : NaN
    var y = root.alfred ? root.alfred.cursorY : NaN
    if (!scr || !isFinite(x) || !isFinite(y)) return false
    return x >= scr.x && x < scr.x + scr.width && y >= scr.y && y < scr.y + scr.height
  }
  property var trayMap: ({})
  property string trayMapSig: ""

  FileView {
    id: trayFile
    path: root.trayPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.mergeTrayFile(text())
  }

  function mergeTrayFile(content) {
    var parsed = null
    try {
      parsed = JSON.parse(String(content || ""))
    } catch (e) {
      return
    }
    if (!parsed || typeof parsed !== "object" || !parsed.screens) return
    var next = Object.assign({}, root.trayMap)
    var names = Object.keys(parsed.screens)
    for (var i = 0; i < names.length; i++) {
      var name = names[i]
      // Our own entry is authoritative in memory; the file is only newer for others.
      if (name === root.screenName && next[name]) continue
      next[name] = parsed.screens[name]
    }
    // Another bar's write can drop our entry (last writer wins). Re-add it from memory.
    var own = root.screenName
    var lost = own !== "" && next[own] !== undefined && parsed.screens[own] === undefined
    var sig = JSON.stringify(next)
    if (sig !== root.trayMapSig) {
      root.trayMapSig = sig
      root.trayMap = next
      if (alfred && typeof alfred.setTrayRect === "function") {
        var keys = Object.keys(next)
        for (var j = 0; j < keys.length; j++) alfred.setTrayRect(keys[j], next[keys[j]])
      }
    }
    if (lost) root.writeTrayFile(next, next[own])
  }

  // Every bar's entry, so a write never erases another screen's icon.
  function mergedTrayMap() {
    return Object.assign({}, root.trayMap, alfred ? alfred.trayRects : {})
  }

  function writeTrayFile(map, rect) {
    trayFile.setText(JSON.stringify({ screens: map, x: rect.x, y: rect.y, s: rect.s }) + "\n")
  }

  function publishTray() {
    if (button.width < 2 || button.height < 2) return
    var size = Style.bar.iconCanvas
    var top = button.mapToGlobal((button.width - size) / 2, (button.height - size) / 2)
    // Skips only the in-memory and file update. mergeTrayFile self-heals on every reload.
    if (Math.abs(top.x - root.publishedX) < 0.5 && Math.abs(top.y - root.publishedY) < 0.5) return
    root.publishedX = top.x
    root.publishedY = top.y
    var rect = { x: top.x, y: top.y, s: size }
    var next = Object.assign({}, root.trayMap)
    if (root.screenName !== "") next[root.screenName] = rect
    root.trayMap = next
    root.trayMapSig = JSON.stringify(next)
    if (alfred) {
      alfred.trayX = top.x
      alfred.trayY = top.y
      alfred.trayS = size
      if (root.screenName !== "" && typeof alfred.setTrayRect === "function") alfred.setTrayRect(root.screenName, rect)
    }
    root.writeTrayFile(root.mergedTrayMap(), rect)
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
    cursorX: root.alfred ? root.alfred.cursorX : NaN
    cursorY: root.alfred ? root.alfred.cursorY : NaN
    cursorAt: root.alfred ? root.alfred.cursorAt : 0
    lookEnabled: !root.blobAway && root.cursorHere
    // Leaving the icon is instant: the hero starts at the icon's size in the
    // same frame. Returning fades in on the 160 ms curve, as the hero fades out.
    opacity: root.blobAway ? 0 : 1
    visible: opacity > 0
    Behavior on opacity {
      enabled: !root.blobAway
      NumberAnimation {
        duration: 160
        easing.type: Easing.OutCubic
      }
    }
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
