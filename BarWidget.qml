import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "kiwel.hermes-hud"

  readonly property var hermes: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(root.moduleName) : null
  readonly property bool busy: hermes ? hermes.busy === true : false
  readonly property bool gatewayActive: hermes ? hermes.gatewayActive === true : false
  readonly property bool alarming: hermes ? (!hermes.gatewayActive && !hermes.busy) : false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function focusHud() {
    if (hermes && typeof hermes.requestFocus === "function") hermes.requestFocus()
    else if (root.bar) root.bar.run("omarchy-shell kiwel.hermes-hud focus")
  }

  function hideHud() {
    if (hermes && typeof hermes.requestHide === "function") hermes.requestHide()
    else if (root.bar) root.bar.run("omarchy-shell kiwel.hermes-hud hide")
  }

  function launchDesktop() {
    if (hermes && typeof hermes.launchDesktop === "function") hermes.launchDesktop()
    else if (root.bar) root.bar.run("hermes-desktop")
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: hermes && hermes.glyph ? hermes.glyph : "󰚩"
    active: root.busy || root.alarming
    tooltipText: root.busy
      ? "Hermes is working"
      : (root.gatewayActive
        ? "Hermes HUD — click to focus · right-click for Desktop"
        : "Hermes gateway is down")

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchDesktop()
      else if (buttonCode === Qt.MiddleButton) root.hideHud()
      else root.focusHud()
    }
  }
}
