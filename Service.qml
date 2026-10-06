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
  property real audioLevel: 0
  property bool voiceCapturing: false
  property bool voiceHearing: false
  property int voiceElapsedMs: 0
  property real voiceStartedAt: 0
  property real voiceHeardUntil: 0
  property real voiceCaptureUntil: 0
  property bool voiceStopRequested: false
  property string voiceError: ""
  property string lastError: ""
  property string statusText: "Checking…"
  property var messages: []
  property var attachments: []
  property string lastReply: ""
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
  property string profileKey: "local:default"
  property string profileShape: "cercle"
  property string profileFill: "#0a0a0c"
  property string profileExpression: "neutre"
  property int profileIdle: 0
  property real profilePhase: 0
  property string profileEyes: "soft"
  property bool statusKnown: false
  property string faceSig: ""
  property var profileOptions: []
  property var roster: []
  property bool pickingFiles: false
  property bool transcribing: false
  property bool awaitingPermission: false
  property string lastOutcome: ""
  property string pickMode: "files"
  property string pickOutPath: ""
  property string pickDonePath: ""
  property int pickExitCode: 1
  property string pickOutRaw: ""
  property var chats: []
  property string activeChatId: ""
  property int chatSeq: 0
  property int busyCount: 0
  readonly property bool anyBusy: busyCount > 0
  property var activity: []
  property string liveText: ""
  property real busyStartedAt: 0
  // Per-chat stream buffers and Process handles; mutated in place, flushed into `chats` by flushTimer.
  property var runtime: ({})
  property var runners: ({})
  // Prompt typed while an agent switch is still running; sent once the new gateway+profile is active.
  property var pendingSend: null
  property string pendingProfileKey: ""
  property var pendingFace: null
  property string rosterWriteKind: ""
  property int rosterSeq: 0
  property var sessionOptions: []
  property bool sessionsLoading: false
  property string sessionsError: ""
  property string loadingSessionChat: ""
  property var shortcutsGlobal: []
  property var shortcutsLocal: []
  property bool shortcutsHooked: false
  property string shortcutsError: ""
  property bool shortcutsSaving: false
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
  signal voiceRequested()
  signal menuRequested(string kind)
  signal replyReceived(string text)
  signal transcriptReady(string text)

  function refreshStatus() {
    if (statusProcess.running) return
    statusProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/status.fish"]
    statusProcess.running = true
  }

  function makeChat(sessionRef, title) {
    root.chatSeq += 1
    return {
      id: "chat" + root.chatSeq,
      title: String(title || "New chat"),
      sessionRef: String(sessionRef || ""),
      // Roster key (gateway:profile) that issued an "id:" sessionRef; ids never cross agents.
      sessionScope: "",
      messages: [],
      busy: false,
      lastError: "",
      lastOutcome: "",
      lastReply: "",
      awaitingPermission: false,
      activity: [],
      liveText: "",
      startedAt: 0
    }
  }

  function chatIndex(id) {
    var want = String(id || "")
    var i
    for (i = 0; i < root.chats.length; i++) {
      if (String(root.chats[i].id) === want) return i
    }
    return -1
  }

  function activeChat() {
    var i = root.chatIndex(root.activeChatId)
    return i >= 0 ? root.chats[i] : null
  }

  function ensureChat() {
    if (root.chats.length > 0 && root.activeChat()) return
    if (root.chats.length > 0) {
      root.activeChatId = root.chats[0].id
    } else {
      var first = root.makeChat(root.sessionName, "Alfred")
      root.chats = [first]
      root.activeChatId = first.id
    }
    root.syncActive()
  }

  function patchChat(id, patch) {
    var idx = root.chatIndex(id)
    if (idx < 0) return
    var list = root.chats.slice()
    var next = Object.assign({}, list[idx])
    for (var key in patch) next[key] = patch[key]
    list[idx] = next
    root.chats = list
    if (String(id) === root.activeChatId) root.syncActive()
    root.syncBusy()
  }

  function syncActive() {
    var c = root.activeChat()
    if (!c) return
    messages = c.messages
    busy = c.busy === true
    lastError = String(c.lastError || "")
    lastOutcome = String(c.lastOutcome || "")
    lastReply = String(c.lastReply || "")
    awaitingPermission = c.awaitingPermission === true
    activity = c.activity || []
    liveText = String(c.liveText || "")
    busyStartedAt = Number(c.startedAt || 0)
  }

  function syncBusy() {
    var n = 0
    var i
    for (i = 0; i < root.chats.length; i++) {
      if (root.chats[i].busy === true) n += 1
    }
    busyCount = n
  }

  function setActiveError(message) {
    root.ensureChat()
    var msg = String(message || "")
    root.patchChat(root.activeChatId, { lastError: msg, lastOutcome: msg !== "" ? "error" : "" })
  }

  function newChat() {
    root.ensureChat()
    var cur = root.activeChat()
    if (cur && !cur.busy && cur.messages.length === 0 && cur.sessionRef === "") return cur.id
    var c = root.makeChat("", "New chat")
    root.chats = root.chats.concat([c])
    root.activeChatId = c.id
    root.syncActive()
    return c.id
  }

  function switchChat(id) {
    if (root.chatIndex(id) < 0) return
    root.activeChatId = String(id)
    root.syncActive()
  }

  function cycleChat(delta) {
    var n = root.chats.length
    if (n < 2) return
    var idx = root.chatIndex(root.activeChatId)
    root.switchChat(root.chats[((idx + delta) % n + n) % n].id)
  }

  function closeChat(id) {
    var idx = root.chatIndex(id)
    if (idx < 0) return
    var runner = root.runners[id]
    if (runner) {
      if (root.runtime[id]) root.runtime[id].aborting = true
      runner.running = false
    }
    var list = root.chats.slice()
    list.splice(idx, 1)
    if (list.length === 0) list.push(root.makeChat("", "New chat"))
    root.chats = list
    if (root.chatIndex(root.activeChatId) < 0)
      root.activeChatId = list[Math.min(idx, list.length - 1)].id
    root.syncActive()
    root.syncBusy()
  }

  function sendPrompt(text, targetId) {
    root.ensureChat()
    var targetIdx = targetId ? root.chatIndex(targetId) : -1
    var chat = targetIdx >= 0 ? root.chats[targetIdx] : root.activeChat()
    var prompt = String(text || "").trim()
    if (prompt === "" && root.attachments.length === 0) return false
    if (chat.busy) {
      root.setActiveError("This chat is still answering. Open a new chat (Ctrl+N) for another task.")
      return false
    }
    if (setRosterProcess.running) {
      root.pendingSend = { chatId: chat.id, text: prompt, attachments: root.attachments.slice() }
      attachments = []
      return true
    }
    if (prompt === "") prompt = "Use the attached files as context."
    var id = chat.id
    var sessionRef = AlfredModel.scopedSessionRef(chat.sessionRef, chat.sessionScope, root.profileKey)
    root.runtime[id] = {
      out: "", err: "", text: "", result: "", resultError: "", sessionId: "",
      scope: root.profileKey,
      activity: [], permission: false, aborting: false, dirty: false
    }
    var patch = {
      messages: AlfredModel.appendMessage(chat.messages, "user", prompt),
      busy: true,
      lastError: "",
      lastReply: "",
      lastOutcome: "",
      awaitingPermission: false,
      activity: [],
      liveText: "",
      startedAt: Date.now()
    }
    if (chat.title === "New chat") patch.title = AlfredModel.chatTitle(prompt)
    root.patchChat(id, patch)
    var cmd = ["fish", "--no-config", root.pluginDir + "/scripts/send.fish", sessionRef, prompt]
    for (var i = 0; i < root.attachments.length; i++) cmd.push(root.attachments[i])
    var runner = sendRunner.createObject(root, { chatId: id, command: cmd })
    root.runners[id] = runner
    runner.running = true
    attachments = []
    flushTimer.start()
    return true
  }

  function flushPendingSend() {
    var pending = root.pendingSend
    root.pendingSend = null
    if (!pending || root.chatIndex(pending.chatId) < 0) return
    attachments = pending.attachments
    root.sendPrompt(pending.text, pending.chatId)
  }

  function ingestSendLine(id, line, fromStderr) {
    var rt = root.runtime[id]
    if (!rt) return
    var value = String(line || "")
    var ev = fromStderr ? null : AlfredModel.parseStreamEvent(value)
    if (ev) {
      root.applyStreamEvent(rt, ev)
    } else {
      if (fromStderr) rt.err += value + "\n"
      else rt.out += value + "\n"
      if (AlfredModel.looksLikePermission(value)) rt.permission = true
    }
    rt.dirty = true
  }

  function applyStreamEvent(rt, ev) {
    var type = String(ev.type || "")
    var i
    if (type === "system") {
      if (ev.session_id) rt.sessionId = String(ev.session_id)
    } else if (type === "text") {
      rt.text += String(ev.text || "")
    } else if (type === "tool_use") {
      rt.activity.push({
        key: String(ev.tool_call_id || ev.name || ""),
        name: String(ev.name || "tool"),
        icon: AlfredModel.toolIcon(ev.name),
        summary: AlfredModel.toolSummary(ev.name, ev.input),
        status: "running",
        startedAt: Number(ev.timestamp || Date.now()),
        durationMs: 0,
        output: ""
      })
      if (rt.activity.length > 80) rt.activity.shift()
    } else if (type === "tool_result") {
      var key = String(ev.tool_call_id || ev.name || "")
      for (i = rt.activity.length - 1; i >= 0; i--) {
        var row = rt.activity[i]
        if (row.status !== "running") continue
        if (row.key !== key && row.name !== String(ev.name || "")) continue
        row.status = ev.is_error === true ? "error" : "done"
        row.durationMs = Number(ev.duration_ms || 0)
        row.output = AlfredModel.previewText(ev.output, 160)
        break
      }
    } else if (type === "result") {
      rt.result = String(ev.text || "")
      if (ev.session_id) rt.sessionId = String(ev.session_id)
      if (ev.error) rt.resultError = String(ev.error)
    }
  }

  function flushRuntime(id) {
    var rt = root.runtime[id]
    if (!rt || !rt.dirty) return
    rt.dirty = false
    var tail = rt.text.length > 1200 ? rt.text.substring(rt.text.length - 1200) : rt.text
    root.patchChat(id, {
      activity: rt.activity.map(function(r) { return Object.assign({}, r) }),
      liveText: tail,
      awaitingPermission: rt.permission === true
    })
  }

  function flushAllRuntime() {
    for (var id in root.runtime) root.flushRuntime(id)
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
    else if (code === 127) root.setActiveError("No file picker (GTK portal / zenity)")
    else if (code !== 1) root.setActiveError("File picker failed")
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
    var id = root.activeChatId
    var runner = root.runners[id]
    if (!runner) return false
    if (root.runtime[id]) root.runtime[id].aborting = true
    runner.running = false
    return true
  }

  function refreshShortcuts() {
    if (shortcutsProcess.running) return
    shortcutsProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/shortcuts.fish", "get"]
    shortcutsProcess.running = true
  }

  function setShortcut(scope, id, keys) {
    if (shortcutsProcess.running) return false
    shortcutsSaving = true
    shortcutsProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/shortcuts.fish", "set", String(scope), String(id), String(keys)]
    shortcutsProcess.running = true
    return true
  }

  function applyShortcuts(raw) {
    var parsed = AlfredModel.parseShortcuts(raw)
    shortcutsSaving = false
    shortcutsError = parsed.error
    shortcutsHooked = parsed.hooked
    if (parsed.global.length > 0) shortcutsGlobal = parsed.global
    if (parsed.local.length > 0) shortcutsLocal = parsed.local
  }

  function localShortcut(id) {
    for (var i = 0; i < root.shortcutsLocal.length; i++) {
      if (root.shortcutsLocal[i].id === id) return root.shortcutsLocal[i].keys
    }
    return ""
  }

  function refreshSessions() {
    if (sessionsProcess.running) return
    sessionsLoading = true
    sessionsProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/sessions.fish", "list", "40"]
    sessionsProcess.running = true
  }

  function openSession(sessionId, title) {
    var sid = String(sessionId || "").trim()
    if (sid === "") return
    root.ensureChat()
    var ref = "id:" + sid
    var i
    for (i = 0; i < root.chats.length; i++) {
      if (root.chats[i].sessionRef === ref) {
        root.switchChat(root.chats[i].id)
        return
      }
    }
    var label = AlfredModel.chatTitle(title || sid)
    var cur = root.activeChat()
    var target = ""
    if (cur && !cur.busy && cur.messages.length === 0) {
      target = cur.id
      root.patchChat(target, { sessionRef: ref, sessionScope: root.profileKey, title: label, lastError: "", lastOutcome: "" })
    } else {
      var c = root.makeChat(ref, label)
      c.sessionScope = root.profileKey
      root.chats = root.chats.concat([c])
      root.activeChatId = c.id
      root.syncActive()
      target = c.id
    }
    if (loadSessionProcess.running) loadSessionProcess.running = false
    root.loadingSessionChat = target
    loadSessionProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/sessions.fish", "load", sid]
    loadSessionProcess.running = true
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
    gatewaysProcess.startedSeq = root.rosterSeq
    gatewaysProcess.running = true
  }

  function setGateway(id) {
    var value = String(id || "").trim()
    if (value === "") return false
    // Gateway and profile move together: pick the same profile on the new gateway, else its default.
    var key = AlfredModel.rosterKeyForGateway(root.roster, value, root.profileName)
    if (key !== "") return root.selectProfile(key)
    if (setGatewayProcess.running) return false
    root.rosterSeq += 1
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
    root.refreshRoster()
  }

  function refreshRoster() {
    if (rosterProcess.running || setRosterProcess.running) return
    rosterProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/roster.fish", "list"]
    rosterProcess.startedSeq = root.rosterSeq
    rosterProcess.running = true
  }

  function setProfile(id) {
    return root.selectProfile(id)
  }

  function selectProfile(key) {
    var value = String(key || "").trim()
    if (value === "") return false
    if (setRosterProcess.running) {
      root.pendingProfileKey = value
      return true
    }
    root.rosterWriteKind = "set"
    root.rosterSeq += 1
    setRosterProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/roster.fish", "set", value]
    setRosterProcess.running = true
    return true
  }

  // One writer. A list or a selection already in flight keeps the face edit queued.
  function setFace(key, shape, fill, expression, idle) {
    var value = String(key || "").trim()
    if (value === "") return false
    var job = {
      op: "face",
      key: value,
      shape: String(shape || "").trim(),
      fill: String(fill || "").trim(),
      expression: String(expression || "").trim(),
      idle: idle === undefined || idle === null ? "" : String(idle)
    }
    if (setRosterProcess.running || rosterProcess.running) {
      root.pendingFace = job
      return true
    }
    root.startFaceJob(job)
    return true
  }

  function resetFace(key) {
    var value = String(key || "").trim()
    if (value === "") return false
    var job = { op: "face-reset", key: value, shape: "", fill: "", expression: "" }
    if (setRosterProcess.running || rosterProcess.running) {
      root.pendingFace = job
      return true
    }
    root.startFaceJob(job)
    return true
  }

  function startFaceJob(job) {
    if (!job) return
    if (setRosterProcess.running || rosterProcess.running) {
      root.pendingFace = job
      return
    }
    var op = String(job.op || "face")
    var key = String(job.key || "").trim()
    if (key === "") return
    root.rosterWriteKind = op
    root.rosterSeq += 1
    if (op === "face-reset")
      setRosterProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/roster.fish", "face-reset", key]
    else
      setRosterProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/roster.fish", "face", key, String(job.shape || ""), String(job.fill || ""), String(job.expression || ""), String(job.idle === undefined || job.idle === null ? "" : job.idle)]
    setRosterProcess.running = true
  }

  function applyRoster(raw) {
    var parsed = AlfredModel.parseRoster(raw)
    if (!parsed.ok) return
    if (parsed.profiles.length > 0) {
      roster = parsed.profiles
      profileOptions = parsed.profiles
    }
    if (parsed.current !== "") profileKey = parsed.current
    if (parsed.profileName !== "") profileName = parsed.profileName
    if (parsed.label !== "") profileLabel = parsed.label
    if (parsed.gatewayId !== "") gatewayConnectionId = parsed.gatewayId
    if (parsed.gatewayLabel !== "") gatewayLabel = parsed.gatewayLabel
    if (parsed.gatewayKind !== "") gatewayKind = parsed.gatewayKind
    if (parsed.shape !== "") profileShape = parsed.shape
    if (parsed.fill !== "") profileFill = parsed.fill
    if (parsed.expression !== "") profileExpression = parsed.expression
    profileIdle = parsed.idle
    profilePhase = parsed.phase
    if (parsed.eyes !== "") profileEyes = parsed.eyes
    if (parsed.model !== "") modelName = parsed.model
    if (parsed.bindsChanged) root.refreshShortcuts()
    root.publishFace()
  }

  // The replacement bar cannot see this service (its shell facade has no
  // service lookup). The tray reads this snapshot instead.
  function publishFace() {
    var mood = "idle"
    if (root.listening) mood = "listening"
    else if (root.awaitingPermission) mood = "attention"
    else if (root.busy) mood = "busy"
    else if (root.lastOutcome === "error") mood = "error"
    else if (root.lastOutcome === "success") mood = "success"
    else if (root.statusKnown && !root.gatewayActive) mood = "error"
    var payload = JSON.stringify({
      key: root.profileKey,
      label: root.profileLabel,
      shape: root.profileShape,
      fill: root.profileFill,
      expression: root.profileExpression,
      idle: root.profileIdle,
      phase: root.profilePhase,
      eyes: root.profileEyes,
      mood: mood
    })
    if (payload === root.faceSig) return
    root.faceSig = payload
    faceFile.setText(payload + "\n")
  }

  function applyProfiles(raw) {
    root.applyRoster(raw)
  }

  function afterProfileChange() {
    slashCatalog = []
    slashItems = []
    sessionOptions = []
    root.refreshModels()
    root.refreshEffort()
    root.refreshStatus()
    root.prefetchSlash()
  }

  function toggleVoice() {
    if (root.listening) root.stopVoice()
    else root.startVoice()
  }

  function ingestVoiceLevel(line) {
    var text = String(line || "").trim()
    if (text.indexOf("LEVEL ") !== 0) return
    var parts = text.split(" ")
    var level = Number(parts[1])
    if (!isFinite(level)) level = 0
    level = Math.max(0, Math.min(1, level))
    root.audioLevel = root.audioLevel * 0.35 + level * 0.65
    if (parts[2] === "1") {
      root.voiceCapturing = true
      root.voiceCaptureUntil = Date.now() + 450
    } else if (Date.now() > root.voiceCaptureUntil) {
      root.voiceCapturing = false
    }
    if (parts[3] === "1") {
      root.voiceHearing = true
      root.voiceHeardUntil = Date.now() + 700
    }
  }

  function noteVoiceError(line) {
    var text = String(line || "").trim()
    if (text !== "") root.voiceError = text
  }

  function startVoice() {
    if (voiceProcess.running || root.transcribing) return
    voicePath = root.runtimeDir + "/alfred-voice.wav"
    root.setActiveError("")
    audioLevel = 0
    voiceCapturing = false
    voiceHearing = false
    voiceElapsedMs = 0
    voiceHeardUntil = 0
    voiceCaptureUntil = 0
    voiceError = ""
    voiceStopRequested = false
    voiceStartedAt = Date.now()
    listening = true
    voiceProcess.command = ["fish", "--no-config", root.pluginDir + "/scripts/voice.fish", "start", voicePath]
    voiceProcess.running = true
  }

  function stopVoice() {
    listening = false
    if (voiceProcess.running) {
      voiceStopRequested = true
      voiceProcess.running = false
      return
    }
    if (voicePath === "") return
    transcribeDelay.restart()
  }

  function cancelVoice() {
    listening = false
    voiceStopRequested = false
    transcribeDelay.stop()
    transcribing = false
    if (voiceProcess.running) voiceProcess.running = false
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
      root.statusKnown = true
      if (parsed.lastError) root.setActiveError(parsed.lastError)
      root.publishFace()
      return
    }
    gatewayActive = parsed.active === true
    gatewayState = parsed.state
    statusText = gatewayActive ? "Ready" : ("Gateway " + parsed.state)
    root.statusKnown = true
    if (gatewayActive && lastError.indexOf("Gateway") === 0) root.setActiveError("")
    root.publishFace()
  }

  function finishSend(id, exitCode) {
    var rt = root.runtime[id]
    delete root.runners[id]
    if (rt) root.flushRuntime(id)
    delete root.runtime[id]
    var idx = root.chatIndex(id)
    if (idx < 0 || !rt) {
      root.syncBusy()
      return
    }
    var chat = root.chats[idx]
    var patch = { busy: false, awaitingPermission: false, liveText: "" }
    if (rt.sessionId !== "") {
      patch.sessionRef = "id:" + rt.sessionId
      patch.sessionScope = rt.scope
    }
    if (rt.aborting) {
      patch.lastError = ""
      patch.lastOutcome = ""
      root.patchChat(id, patch)
      return
    }
    var reply = rt.result !== "" ? rt.result : (rt.text !== "" ? rt.text : AlfredModel.parseReply(rt.out))
    var err = rt.resultError !== "" ? rt.resultError : AlfredModel.parseReply(rt.err).trim()
    var failed = exitCode !== 0 || (reply === "" && err !== "")
    if (failed) {
      patch.lastError = err !== "" ? AlfredModel.previewText(err, 240) : ("Alfred exited " + exitCode)
      patch.lastOutcome = "error"
    } else {
      if (reply === "") reply = "(no output)"
      patch.lastError = ""
      patch.lastOutcome = "success"
    }
    if (reply !== "") {
      patch.lastReply = reply
      patch.messages = AlfredModel.appendMessage(chat.messages, "assistant", reply)
    }
    root.patchChat(id, patch)
    if (reply !== "") root.replyReceived(reply)
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
    function menu(kind: string): string {
      root.menuRequested(kind)
      return "ok"
    }
    function resume(sessionId: string): string {
      root.openSession(sessionId, "")
      return root.activeChatId
    }
    function attach(path: string): string {
      root.addAttachments(path)
      return String(root.attachments.length)
    }
    function voice(): string {
      root.voiceRequested()
      return root.listening ? "listening" : "stopped"
    }
    function newchat(): string {
      root.newChat()
      root.requestFocus()
      return "ok"
    }
    function profile(key: string): string {
      root.selectProfile(key)
      return root.profileKey
    }
    function chats(): string { return String(root.chats.length) }
    function last(): string {
      var c = root.activeChat()
      return JSON.stringify({
        profileKey: root.profileKey, gateway: root.gatewayConnectionId, gatewayUrl: root.gatewayUrl,
        busy: c ? c.busy === true : false, sessionRef: c ? c.sessionRef : "", sessionScope: c ? c.sessionScope : "",
        lastReply: c ? AlfredModel.previewText(c.lastReply, 240) : "", lastError: c ? String(c.lastError || "") : ""
      })
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

  Component {
    id: sendRunner

    Process {
      id: runner
      property string chatId: ""
      running: false
      stdout: SplitParser {
        onRead: function(line) { root.ingestSendLine(runner.chatId, line, false) }
      }
      stderr: SplitParser {
        onRead: function(line) { root.ingestSendLine(runner.chatId, line, true) }
      }
      onExited: function(exitCode) {
        root.finishSend(runner.chatId, exitCode)
        Qt.callLater(function() { runner.destroy() })
      }
    }
  }

  Timer {
    id: flushTimer
    interval: 120
    repeat: true
    running: false
    onTriggered: {
      root.flushAllRuntime()
      if (root.busyCount === 0) stop()
    }
  }

  Process {
    id: shortcutsProcess
    running: false
    stdout: StdioCollector {
      id: shortcutsOut
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() { root.applyShortcuts(shortcutsOut.text) }
  }

  Process {
    id: sessionsProcess
    running: false
    stdout: StdioCollector {
      id: sessionsOut
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      var parsed = AlfredModel.parseSessions(sessionsOut.text)
      root.sessionsLoading = false
      root.sessionsError = parsed.ok ? "" : (parsed.error || "Could not read sessions")
      if (parsed.ok) root.sessionOptions = parsed.sessions
    }
  }

  Process {
    id: loadSessionProcess
    running: false
    stdout: StdioCollector {
      id: loadSessionOut
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      var target = root.loadingSessionChat
      root.loadingSessionChat = ""
      var parsed = AlfredModel.parseSessionLoad(loadSessionOut.text)
      var idx = root.chatIndex(target)
      if (idx < 0 || root.chats[idx].busy) return
      if (!parsed.ok) {
        root.patchChat(target, { lastError: parsed.error || "Could not load session", lastOutcome: "error" })
        return
      }
      root.patchChat(target, { messages: parsed.messages, lastError: "", lastOutcome: "" })
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
        if (err !== "") root.setActiveError(AlfredModel.previewText(err, 240))
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
        if (err !== "") root.setActiveError(AlfredModel.previewText(err, 240))
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
    property int startedSeq: 0
    running: false
    stdout: StdioCollector {
      id: gatewaysOut
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      if (gatewaysProcess.startedSeq !== root.rosterSeq) {
        Qt.callLater(root.refreshGateways)
        return
      }
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
      root.refreshRoster()
      root.afterProfileChange()
    }
  }

  Process {
    id: rosterProcess
    property int startedSeq: 0
    running: false
    stdout: StdioCollector {
      id: rosterOut
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      if (rosterProcess.startedSeq === root.rosterSeq)
        root.applyRoster(rosterOut.text)
      if (!root.pendingFace || setRosterProcess.running) return
      var face = root.pendingFace
      root.pendingFace = null
      Qt.callLater(function() { root.startFaceJob(face) })
    }
  }

  Process {
    id: setRosterProcess
    running: false
    stdout: StdioCollector {
      id: setRosterOut
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      root.applyRoster(setRosterOut.text)
      var kind = root.rosterWriteKind
      root.rosterWriteKind = ""
      if (root.pendingFace && !rosterProcess.running) {
        var face = root.pendingFace
        root.pendingFace = null
        Qt.callLater(function() { root.startFaceJob(face) })
        if (kind === "set") {
          root.refreshStatus()
          root.refreshGateways()
          root.afterProfileChange()
          root.flushPendingSend()
        }
        return
      }
      var next = root.pendingProfileKey
      root.pendingProfileKey = ""
      if (next !== "" && next !== root.profileKey) {
        Qt.callLater(function() { root.selectProfile(next) })
        return
      }
      if (kind === "face" || kind === "face-reset") return
      root.refreshStatus()
      root.refreshGateways()
      root.afterProfileChange()
      root.flushPendingSend()
    }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.refreshRoster()
  }

  Timer {
    id: voiceClock
    interval: 100
    repeat: true
    running: root.listening
    onTriggered: {
      if (root.voiceStartedAt > 0)
        root.voiceElapsedMs = Math.max(0, Math.round(Date.now() - root.voiceStartedAt))
      if (root.voiceHeardUntil > 0 && Date.now() > root.voiceHeardUntil)
        root.voiceHearing = false
      if (!root.listening) return
      if (root.voiceCaptureUntil > 0 && Date.now() > root.voiceCaptureUntil)
        root.voiceCapturing = false
    }
  }

  Process {
    id: voiceProcess
    running: false
    stdout: SplitParser {
      onRead: function(line) { root.ingestVoiceLevel(line) }
    }
    stderr: SplitParser {
      onRead: function(line) { root.noteVoiceError(line) }
    }
    onExited: function(exitCode) {
      var failed = root.listening && exitCode !== 0
      if (root.listening) root.listening = false
      if (root.voiceStopRequested) {
        root.voiceStopRequested = false
        if (root.voicePath !== "") transcribeDelay.restart()
      } else if (failed) {
        var err = String(root.voiceError || "").trim()
        if (err !== "") root.setActiveError(AlfredModel.previewText(err, 240))
      }
    }
  }

  FileView {
    id: faceFile
    path: root.home + "/.config/Hermes/alfred-face.json"
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  onBusyChanged: root.publishFace()
  onListeningChanged: root.publishFace()
  onAwaitingPermissionChanged: root.publishFace()
  onLastOutcomeChanged: root.publishFace()
  onGatewayActiveChanged: root.publishFace()

  Component.onCompleted: {
    root.publishFace()
    root.ensureChat()
    root.refreshShortcuts()
    root.refreshStatus()
    root.refreshProfiles()
    root.refreshModels()
    root.refreshEffort()
    root.refreshGateways()
    root.prefetchSlash()
  }
}
