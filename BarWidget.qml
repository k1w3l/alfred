import QtQuick
import qs.Commons
import qs.Ui
import "AlfredModel.js" as AlfredModel

BarWidget {
  id: root
  moduleName: "kiwel.alfred"

  readonly property var alfred: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(root.moduleName) : null
  readonly property bool busy: alfred ? alfred.busy === true : false
  readonly property bool gatewayActive: alfred ? alfred.gatewayActive === true : false
  readonly property bool alarming: alfred ? (!alfred.gatewayActive && !alfred.busy) : false
  readonly property bool opened: alfred ? alfred.hudOpen === true : false
  property bool popoutSwitchClosing: false
  property real spin: 0

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

  NumberAnimation on spin {
    from: 0
    to: 360
    duration: 1100
    loops: Animation.Infinite
    running: root.busy
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: AlfredModel.butlerGlyph()
    textRotation: root.busy ? root.spin : 0
    active: root.busy || root.alarming
    tooltipText: root.busy
      ? "Alfred is working"
      : (root.gatewayActive
        ? "Alfred — click to open · right-click for Desktop"
        : "Gateway is down")

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchDesktop()
      else if (buttonCode === Qt.MiddleButton) root.hideHud()
      else root.focusHud()
    }
  }
}
