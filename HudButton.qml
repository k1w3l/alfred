import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "ComposerTheme.js" as Theme

// GHOST_ICON_BTN / PRIMARY_ICON_BTN / ACTIVE_ICON_BTN from
// apps/desktop/src/app/chat/composer/control-classes.ts
Rectangle {
  id: root

  property string icon: ""
  property string trailingIcon: ""
  property string label: ""
  property string tooltipText: ""
  property bool primary: false
  property bool active: false
  property bool opened: false
  property bool wide: false
  property bool compact: false
  property int badge: 0

  signal clicked()
  signal rightClicked()

  readonly property int controlSize: Style.space(Theme.controlPx())
  readonly property int primarySize: Style.space(Theme.primaryPx())
  readonly property int glyphPx: Style.space(Theme.iconPx())
  readonly property bool hot: hit.containsMouse && root.enabled
  readonly property color ink: {
    if (!root.enabled && root.primary) return Util.alpha(Color.background, 0.9)
    if (root.primary) return Color.background
    if (root.active) return Color.accent
    if (root.hot || root.opened) return Color.foreground
    return Color.muted
  }
  readonly property color fill: {
    if (root.primary) {
      if (!root.enabled) return Util.alpha(Color.foreground, 0.30)
      return root.hot ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.90) : Color.foreground
    }
    if (root.active) return Util.alpha(Color.accent, root.hot ? 0.15 : 0.10)
    if (root.hot || root.opened) return Util.alpha(Color.foreground, 0.10)
    return "transparent"
  }

  Layout.preferredWidth: implicitWidth
  Layout.preferredHeight: implicitHeight
  Layout.minimumWidth: primary ? primarySize : controlSize
  Layout.maximumWidth: wide && !compact ? Style.space(Theme.modelMaxPx()) : implicitWidth
  Layout.alignment: Qt.AlignVCenter
  Layout.fillWidth: false
  Layout.fillHeight: false

  implicitWidth: {
    if (wide && !compact)
      return Math.min(Style.space(Theme.modelMaxPx()), Math.max(controlSize, labelRow.implicitWidth + Style.space(16)))
    return primary ? primarySize : controlSize
  }
  implicitHeight: primary ? primarySize : controlSize
  radius: primary ? height / 2 : Style.space(6)
  color: fill
  opacity: 1
  z: 20

  FontLoader {
    id: codiconFont
    source: Qt.resolvedUrl("fonts/codicon.ttf")
  }

  Row {
    id: labelRow
    anchors.centerIn: parent
    spacing: Style.space(4)

    Item {
      visible: root.icon === "audio-lines"
      width: root.glyphPx
      height: root.glyphPx
      anchors.verticalCenter: parent.verticalCenter

      Row {
        anchors.centerIn: parent
        spacing: Math.max(1, Math.round(root.glyphPx * 0.12))
        Repeater {
          model: 4
          Rectangle {
            required property int index
            width: Math.max(1.5, root.glyphPx * 0.12)
            height: root.glyphPx * (index === 1 || index === 2 ? 0.92 : 0.55)
            radius: width / 2
            color: root.ink
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }

    Rectangle {
      visible: root.icon === "stop"
      width: Style.space(Theme.stopPx())
      height: Style.space(Theme.stopPx())
      radius: Style.space(3)
      color: root.ink
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      visible: root.icon !== "" && root.icon !== "audio-lines" && root.icon !== "stop"
      textFormat: Text.PlainText
      text: Theme.glyph(root.icon)
      color: root.ink
      font.family: codiconFont.name !== "" ? codiconFont.name : "codicon"
      font.pixelSize: root.glyphPx
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      visible: root.label !== "" && !root.compact
      textFormat: Text.PlainText
      text: root.label
      color: root.ink
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      width: Math.min(implicitWidth, Style.space(Theme.modelMaxPx()) - root.glyphPx - Style.space(20))
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      visible: root.trailingIcon !== "" && !root.compact
      textFormat: Text.PlainText
      text: Theme.glyph(root.trailingIcon)
      color: root.ink
      opacity: 0.5
      font.family: codiconFont.name !== "" ? codiconFont.name : "codicon"
      font.pixelSize: Math.max(10, Math.round(root.glyphPx * 0.72))
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  Rectangle {
    visible: root.badge > 0
    z: 2
    width: Math.max(height, badgeText.implicitWidth + Style.space(6))
    height: Style.space(14)
    radius: height / 2
    color: Color.accent
    border.width: 1
    border.color: Color.background
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: -Style.space(4)
    anchors.topMargin: -Style.space(4)

    Text {
      id: badgeText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.badge > 9 ? "9+" : String(root.badge)
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Math.max(9, Style.space(9))
      font.bold: true
    }
  }

  MouseArea {
    id: hit
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    enabled: root.enabled
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    preventStealing: true
    propagateComposedEvents: false
    onPressed: function(mouse) {
      mouse.accepted = true
    }
    onClicked: function(mouse) {
      mouse.accepted = true
      if (mouse.button === Qt.RightButton) root.rightClicked()
      else root.clicked()
    }
  }

  ToolTip.visible: root.tooltipText !== "" && hit.containsMouse
  ToolTip.text: root.tooltipText
  ToolTip.delay: 400
}
