function pluginDirFromUrl(url) {
  var value = String(url || "")
  if (value.indexOf("file://") === 0)
    value = decodeURIComponent(value.substring(7))
  return value.replace(/\/$/, "")
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
