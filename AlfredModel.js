function pluginDirFromUrl(url) {
  var value = String(url || "")
  if (value.indexOf("file://") === 0)
    value = decodeURIComponent(value.substring(7))
  return value.replace(/\/$/, "")
}

function butlerGlyph() {
  return "󰙃"
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "")
    return { ok: false, active: false, state: "unknown", lastError: "empty status" }
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object")
      return { ok: false, active: false, state: "unknown", lastError: "bad status json" }
    return {
      ok: true,
      active: parsed.active === true,
      state: String(parsed.state || (parsed.active === true ? "active" : "down")),
      lastError: String(parsed.lastError || "")
    }
  } catch (e) {
    var active = text === "active" || text === "active\n"
    return {
      ok: true,
      active: active,
      state: active ? "active" : text,
      lastError: ""
    }
  }
}

function parseReply(raw) {
  var text = String(raw || "").replace(/\s+$/, "")
  if (text === "") return ""
  var lines = text.split("\n")
  while (lines.length > 0) {
    var line = String(lines[lines.length - 1] || "").trim()
    if (line === "") {
      lines.pop()
      continue
    }
    if (/^session[:\s]/i.test(line)) {
      lines.pop()
      continue
    }
    if (/^id[:\s]/i.test(line) && line.length < 80) {
      lines.pop()
      continue
    }
    break
  }
  return lines.join("\n").replace(/\s+$/, "")
}

function clipMessages(messages, limit) {
  var list = Array.isArray(messages) ? messages.slice() : []
  var cap = Number(limit)
  if (!isFinite(cap) || cap < 1) cap = 40
  if (list.length > cap) list = list.slice(list.length - cap)
  return list
}

var MESSAGE_CAP = 200

function appendMessage(messages, role, text) {
  var next = clipMessages(messages, MESSAGE_CAP - 1)
  next.push({
    role: String(role || "assistant"),
    text: String(text || "")
  })
  return next
}

function previewText(text, max) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  var cap = Number(max)
  if (!isFinite(cap) || cap < 8) cap = 80
  if (value.length <= cap) return value
  return value.substring(0, cap - 1) + "…"
}

function fileName(path) {
  var value = String(path || "").replace(/\/+$/, "")
  var parts = value.split("/")
  return parts.length ? parts[parts.length - 1] : value
}

function splitPaths(raw) {
  var text = String(raw || "").replace(/\r/g, "")
  var lines = text.split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = String(lines[i] || "").trim()
    if (line !== "") out.push(line)
  }
  return out
}

function shortModelName(name) {
  var value = String(name || "").trim()
  if (value === "") return "Model"
  var slash = value.lastIndexOf("/")
  if (slash >= 0 && slash < value.length - 1) value = value.substring(slash + 1)
  return value
}

function effortLabel(level) {
  var key = String(level || "").toLowerCase()
  var map = {
    none: "Off",
    minimal: "Min",
    low: "Low",
    medium: "Med",
    high: "High",
    xhigh: "XHigh",
    max: "Max",
    ultra: "Ultra"
  }
  return map[key] || (key !== "" ? key : "Med")
}

function parseModels(raw) {
  var text = String(raw || "").trim()
  var empty = { ok: false, provider: "", current: "", models: [] }
  if (text === "") return empty
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return empty
    var list = []
    var models = parsed.models
    var i
    if (Array.isArray(models)) {
      for (i = 0; i < models.length; i++) {
        var item = models[i]
        var id = typeof item === "string" ? item : (item && item.id ? String(item.id) : "")
        if (id !== "") list.push(id)
      }
    }
    return {
      ok: parsed.ok !== false,
      provider: String(parsed.provider || ""),
      current: String(parsed.current || parsed.default || ""),
      models: list
    }
  } catch (e) {
    return empty
  }
}

function parseEffort(raw) {
  var text = String(raw || "").trim()
  var empty = { ok: false, current: "medium", options: ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"] }
  if (text === "") return empty
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return empty
    var options = Array.isArray(parsed.options) ? parsed.options.map(function(v) { return String(v) }) : empty.options
    return {
      ok: parsed.ok !== false,
      current: String(parsed.current || "medium").toLowerCase(),
      options: options
    }
  } catch (e) {
    return empty
  }
}

function parseGateways(raw) {
  var text = String(raw || "").trim()
  var empty = { ok: false, current: "local", label: "This device", kind: "local", url: "", connections: [] }
  if (text === "") return empty
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return empty
    var list = []
    var rows = Array.isArray(parsed.connections) ? parsed.connections : []
    var i
    for (i = 0; i < rows.length; i++) {
      var row = rows[i]
      if (!row || typeof row !== "object") continue
      var id = String(row.id || "").trim()
      if (id === "") continue
      list.push({
        id: id,
        label: String(row.label || id),
        kind: String(row.kind || "local"),
        url: String(row.url || ""),
        selected: row.selected === true || id === String(parsed.current || ""),
        reachable: row.reachable !== false,
        gateway_running: row.gateway_running === true
      })
    }
    return {
      ok: parsed.ok !== false,
      current: String(parsed.current || "local"),
      label: String(parsed.label || parsed.current || "This device"),
      kind: String(parsed.kind || "local"),
      url: String(parsed.url || ""),
      connections: list
    }
  } catch (e) {
    return empty
  }
}

function parseRoster(raw) {
  var text = String(raw || "").trim()
  var empty = {
    ok: false, current: "", profileName: "default", label: "default",
    gatewayId: "local", gatewayLabel: "This device", gatewayKind: "local",
    shape: "cercle", fill: "#0a0a0c", expression: "neutre", idle: 0, phase: 0,
    eyes: "soft", profiles: [], bindsChanged: false
  }
  if (text === "") return empty
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return empty
    var list = []
    var rows = Array.isArray(parsed.profiles) ? parsed.profiles : []
    var i
    for (i = 0; i < rows.length; i++) {
      var row = rows[i]
      if (!row || typeof row !== "object") continue
      var key = String(row.key || row.id || "").trim()
      if (key === "") continue
      list.push({
        key: key,
        id: key,
        profileId: String(row.profileId || ""),
        gatewayId: String(row.gatewayId || "local"),
        gatewayLabel: String(row.gatewayLabel || ""),
        gatewayKind: String(row.gatewayKind || "local"),
        label: String(row.label || key),
        model: String(row.model || ""),
        shortcut: String(row.shortcut || ""),
        globalShortcut: String(row.globalShortcut || ""),
        shape: String(row.shape || "cercle"),
        fill: String(row.fill || "#0a0a0c"),
        expression: String(row.expression || "neutre"),
        idle: Number(row.idle || 0),
        phase: Number(row.phase || 0),
        eyes: String(row.eyes || "soft"),
        selected: row.selected === true || key === String(parsed.current || "")
      })
    }
    var current = String(parsed.current || "")
    var selected = null
    for (i = 0; i < list.length; i++) {
      if (list[i].key === current) selected = list[i]
    }
    if (!selected && list.length > 0) selected = list[0]
    return {
      ok: parsed.ok !== false && list.length > 0,
      current: selected ? selected.key : current,
      profileName: String(parsed.profileName || (selected ? selected.profileId : "default")),
      label: String(parsed.label || (selected ? selected.label : "default")),
      gatewayId: String(parsed.gatewayId || (selected ? selected.gatewayId : "local")),
      gatewayLabel: String(parsed.gatewayLabel || (selected ? selected.gatewayLabel : "This device")),
      gatewayKind: String(parsed.gatewayKind || (selected ? selected.gatewayKind : "local")),
      model: String(parsed.model || ""),
      shape: String(parsed.shape || (selected ? selected.shape : "cercle")),
      fill: String(parsed.fill || (selected ? selected.fill : "#0a0a0c")),
      expression: String(parsed.expression || (selected ? selected.expression : "neutre")),
      idle: Number(parsed.idle !== undefined && parsed.idle !== "" ? parsed.idle : (selected ? selected.idle : 0)),
      phase: Number(parsed.phase !== undefined && parsed.phase !== "" ? parsed.phase : (selected ? selected.phase : 0)),
      eyes: String(parsed.eyes || (selected ? selected.eyes : "soft")),
      profiles: list,
      bindsChanged: parsed.bindsChanged === true
    }
  } catch (e) {
    return empty
  }
}

// "id:<session>" is only valid on the gateway+profile that issued it; elsewhere start a fresh session.
function scopedSessionRef(sessionRef, sessionScope, profileKey) {
  var ref = String(sessionRef || "")
  var scope = String(sessionScope || "")
  if (ref.indexOf("id:") !== 0) return ref
  if (scope === "" || scope === String(profileKey || "")) return ref
  return ""
}

function rosterKeyForGateway(roster, gatewayId, profileName) {
  var rows = Array.isArray(roster) ? roster : []
  var gid = String(gatewayId || "")
  var want = String(profileName || "")
  var fallback = ""
  var first = ""
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (!row || String(row.gatewayId) !== gid) continue
    if (String(row.profileId) === want) return String(row.key)
    if (String(row.profileId) === "default" && fallback === "") fallback = String(row.key)
    if (first === "") first = String(row.key)
  }
  return fallback !== "" ? fallback : first
}

function parseProfiles(raw) {
  var text = String(raw || "").trim()
  var empty = { ok: false, current: "default", label: "default", profiles: [] }
  if (text === "") return empty
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return empty
    var list = []
    var rows = Array.isArray(parsed.profiles) ? parsed.profiles : []
    var i
    for (i = 0; i < rows.length; i++) {
      var row = rows[i]
      if (!row || typeof row !== "object") continue
      var id = String(row.id || "").trim()
      if (id === "") continue
      list.push({
        id: id,
        label: String(row.label || id),
        model: String(row.model || ""),
        provider: String(row.provider || ""),
        description: String(row.description || ""),
        isDefault: row.isDefault === true,
        gatewayRunning: row.gatewayRunning === true,
        selected: row.selected === true || id === String(parsed.current || "")
      })
    }
    return {
      ok: parsed.ok !== false,
      current: String(parsed.current || "default"),
      label: String(parsed.label || parsed.current || "default"),
      model: String(parsed.model || ""),
      provider: String(parsed.provider || ""),
      profiles: list
    }
  } catch (e) {
    return empty
  }
}

function parseStreamEvent(line) {
  var text = String(line || "").trim()
  if (text === "" || text.charAt(0) !== "{") return null
  try {
    var parsed = JSON.parse(text)
    if (parsed && typeof parsed === "object" && typeof parsed.type === "string") return parsed
  } catch (e) {
  }
  return null
}

function toolSummary(name, input) {
  var args = input && typeof input === "object" ? input : {}
  var keys = ["command", "cmd", "path", "file_path", "file", "query", "url", "name", "pattern", "skill", "goal", "task"]
  var i
  for (i = 0; i < keys.length; i++) {
    var v = args[keys[i]]
    if (typeof v === "string" && v.trim() !== "") return previewText(v, 96)
  }
  for (var k in args) {
    if (typeof args[k] === "string" && args[k].trim() !== "") return previewText(args[k], 96)
  }
  return ""
}

function toolIcon(name) {
  var n = String(name || "").toLowerCase()
  if (/terminal|shell|bash|exec|command|process/.test(n)) return "terminal"
  if (/search|grep|find/.test(n)) return "search"
  if (/web|browser|http|fetch|url/.test(n)) return "globe"
  if (/write|edit|patch|replace/.test(n)) return "edit"
  if (/read|file|view|skill/.test(n)) return "file-code"
  if (/todo|plan|list/.test(n)) return "list-unordered"
  return "tools"
}

function formatDuration(ms) {
  var value = Number(ms)
  if (!isFinite(value) || value < 0) return ""
  if (value < 1000) return Math.round(value) + "ms"
  var s = value / 1000
  if (s < 60) return (s < 10 ? s.toFixed(1) : Math.round(s)) + "s"
  var m = Math.floor(s / 60)
  return m + "m" + (Math.round(s % 60) < 10 ? "0" : "") + Math.round(s % 60) + "s"
}

function chatTitle(prompt) {
  var value = previewText(prompt, 28)
  return value !== "" ? value : "New chat"
}

function parseSessions(raw) {
  var text = String(raw || "").trim()
  var empty = { ok: false, sessions: [], error: "" }
  if (text === "") return empty
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return empty
    var rows = Array.isArray(parsed.sessions) ? parsed.sessions : []
    var list = []
    var i
    for (i = 0; i < rows.length; i++) {
      var row = rows[i]
      if (!row || typeof row !== "object" || !row.id) continue
      list.push({
        id: String(row.id),
        title: String(row.title || row.id),
        preview: String(row.preview || ""),
        source: String(row.source || ""),
        lastActive: String(row.lastActive || ""),
        messageCount: Number(row.messageCount || 0)
      })
    }
    return { ok: parsed.ok !== false, sessions: list, error: String(parsed.error || "") }
  } catch (e) {
    return empty
  }
}

function parseSessionLoad(raw) {
  var text = String(raw || "").trim()
  var empty = { ok: false, id: "", title: "", messages: [], error: "bad session json" }
  if (text === "") return empty
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return empty
    var rows = Array.isArray(parsed.messages) ? parsed.messages : []
    var list = []
    var i
    for (i = 0; i < rows.length; i++) {
      var row = rows[i]
      if (!row || typeof row !== "object") continue
      list.push({ role: String(row.role || "assistant"), text: String(row.text || "") })
    }
    return {
      ok: parsed.ok !== false,
      id: String(parsed.id || ""),
      title: String(parsed.title || ""),
      messages: clipMessages(list, MESSAGE_CAP),
      error: String(parsed.error || "")
    }
  } catch (e) {
    return empty
  }
}

// Qt key codes / modifier masks (Qt::Key, Qt::KeyboardModifier).
var KEY_NAMES = {
  0x01000001: "Tab", 0x01000002: "Tab", 0x01000003: "Backspace", 0x01000004: "Return",
  0x01000005: "Return", 0x01000006: "Insert", 0x01000007: "Delete", 0x01000010: "Home",
  0x01000011: "End", 0x01000012: "Left", 0x01000013: "Up", 0x01000014: "Right",
  0x01000015: "Down", 0x01000016: "PageUp", 0x01000017: "PageDown", 0x20: "Space",
  0x2c: "Comma", 0x2e: "Period", 0x2f: "Slash", 0x2d: "Minus", 0x3d: "Equal",
  0x3b: "Semicolon", 0x27: "Apostrophe", 0x5b: "BracketLeft", 0x5d: "BracketRight",
  0x5c: "Backslash", 0x60: "Grave"
}
var MODIFIER_KEYS = [0x01000020, 0x01000021, 0x01000022, 0x01000023, 0x01001103, 0x01000053, 0x01000054]
var HYPR_KEYS = {
  Tab: "Tab", Backspace: "BackSpace", Return: "Return", Insert: "Insert", Delete: "Delete",
  Home: "Home", End: "End", Left: "left", Up: "up", Right: "right", Down: "down",
  PageUp: "Prior", PageDown: "Next", Space: "space", Comma: "comma", Period: "period",
  Slash: "slash", Minus: "minus", Equal: "equal", Semicolon: "semicolon",
  Apostrophe: "apostrophe", BracketLeft: "bracketleft", BracketRight: "bracketright",
  Backslash: "backslash", Grave: "grave"
}

function isModifierKey(key) {
  return MODIFIER_KEYS.indexOf(Number(key)) >= 0
}

function keyName(key) {
  var k = Number(key)
  if (k >= 0x41 && k <= 0x5a) return String.fromCharCode(k)
  if (k >= 0x30 && k <= 0x39) return String.fromCharCode(k)
  if (k >= 0x01000030 && k <= 0x0100003b) return "F" + (k - 0x01000030 + 1)
  return KEY_NAMES[k] || ""
}

// Returns { mods: [...], key: "N" } or null for bare modifier presses / unknown keys.
function comboFromEvent(key, modifiers) {
  if (isModifierKey(key)) return null
  var name = keyName(key)
  if (name === "") return null
  var m = Number(modifiers)
  var mods = []
  if (m & 0x04000000) mods.push("Ctrl")
  if (m & 0x02000000) mods.push("Shift")
  if (m & 0x08000000) mods.push("Alt")
  if (m & 0x10000000) mods.push("Super")
  return { mods: mods, key: name }
}

function comboText(combo) {
  if (!combo) return ""
  return combo.mods.concat([combo.key]).join("+")
}

function comboHypr(combo) {
  if (!combo) return ""
  var map = { Ctrl: "CTRL", Shift: "SHIFT", Alt: "ALT", Super: "SUPER" }
  var order = ["Super", "Ctrl", "Shift", "Alt"]
  var parts = []
  for (var i = 0; i < order.length; i++) {
    if (combo.mods.indexOf(order[i]) >= 0) parts.push(map[order[i]])
  }
  parts.push(HYPR_KEYS[combo.key] || combo.key)
  return parts.join(" + ")
}

function normalizeCombo(text) {
  var parts = String(text || "").split("+").map(function(p) { return p.trim() }).filter(function(p) { return p !== "" })
  if (parts.length === 0) return ""
  var key = parts.pop()
  var mods = []
  var order = ["Ctrl", "Shift", "Alt", "Super"]
  for (var i = 0; i < order.length; i++) {
    for (var j = 0; j < parts.length; j++) {
      if (parts[j].toLowerCase() === order[i].toLowerCase()) mods.push(order[i])
    }
  }
  return mods.concat([key.length === 1 ? key.toUpperCase() : key]).join("+")
}

function parseShortcuts(raw) {
  var empty = { ok: false, error: "", hooked: false, global: [], local: [] }
  var text = String(raw || "").trim()
  if (text === "") return empty
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return empty
    function rows(list) {
      var out = []
      var src = Array.isArray(list) ? list : []
      for (var i = 0; i < src.length; i++) {
        if (!src[i] || !src[i].id) continue
        out.push({
          id: String(src[i].id),
          label: String(src[i].label || src[i].id),
          keys: String(src[i].keys || ""),
          defaultKeys: String(src[i]["default"] || "")
        })
      }
      return out
    }
    return {
      ok: parsed.ok !== false,
      error: String(parsed.error || ""),
      hooked: parsed.hooked === true,
      global: rows(parsed.global),
      local: rows(parsed.local)
    }
  } catch (e) {
    return empty
  }
}

function attachmentIcon(path) {
  var p = String(path || "").toLowerCase()
  if (/\/$/.test(p)) return "folder"
  if (/\.(png|jpe?g|gif|webp|bmp|svg|heic|avif|tiff?)$/.test(p)) return "file-media"
  if (/\.pdf$/.test(p)) return "file-pdf"
  if (/\.(zip|tar|gz|tgz|xz|7z|rar|zst)$/.test(p)) return "file-zip"
  if (/\.(wav|mp3|ogg|flac|m4a|opus)$/.test(p)) return "mic"
  if (/\.(js|ts|tsx|py|qml|fish|sh|rs|go|c|cpp|h|java|kt|lua|json|ya?ml|toml|md|html|css)$/.test(p)) return "file-code"
  return "file"
}

function looksLikePermission(text) {
  var value = String(text || "").toLowerCase()
  if (value === "") return false
  return /approval|permission required|awaiting (your )?approval|waiting for (your )?approval|allow this|dangerous command|confirm to (run|execute)|y\/n|\[y\/n\]|tool approval|needs approval/.test(value)
}

function parseTranscript(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, transcript: "", error: "empty transcript" }
  try {
    var parsed = JSON.parse(text)
    if (parsed && typeof parsed === "object") {
      var t = String(parsed.transcript || parsed.text || "")
      var ok = parsed.success !== false && parsed.ok !== false
      return { ok: ok, transcript: t, error: String(parsed.error || "") }
    }
  } catch (e) {
  }
  return { ok: true, transcript: text, error: "" }
}

function mergePaths(existing, incoming) {
  var next = Array.isArray(existing) ? existing.slice() : []
  var seen = {}
  var i
  for (i = 0; i < next.length; i++) seen[String(next[i])] = true
  var extra = Array.isArray(incoming) ? incoming : splitPaths(incoming)
  for (i = 0; i < extra.length; i++) {
    var path = String(extra[i] || "").trim()
    if (path === "" || seen[path]) continue
    seen[path] = true
    next.push(path)
  }
  return next
}

function slashQueryFrom(text) {
  var value = String(text || "")
  var match = value.match(/(^|\s)(\/[^\s]*)$/)
  return match ? match[2] : ""
}

function parseSlash(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, items: [], query: "", error: "empty slash" }
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object")
      return { ok: false, items: [], query: "", error: "bad slash json" }
    var rows = Array.isArray(parsed.items) ? parsed.items : []
    var items = []
    var i
    for (i = 0; i < rows.length; i++) {
      var row = rows[i]
      if (!row || typeof row !== "object") continue
      var cmd = String(row.text || row.display || "").trim()
      if (cmd === "") continue
      if (cmd.charAt(0) !== "/") cmd = "/" + cmd
      cmd = cmd.split(/\s/)[0]
      items.push({
        text: cmd,
        display: String(row.display || cmd),
        meta: String(row.meta || ""),
        group: String(row.group || (String(row.kind || "") === "skill" ? "Skills" : "Commands")),
        kind: String(row.kind || "command")
      })
    }
    return {
      ok: parsed.ok !== false,
      items: items,
      query: String(parsed.query || ""),
      error: String(parsed.error || "")
    }
  } catch (e) {
    return { ok: false, items: [], query: "", error: "bad slash json" }
  }
}

function applySlashInsert(current, command) {
  var cur = String(current || "")
  var cmd = String(command || "").trim()
  if (cmd === "") return cur
  if (cmd.charAt(0) !== "/") cmd = "/" + cmd
  cmd = cmd.split(/\s/)[0]
  var name = cmd.replace(/^\//, "").toLowerCase()
  if (name !== "model" && name !== "skin" && name !== "personality") cmd += " "
  var match = cur.match(/^(.*?)(\/[^\s]*)$/)
  if (match) return match[1] + cmd
  return cmd
}
