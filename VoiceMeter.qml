pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "ComposerTheme.js" as Theme

// Capture readout for voice dictation. The traveling border only says the
// mode is on; this shows whether samples are arriving, whether they have
// level, and how long the mic has been open.
// Overlay owns placement. Drop it in hudColumn, after the pill Rectangle.
Item {
  id: root

  property real level: 0
  property bool capturing: false
  property bool hearing: false
  property int elapsedMs: 0
  property real uiScale: 1

  implicitWidth: 188
  implicitHeight: 36

  readonly property string statusText: hearing ? "Hearing you" : (capturing ? "Listening" : "Waiting")
  readonly property string clockText: {
    var total = Math.floor(Math.max(0, elapsedMs) / 1000)
    var mins = Math.floor(total / 60)
    var secs = total % 60
    return mins + ":" + (secs < 10 ? "0" : "") + secs
  }
  readonly property color live: Theme.moodRed()

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: "#141418"
    border.width: 1
    border.color: root.hearing ? root.live : (root.capturing ? Qt.rgba(root.live.r, root.live.g, root.live.b, 0.45) : Qt.rgba(1, 1, 1, 0.14))
  }

  Row {
    id: bars
    anchors.left: parent.left
    anchors.leftMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    spacing: 3

    Repeater {
      model: 8
      Rectangle {
        required property int index
        width: Math.max(2, 3 * root.uiScale)
        height: (6 + (index * 2)) * root.uiScale
        radius: 1.5
        color: root.level >= (index + 0.55) / 8 ? root.live : Qt.rgba(1, 1, 1, 0.16)
      }
    }
  }

  Text {
    anchors.left: bars.right
    anchors.leftMargin: 8
    anchors.right: clock.left
    anchors.rightMargin: 6
    anchors.verticalCenter: parent.verticalCenter
    text: root.statusText
    elide: Text.ElideRight
    color: root.hearing ? root.live : Color.foreground
    font.family: Style.font.family
    font.pixelSize: Math.round(Style.font.caption * root.uiScale)
  }

  Text {
    id: clock
    anchors.right: parent.right
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    text: root.clockText
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Math.round(Style.font.caption * root.uiScale)
  }
}
