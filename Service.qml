import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "HermesModel.js" as HermesModel

Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null
  property var settings: ({})

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string pluginDir: {
    var fromManifest = manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
    if (fromManifest) return fromManifest.replace(/\/$/, "")
    return HermesModel.pluginDirFromUrl(Qt.resolvedUrl("."))
  }

  readonly property string sessionName: {
    var value = settings && settings.sessionName !== undefined && settings.sessionName !== null
      ? String(settings.sessionName).trim() : "hud"
    return value === "" ? "hud" : value
  }

  property bool gatewayActive: false
  property string gatewayState: "unknown"
  property bool busy: false
  property string lastError: ""
  property string statusText: "Checking…"
  property var messages: []
  property string lastReply: ""

  readonly property string glyph: busy ? "󰑐" : (gatewayActive ? "󰚩" : "󰚌")
  readonly property color statusColor: busy ? Color.accent : (gatewayActive ? Color.foreground : Color.urgent)

  signal focusRequested()
  signal hideRequested()
  signal replyReceived(string text)

  function refreshStatus() {
    if (statusProcess.running) return
    statusProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/status.fish"]
    statusProcess.running = true
  }

  function send(text) {
    var prompt = String(text || "").trim()
    if (prompt === "") return false
    if (sendProcess.running) {
      lastError = "Hermes is already answering"
      return false
    }
    lastError = ""
    lastReply = ""
    messages = HermesModel.appendMessage(messages, "user", prompt)
    busy = true
    sendProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/send.fish", root.sessionName, prompt]
    sendProcess.running = true
    return true
  }

  function launchDesktop() {
    Quickshell.execDetached(["fish", "--no-config", root.pluginDir + "/scripts/desktop.fish"])
  }

  function requestFocus() {
    root.focusRequested()
  }

  function requestHide() {
    root.hideRequested()
  }

  function applyStatus(raw) {
    var parsed = HermesModel.parseStatus(raw)
    if (!parsed.ok) {
      gatewayActive = false
      gatewayState = "unknown"
      statusText = parsed.lastError || "Status failed"
      if (parsed.lastError) lastError = parsed.lastError
      return
    }
    gatewayActive = parsed.active === true
    gatewayState = parsed.state
    statusText = gatewayActive ? "Ready" : ("Gateway " + parsed.state)
    if (gatewayActive && lastError.indexOf("Gateway") === 0) lastError = ""
  }

  function finishSend(exitCode, stdoutText, stderrText) {
    busy = false
    var reply = HermesModel.parseReply(stdoutText)
    var err = String(stderrText || "").trim()
    if (exitCode !== 0) {
      lastError = err !== "" ? HermesModel.previewText(err, 240) : ("Hermes exited " + exitCode)
      if (reply !== "") {
        lastReply = reply
        messages = HermesModel.appendMessage(messages, "assistant", reply)
        root.replyReceived(reply)
      }
      return
    }
    if (reply === "") reply = err
    if (reply === "") reply = "(no output)"
    lastError = ""
    lastReply = reply
    messages = HermesModel.appendMessage(messages, "assistant", reply)
    root.replyReceived(reply)
  }

  Timer {
    interval: 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
  }

  Process {
    id: statusProcess
    running: false
    stdout: StdioCollector {
      id: statusOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: statusErr
      waitForEnd: true
    }
    onExited: function() {
      var raw = String(statusOut.text || "")
      if (raw.trim() === "") raw = String(statusErr.text || "")
      root.applyStatus(raw)
    }
  }

  Process {
    id: sendProcess
    running: false
    stdout: StdioCollector {
      id: sendOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: sendErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.finishSend(exitCode, sendOut.text, sendErr.text)
    }
  }

  Component.onCompleted: root.refreshStatus()
}
