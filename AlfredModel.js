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

function appendMessage(messages, role, text) {
  var next = clipMessages(messages, 40)
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
  var value = String(path || "")
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
