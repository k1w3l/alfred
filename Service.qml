import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "AlfredModel.js" as AlfredModel

Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null
  property var settings: ({})

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string pluginDir: {
    var fromManifest = manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
    if (fromManifest) return fromManifest.replace(/\/$/, "")
    return AlfredModel.pluginDirFromUrl(Qt.resolvedUrl("."))
  }

  readonly property string sessionName: {
    var value = settings && settings.sessionName !== undefined && settings.sessionName !== null
      ? String(settings.sessionName).trim() : "alfred"
    return value === "" ? "alfred" : value
  }

  property bool gatewayActive: false
  property string gatewayState: "unknown"
  property bool busy: false
  property bool listening: false
  property string lastError: ""
  property string statusText: "Checking…"
  property var messages: []
  property var attachments: []
  property string lastReply: ""
  property string pendingPrompt: ""
  property bool hudOpen: false
  property bool hudFocused: false
  property string voicePath: ""
  property string modelName: ""
  property string modelProvider: ""
  property var modelOptions: []
  property string reasoningEffort: "medium"
  property var effortOptions: ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]
  property string gatewayConnectionId: "local"
  property string gatewayLabel: "This device"
  property string gatewayKind: "local"
  property string gatewayUrl: ""
  property var gatewayOptions: []
  property string profileName: "default"
  property string profileLabel: "default"
  property var profileOptions: []
  property bool pickingFiles: false
  property bool aborting: false
  property bool transcribing: false
  property bool awaitingPermission: false
  property string lastOutcome: ""
  property string pickMode: "files"
  property string pickOutPath: ""
  property string pickDonePath: ""
  property int pickExitCode: 1
  property string pickOutRaw: ""
  property string sendOutBuf: ""
  property string sendErrBuf: ""
  property var slashItems: []
  property var slashCatalog: []
  property string slashQuery: ""
  property string slashPending: ""
  property string slashRequested: ""
  property bool slashLoading: false

  readonly property string glyph: AlfredModel.butlerGlyph()
  readonly property color statusColor: busy ? Color.accent : (gatewayActive ? Color.foreground : Color.urgent)

  signal focusRequested()
  signal compactRequested()
  signal hideRequested()
  signal replyReceived(string text)
  signal transcriptReady(string text)

  function refreshStatus() {
    if (statusProcess.running) return
    statusProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/status.fish"]
    statusProcess.running = true
  }

  function sendPrompt(text) {
    var prompt = String(text || "").trim()
    if (prompt === "" && root.attachments.length === 0) return false
    if (sendProcess.running) {
      lastError = "Alfred is already answering"
      return false
    }
    if (prompt === "") prompt = "Use the attached files as context."
    lastError = ""
    lastReply = ""
    lastOutcome = ""
    awaitingPermission = false
    sendOutBuf = ""
    sendErrBuf = ""
    pendingPrompt = prompt
    messages = AlfredModel.appendMessage(messages, "user", prompt)
    busy = true
    var cmd = ["fish", "--no-config", root.pluginDir + "/scripts/send.fish", root.sessionName, prompt]
    for (var i = 0; i < root.attachments.length; i++) cmd.push(root.attachments[i])
    sendProcess.command = cmd
    sendProcess.running = true
    attachments = []
    return true
  }

  function addAttachments(raw) {
    attachments = AlfredModel.mergePaths(attachments, raw)
  }

  function removeAttachment(path) {
    var want = String(path || "")
    if (want === "") return
    var next = []
    var i
    for (i = 0; i < root.attachments.length; i++) {
      if (String(root.attachments[i]) !== want) next.push(root.attachments[i])
    }
    attachments = next
  }

  function clearAttachments() {
    attachments = []
  }

  function copyText(value) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
  }

  function pickFiles(kind) {
    var mode = String(kind || "files")
    if (mode === "paste") {
      root.pasteClipboardImage()
      return
    }
  }

  function finishPickFromFiles() {
    if (!root.pickingFiles) return
    pickTimeout.stop()
    pickWait.running = false
    var code = root.pickExitCode
    var raw = String(root.pickOutRaw || "")
    pickingFiles = false
    if (code === 0) root.addAttachments(raw)
    else if (code === 127) {
      root.lastError = "No file picker (GTK portal / zenity)"
      root.lastOutcome = "error"
    } else if (code !== 1) {
      root.lastError = "File picker failed"
      root.lastOutcome = "error"
    }
    if (!root.hudOpen) Qt.callLater(function() { root.requestFocus() })
    else root.hudFocused = true
  }

  function pasteClipboardImage() {
    if (pickProcess.running || root.pickingFiles) return
    var dest = root.runtimeDir + "/alfred-paste.png"
    pickMode = "paste"
    pickProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/pick-files.fish", "paste", dest]
    pickProcess.running = true
  }

  function abortSend() {
    if (!sendProcess.running) return false
    aborting = true
    sendProcess.running = false
    return true
  }

  function refreshModels() {
    if (modelsProcess.running) return
    modelsProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/models.fish", "list"]
    modelsProcess.running = true
  }

  function setModel(name) {
    var id = String(name || "").trim()
    if (id === "" || setModelProcess.running) return false
    modelName = id
    setModelProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/models.fish", "set", id]
    setModelProcess.running = true
    return true
  }

  function applyModels(raw) {
    var parsed = AlfredModel.parseModels(raw)
    if (parsed.provider !== "") modelProvider = parsed.provider
    if (parsed.current !== "") modelName = parsed.current
    if (parsed.models.length > 0) modelOptions = parsed.models
  }

  function refreshEffort() {
    if (effortProcess.running) return
    effortProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/effort.fish", "list"]
    effortProcess.running = true
  }

  function setEffort(level) {
    var value = String(level || "").trim().toLowerCase()
    if (value === "" || setEffortProcess.running) return false
    reasoningEffort = value
    setEffortProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/effort.fish", "set", value]
    setEffortProcess.running = true
    return true
  }

  function applyEffort(raw) {
    var parsed = AlfredModel.parseEffort(raw)
    if (parsed.current !== "") reasoningEffort = parsed.current
    if (parsed.options.length > 0) effortOptions = parsed.options
  }

  function refreshGateways() {
    if (gatewaysProcess.running) return
    gatewaysProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/gateways.fish", "list"]
    gatewaysProcess.running = true
  }

  function setGateway(id) {
    var value = String(id || "").trim()
    if (value === "" || setGatewayProcess.running) return false
    gatewayConnectionId = value
    setGatewayProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/gateways.fish", "set", value]
    setGatewayProcess.running = true
    return true
  }

  function applyGateways(raw) {
    var parsed = AlfredModel.parseGateways(raw)
    if (parsed.current !== "") gatewayConnectionId = parsed.current
    if (parsed.label !== "") gatewayLabel = parsed.label
    if (parsed.kind !== "") gatewayKind = parsed.kind
    gatewayUrl = parsed.url || ""
    if (parsed.connections.length > 0) gatewayOptions = parsed.connections
    var i
    for (i = 0; i < parsed.connections.length; i++) {
      if (String(parsed.connections[i].id) === gatewayConnectionId) {
        if (parsed.kind === "local" || String(parsed.connections[i].kind) === "local")
          gatewayActive = parsed.connections[i].gateway_running === true
        else
          gatewayActive = parsed.connections[i].reachable === true && parsed.connections[i].gateway_running === true
        break
      }
    }
  }

  function refreshProfiles() {
    if (profilesProcess.running) return
    profilesProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/profiles.fish", "list"]
    profilesProcess.running = true
  }

  function setProfile(id) {
    var value = String(id || "").trim()
    if (value === "" || setProfileProcess.running) return false
    profileName = value
    setProfileProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/profiles.fish", "set", value]
    setProfileProcess.running = true
    return true
  }

  function applyProfiles(raw) {
    var parsed = AlfredModel.parseProfiles(raw)
    if (parsed.current !== "") profileName = parsed.current
    if (parsed.label !== "") profileLabel = parsed.label
    if (parsed.profiles.length > 0) profileOptions = parsed.profiles
    if (parsed.model !== "") modelName = parsed.model
    if (parsed.provider !== "") modelProvider = parsed.provider
  }

  function afterProfileChange() {
    slashCatalog = []
    slashItems = []
    root.refreshModels()
    root.refreshEffort()
    root.refreshStatus()
    root.prefetchSlash()
  }

  function toggleVoice() {
    if (root.listening) root.stopVoice()
    else root.startVoice()
  }

  function startVoice() {
    if (voiceProcess.running || root.transcribing) return
    voicePath = root.runtimeDir + "/alfred-voice.wav"
    lastError = ""
    lastOutcome = ""
    listening = true
    voiceProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/voice.fish", "start", voicePath]
    voiceProcess.running = true
  }

  function stopVoice() {
    listening = false
    if (voiceProcess.running) voiceProcess.running = false
    if (voicePath === "") return
    transcribeDelay.restart()
  }

  function cancelVoice() {
    listening = false
    transcribeDelay.stop()
    transcribing = false
    if (voiceProcess.running) voiceProcess.running = false
  }

  function ingestAgentLine(line) {
    if (AlfredModel.looksLikePermission(line)) awaitingPermission = true
  }

  function launchDesktop() {
    Quickshell.execDetached(["fish", "--no-config", root.pluginDir + "/scripts/desktop.fish"])
  }

  function clearSlash() {
    slashPending = ""
    slashQuery = ""
    slashItems = []
    slashLoading = false
    slashDebounce.stop()
  }

  function prefetchSlash() {
    if (root.slashCatalog.length > 0 || slashProcess.running) return
    root.refreshSlash("/")
  }

  function refreshSlash(text) {
    var value = String(text || "")
    var query = AlfredModel.slashQueryFrom(value)
    if (query === "") {
      slashItems = []
      slashQuery = ""
      var warming = slashPending === "/" || AlfredModel.slashQueryFrom(slashPending) === "/"
      if (warming && (slashProcess.running || slashDebounce.running || root.slashCatalog.length === 0))
        return
      slashPending = ""
      slashLoading = false
      slashDebounce.stop()
      return
    }
    slashPending = value === "" ? "/" : value
    if (query === "/" && root.slashCatalog.length > 0) {
      slashItems = root.slashCatalog
      slashQuery = "/"
      slashLoading = false
      return
    }
    if (query !== "/" && root.slashCatalog.length > 0) {
      slashItems = root.filterSlashCatalog(query)
      slashQuery = query
    }
    slashDebounce.restart()
  }

  function filterSlashCatalog(query) {
    var needle = String(query || "").toLowerCase()
    var name = needle.replace(/^\//, "")
    var out = []
    var i
    for (i = 0; i < root.slashCatalog.length; i++) {
      var item = root.slashCatalog[i]
      var text = String(item.text || "").toLowerCase()
      var meta = String(item.meta || "").toLowerCase()
      if (needle === "/" || text.indexOf(needle) === 0 || (name !== "" && (text.indexOf(name) >= 0 || meta.indexOf(name) >= 0)))
        out.push(item)
    }
    return out
  }

  function applySlashResult(raw, requested) {
    var parsed = AlfredModel.parseSlash(raw)
    var query = AlfredModel.slashQueryFrom(requested)
    if (query === "/" && parsed.items.length > 0) root.slashCatalog = parsed.items
    if (root.slashPending !== requested) return
    slashQuery = query
    slashItems = parsed.items
    slashLoading = false
  }

  function requestFocus() {
    root.hudOpen = true
    root.hudFocused = true
    if (shell && typeof shell.summon === "function") shell.summon("kiwel.alfred", "{}")
    root.focusRequested()
  }

  function requestCompact() {
    if (!root.hudOpen) return
    root.hudFocused = false
    root.compactRequested()
  }

  function requestHide() {
    root.hudOpen = false
    root.hudFocused = false
    if (root.listening) root.cancelVoice()
    root.hideRequested()
  }

  function applyStatus(raw) {
    var parsed = AlfredModel.parseStatus(raw)
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
    pendingPrompt = ""
    awaitingPermission = false
    if (aborting) {
      aborting = false
      lastError = ""
      lastOutcome = ""
      return
    }
    var reply = AlfredModel.parseReply(stdoutText)
    var err = String(stderrText || "").trim()
    if (exitCode !== 0) {
      lastError = err !== "" ? AlfredModel.previewText(err, 240) : ("Alfred exited " + exitCode)
      lastOutcome = "error"
      if (reply !== "") {
        lastReply = reply
        messages = AlfredModel.appendMessage(messages, "assistant", reply)
        root.replyReceived(reply)
      }
      return
    }
    if (reply === "") reply = err
    if (reply === "") reply = "(no output)"
    lastError = ""
    lastOutcome = "success"
    lastReply = reply
    messages = AlfredModel.appendMessage(messages, "assistant", reply)
    root.replyReceived(reply)
  }

  IpcHandler {
    target: "kiwel.alfred"
    function open(): string { root.requestFocus(); return "ok" }
    function show(): string { root.requestFocus(); return "ok" }
    function close(): string { root.requestHide(); return "ok" }
    function hide(): string { root.requestHide(); return "ok" }
    function toggle(): string {
      if (!root.hudOpen) root.requestFocus()
      else if (root.hudFocused) root.requestHide()
      else root.requestFocus()
      return "ok"
    }
    function focus(): string { root.requestFocus(); return "ok" }
    function send(text: string): string {
      root.requestFocus()
      root.sendPrompt(text)
      return "ok"
    }
    function ping(): string { return "ok" }
    function state(): string {
      if (!root.hudOpen) return "hidden"
      if (root.hudFocused) return "focused"
      return "compact"
    }
  }

  Timer {
    interval: 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
  }

  Timer {
    id: pickLaunch
    interval: 80
    repeat: false
    onTriggered: {
      Quickshell.execDetached([
        "fish", "--no-config",
        root.pluginDir + "/scripts/pick-files.fish",
        root.pickMode, root.pickOutPath, root.pickDonePath
      ])
    }
  }

  Timer {
    id: pickTimeout
    interval: 300000
    repeat: false
    onTriggered: {
      if (!root.pickingFiles) return
      pickWait.running = false
      root.pickExitCode = 1
      root.finishPickFromFiles()
    }
  }

  Process {
    id: pickWait
    running: false
    stdout: StdioCollector {
      id: pickWaitOut
      waitForEnd: true
    }
    onExited: function() {
      if (!root.pickingFiles) return
      var text = String(pickWaitOut.text || "")
      var marker = "__ALFRED_OUT__"
      var at = text.indexOf(marker)
      var head = at >= 0 ? text.substring(0, at) : text
      var body = at >= 0 ? text.substring(at + marker.length) : ""
      var code = Number(String(head || "").trim())
      if (!isFinite(code)) code = 1
      root.pickExitCode = code
      root.pickOutRaw = body
      Qt.callLater(root.finishPickFromFiles)
    }
  }

  Timer {
    id: transcribeDelay
    interval: 200
    repeat: false
    onTriggered: {
      if (root.voicePath === "") return
      root.transcribing = true
      transcribeProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/transcribe.fish", root.voicePath]
      transcribeProcess.running = true
    }
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
    stdout: SplitParser {
      onRead: function(line) {
        root.sendOutBuf += String(line || "") + "\n"
        root.ingestAgentLine(line)
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        root.sendErrBuf += String(line || "") + "\n"
        root.ingestAgentLine(line)
      }
    }
    onExited: function(exitCode) {
      root.finishSend(exitCode, root.sendOutBuf, root.sendErrBuf)
    }
  }

  Process {
    id: pickProcess
    running: false
    stdout: StdioCollector {
      id: pickOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: pickErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0) root.addAttachments(pickOut.text)
      else if (exitCode !== 1) {
        var err = String(pickErr.text || "").trim()
        if (err !== "") {
          root.lastError = AlfredModel.previewText(err, 240)
          root.lastOutcome = "error"
        }
      }
      root.requestFocus()
    }
  }

  Process {
    id: modelsProcess
    running: false
    stdout: StdioCollector {
      id: modelsOut
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      root.applyModels(modelsOut.text)
    }
  }

  Process {
    id: setModelProcess
    running: false
    stdout: StdioCollector {
      id: setModelOut
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      root.applyModels(setModelOut.text)
      root.refreshModels()
    }
  }

  Process {
    id: transcribeProcess
    running: false
    stdout: StdioCollector {
      id: transcribeOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: transcribeErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.transcribing = false
      var parsed = AlfredModel.parseTranscript(transcribeOut.text)
      var text = String(parsed.transcript || "").trim()
      if (exitCode !== 0 && text === "") {
        var err = String(transcribeErr.text || parsed.error || "").trim()
        if (err !== "") root.lastError = AlfredModel.previewText(err, 240)
        root.transcriptReady("")
        return
      }
      root.transcriptReady(text)
    }
  }

  Timer {
    id: slashDebounce
    interval: 70
    repeat: false
    onTriggered: {
      if (AlfredModel.slashQueryFrom(root.slashPending) === "") return
      if (slashProcess.running) return
      root.slashLoading = root.slashItems.length === 0
      root.slashRequested = root.slashPending
      slashProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/slash.fish", root.slashPending]
      slashProcess.running = true
    }
  }

  Process {
    id: slashProcess
    running: false
    stdout: StdioCollector {
      id: slashOut
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      root.applySlashResult(slashOut.text, root.slashRequested)
      if (root.slashPending !== root.slashRequested && AlfredModel.slashQueryFrom(root.slashPending) !== "")
        slashDebounce.restart()
    }
  }

  Process {
    id: effortProcess
    running: false
    stdout: StdioCollector {
      id: effortOut
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      root.applyEffort(effortOut.text)
    }
  }

  Process {
    id: setEffortProcess
    running: false
    stdout: StdioCollector {
      id: setEffortOut
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      root.applyEffort(setEffortOut.text)
    }
  }

  Process {
    id: gatewaysProcess
    running: false
    stdout: StdioCollector {
      id: gatewaysOut
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      root.applyGateways(gatewaysOut.text)
    }
  }

  Process {
    id: setGatewayProcess
    running: false
    stdout: StdioCollector {
      id: setGatewayOut
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      root.applyGateways(setGatewayOut.text)
      root.refreshStatus()
    }
  }

  Process {
    id: profilesProcess
    running: false
    stdout: StdioCollector {
      id: profilesOut
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      root.applyProfiles(profilesOut.text)
    }
  }

  Process {
    id: setProfileProcess
    running: false
    stdout: StdioCollector {
      id: setProfileOut
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      root.applyProfiles(setProfileOut.text)
      root.afterProfileChange()
    }
  }

  Process {
    id: voiceProcess
    running: false
    onExited: function() {
      if (root.listening) root.listening = false
    }
  }

  Component.onCompleted: {
    root.refreshStatus()
    root.refreshProfiles()
    root.refreshModels()
    root.refreshEffort()
    root.refreshGateways()
    root.prefetchSlash()
  }
}
