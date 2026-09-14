import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "AlfredModel.js" as AlfredModel
import "ComposerTheme.js" as Theme

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null

  property bool opened: false
  property bool focused: false

  readonly property var alfred: service ? service : (shell && typeof shell.serviceFor === "function" ? shell.serviceFor("kiwel.alfred") : null)
  readonly property bool busy: alfred ? alfred.busy === true : false
  readonly property bool listening: alfred ? alfred.listening === true : false
  readonly property bool gatewayActive: alfred ? alfred.gatewayActive === true : false
  readonly property var messages: alfred && alfred.messages ? alfred.messages : []
  readonly property var attachments: alfred && alfred.attachments ? alfred.attachments : []
  readonly property string lastError: alfred ? String(alfred.lastError || "") : ""
  readonly property string lastReply: alfred ? String(alfred.lastReply || "") : ""
  readonly property bool compact: root.opened && !root.focused
  readonly property bool picking: alfred ? alfred.pickingFiles === true : false
  readonly property bool transcribing: alfred ? alfred.transcribing === true : false
  readonly property bool awaitingPermission: alfred ? alfred.awaitingPermission === true : false
  readonly property string lastOutcome: alfred ? String(alfred.lastOutcome || "") : ""
  readonly property string modelName: alfred ? String(alfred.modelName || "") : ""
  readonly property var modelOptions: alfred && alfred.modelOptions ? alfred.modelOptions : []
  property string menuKind: ""
  property string pickerMode: ""
  readonly property bool menuOpen: root.menuKind !== ""
  readonly property bool pickerOpen: root.pickerMode !== ""
  readonly property bool hasPayload: (composerInput ? String(composerInput.text || "").trim() !== "" : false) || root.attachments.length > 0
  readonly property bool showVoicePrimary: !root.busy && !root.hasPayload
  readonly property bool showStop: root.busy && !root.hasPayload
  readonly property var slashItems: alfred && alfred.slashItems ? alfred.slashItems : []
  readonly property bool slashLoading: alfred ? alfred.slashLoading === true : false
  property int slashIndex: 0
  property bool slashDismissed: false
  property string slashDraft: ""
  readonly property bool slashPanelOpen: root.focused && !root.pickerOpen && !root.menuOpen && !root.busy && root.slashDraft !== "" && !root.slashDismissed
  readonly property bool slashOpen: root.slashPanelOpen && root.slashItems.length > 0
  readonly property var slashViewRows: {
    var items = root.slashItems
    var rows = []
    var last = "\u0001"
    var i
    for (i = 0; i < items.length; i++) {
      var it = items[i]
      var g = String(it.group || "")
      if (g !== last) {
        rows.push({ rowType: "header", group: g, itemIndex: -1, text: "", display: "", meta: "", kind: "" })
        last = g
      }
      rows.push({
        rowType: "item",
        group: g,
        itemIndex: i,
        text: String(it.text || ""),
        display: String(it.display || it.text || ""),
        meta: String(it.meta || ""),
        kind: String(it.kind || "")
      })
    }
    return rows
  }
  readonly property bool showThread: root.focused && !root.busy && !root.listening && !root.slashPanelOpen && (root.lastError !== "" || root.messages.length > 0 || root.attachments.length > 0)
  readonly property string mood: {
    if (root.listening) return "listening"
    if (root.awaitingPermission) return "permission"
    if (root.busy) return "busy"
    if (root.lastError !== "" || root.lastOutcome === "error") return "error"
    if (root.lastOutcome === "success") return "success"
    return "idle"
  }
  readonly property color moodColor: {
    if (root.mood === "listening" || root.mood === "error") return Theme.moodRed()
    if (root.mood === "permission") return Theme.moodYellow()
    if (root.mood === "success") return Theme.moodGreen()
    if (root.mood === "busy") return Color.accent
    return Color.accent
  }

  readonly property color foreground: Color.foreground
  readonly property color dim: Color.muted
  readonly property color surface: Util.alpha(Qt.darker(Color.background, 1.45), 0.94)
  readonly property color sheet: Util.alpha(Qt.darker(Color.background, 1.25), 0.92)
  readonly property color rim: {
    if (root.mood === "idle") return Util.alpha(Color.accent, root.focused ? 0.55 : 0.28)
    return root.moodColor
  }
  readonly property string fontFamily: Style.font.family
  readonly property int ballSize: Math.max(Style.space(52), Style.font.title + Style.space(28))
  readonly property int pillWidth: root.focused ? Style.space(720) : root.ballSize
  readonly property int pillHeight: root.ballSize
  readonly property int controlGap: Style.space(Theme.gapPx())
  readonly property int surfacePadX: Style.space(Theme.padXPx())
  readonly property int surfacePadY: Style.space(Theme.padYPx())
  readonly property int bandMaxHeight: Style.space(280)
  property string hudScreenName: ""
  readonly property var activeScreen: root.screenByName(root.hudScreenName) || root.focusedScreen()

  function screenByName(name) {
    var want = String(name || "")
    var screens = Quickshell.screens
    var i
    if (want === "") return null
    for (i = 0; i < screens.length; i++) {
      if (String(screens[i].name || "") === want) return screens[i]
    }
    return null
  }

  function pinHudScreen() {
    var s = root.focusedScreen()
    root.hudScreenName = s ? String(s.name || "") : ""
  }

  function focusedScreen() {
    var mon = Hyprland.focusedMonitor
    var name = mon ? String(mon.name || "") : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (name !== "" && String(screens[i].name || "") === name) return screens[i]
    }
    return screens.length > 0 ? screens[0] : null
  }

  function open(payloadJson) {
    root.focusHud()
  }

  function close() {
    root.hideHud()
  }

  function toggle() {
    if (root.focused) root.hideHud()
    else root.focusHud()
  }

  function hideHud() {
    grabFocusTimer.stop()
    root.closeMenus()
    root.closePicker()
    root.closeSlash()
    if (alfred && alfred.listening && typeof alfred.cancelVoice === "function") alfred.cancelVoice()
    root.focused = false
    root.opened = false
    root.hudScreenName = ""
    if (composerInput) composerInput.focus = false
    if (alfred) {
      alfred.hudOpen = false
      alfred.hudFocused = false
    }
  }

  function unfocusHud() {
    grabFocusTimer.stop()
    root.closeMenus()
    root.closePicker()
    root.focused = false
    root.opened = true
    if (composerInput) composerInput.focus = false
    if (alfred) {
      alfred.hudOpen = true
      alfred.hudFocused = false
    }
  }

  function focusHud() {
    if (!root.opened) root.pinHudScreen()
    root.opened = true
    root.focused = true
    if (alfred) {
      alfred.hudOpen = true
      alfred.hudFocused = true
    }
    grabFocusTimer.tries = 0
    grabFocusTimer.restart()
    if (alfred && typeof alfred.prefetchSlash === "function") alfred.prefetchSlash()
    Qt.callLater(root.syncSlash)
  }

  function submit() {
    var prompt = composerInput ? String(composerInput.text || "").trim() : ""
    if (!alfred || typeof alfred.sendPrompt !== "function") return
    if (alfred.sendPrompt(prompt)) {
      if (composerInput) composerInput.text = ""
    }
  }

  function sendText(text) {
    if (composerInput) composerInput.text = String(text || "")
    root.submit()
  }

  property var menuRows: []

  function closeMenus() {
    root.menuKind = ""
    root.menuRows = []
  }

  function closePicker() {
    root.pickerMode = ""
  }

  function closeSlash() {
    root.slashDraft = ""
    root.slashDismissed = false
    root.slashIndex = 0
    if (alfred && typeof alfred.clearSlash === "function") alfred.clearSlash()
  }

  function syncSlash() {
    if (!composerInput) return
    var q = AlfredModel.slashQueryFrom(composerInput.text)
    if (q !== root.slashDraft) {
      root.slashDismissed = false
      root.slashIndex = 0
    }
    root.slashDraft = q
    if (q === "" || root.slashDismissed || root.busy) {
      if (q === "" && alfred && typeof alfred.clearSlash === "function") alfred.clearSlash()
      return
    }
    root.closeMenus()
    if (alfred && typeof alfred.refreshSlash === "function")
      alfred.refreshSlash(String(composerInput.text || ""))
  }

  function moveSlash(delta) {
    var n = root.slashItems.length
    if (n === 0) return
    var next = root.slashIndex + delta
    if (next < 0) next = 0
    if (next > n - 1) next = n - 1
    root.slashIndex = next
  }

  function slashRowY(itemIndex) {
    var rows = root.slashViewRows
    var y = 0
    var i
    for (i = 0; i < rows.length; i++) {
      var h = rows[i].rowType === "header" ? Style.space(22) : Style.space(40)
      if (rows[i].itemIndex === itemIndex) return y
      y += h
    }
    return 0
  }

  function applySlashAt(index) {
    var items = root.slashItems
    if (index < 0 || index >= items.length) return
    var cmd = String(items[index].text || "")
    if (composerInput) {
      composerInput.text = AlfredModel.applySlashInsert(composerInput.text, cmd)
      composerInput.cursorPosition = String(composerInput.text || "").length
      composerInput.forceActiveFocus()
    }
    root.slashDismissed = true
    root.slashDraft = composerInput ? AlfredModel.slashQueryFrom(composerInput.text) : ""
  }

  function tryApplySlash() {
    if (!root.slashPanelOpen) return false
    if (root.slashItems.length === 0) return true
    root.applySlashAt(root.slashIndex)
    return true
  }

  function openPicker(mode) {
    root.closeMenus()
    root.pickerMode = String(mode || "files")
    grabFocusTimer.stop()
  }

  function rebuildMenu() {
    var rows = []
    var i
    if (root.menuKind === "attach") {
      rows = [
        { id: "files", icon: "file", label: "Files", checked: false },
        { id: "folder", icon: "folder", label: "Folder", checked: false },
        { id: "images", icon: "file-media", label: "Images", checked: false },
        { id: "paste", icon: "copy", label: "Paste image", checked: false }
      ]
    } else if (root.menuKind === "voice") {
      rows = [
        { id: "conversation", icon: "audio-lines", label: "Start voice conversation", checked: false },
        { id: "dictate", icon: "mic", label: root.listening ? "Stop dictation" : "Voice dictation", checked: root.listening }
      ]
    } else if (root.menuKind === "model") {
      for (i = 0; i < root.modelOptions.length; i++) {
        rows.push({
          id: String(root.modelOptions[i]),
          icon: "",
          label: String(root.modelOptions[i]),
          checked: String(root.modelOptions[i]) === root.modelName
        })
      }
    }
    root.menuRows = rows
  }

  function toggleMenu(kind) {
    root.closePicker()
    root.menuKind = root.menuKind === kind ? "" : kind
    if (root.menuKind === "") {
      root.menuRows = []
      return
    }
    if (root.menuKind === "model" && alfred && typeof alfred.refreshModels === "function")
      alfred.refreshModels()
    root.rebuildMenu()
  }

  function activateMenuItem(item) {
    var id = item && item.id ? String(item.id) : ""
    if (root.menuKind === "attach") {
      root.pickKind(id)
      return
    }
            if (root.menuKind === "voice") {
      if (id === "conversation" || id === "dictate") root.startListen()
      return
    }
    if (root.menuKind === "model") root.chooseModel(id)
  }

  function copyText(value) {
    if (alfred && typeof alfred.copyText === "function") alfred.copyText(value)
  }

  function removeAttachment(path) {
    if (alfred && typeof alfred.removeAttachment === "function") alfred.removeAttachment(path)
  }

  function pickKind(kind) {
    var mode = String(kind || "files")
    root.closeMenus()
    if (mode === "paste") {
      if (alfred && typeof alfred.pickFiles === "function") alfred.pickFiles("paste")
      return
    }
    root.openPicker(mode)
  }

  function openDesktop() {
    root.hideHud()
    if (alfred && typeof alfred.launchDesktop === "function") alfred.launchDesktop()
  }

  function chooseModel(name) {
    root.closeMenus()
    if (alfred && typeof alfred.setModel === "function") alfred.setModel(name)
  }

  function startListen() {
    root.closeMenus()
    if (alfred && typeof alfred.startVoice === "function") alfred.startVoice()
    root.unfocusHud()
  }

  function stopListen() {
    if (alfred && typeof alfred.stopVoice === "function") alfred.stopVoice()
    root.focusHud()
  }

  function toggleVoice() {
    if (root.listening) root.stopListen()
    else root.startListen()
  }

  function handlePrimary() {
    if (root.showStop) {
      if (alfred && typeof alfred.abortSend === "function") alfred.abortSend()
      return
    }
    if (root.showVoicePrimary) {
      root.startListen()
      return
    }
    root.submit()
  }

  function handleEscape() {
    if (root.pickerOpen) {
      root.closePicker()
      grabFocusTimer.tries = 0
      grabFocusTimer.restart()
      return
    }
    if (root.slashPanelOpen) {
      root.slashDismissed = true
      if (alfred && typeof alfred.clearSlash === "function") alfred.clearSlash()
      return
    }
    if (root.menuOpen) {
      root.closeMenus()
      return
    }
    if (root.busy) root.unfocusHud()
    else root.hideHud()
  }

  Timer {
    id: grabFocusTimer
    property int tries: 0
    interval: 50
    repeat: true
    onTriggered: {
      tries += 1
      if (root.opened && root.focused) {
        if (root.pickerOpen) {
          stop()
          tries = 0
          return
        }
        if (root.busy) escScope.forceActiveFocus()
        else if (composerInput) composerInput.forceActiveFocus()
      }
      var gotIt = root.busy ? escScope.activeFocus : (composerInput && composerInput.activeFocus)
      if (!root.focused || gotIt || tries >= 16) {
        stop()
        tries = 0
      }
    }
  }

  Connections {
    target: root.alfred
    function onFocusRequested() { root.focusHud() }
    function onCompactRequested() { root.unfocusHud() }
    function onHideRequested() { root.hideHud() }
    function onTranscriptReady(text) {
      var t = String(text || "").trim()
      if (composerInput && t !== "") {
        var cur = String(composerInput.text || "").trim()
        composerInput.text = cur === "" ? t : (cur + " " + t)
      }
      if (root.opened) root.focusHud()
    }
  }

  FontLoader {
    id: menuCodicon
    source: Qt.resolvedUrl("fonts/codicon.ttf")
  }

  readonly property var attachItems: [
    { action: "files", iconName: "file", rowLabel: "Files" },
    { action: "folder", iconName: "folder", rowLabel: "Folder" },
    { action: "images", iconName: "file-media", rowLabel: "Images" },
    { action: "paste", iconName: "copy", rowLabel: "Paste image" }
  ]

  onListeningChanged: {
    if (root.menuKind === "voice") root.rebuildMenu()
  }

  onModelOptionsChanged: {
    if (root.menuKind === "model") root.rebuildMenu()
  }

  onModelNameChanged: {
    if (root.menuKind === "model") root.rebuildMenu()
  }

  onAwaitingPermissionChanged: {
    if (root.awaitingPermission && root.opened) root.unfocusHud()
  }

  onBusyChanged: {
    if (!root.focused) return
    if (root.busy) {
      grabFocusTimer.stop()
      escScope.forceActiveFocus()
    } else {
      grabFocusTimer.tries = 0
      grabFocusTimer.restart()
    }
  }

  onSlashItemsChanged: {
    if (root.slashIndex >= root.slashItems.length)
      root.slashIndex = Math.max(0, root.slashItems.length - 1)
  }

  onSlashIndexChanged: {
    if (!slashList || !root.slashOpen) return
    var y = root.slashRowY(root.slashIndex)
    var top = slashList.contentY
    var bottom = top + slashList.height
    var rowH = Style.space(40)
    if (y < top) slashList.contentY = Math.max(0, y)
    else if (y + rowH > bottom) slashList.contentY = Math.max(0, y + rowH - slashList.height)
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.activeScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "kiwel-alfred"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: root.focused ? screenMask : pillMask

    Region {
      id: screenMask
      width: panel.width
      height: panel.height
    }

    Region {
      id: pillMask
      item: hudColumn
    }

    FocusScope {
      id: escScope
      anchors.fill: parent
      focus: root.focused
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.handleEscape()
          event.accepted = true
          return
        }
        if (event.matches(StandardKey.Copy)) {
          var fieldSel = composerInput ? String(composerInput.selectedText || "") : ""
          if (composerInput && composerInput.activeFocus && fieldSel !== "") return
          var payload = fieldSel !== "" ? fieldSel : root.lastReply
          if (payload === "" && root.lastError !== "") payload = root.lastError
          if (payload !== "") {
            root.copyText(payload)
            event.accepted = true
          }
        }
      }

    MouseArea {
      z: -1
      anchors.fill: parent
      enabled: root.focused
      hoverEnabled: false
      onPressed: function(mouse) {
        var p = mapToItem(hudColumn, mouse.x, mouse.y)
        if (p.x >= 0 && p.y >= 0 && p.x <= hudColumn.width && p.y <= hudColumn.height) {
          mouse.accepted = false
          return
        }
        mouse.accepted = true
        if (root.pickerOpen) {
          root.closePicker()
          return
        }
        if (root.menuOpen) {
          root.closeMenus()
          return
        }
        root.unfocusHud()
      }
    }

    Column {
      id: hudColumn
      width: root.pillWidth
      spacing: 0
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Style.bar.sizeHorizontal + Style.gapsOut + Style.space(12)
      z: 2

      Behavior on width {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
      }

      Rectangle {
        id: pill
        width: parent.width
        height: root.pillHeight
        radius: root.compact ? height / 2 : Style.space(Theme.arcRadiusPx())
        color: root.surface
        border.width: root.mood === "idle" ? 1 : 2
        border.color: root.rim
        clip: true

        GlowRing {
          anchors.fill: parent
          z: 0
          running: root.listening || (root.busy && !root.awaitingPermission)
          accent: root.listening ? Theme.moodRed() : root.foreground
        }

        MouseArea {
          anchors.fill: parent
          z: 10
          enabled: root.compact
          hoverEnabled: !root.listening
          cursorShape: Qt.PointingHandCursor
          onEntered: {
            if (!root.listening) root.focusHud()
          }
          onClicked: {
            if (root.listening) root.stopListen()
            else root.focusHud()
          }
        }

        Item {
          visible: root.compact
          z: 3
          anchors.centerIn: parent
          width: Style.space(22)
          height: Style.space(22)

          Rectangle {
            visible: root.mood === "listening"
            anchors.centerIn: parent
            width: Style.space(Theme.stopPx())
            height: Style.space(Theme.stopPx())
            radius: Style.space(3)
            color: Theme.moodRed()
          }

          Text {
            visible: root.mood !== "listening"
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.mood === "permission"
              ? Theme.glyph("lock")
              : (root.mood === "error"
                ? Theme.glyph("close")
                : (root.mood === "success" ? Theme.glyph("check") : AlfredModel.butlerGlyph()))
            color: root.mood === "idle" || root.mood === "busy" ? (root.busy ? Color.accent : root.foreground) : root.moodColor
            font.family: root.mood === "idle" || root.mood === "busy" ? root.fontFamily : (menuCodicon.name !== "" ? menuCodicon.name : "codicon")
            font.pixelSize: Style.font.title
          }
        }

        RowLayout {
          id: pillRow
          z: 4
          visible: root.focused
          spacing: root.controlGap
          anchors.fill: parent
          anchors.leftMargin: root.surfacePadX
          anchors.rightMargin: root.surfacePadX
          anchors.topMargin: root.surfacePadY
          anchors.bottomMargin: root.surfacePadY

          HudButton {
            icon: "add"
            opened: root.menuKind === "attach"
            tooltipText: "Attach"
            onClicked: root.toggleMenu("attach")
          }

          TextField {
            id: composerInput
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 0
            Layout.minimumWidth: Style.space(Theme.inputMinPx())
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 0
            foreground: root.foreground
            accent: Color.accent
            placeholderText: root.busy ? "Alfred is working…" : (root.transcribing ? "Transcribing…" : (root.listening ? "Listening…" : (root.gatewayActive ? "Ask Alfred" : "Gateway down")))
            placeholderTextColor: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            background: Item {}
            leftPadding: Style.space(4)
            rightPadding: Style.space(4)
            topPadding: 0
            bottomPadding: 0
            horizontalPadding: Style.space(4)
            verticalPadding: 0
            readOnly: root.busy
            enabled: root.focused && !root.busy
            onTextChanged: root.syncSlash()
            onAccepted: {
              if (root.tryApplySlash()) return
              root.submit()
            }
            Keys.onReturnPressed: function(event) {
              if (event.modifiers & Qt.ShiftModifier) return
              if (root.tryApplySlash()) {
                event.accepted = true
                return
              }
              root.submit()
              event.accepted = true
            }
            Keys.onEnterPressed: function(event) {
              if (event.modifiers & Qt.ShiftModifier) return
              if (root.tryApplySlash()) {
                event.accepted = true
                return
              }
              root.submit()
              event.accepted = true
            }
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.handleEscape()
                event.accepted = true
                return
              }
              if (!root.slashPanelOpen) return
              if (event.key === Qt.Key_Down) {
                root.moveSlash(1)
                event.accepted = true
                return
              }
              if (event.key === Qt.Key_Up) {
                root.moveSlash(-1)
                event.accepted = true
                return
              }
              if (event.key === Qt.Key_Tab) {
                root.tryApplySlash()
                event.accepted = true
              }
            }
          }

          HudButton {
            wide: true
            compact: root.pillWidth < Style.space(560)
            icon: root.pillWidth < Style.space(560) ? "chevron-down" : ""
            trailingIcon: root.pillWidth < Style.space(560) ? "" : "chevron-down"
            label: AlfredModel.shortModelName(root.modelName)
            opened: root.menuKind === "model"
            tooltipText: root.modelName !== "" ? ("Model: " + root.modelName) : "Switch model"
            onClicked: root.toggleMenu("model")
          }

          HudButton {
            icon: root.listening ? "stop" : "mic"
            active: root.listening
            tooltipText: root.listening ? "Stop dictation" : "Dictate"
            onClicked: root.toggleVoice()
          }

          HudButton {
            primary: true
            icon: root.showVoicePrimary ? "audio-lines" : (root.showStop ? "stop" : "arrow-up")
            enabled: root.showVoicePrimary || root.showStop || root.hasPayload
            tooltipText: root.showVoicePrimary ? "Start voice conversation" : (root.showStop ? "Stop" : "Send")
            onClicked: root.handlePrimary()
          }

          HudButton {
            icon: "screen-normal"
            tooltipText: "Exit HUD"
            onClicked: root.openDesktop()
          }
        }
      }

      Item {
        id: menuWrap
        width: parent.width
        height: root.focused && root.menuOpen && !root.pickerOpen && !root.slashPanelOpen ? Math.min(menuCol.implicitHeight + Style.space(20), Style.space(240)) : 0
        clip: true
        opacity: height > 0 ? 1 : 0
        z: 20

        Behavior on height {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Rectangle {
          anchors.fill: parent
          anchors.topMargin: Style.space(6)
          radius: Style.space(Theme.arcRadiusPx())
          color: root.sheet
          border.width: 1
          border.color: Util.alpha(Color.accent, 0.18)

          Column {
            id: menuCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.menuKind === "attach" ? "ATTACH" : (root.modelOptions.length === 0 ? "No cached models" : "Model")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: root.menuKind === "attach"
            }

            Repeater {
              model: root.menuKind === "attach" ? 4 : 0

              Rectangle {
                required property int index
                readonly property var row: root.attachItems[index]
                width: menuCol.width
                height: Style.space(30)
                radius: Style.space(6)
                color: attachHit.containsMouse ? Util.alpha(Color.foreground, 0.10) : "transparent"

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    text: Theme.glyph(row.iconName)
                    color: root.dim
                    font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
                    font.pixelSize: Style.space(Theme.iconPx())
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: String(row.rowLabel)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  id: attachHit
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  preventStealing: true
                  propagateComposedEvents: false
                  onPressed: function(mouse) {
                    mouse.accepted = true
                    var mode = String(row.action)
                    Qt.callLater(function() { root.pickKind(mode) })
                  }
                }
              }
            }

            Repeater {
              model: root.menuKind === "model" ? root.modelOptions : 0

              Rectangle {
                required property var modelData
                width: menuCol.width
                height: Style.space(28)
                radius: Style.space(6)
                color: String(modelData) === root.modelName
                  ? Util.alpha(Color.accent, 0.18)
                  : (modelHit.containsMouse ? Util.alpha(Color.foreground, 0.08) : "transparent")

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  textFormat: Text.PlainText
                  text: String(modelData)
                  elide: Text.ElideRight
                  color: String(modelData) === root.modelName ? Color.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: modelHit
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  preventStealing: true
                  onPressed: function(mouse) {
                    mouse.accepted = true
                    var name = String(modelData)
                    Qt.callLater(function() { root.chooseModel(name) })
                  }
                }
              }
            }
          }
        }
      }

      Item {
        id: slashWrap
        width: parent.width
        height: root.slashPanelOpen ? Style.space(280) : 0
        clip: true
        opacity: height > 0 ? 1 : 0
        z: 20

        Behavior on height {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Rectangle {
          anchors.fill: parent
          anchors.topMargin: Style.space(6)
          radius: Style.space(Theme.arcRadiusPx())
          color: root.sheet
          border.width: 1
          border.color: Util.alpha(Color.accent, 0.18)

          Flickable {
            id: slashList
            anchors.fill: parent
            anchors.margins: Style.space(8)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: slashCol.implicitHeight
            flickableDirection: Flickable.VerticalFlick

            Column {
              id: slashCol
              width: slashList.width
              spacing: 0

              Text {
                width: parent.width
                visible: root.slashItems.length === 0
                height: visible ? Style.space(22) : 0
                textFormat: Text.PlainText
                text: root.slashLoading ? "Loading commands and skills…" : "No matching commands"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Repeater {
                model: root.slashViewRows

                Item {
                  required property var modelData
                  width: slashCol.width
                  height: modelData.rowType === "header" ? Style.space(22) : Style.space(40)

                  Text {
                    visible: modelData.rowType === "header"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(8)
                    textFormat: Text.PlainText
                    text: String(modelData.group || "").toUpperCase()
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Rectangle {
                    visible: modelData.rowType === "item"
                    anchors.fill: parent
                    radius: Style.space(6)
                    color: modelData.itemIndex === root.slashIndex
                      ? Util.alpha(Color.accent, 0.18)
                      : (slashHit.containsMouse ? Util.alpha(Color.foreground, 0.08) : "transparent")

                    Column {
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(8)
                      anchors.rightMargin: Style.space(8)
                      spacing: Style.space(1)

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: String(modelData.display || modelData.text || "")
                        elide: Text.ElideRight
                        color: String(modelData.kind) === "skill" ? Color.accent : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }

                      Text {
                        width: parent.width
                        visible: String(modelData.meta || "") !== ""
                        textFormat: Text.PlainText
                        text: String(modelData.meta || "")
                        elide: Text.ElideRight
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    MouseArea {
                      id: slashHit
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      preventStealing: true
                      onEntered: {
                        if (modelData.itemIndex >= 0) root.slashIndex = modelData.itemIndex
                      }
                      onPressed: function(mouse) {
                        mouse.accepted = true
                        var idx = modelData.itemIndex
                        Qt.callLater(function() { root.applySlashAt(idx) })
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      Item {
        id: pickerWrap
        width: parent.width
        height: root.focused && root.pickerOpen ? Style.space(280) : 0
        clip: true
        opacity: height > 0 ? 1 : 0
        z: 20

        Behavior on height {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        FilePicker {
          anchors.fill: parent
          anchors.topMargin: Style.space(6)
          visible: root.pickerOpen
          mode: root.pickerMode !== "" ? root.pickerMode : "files"
          onAccepted: function(paths) {
            if (alfred && typeof alfred.addAttachments === "function") alfred.addAttachments(paths)
            root.closePicker()
            grabFocusTimer.tries = 0
            grabFocusTimer.restart()
          }
          onCancelled: {
            root.closePicker()
            grabFocusTimer.tries = 0
            grabFocusTimer.restart()
          }
        }
      }

      Item {
        id: chipWrap
        width: parent.width
        height: root.focused && !root.busy && root.attachments.length > 0 ? chipRow.implicitHeight + Style.space(8) : 0
        clip: true
        opacity: height > 0 ? 1 : 0

        Behavior on height {
          NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        Flow {
          id: chipRow
          width: parent.width
          y: Style.space(8)
          spacing: Style.space(6)

          Repeater {
            model: root.attachments
            Rectangle {
              required property var modelData
              height: Style.space(22)
              width: chipRowInner.implicitWidth + Style.space(14)
              radius: height / 2
              color: Util.alpha(Color.accent, 0.16)

              Row {
                id: chipRowInner
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                spacing: Style.space(4)

                Text {
                  id: chipLabel
                  textFormat: Text.PlainText
                  text: AlfredModel.fileName(modelData)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: Theme.glyph("close")
                  color: chipClose.containsMouse ? Color.urgent : root.dim
                  font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
                  font.pixelSize: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  MouseArea {
                    id: chipClose
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true
                    onClicked: root.removeAttachment(modelData)
                  }
                }
              }
            }
          }
        }
      }

      Item {
        id: bandWrap
        width: parent.width
        height: root.showThread ? Math.min(bandColumn.implicitHeight + Style.space(24), root.bandMaxHeight) : 0
        clip: true
        opacity: root.showThread ? 1 : 0

        Behavior on height {
          NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
          NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Rectangle {
          id: band
          anchors.fill: parent
          anchors.topMargin: Style.space(8)
          radius: Style.space(18)
          color: root.sheet
          border.width: 1
          border.color: Util.alpha(Color.accent, 0.18)

          Flickable {
            id: bandFlick
            anchors.fill: parent
            anchors.margins: Style.space(14)
            contentWidth: width
            contentHeight: bandColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height
            pressDelay: 180

            Column {
              id: bandColumn
              width: bandFlick.width
              spacing: Style.space(8)

              TextEdit {
                visible: root.lastError !== ""
                width: parent.width
                height: contentHeight
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                color: Color.urgent
                text: root.lastError
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                textFormat: TextEdit.PlainText
              }

              Repeater {
                model: root.messages

                Column {
                  required property var modelData
                  width: bandColumn.width
                  spacing: Style.space(2)

                  Row {
                    spacing: Style.space(8)
                    Text {
                      textFormat: Text.PlainText
                      text: modelData.role === "user" ? "You" : "Alfred"
                      color: modelData.role === "user" ? Color.accent : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                      visible: String(modelData.text || "") !== ""
                      textFormat: Text.PlainText
                      text: Theme.glyph("copy")
                      color: copyHit.containsMouse ? root.foreground : root.dim
                      font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
                      font.pixelSize: Style.space(Theme.iconPx())
                      anchors.verticalCenter: parent.verticalCenter
                      z: 4
                      MouseArea {
                        id: copyHit
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        preventStealing: true
                        onPressed: function(mouse) {
                          mouse.accepted = true
                          grabFocusTimer.stop()
                        }
                        onClicked: root.copyText(modelData.text)
                      }
                    }
                  }

                  TextEdit {
                    width: parent.width
                    height: contentHeight
                    readOnly: true
                    selectByMouse: true
                    selectByKeyboard: true
                    persistentSelection: true
                    wrapMode: TextEdit.Wrap
                    color: root.foreground
                    selectedTextColor: Color.background
                    selectionColor: Color.accent
                    text: modelData.text || ""
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    textFormat: TextEdit.PlainText
                    activeFocusOnPress: true
                    Keys.onPressed: function(event) {
                      if (event.matches(StandardKey.Copy)) {
                        root.copyText(selectedText !== "" ? selectedText : text)
                        event.accepted = true
                      }
                    }
                    onActiveFocusChanged: {
                      if (activeFocus) grabFocusTimer.stop()
                    }
                  }
                }
              }

              Text {
                visible: root.messages.length === 0 && root.lastError === ""
                width: parent.width
                textFormat: Text.PlainText
                text: root.busy ? "Thinking…" : "Ready."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
    }
  }

  onMessagesChanged: {
    Qt.callLater(function() {
      bandFlick.contentY = Math.max(0, bandFlick.contentHeight - bandFlick.height)
    })
  }

  Component.onCompleted: {
    if (alfred && typeof alfred.refreshStatus === "function") alfred.refreshStatus()
    if (alfred && typeof alfred.refreshModels === "function") alfred.refreshModels()
  }
}
