import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import qs.Commons
import "ComposerTheme.js" as Theme

Rectangle {
  id: root

  property real uiScale: 1

  function px(n) {
    var g = Number(Style.spacing.scale)
    if (!(g > 0)) g = 1
    var v = Style.space(n) * root.uiScale / g
    if (!isFinite(v) || v <= 0) return 0
    return Math.round(v)
  }

  function fontPx(size) {
    var n = Number(size)
    if (!isFinite(n) || n <= 0) return 0
    return Math.max(1, Math.round(n * root.uiScale))
  }

  property string mode: "files"
  property string homePath: {
    var home = Quickshell.env("HOME") || ""
    return home !== "" ? home : "/home"
  }
  property url folder: "file://" + root.homePath
  property var selected: []

  signal accepted(var paths)
  signal cancelled()

  readonly property string folderPath: root.urlToPath(root.folder)
  readonly property bool folderMode: root.mode === "folder"
  readonly property bool canOpen: root.folderMode || root.selected.length > 0
  readonly property color ink: Color.foreground
  readonly property color dim: Color.muted

  function urlToPath(value) {
    var text = String(value || "")
    if (text.indexOf("file://") === 0) {
      text = decodeURIComponent(text.substring(7))
      if (/^\/[A-Za-z]:/.test(text)) text = text.substring(1)
    }
    return text
  }

  function pathToUrl(path) {
    var text = String(path || "")
    if (text.indexOf("file://") === 0) return text
    return "file://" + text
  }

  function isSelected(path) {
    var want = String(path || "")
    var i
    for (i = 0; i < root.selected.length; i++) {
      if (String(root.selected[i]) === want) return true
    }
    return false
  }

  function togglePath(path) {
    var want = String(path || "")
    if (want === "") return
    var next = []
    var found = false
    var i
    for (i = 0; i < root.selected.length; i++) {
      if (String(root.selected[i]) === want) {
        found = true
        continue
      }
      next.push(root.selected[i])
    }
    if (!found) next.push(want)
    root.selected = next
  }

  function goUp() {
    var parentUrl = listing.parentFolder
    if (!parentUrl || String(parentUrl) === "" || String(parentUrl) === String(root.folder)) return
    root.selected = []
    root.folder = parentUrl
  }

  function confirm() {
    if (root.folderMode) {
      var current = root.folderPath
      if (current !== "") root.accepted([current.replace(/\/?$/, "/")])
      return
    }
    if (root.selected.length > 0) root.accepted(root.selected.slice())
  }

  radius: root.px(Theme.arcRadiusPx())
  color: Util.alpha(Qt.darker(Color.background, 1.25), 0.92)
  border.width: 1
  border.color: Util.alpha(Color.accent, 0.18)

  FolderListModel {
    id: listing
    folder: root.folder
    showDirs: true
    showDirsFirst: true
    showDotAndDotDot: false
    showFiles: !root.folderMode
    nameFilters: root.mode === "images" ? ["*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.bmp", "*.svg", "*.tiff"] : []
    sortField: FolderListModel.Name
  }

  Column {
    anchors.fill: parent
    anchors.margins: root.px(8)
    spacing: root.px(6)

    Row {
      width: parent.width
      spacing: root.px(6)
      height: root.px(26)

      Rectangle {
        width: root.px(26)
        height: root.px(26)
        radius: root.px(6)
        color: upHit.containsMouse ? Util.alpha(Color.foreground, 0.10) : "transparent"
        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: ".."
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: root.fontPx(Style.font.caption)
        }
        MouseArea {
          id: upHit
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.goUp()
        }
      }

      Text {
        width: parent.width - root.px(32)
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        text: root.folderPath
        elide: Text.ElideMiddle
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: root.fontPx(Style.font.caption)
      }
    }

    ListView {
      id: list
      width: parent.width
      height: parent.height - root.px(70)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: listing
      spacing: 1

      delegate: Rectangle {
        required property string fileName
        required property string filePath
        required property bool fileIsDir
        width: list.width
        height: root.px(28)
        radius: root.px(6)
        color: {
          if (!fileIsDir && root.isSelected(filePath)) return Util.alpha(Color.accent, 0.18)
          if (rowHit.containsMouse) return Util.alpha(Color.foreground, 0.08)
          return "transparent"
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: root.px(8)
          anchors.rightMargin: root.px(8)
          textFormat: Text.PlainText
          text: fileIsDir ? (fileName + "/") : fileName
          elide: Text.ElideRight
          color: fileIsDir ? Color.accent : root.ink
          font.family: Style.font.family
          font.pixelSize: root.fontPx(Style.font.caption)
        }

        MouseArea {
          id: rowHit
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton
          onClicked: function(mouse) {
            if (fileIsDir) {
              root.selected = []
              root.folder = root.pathToUrl(filePath)
              return
            }
            root.togglePath(filePath)
          }
          onDoubleClicked: {
            if (fileIsDir) return
            root.accepted([filePath])
          }
        }
      }
    }

    Row {
      width: parent.width
      spacing: root.px(8)
      layoutDirection: Qt.RightToLeft
      height: root.px(28)

      Rectangle {
        width: root.px(64)
        height: root.px(26)
        radius: root.px(6)
        color: root.canOpen ? Util.alpha(Color.accent, openHit.containsMouse ? 0.28 : 0.18) : Util.alpha(Color.foreground, 0.06)
        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "Open"
          color: root.canOpen ? Color.accent : root.dim
          font.family: Style.font.family
          font.pixelSize: root.fontPx(Style.font.caption)
        }
        MouseArea {
          id: openHit
          anchors.fill: parent
          enabled: root.canOpen
          hoverEnabled: true
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.confirm()
        }
      }

      Rectangle {
        width: root.px(72)
        height: root.px(26)
        radius: root.px(6)
        color: cancelHit.containsMouse ? Util.alpha(Color.foreground, 0.10) : "transparent"
        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "Cancel"
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: root.fontPx(Style.font.caption)
        }
        MouseArea {
          id: cancelHit
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.cancelled()
        }
      }
    }
  }
}
