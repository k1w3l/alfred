import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null

  property bool opened: true
  property bool focused: false
  property bool recent: false

  readonly property var hermes: service ? service : (shell && typeof shell.serviceFor === "function" ? shell.serviceFor("kiwel.hermes-hud") : null)
  readonly property bool busy: hermes ? hermes.busy === true : false
  readonly property bool gatewayActive: hermes ? hermes.gatewayActive === true : false
  readonly property var messages: hermes && hermes.messages ? hermes.messages : []
  readonly property string lastError: hermes ? String(hermes.lastError || "") : ""
  readonly property bool showThread: root.focused || root.busy || root.recent || (root.lastError !== "" && root.opened)

  readonly property color foreground: Color.popups.text
  readonly property color dim: Color.muted
  readonly property color surface: Util.alpha(Color.popups.background, 0.92)
  readonly property color sheet: Util.alpha(Color.background, 0.78)
  readonly property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
  readonly property string fontFamily: Style.font.family
  readonly property int pillWidth: Style.space(720)
  readonly property int pillHeight: Math.max(Style.space(48), Style.font.body + Style.spacing.controlPaddingY * 2 + Style.space(16))
  readonly property int bandMaxHeight: Style.space(280)

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
    root.unfocusHud()
  }

  function toggle() {
    if (root.opened && root.focused) root.unfocusHud()
    else root.focusHud()
  }

  function hideHud() {
    root.focused = false
    root.opened = false
    if (composerInput) composerInput.text = ""
  }

  function focusHud() {
    root.opened = true
    root.focused = true
    root.bumpRecent()
    panel.screen = root.focusedScreen()
    Qt.callLater(function() { composerInput.forceActiveFocus() })
  }

  function unfocusHud() {
    root.focused = false
    composerInput.focus = false
    root.bumpRecent()
  }

  function bumpRecent() {
    root.recent = true
    recentTimer.restart()
  }

  function submit() {
    var prompt = composerInput ? String(composerInput.text || "").trim() : ""
    if (prompt === "" || !hermes) return
    if (hermes.send(prompt)) {
      composerInput.text = ""
      root.bumpRecent()
    }
  }

  function sendText(text) {
    if (composerInput) composerInput.text = String(text || "")
    root.submit()
  }

  Timer {
    id: recentTimer
    interval: 1100
    repeat: false
    onTriggered: root.recent = false
  }

  Connections {
    target: root.hermes
    function onFocusRequested() { root.focusHud() }
    function onHideRequested() { root.hideHud() }
    function onReplyReceived(text) { root.bumpRecent() }
    function onBusyChanged() {
      if (root.hermes && root.hermes.busy) root.bumpRecent()
    }
  }

  IpcHandler {
    target: "kiwel.hermes-hud"
    function open(): string { root.focusHud(); return "ok" }
    function show(): string { root.focusHud(); return "ok" }
    function close(): string { root.unfocusHud(); return "ok" }
    function hide(): string { root.hideHud(); return "ok" }
    function toggle(): string { root.toggle(); return "ok" }
    function focus(): string { root.focusHud(); return "ok" }
    function send(text: string): string {
      root.focusHud()
      root.sendText(text)
      return "ok"
    }
    function ping(): string { return "ok" }
    function state(): string {
      if (!root.opened) return "hidden"
      if (root.focused) return "focused"
      return "idle"
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "kiwel-hermes-hud"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region { item: hudColumn }

    Column {
      id: hudColumn
      width: root.pillWidth
      spacing: 0
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Style.bar.sizeHorizontal + Style.gapsOut + Style.space(12)

      BorderSurface {
        id: pill
        width: parent.width
        height: root.pillHeight
        radius: height / 2
        color: root.surface
        borderSpec: root.borderSpec
        z: 2

        MouseArea {
          anchors.fill: parent
          enabled: !root.focused
          cursorShape: Qt.IBeamCursor
          onClicked: root.focusHud()
        }

        Row {
          id: pillRow
          anchors.fill: parent
          anchors.leftMargin: Style.space(18)
          anchors.rightMargin: Style.space(14)
          spacing: Style.space(10)

          Text {
            id: mark
            textFormat: Text.PlainText
            text: hermes ? hermes.glyph : "󰚩"
            color: hermes ? hermes.statusColor : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(28)
            horizontalAlignment: Text.AlignHCenter
          }

          TextField {
            id: composerInput
            width: parent.width - mark.width - sendGlyph.width - parent.spacing * 2
            anchors.verticalCenter: parent.verticalCenter
            foreground: root.foreground
            placeholderText: root.busy ? "Hermes is working…" : (root.gatewayActive ? "Ask Hermes" : "Gateway down")
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            background: Item {}
            leftPadding: 0
            rightPadding: 0
            topPadding: 0
            bottomPadding: 0
            horizontalPadding: 0
            verticalPadding: 0
            readOnly: root.busy
            enabled: root.opened
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                if (String(text || "") !== "") text = ""
                else root.unfocusHud()
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (event.modifiers & Qt.ShiftModifier) return
                root.submit()
                event.accepted = true
              }
            }
          }

          Text {
            id: sendGlyph
            textFormat: Text.PlainText
            text: root.busy ? "󰔟" : "󰒊"
            color: root.busy ? Color.accent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(24)
            horizontalAlignment: Text.AlignHCenter

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.submit()
            }
          }
        }
      }

      Item {
        id: bandWrap
        width: parent.width - Style.space(16)
        anchors.horizontalCenter: parent.horizontalCenter
        height: root.showThread ? Math.min(bandColumn.implicitHeight, root.bandMaxHeight) : 0
        clip: true
        opacity: root.showThread ? 1 : 0
        z: 1

        Behavior on height {
          NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
          NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        BorderSurface {
          id: band
          anchors.fill: parent
          radius: Style.cornerRadius
          color: root.sheet
          borderSpec: Border.none()

          Flickable {
            id: bandFlick
            anchors.fill: parent
            anchors.margins: Style.space(12)
            contentWidth: width
            contentHeight: bandColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height

            Column {
              id: bandColumn
              width: bandFlick.width
              spacing: Style.space(8)

              Text {
                visible: root.lastError !== ""
                width: parent.width
                textFormat: Text.PlainText
                text: root.lastError
                color: Color.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Repeater {
                model: root.messages

                Column {
                  required property var modelData
                  width: bandColumn.width
                  spacing: Style.space(2)

                  Text {
                    textFormat: Text.PlainText
                    text: modelData.role === "user" ? "You" : "Hermes"
                    color: modelData.role === "user" ? Color.accent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: modelData.text || ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                  }
                }
              }

              Text {
                visible: root.messages.length === 0 && root.lastError === ""
                width: parent.width
                textFormat: Text.PlainText
                text: root.busy ? "Thinking…" : "Ready for a command."
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

  onMessagesChanged: {
    Qt.callLater(function() {
      bandFlick.contentY = Math.max(0, bandFlick.contentHeight - bandFlick.height)
    })
  }

  Component.onCompleted: {
    panel.screen = root.focusedScreen()
    if (hermes && typeof hermes.refreshStatus === "function") hermes.refreshStatus()
  }
}
