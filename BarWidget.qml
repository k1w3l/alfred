import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "kiwel.alfred"

  readonly property var alfred: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(root.moduleName) : null
  readonly property bool busy: alfred ? alfred.busy === true : false
  readonly property bool gatewayActive: alfred ? alfred.gatewayActive === true : false
  readonly property bool alarming: alfred ? (!alfred.gatewayActive && !alfred.busy) : false
  readonly property bool opened: alfred ? alfred.hudOpen === true : false
  readonly property string profileLabel: alfred ? String(alfred.profileLabel || "Alfred") : "Alfred"
  readonly property string profileShape: alfred ? String(alfred.profileShape || "cercle") : "cercle"
  readonly property string profileFill: alfred ? String(alfred.profileFill || "#0a0a0c") : "#0a0a0c"
  readonly property string profileExpression: alfred ? String(alfred.profileExpression || "neutre") : "neutre"
  readonly property int profileIdle: alfred ? Number(alfred.profileIdle || 0) : 0
  readonly property real profilePhase: alfred ? Number(alfred.profilePhase || 0) : 0
  readonly property string profileEyes: alfred ? String(alfred.profileEyes || "soft") : "soft"
  readonly property string profileKey: alfred ? String(alfred.profileKey || "local:default") : "local:default"
  property bool popoutSwitchClosing: false

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
    active: root.busy || root.alarming
    tooltipText: root.busy
      ? (root.profileLabel + " is working")
      : (root.gatewayActive
        ? (root.profileLabel + " — click to open · right-click for Desktop")
        : (root.profileLabel + " — gateway is down"))
    iconComponent: Component {
      ProfileBlob {
        anchors.fill: parent
        agentId: root.profileKey
        slot: "tray"
        shape: root.profileShape
        fill: root.profileFill
        expression: root.profileExpression
        idleVariant: root.profileIdle
        phase: root.profilePhase
        eyes: root.profileEyes
        mood: root.busy ? "busy" : (root.alarming ? "error" : "idle")
      }
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchDesktop()
      else if (buttonCode === Qt.MiddleButton) root.hideHud()
      else root.focusHud()
    }
  }
}
