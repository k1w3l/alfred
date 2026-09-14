// Tokens from Hermes Desktop HUD:
// apps/desktop/src/styles.css (:root composer + .arc-composer)
// apps/desktop/src/app/chat/composer/control-classes.ts
// @vscode/codicons 0.0.45 dist/codicon.css

function controlPx() {
  return 24
}

function primaryPx() {
  return 26
}

function gapPx() {
  return 4
}

function padXPx() {
  return 8
}

function padYPx() {
  return 5
}

function iconPx() {
  return 14
}

function stopPx() {
  return 10
}

function arcRadiusPx() {
  return 12
}

function modelMaxPx() {
  return 160
}

function inputMinPx() {
  return 128
}

function glyph(name) {
  var map = {
    "add": "\uEA60",
    "arrow-up": "\uEAA1",
    "chevron-down": "\uEAB4",
    "discard": "\uEAE2",
    "screen-normal": "\uEB4D",
    "mic": "\uEC12",
    "file": "\uEA7B",
    "folder": "\uEA83",
    "file-media": "\uEAEA",
    "copy": "\uEBCC",
    "check": "\uEAB2",
    "close": "\uEA76",
    "lock": "\uEA75",
    "warning": "\uEA6C",
    "error": "\uEA87",
    "pass": "\uEBA4",
    "key": "\uEB11",
    "shield": "\uEB53"
  }
  return map[String(name || "")] || ""
}

function moodRed() {
  return "#e5484d"
}

function moodYellow() {
  return "#e5a00d"
}

function moodGreen() {
  return "#3dd68c"
}
