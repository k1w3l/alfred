import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "AlfredModel.js" as AlfredModel
import "ComposerTheme.js" as Theme
import "BloubEngine.js" as Bloub

Item {
  id: root

  // Sheets still use a short overshoot. The notch itself does not: open is
  // the boring.notch ease (fast, then a long settle) and close is Coucou's
  // timing curve, so the return does not bounce.
  component SheetEase: NumberAnimation {
    property bool closing: false
    duration: closing ? 180 : 240
    easing.type: closing ? Easing.OutCubic : Easing.BezierSpline
    easing.bezierCurve: [0.32, 1.22, 0.42, 1.0, 1.0, 1.0]
  }

  // Swatch delegates cannot see document ids. Every field is copied off
  // modelData; the press only emits this signal.
  component FaceSwatch: Item {
    id: swatch
    required property string kind
    required property string value
    required property string shape
    required property string fill
    required property string expression
    required property string eyes
    required property string agentId
    required property bool chosen
    required property int idle
    required property real phase
    required property int size
    required property int blob
    required property int radius
    required property string label
    required property int labelSize
    required property string labelFont
    required property color labelColor
    required property bool still
    property bool wired: false
    signal picked(string kind, string value)
    width: swatch.size
    height: swatch.blob + swatch.labelSize + swatch.radius

    Rectangle {
      anchors.fill: parent
      radius: swatch.radius
      color: swatchHit.containsMouse ? Util.alpha(Color.foreground, 0.08) : "transparent"
      border.width: swatch.chosen ? 1 : 0
      border.color: Util.alpha(Color.accent, 0.9)
    }

    Column {
      anchors.centerIn: parent
      width: parent.width
      spacing: 1

      ProfileBlob {
        anchors.horizontalCenter: parent.horizontalCenter
        width: swatch.blob
        height: swatch.blob
        agentId: swatch.agentId
        slot: "swatch"
        shape: swatch.shape
        fill: swatch.fill
        expression: swatch.expression
        idleVariant: swatch.idle
        phase: swatch.phase
        eyes: swatch.eyes
        mood: "idle"
        still: swatch.still
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: swatch.label
        color: swatch.labelColor
        font.family: swatch.labelFont
        font.pixelSize: swatch.labelSize
      }
    }

    MouseArea {
      id: swatchHit
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      preventStealing: true
      onPressed: function(mouse) {
        mouse.accepted = true
        swatch.picked(swatch.kind, swatch.value)
      }
    }
  }

  component FaceRow: Column {
    id: row
    required property string caption
    required property var swatches
    required property int gap
    required property int inset
    required property color labelColor
    required property string labelFont
    required property int labelSize
    required property int rowSpacing
    required property int below
    property bool wired: false
    signal picked(string kind, string value)
    width: parent.width
    spacing: row.rowSpacing
    bottomPadding: row.below

    Text {
      width: parent.width
      leftPadding: row.inset
      textFormat: Text.PlainText
      text: row.caption
      color: row.labelColor
      font.family: row.labelFont
      font.pixelSize: row.labelSize
      font.bold: true
    }

    Flow {
      x: row.inset
      width: Math.max(0, parent.width - row.inset)
      spacing: row.gap

      Repeater {
        model: row.swatches
        delegate: FaceSwatch {
          required property var modelData
          kind: modelData.kind
          value: modelData.value
          shape: modelData.shape
          fill: modelData.fill
          expression: modelData.expression
          eyes: modelData.eyes
          agentId: modelData.agentId
          chosen: modelData.chosen
          idle: modelData.idle
          phase: modelData.phase
          size: modelData.size
          blob: modelData.blob
          radius: modelData.radius
          label: modelData.label
          labelSize: modelData.labelSize
          labelFont: modelData.labelFont
          labelColor: modelData.labelColor
          still: modelData.still
        }
        onItemAdded: function(index, item) {
          if (item.wired) return
          item.wired = true
          item.picked.connect(function(kind, value) { row.picked(kind, value) })
        }
      }
    }
  }

  function trackSheet(sheet) {
    if (!sheet || !sheet.motionReady) return
    var next = sheet.targetHeight
    sheet.closing = next + 0.5 < sheet.height
    sheet.shownHeight = next
    var open = next > 0.5
    sheet.shownOpacity = open ? 1 : 0
    sheet.shownScale = open ? 1 : 0.98
  }

  function armSheet(sheet) {
    var next = sheet.targetHeight
    var open = next > 0.5
    sheet.shownHeight = next
    sheet.shownOpacity = open ? 1 : 0
    sheet.shownScale = open ? 1 : 0.98
    sheet.closing = false
    sheet.motionReady = true
  }

  property var shell: null
  property var manifest: null
  property var service: null

  property bool opened: false
  property bool focused: false
  // 0 = compact ball, 1 = the face sitting in the pill's agent row.
  property real dock: 0
  property bool departing: false
  // Exclusive only for the first frames after open, then OnDemand so the
  // rest of the desktop can take the pointer and the keyboard.
  property bool focusPrimed: false
  property Item leadChip: null
  // Free ball: offset of the compact ball from its top-centre rest, per screen
  // name. The pill never moves; only the ball's place is offset.
  property real ballOffsetX: 0
  property real ballOffsetY: 0
  property var ballOffsets: ({})
  property bool ballDragging: false
  readonly property string ballScreen: root.activeScreen ? String(root.activeScreen.name || "") : ""
  // The column sits at the ball only once the pill has faded out and the face
  // has landed (ballHome). Until then the pill stays at the top centre, so it
  // never slides; the ball's place comes from ballCentre() meanwhile.
  property bool ballHome: false
  readonly property real ballShiftX: root.ballHome ? root.ballOffsetX : 0
  readonly property real ballShiftY: root.ballHome ? root.ballOffsetY : 0
  // Pill opacity: 1 open, 0 at the ball. It fades in and out in place.
  property real pillFade: 1
  // Ball arrival: 0 just after the face lands, 1 once the ball body has settled.
  property real ballAppear: 1
  readonly property int hudTopY: Style.bar.sizeHorizontal + Style.gapsOut + root.px(12)
  property real trayX: -1
  property real trayY: -1
  property real trayS: 0
  // Icon rects per screen name from alfred-tray.json, {name: {x, y, s}}.
  property var trayRects: ({})
  // Hero centre from the previous tick, and its low-passed velocity (px/s).
  property real heroPrevX: 0
  property real heroPrevY: 0
  property real heroPrevT: 0
  property real heroVx: 0
  property real heroVy: 0
  property real heroStretch: 1
  property real heroStretchAngle: 0
  property real heroOpacity: 1
  // 0 = a chin sitting on the bar icon, 1 = the pill at rest.
  // Open 560 ms and close 440 ms, both smooth, close without overshoot.
  property real notch: 1
  property bool notchMoving: false
  property bool notchClosing: false
  property bool notchHold: false
  property bool notchArm: false
  // Keeps the pill fill from fading in after the chin hands off to it.
  property bool notchSnap: false
  property bool notchDocked: false
  property bool compactAfterNotch: false
  property real closeDock: 0
  property real holdX: 0
  property real holdY: 0
  property real holdW: 0
  property real holdH: 0
  property real holdR: 0
  property real notchFx: 0
  property real notchFy: 0
  property real notchFw: 1
  property real notchFh: 1
  property real notchFr: 0
  property real notchShown: 1
  property real plateOpacity: 1
  // Set at the close handoff: the hero and plate are fading out and the bar
  // icon is taking the face back. Cleared once the fade has finished.
  property bool closeFading: false
  // Flight the engine plays on the hero: "open" while the chin climbs out of
  // the bar, "close" from the start of the close until the fade has ended.
  readonly property string flightPhase: root.notchClosing || root.closeFading
    ? "close" : (root.notchMoving ? "open" : "")

  // Notch thresholds. The value is t: 0 = chin on the bar icon, 1 = pill at rest.
  readonly property QtObject phase: QtObject {
    // Open: the dock slide starts once the chin has left the bar.
    readonly property real dockStart: 0.7
    // Open: composer content starts to show, and the hero flow goes "open".
    readonly property real contentShow: 0.9
    // Open: close enough to rest to snap onto the pill and finish.
    readonly property real settle: 0.96
    // Close: composer content is fully hidden below contentHide.
    readonly property real contentFade: 0.9
    readonly property real contentHide: 0.72
    // Close: the hero leaves the plate for the dock below this value.
    readonly property real dockLeave: 0.72
    // Close: the bar icon takes the face back and the hero and plate fade out.
    readonly property real handoff: 0.28
    // Close: the chin sits on the icon; the notch is done and hudOpen drops.
    readonly property real landed: 0.04
    // Plate shows its 1px rim above this value.
    readonly property real rimShow: 0.5
    // Only a notch near rest counts as "still moving" for placement and focus.
    readonly property real nearRest: 0.98
    // Snap guards for the notch frame at the two ends.
    readonly property real atRest: 0.999
    readonly property real atSeed: 0.001
    // Close: the hero keeps the agent-row size above closeRide, and only starts
    // leaving the plate above closeLeave.
    readonly property real closeRide: 0.4
    readonly property real closeLeave: 0.2
    // Seed capsule: width is the icon size times seedWidth, at least icon + seedPad.
    readonly property real seedWidth: 1.9
    readonly property real seedPad: 10
    // Lead exponent for width, x and height; lag exponent for the top edge.
    readonly property real leadExp: 1.2
    readonly property real lagExp: 1.4
    // Tolerance under which runNotch treats the notch as already there.
    readonly property real settleEpsilon: 0.01
    // Mid-flight size swell: size *= 1 + flightBump * sin(pi * t), zero at both ends.
    readonly property real flightBump: 1.1
    // Low-pass factor for the hero's velocity and stretch, per 16 ms tick.
    readonly property real velSmooth: 0.35
    // Stretch in flight: 1 + min(stretchMax, speed px/s / stretchSpeed).
    readonly property real stretchMax: 0.38
    readonly property real stretchSpeed: 2200
    // Landing plop: squash depth at the bottom, press time up and release time down (ms).
    readonly property real plopDepth: 0.16
    readonly property int plopUp: 90
    readonly property int plopDown: 220
    // Face travel between the ball and the pill row (ms). The curve is a soft
    // start and a soft landing; the path is a quadratic curve, its control point
    // lifted flyArc base px above the chord so the face arcs toward the top.
    readonly property int flyDuration: 700
    readonly property var flyCurve: [0.45, 0.0, 0.25, 1.0, 1.0, 1.0]
    readonly property real flyArc: 80
    // Pill fade in place (ms) and the scale it grows from while fading in.
    readonly property int pillFadeMs: 260
    readonly property real pillScaleFrom: 0.96
    // Ball body arrival: it dims and dips slightly, then clears over ballAppearMs.
    readonly property int ballAppearMs: 200
    readonly property real ballAppearDim: 0.25
    readonly property real ballAppearDip: 0.04
  }

  onNotchChanged: root.syncNotchFrame()

  readonly property var alfred: service ? service : (shell && typeof shell.serviceFor === "function" ? shell.serviceFor("kiwel.alfred") : null)
  readonly property bool busy: alfred ? alfred.busy === true : false
  readonly property bool listening: alfred ? alfred.listening === true : false
  readonly property bool gatewayActive: alfred ? alfred.gatewayActive === true : false
  readonly property var messages: alfred && alfred.messages ? alfred.messages : []
  readonly property var attachments: alfred && alfred.attachments ? alfred.attachments : []
  readonly property string lastError: alfred ? String(alfred.lastError || "") : ""
  readonly property string lastReply: alfred ? String(alfred.lastReply || "") : ""
  readonly property bool compact: root.opened && !root.focused
  readonly property bool picking: alfred ? alfred.pickingFiles === true : false
  readonly property bool transcribing: alfred ? alfred.transcribing === true : false
  readonly property bool awaitingPermission: alfred ? alfred.awaitingPermission === true : false
  readonly property string lastOutcome: alfred ? String(alfred.lastOutcome || "") : ""
  readonly property bool outcomeSeen: alfred ? alfred.outcomeSeen === true : false
  readonly property bool reasoning: alfred ? alfred.reasoning === true : false
  readonly property bool streaming: alfred ? alfred.streaming === true : false
  readonly property string modelName: alfred ? String(alfred.modelName || "") : ""
  readonly property var modelOptions: alfred && alfred.modelOptions ? alfred.modelOptions : []
  readonly property string modelProvider: alfred ? String(alfred.modelProvider || "") : ""
  readonly property string modelProviderLabel: alfred ? String(alfred.modelProviderLabel || alfred.modelProvider || "") : ""
  readonly property var providerOptions: alfred && alfred.providerOptions ? alfred.providerOptions : []
  readonly property string uiTheme: alfred ? String(alfred.uiTheme || "classic") : "classic"
  readonly property string uiThemeLabel: alfred ? String(alfred.uiThemeLabel || "") : "Classic"
  readonly property var themeOptions: alfred && alfred.themeOptions ? alfred.themeOptions : []
  readonly property bool glassy: root.uiTheme === "glassy"
  readonly property string reasoningEffort: alfred ? String(alfred.reasoningEffort || "medium") : "medium"
  readonly property var effortOptions: alfred && alfred.effortOptions ? alfred.effortOptions : ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]
  readonly property string gatewayLabel: alfred ? String(alfred.gatewayLabel || "This device") : "This device"
  readonly property string gatewayConnectionId: alfred ? String(alfred.gatewayConnectionId || "local") : "local"
  readonly property var gatewayOptions: alfred && alfred.gatewayOptions ? alfred.gatewayOptions : []
  readonly property string profileLabel: alfred ? String(alfred.profileLabel || "default") : "default"
  readonly property string profileName: alfred ? String(alfred.profileName || "default") : "default"
  readonly property string profileKey: alfred ? String(alfred.profileKey || "local:default") : "local:default"
  readonly property string profileShape: alfred ? String(alfred.profileShape || "cercle") : "cercle"
  readonly property string profileFill: alfred ? String(alfred.profileFill || "#0a0a0c") : "#0a0a0c"
  readonly property string profileExpression: alfred ? String(alfred.profileExpression || "neutre") : "neutre"
  readonly property int profileIdle: alfred ? Number(alfred.profileIdle || 0) : 0
  readonly property real profilePhase: alfred ? Number(alfred.profilePhase || 0) : 0
  readonly property string profileEyes: alfred ? String(alfred.profileEyes || "soft") : "soft"
  readonly property var profileOptions: alfred && alfred.profileOptions ? alfred.profileOptions : []
  readonly property var roster: alfred && alfred.roster ? alfred.roster : []
  readonly property var visibleRoster: {
    var rows = root.roster || []
    var out = []
    var i
    for (i = 0; i < rows.length; i++) {
      var row = rows[i]
      if (row && row.hidden !== true) out.push(row)
    }
    return out
  }
  readonly property var profileMenuModel: {
    var rows = root.roster || []
    var shown = []
    var parked = []
    var i
    for (i = 0; i < rows.length; i++) {
      var row = rows[i]
      if (!row) continue
      if (row.hidden === true) parked.push(row)
      else shown.push(row)
    }
    if (parked.length > 0) {
      shown.push({ rowType: "header", label: "HIDDEN" })
      for (i = 0; i < parked.length; i++) shown.push(parked[i])
    }
    return shown
  }
  readonly property string gatewayKind: alfred ? String(alfred.gatewayKind || "local") : "local"
  readonly property bool anyBusy: alfred ? alfred.anyBusy === true : false
  readonly property var chats: alfred && alfred.chats ? alfred.chats : []
  readonly property string activeChatId: alfred ? String(alfred.activeChatId || "") : ""
  readonly property var activity: alfred && alfred.activity ? alfred.activity : []
  readonly property string liveText: alfred ? String(alfred.liveText || "") : ""
  readonly property real busyStartedAt: alfred ? Number(alfred.busyStartedAt || 0) : 0
  readonly property var sessionOptions: alfred && alfred.sessionOptions ? alfred.sessionOptions : []
  readonly property bool sessionsLoading: alfred ? alfred.sessionsLoading === true : false
  readonly property string sessionsError: alfred ? String(alfred.sessionsError || "") : ""
  readonly property bool showChatStrip: root.focused
  readonly property var shortcutsGlobal: alfred && alfred.shortcutsGlobal ? alfred.shortcutsGlobal : []
  readonly property var shortcutsLocal: alfred && alfred.shortcutsLocal ? alfred.shortcutsLocal : []
  readonly property bool shortcutsHooked: alfred ? alfred.shortcutsHooked === true : false
  readonly property string shortcutsError: alfred ? String(alfred.shortcutsError || "") : ""
  readonly property bool shortcutsSaving: alfred ? alfred.shortcutsSaving === true : false
  property string captureScope: ""
  property string captureId: ""
  property bool previewOpen: false
  property bool followThread: true
  readonly property bool previewVisible: root.focused && root.busy && root.previewOpen && !root.menuOpen && !root.pickerOpen
  property real nowMs: Date.now()
  property string menuParent: ""
  property string menuKind: ""
  property string faceKey: ""
  property string faceLabel: ""
  property string faceShape: "cercle"
  property string faceFill: "#0a0a0c"
  property string faceExpression: "neutre"
  property int faceIdle: 0
  property real facePhase: 0
  readonly property var faceShapes: ["cercle", "galet", "squircle", "capsule", "triangle", "hexagone", "nuage", "goutte"]
  readonly property var faceShapeLabels: ["Circle", "Pebble", "Squircle", "Capsule", "Triangle", "Hexagon", "Cloud", "Droplet"]
  readonly property var faceColors: ["#0a0a0c", "#8b5e3c", "#e8483f", "#f08a24", "#f0b429", "#3ecf8e", "#2fbfa0", "#3b93f0", "#8b5cf6", "#e152b0", "#a3a3a3"]
  readonly property var faceColorLabels: ["Ink", "Brown", "Red", "Orange", "Amber", "Green", "Turquoise", "Blue", "Purple", "Pink", "Grey"]
  readonly property var faceExpressions: ["neutre", "attentif", "surpris", "excite", "heureux", "hilare", "colere", "triste", "effraye", "mefiant", "confus", "curieux", "fier", "timide", "blase", "somnolent"]
  readonly property var faceExpressionLabels: ["Neutral", "Attentive", "Surprised", "Excited", "Happy", "Laughing", "Angry", "Sad", "Scared", "Suspicious", "Confused", "Curious", "Proud", "Shy", "Unimpressed", "Sleepy"]
  readonly property var faceIdles: ["0", "1", "2"]
  readonly property var faceIdleLabels: ["Idle 1", "Idle 2", "Idle 3"]
  property string pickerMode: ""
  readonly property bool menuOpen: root.menuKind !== ""
  readonly property bool pickerOpen: root.pickerMode !== ""
  readonly property bool hasPayload: (composerInput ? String(composerInput.text || "").trim() !== "" : false) || root.attachments.length > 0
  readonly property bool showVoicePrimary: !root.busy && !root.hasPayload
  readonly property bool showStop: root.busy && !root.hasPayload
  readonly property var slashItems: alfred && alfred.slashItems ? alfred.slashItems : []
  readonly property bool slashLoading: alfred ? alfred.slashLoading === true : false
  property int slashIndex: 0
  property bool slashDismissed: false
  property string slashDraft: ""
  readonly property bool slashPanelOpen: root.focused && !root.pickerOpen && !root.menuOpen && !root.busy && root.slashDraft !== "" && !root.slashDismissed
  readonly property bool slashOpen: root.slashPanelOpen && root.slashItems.length > 0
  readonly property var slashViewRows: {
    var items = root.slashItems
    var rows = []
    var last = "\u0001"
    var i
    for (i = 0; i < items.length; i++) {
      var it = items[i]
      var g = String(it.group || "")
      if (g !== last) {
        rows.push({ rowType: "header", group: g, itemIndex: -1, text: "", display: "", meta: "", kind: "" })
        last = g
      }
      rows.push({
        rowType: "item",
        group: g,
        itemIndex: i,
        text: String(it.text || ""),
        display: String(it.display || it.text || ""),
        meta: String(it.meta || ""),
        kind: String(it.kind || "")
      })
    }
    return rows
  }
  readonly property bool showThread: root.focused && !root.busy && !root.listening && !root.slashPanelOpen && (root.lastError !== "" || root.messages.length > 0)
  readonly property string mood: {
    if (root.listening) return "listening"
    if (root.awaitingPermission) return "permission"
    // Text is streaming (speaking), or the model is still thinking (reasoning).
    if (root.busy && root.streaming) return "speaking"
    if (root.busy && root.reasoning) return "reasoning"
    if (root.busy || (root.compact && root.anyBusy)) return "busy"
    if (!root.outcomeSeen && (root.lastError !== "" || root.lastOutcome === "error")) return "error"
    if (!root.outcomeSeen && root.lastOutcome === "success") return "success"
    return "idle"
  }
  readonly property color moodColor: {
    if (root.mood === "listening" || root.mood === "error") return Theme.moodRed()
    if (root.mood === "permission") return Theme.moodYellow()
    if (root.mood === "success") return Theme.moodGreen()
    return Color.accent
  }

  readonly property color foreground: root.glassy ? Qt.rgba(1, 1, 1, 0.98) : Color.foreground
  readonly property color dim: root.glassy ? Qt.rgba(1, 1, 1, 0.84) : Color.muted
  readonly property color glassFill: {
    var c = Color.bar.background
    return Qt.rgba(c.r, c.g, c.b, Math.min(c.a, 0.35))
  }
  readonly property color glassSheet: {
    var c = Color.bar.background
    return Qt.rgba(c.r, c.g, c.b, 0.42)
  }
  readonly property color surface: root.glassy ? root.glassFill : Util.alpha(Qt.darker(Color.background, 1.45), 0.94)
  readonly property color sheet: root.glassy ? root.glassSheet : Util.alpha(Qt.darker(Color.background, 1.25), 0.92)
  readonly property color rim: {
    if (root.mood === "idle")
      return root.glassy
        ? Qt.rgba(1, 1, 1, root.focused ? 0.28 : 0.16)
        : Util.alpha(Color.accent, root.focused ? 0.55 : 0.28)
    return root.moodColor
  }
  readonly property int inkWeight: root.glassy ? Font.DemiBold : Font.Normal
  readonly property string fontFamily: Style.font.family
  // Pill scale follows the Hyprland output scale of activeScreen.
  // Screen.width/height are logical (DP-3 is 2560x1440) and devicePixelRatio
  // is the integer Wayland buffer scale (2 there). Omarchy uses that ratio
  // only for image sourceSize. Hyprland scale is 1.5 on that 4K panel and 1
  // on the 1080p outputs, including HDMI-A-1 in portrait.
  readonly property real uiScale: {
    var s = root.activeScreen
    var name = s ? String(s.name || "") : ""
    var mons = Hyprland.monitors && Hyprland.monitors.values ? Hyprland.monitors.values : []
    var i
    for (i = 0; i < mons.length; i++) {
      var m = mons[i]
      if (!m || String(m.name || "") !== name) continue
      var sc = Number(m.scale)
      if (isFinite(sc) && sc > 0) return sc
    }
    return 1
  }

  // Style.space already includes the global spacing/font scale. Divide it
  // back out and apply uiScale so only the monitor factor is added.
  function px(n) {
    var g = Number(Style.spacing.scale)
    if (!(g > 0)) g = 1
    var v = Style.space(n) * root.uiScale / g
    if (!isFinite(v) || v <= 0) return 0
    return Math.round(v)
  }

  function fontPx(size) {
    var n = Number(size)
    if (!isFinite(n) || n <= 0) return 0
    return Math.max(1, Math.round(n * root.uiScale))
  }
  readonly property int ballSize: Math.max(root.px(60), root.fontPx(Style.font.title) + root.px(34))
  readonly property int agentSize: root.px(Theme.primaryPx())
  // Every turn in progress: reasoning, speaking and busy share the ball's look.
  readonly property bool working: root.mood === "busy" || root.mood === "reasoning" || root.mood === "speaking"
  readonly property bool ballOrbits: root.compact && (root.working || root.mood === "listening")
  readonly property int ballPad: root.ballOrbits ? root.px(18) : 0
  // the compact ball swells a little while its agent works
  readonly property int ballFace: root.compact && root.working ? Math.round(root.ballSize * 1.3) : root.ballSize
  // The hero is moved by placeHero every tick, so it cannot carry a Behavior.
  // Its ball size and orbit pad ease on the pill's 340 ms curve instead, which
  // keeps the hero and the pill from snapping apart on a busy swell.
  property real ballFaceShown: root.ballFace
  property real ballPadShown: root.ballPad
  Behavior on ballFaceShown {
    NumberAnimation {
      duration: 340
      easing.type: Easing.BezierSpline
      easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1]
    }
  }
  Behavior on ballPadShown {
    NumberAnimation {
      duration: 340
      easing.type: Easing.BezierSpline
      easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1]
    }
  }
  readonly property int pillWidth: root.focused ? root.px(720) : root.ballFace + root.ballPad * 2
  readonly property int composerTextHeight: composerInput ? Math.min(Math.ceil(composerInput.implicitHeight), root.px(Theme.composerMaxPx())) : root.fontPx(Style.font.body)
  readonly property bool composerMultiline: composerInput ? composerInput.lineCount > 1 : false
  readonly property int pillHeight: root.focused
    ? root.surfacePadY * 2 + root.controlGap + Math.max(root.composerTextHeight, root.agentSize) + root.agentSize
    : root.ballFace + root.ballPad * 2
  readonly property int rowAlign: root.composerMultiline ? Qt.AlignBottom : Qt.AlignVCenter
  readonly property int controlGap: root.px(Theme.gapPx())
  readonly property int surfacePadX: root.px(Theme.padXPx())
  readonly property int surfacePadY: root.px(Theme.padYPx())
  readonly property int bandMaxHeight: Math.max(root.px(280), Math.min(root.px(560),
    Math.round((root.activeScreen ? root.activeScreen.height : 1080) * 0.55)))
  property string hudScreenName: ""
  readonly property var activeScreen: root.screenByName(root.hudScreenName) || root.focusedScreen()

  function screenByName(name) {
    var want = String(name || "")
    var screens = Quickshell.screens
    var i
    if (want === "") return null
    for (i = 0; i < screens.length; i++) {
      if (String(screens[i].name || "") === want) return screens[i]
    }
    return null
  }

  function pinHudScreen() {
    var s = root.focusedScreen()
    root.hudScreenName = s ? String(s.name || "") : ""
  }

  function focusedScreen() {
    var mon = Hyprland.focusedMonitor
    var name = mon ? String(mon.name || "") : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (name !== "" && String(screens[i].name || "") === name) return screens[i]
    }
    return screens.length > 0 ? screens[0] : null
  }

  function open(payloadJson) {
    root.focusHud()
  }

  function close() {
    root.hideHud()
  }

  function toggle() {
    if (root.focused) root.hideHud()
    else root.focusHud()
  }

  function noteTray(x, y, s) {
    if (!(s > 2) || !isFinite(x) || !isFinite(y)) return
    root.trayX = x
    root.trayY = y
    root.trayS = s
  }

  // Centre of the compact ball, from the saved offset and not from the pill, so
  // the face can fly to and from it while the pill stays where it is.
  function ballCentre() {
    return Qt.point(escScope.width / 2 + root.ballOffsetX,
      root.hudTopY + root.ballOffsetY + (root.ballFaceShown + root.ballPadShown * 2) / 2)
  }

  function chipTopLeft() {
    if (root.leadChip && root.leadChip.width > 2 && root.dock > 0.35) {
      return root.leadChip.mapToItem(escScope, 0, 0)
    }
    // The pill is scaled while it fades in; its layout slot is not.
    var origin = pillSlot.mapToItem(escScope, (pillSlot.width - pill.width) / 2, 0)
    var index = 0
    var rows = root.visibleRoster || []
    var i
    for (i = 0; i < rows.length; i++) {
      var key = String(rows[i].key || rows[i].id || "")
      if (key === root.profileKey) {
        index = i
        break
      }
    }
    var rowY = root.surfacePadY + Math.max(root.composerTextHeight, root.agentSize) + root.controlGap
    var scroll = agentFlick ? agentFlick.contentX : 0
    return Qt.point(
      origin.x + root.surfacePadX + index * (root.agentSize + root.controlGap) - scroll,
      origin.y + rowY
    )
  }

  // The screen the HUD is on: the one it was summoned to, else the active one.
  function hudScreenKey() {
    if (root.hudScreenName !== "") return root.hudScreenName
    return root.activeScreen ? String(root.activeScreen.name || "") : ""
  }

  function trayRectFor(name) {
    if (name === "") return null
    var maps = [alfred ? alfred.trayRects : null, root.trayRects]
    for (var i = 0; i < maps.length; i++) {
      var m = maps[i]
      if (m && m[name] && m[name].s > 2) return m[name]
    }
    return null
  }

  function trayTopLeft() {
    var x = root.trayX
    var y = root.trayY
    var s = root.trayS
    var rect = root.trayRectFor(root.hudScreenKey())
    if (rect) {
      x = rect.x
      y = rect.y
      s = rect.s
    } else if (alfred && alfred.trayS > 2) {
      x = alfred.trayX
      y = alfred.trayY
      s = alfred.trayS
    }
    if (!(s > 2) || typeof escScope.mapFromGlobal !== "function") {
      var above = pill.mapToItem(escScope, pill.width / 2, 0)
      var fallback = root.agentSize
      return { x: above.x - fallback / 2, y: Math.max(2, above.y - fallback - 8), s: fallback }
    }
    var p = escScope.mapFromGlobal(x, y)
    return { x: p.x, y: p.y, s: s }
  }

  function screenWidth() {
    if (escScope && escScope.width > 2) return escScope.width
    return root.activeScreen ? root.activeScreen.width : 0
  }

  // The closed notch is the bar icon itself: a short capsule on that glyph.
  function seedFrame() {
    var tray = root.trayTopLeft()
    var s = tray.s > 2 ? tray.s : Math.max(root.agentSize, 16)
    var w = Math.max(s * root.phase.seedWidth, s + root.phase.seedPad)
    var h = s
    return {
      x: tray.x + s / 2 - w / 2,
      y: tray.y,
      w: w,
      h: h,
      r: h / 2
    }
  }

  function liveRestFrame() {
    var w = root.pillWidth
    var h = root.pillHeight
    var screenW = root.screenWidth()
    var r = (!root.focused || root.compact) ? h / 2 : root.px(Theme.arcRadiusPx())
    return {
      x: screenW > 2 ? (screenW - w) / 2 + root.ballShiftX : 0,
      y: root.hudTopY + root.ballShiftY,
      w: w,
      h: h,
      r: r
    }
  }

  function holdRest() {
    var f = root.liveRestFrame()
    root.holdX = f.x
    root.holdY = f.y
    root.holdW = f.w
    root.holdH = f.h
    root.holdR = f.r
    root.notchHold = true
  }

  // Share of the seed-to-rest travel covered at notch t. The plate's width and
  // chin use it, and so does the hero's size, so the face never runs on a
  // different curve from the shape it rides.
  function notchLead(t) {
    return 1 - Math.pow(1 - t, root.phase.leadExp)
  }

  // Width and the horizontal slide lead; the top edge lags, so the chin
  // drops out of the bar before the shape lets go of it.
  function notchFrame() {
    var seed = root.seedFrame()
    var rest = root.notchHold
      ? { x: root.holdX, y: root.holdY, w: root.holdW, h: root.holdH, r: root.holdR }
      : root.liveRestFrame()
    var t = root.notch
    if (!isFinite(t) || t >= root.phase.atRest) return rest
    if (t <= root.phase.atSeed) return seed
    var tc = Math.max(0, Math.min(1, t))
    // Chin and width lead a little; the top edge stays on the bar longer.
    var lead = root.notchLead(tc)
    var lag = Math.pow(tc, root.phase.lagExp)
    var cx = (seed.x + seed.w / 2) + ((rest.x + rest.w / 2) - (seed.x + seed.w / 2)) * lead
    var w = seed.w + (rest.w - seed.w) * lead
    var h = seed.h + (rest.h - seed.h) * lead
    var top = seed.y + (rest.y - seed.y) * lag
    var rad = Math.min(h / 2, seed.r + (rest.r - seed.r) * lead)
    return {
      x: cx - w / 2,
      y: Math.max(0, top),
      w: Math.max(1, w),
      h: Math.max(1, h),
      r: Math.max(0, rad)
    }
  }

  function notchContentOf(t, closing) {
    if (!isFinite(t)) return closing ? 0 : 1
    t = Math.max(0, Math.min(1, t))
    if (closing) {
      if (t > root.phase.contentFade) return 1
      if (t < root.phase.contentHide) return 0
      return (t - root.phase.contentHide) / (root.phase.contentFade - root.phase.contentHide)
    }
    if (t < root.phase.contentShow) return 0
    return (t - root.phase.contentShow) / (1 - root.phase.contentShow)
  }

  function syncNotchFrame() {
    var f = root.notchFrame()
    root.notchFx = f.x
    root.notchFy = f.y
    root.notchFw = f.w
    root.notchFh = f.h
    root.notchFr = f.r
    root.notchShown = root.notchMoving ? root.notchContentOf(root.notch, root.notchClosing) : 1
    if (root.notchMoving && !root.notchClosing && root.focused && !root.compactAfterNotch
        && !root.notchDocked && root.notch > root.phase.dockStart) {
      root.notchDocked = true
      dockAnim.to = 1
      dockAnim.restart()
    }
    if (root.notchMoving && root.notchClosing && root.notch <= root.phase.handoff)
      root.beginCloseFade()
  }

  // Close handoff. The hero and plate fade out while the bar icon fades in
  // on the same 160 ms curve, so the glyph takes the face back as the chin lands.
  function beginCloseFade() {
    if (root.closeFading) return
    root.closeFading = true
    if (alfred) alfred.trayAway = false
    heroPlop.restart()
    root.fadeOutFlight()
  }

  function fadeOutFlight() {
    heroFade.to = 0
    plateFade.to = 0
    heroFade.restart()
    plateFade.restart()
  }

  // The fade is over and the chin is home: drop the flight state.
  function finishHudClose() {
    plateFade.stop()
    root.plateOpacity = 1
    root.notchMoving = false
    root.notchHold = false
    root.notchClosing = false
    root.notch = 1
    root.notchShown = 1
    root.closeFading = false
    root.opened = false
    root.hudScreenName = ""
    root.dock = 0
    root.heroOpacity = 1
  }

  // Hero centre velocity from the last tick, low-passed. In flight, and while the
  // face travels between the ball and the pill row, the hero stretches along its
  // heading and keeps its area; at rest it eases back.
  function updateHeroMotion() {
    var now = Date.now()
    var cx = hero.x + hero.width / 2
    var cy = hero.y + hero.height / 2
    var dt = (now - root.heroPrevT) / 1000
    var rawX = 0
    var rawY = 0
    if (root.heroPrevT > 0 && dt > 0.0005 && dt < 0.1) {
      rawX = (cx - root.heroPrevX) / dt
      rawY = (cy - root.heroPrevY) / dt
    }
    root.heroPrevX = cx
    root.heroPrevY = cy
    root.heroPrevT = now
    root.heroVx += (rawX - root.heroVx) * root.phase.velSmooth
    root.heroVy += (rawY - root.heroVy) * root.phase.velSmooth
    var speed = Math.hypot(root.heroVx, root.heroVy)
    var moving = root.flightPhase !== "" || ballFlyAnim.running
    var target = moving
      ? 1 + Math.min(root.phase.stretchMax, speed / root.phase.stretchSpeed)
      : 1
    root.heroStretch += (target - root.heroStretch) * root.phase.velSmooth
    // Screen-space heading in degrees (y down, so clockwise positive, as Rotation).
    if (speed > 1) root.heroStretchAngle = Math.atan2(root.heroVy, root.heroVx) * 180 / Math.PI
  }

  // What the engine is flying the face toward, as a unit vector from the hero's
  // centre: the pill rest when opening, the bar icon when closing.
  function flightDirection() {
    var target
    if (root.flightPhase === "close") {
      var tray = root.trayTopLeft()
      target = { x: tray.x + tray.s / 2, y: tray.y + tray.s / 2 }
    } else {
      var rest = root.notchHold
        ? { x: root.holdX, y: root.holdY, w: root.holdW, h: root.holdH }
        : root.liveRestFrame()
      target = { x: rest.x + rest.w / 2, y: rest.y + rest.h / 2 }
    }
    var dx = target.x - (hero.x + hero.width / 2)
    var dy = target.y - (hero.y + hero.height / 2)
    var len = Math.hypot(dx, dy)
    if (len < 0.5) return Qt.point(0, 0)
    return Qt.point(dx / len, dy / len)
  }

  function runNotch(closing) {
    var dest = closing ? 0 : 1
    root.notchArm = false
    notchOpenAnim.stop()
    notchCloseAnim.stop()
    root.notchMoving = true
    root.notchClosing = closing
    root.syncNotchFrame()
    if (Math.abs(root.notch - dest) < root.phase.settleEpsilon) {
      root.notch = dest
      root.notchArm = true
      root.finishNotch(closing)
      return
    }
    if (closing) {
      notchCloseAnim.to = 0
      notchCloseAnim.restart()
    } else {
      notchOpenAnim.to = 1
      notchOpenAnim.restart()
    }
    root.notchArm = true
  }

  function finishNotch(closing) {
    if (!root.notchArm) return
    if (closing) {
      if (!root.notchClosing || root.notch > root.phase.landed) return
      root.notchArm = false
      root.notch = 0
      root.syncNotchFrame()
      root.departing = false
      root.notchClosing = false
      if (alfred) {
        alfred.hudOpen = false
        alfred.hudFocused = false
      }
      // The chin is on the icon. The handoff normally started the fade already;
      // a fade that ended early, or was stopped, is finished or restarted here.
      root.beginCloseFade()
      if (!heroFade.running) {
        if (root.heroOpacity > 0.05) root.fadeOutFlight()
        else root.finishHudClose()
      }
      return
    }
    if (root.notchClosing || root.notch < root.phase.settle) return
    root.notchArm = false
    root.notchSnap = true
    root.notch = 1
    root.notchMoving = false
    root.notchClosing = false
    root.notchHold = false
    root.notchShown = 1
    root.syncNotchFrame()
    heroPlop.restart()
    Qt.callLater(function() { root.notchSnap = false })
    if (root.compactAfterNotch) {
      root.compactAfterNotch = false
      root.unfocusHud()
      return
    }
    if (root.focused && root.dock < 0.98 && !dockAnim.running) {
      dockAnim.to = 1
      dockAnim.restart()
    }
  }

  function placeHeroOnNotch() {
    var f = root.notchFrame()
    var t = Math.max(0, Math.min(1, root.notch))
    var tray = root.trayTopLeft()
    var home = tray.s > 2 ? tray.s : f.h
    var riding = (root.focused && !root.notchClosing && !root.compactAfterNotch) ? root.agentSize : root.ballFaceShown
    if (root.notchClosing)
      riding = root.closeDock > root.phase.closeRide ? root.agentSize : root.ballFaceShown
    // Same lead curve as the plate's width and chin, so the face and the shape agree.
    var size = home + (riding - home) * root.notchLead(t)
    // The face swells mid-flight so it reads; both ends keep their sizes.
    size *= 1 + root.phase.flightBump * Math.sin(Math.PI * t)
    var plateX = f.x + f.w / 2 - size / 2
    var plateY = f.y + f.h / 2 - size / 2
    var u = 0
    if (!root.notchClosing) u = Math.max(0, Math.min(1, root.dock))
    else if (root.closeDock > root.phase.closeLeave)
      u = Math.max(0, Math.min(1, (t - root.phase.dockLeave) / (1 - root.phase.dockLeave)))
    var destX = plateX
    var destY = plateY
    var destS = size
    if (u > 0.001 && pill.width > 2) {
      var chip = root.chipTopLeft()
      destX = chip.x
      destY = chip.y
      destS = root.agentSize
    }
    hero.width = size * (1 - u) + destS * u
    hero.height = hero.width
    hero.x = plateX * (1 - u) + destX * u
    hero.y = plateY * (1 - u) + destY * u
  }

  function placeHero() {
    if (root.notchMoving || (root.opened && root.plateOpacity < 0.99 && root.notch < root.phase.nearRest)) {
      root.placeHeroOnNotch()
      return
    }
    if (!root.opened || pill.width < 2) return
    var d = Math.max(0, Math.min(1, root.dock))
    var ballSize = root.ballFaceShown
    var ballC = root.ballCentre()
    var chip = root.chipTopLeft()
    var rowC = Qt.point(chip.x + root.agentSize / 2, chip.y + root.agentSize / 2)
    // Quadratic curve from the ball to the row; the control point sits above the chord.
    var lift = root.px(root.phase.flyArc)
    var ctlX = (ballC.x + rowC.x) / 2
    var ctlY = (ballC.y + rowC.y) / 2 - lift
    var u = 1 - d
    var px = u * u * ballC.x + 2 * u * d * ctlX + d * d * rowC.x
    var py = u * u * ballC.y + 2 * u * d * ctlY + d * d * rowC.y
    var size = ballSize * u + root.agentSize * d
    hero.width = size
    hero.height = size
    hero.x = px - size / 2
    hero.y = py - size / 2
  }

  function releaseKeyboard() {
    grabFocusTimer.stop()
    focusPrimeTimer.stop()
    root.focusPrimed = false
    if (composerInput) composerInput.focus = false
  }

  function hideHud() {
    if (!root.opened) {
      root.departing = false
      root.notchMoving = false
      root.dock = 0
      if (alfred) {
        alfred.hudOpen = false
        alfred.trayAway = false
      }
      return
    }
    if (root.departing) return
    // Snapshot the shape that is on screen before focus collapses it to the ball.
    root.closeDock = root.dock
    root.holdRest()
    root.releaseKeyboard()
    root.closeMenus()
    root.closePicker()
    root.closeSlash()
    if (alfred && alfred.listening && typeof alfred.cancelVoice === "function") alfred.cancelVoice()
    root.focused = false
    if (alfred) alfred.hudFocused = false
    root.departing = true
    // The face stays away from the bar icon until the close handoff (notch 0.28).
    // hudOpen may already be false (the service clears it on hide), so the
    // bar reads trayAway, not hudOpen, to keep the icon empty during the flight.
    root.runNotch(true)
  }

  function unfocusHud() {
    if (!root.opened) {
      root.pinHudScreen()
      root.ballHome = false
      ballFlyAnim.stop()
      pillFadeAnim.stop()
      root.pillFade = 1
      ballAppearAnim.stop()
      root.ballAppear = 1
      plateFade.stop()
      heroFade.stop()
      root.closeFading = false
      root.heroOpacity = 1
      root.plateOpacity = 1
      root.notchHold = false
      root.notchDocked = false
      root.compactAfterNotch = false
      root.dock = 0
      root.notch = 0
      root.focused = false
      root.departing = false
      root.opened = true
      if (alfred) {
        alfred.hudOpen = true
        alfred.hudFocused = false
        alfred.trayAway = true
      }
      root.releaseKeyboard()
      root.closeMenus()
      root.closePicker()
      root.syncNotchFrame()
      root.runNotch(false)
      // The hero sits on the icon now, not on the next 16 ms tick.
      root.placeHero()
      return
    }
    // Still climbing out of the bar: let it arrive, then shrink to the ball.
    if (root.notchMoving && !root.notchClosing && root.notch < root.phase.nearRest) {
      if (root.focused) root.compactAfterNotch = true
      root.releaseKeyboard()
      root.closeMenus()
      root.closePicker()
      return
    }
    root.releaseKeyboard()
    root.closeMenus()
    root.closePicker()
    if (root.heroOpacity < 1) {
      heroFade.stop()
      root.heroOpacity = 1
    }
    root.focused = false
    root.opened = true
    if (root.departing) root.departing = false
    if (alfred) {
      alfred.hudOpen = true
      alfred.hudFocused = false
      alfred.trayAway = true
    }
    root.returnBall()
  }

  // Focus lost: the pill fades out in place and the face flies back to the ball.
  // The column moves to the ball only when the fade is done and the face has landed.
  function returnBall() {
    dockAnim.stop()
    pillFadeAnim.to = 0
    pillFadeAnim.restart()
    if (root.dock < 0.001) {
      ballFlyAnim.stop()
      pillFadeAnim.stop()
      root.dock = 0
      root.pillFade = 0
      root.settleBall()
      return
    }
    ballFlyAnim.to = 0
    ballFlyAnim.restart()
  }

  // The face is home: the column takes the ball's place, the face lands with a
  // plop and the ball body eases in.
  function settleBall() {
    if (!root.opened || root.focused) return
    root.ballHome = true
    root.ballAppear = 0
    ballAppearAnim.restart()
    heroPlop.restart()
  }

  // Entry point for the ball and the bar: the avatar reacts, the chat's outcome
  // is acknowledged, and the pill opens.
  function pokeAndOpen() {
    if (alfred && typeof alfred.acknowledgeOutcome === "function") alfred.acknowledgeOutcome(root.activeChatId)
    if (!root.focused) {
      heroPlop.restart()
      Bloub.react(root.profileKey, "poke", Date.now())
    }
    root.focusHud()
  }

  // Keeps the compact ball fully on screen. The column is centred, so x is
  // bounded by the free space on either side; y by the bar and the bottom edge.
  function clampBallOffset(x, y) {
    var W = escScope.width
    var H = escScope.height
    if (!(W > 2) || !(H > 2)) return Qt.point(x, y)
    var maxX = Math.max(0, (W - hudColumn.width) / 2)
    var minY = -root.hudTopY
    var maxY = Math.max(minY, H - root.pillHeight - root.hudTopY)
    return Qt.point(Math.max(-maxX, Math.min(maxX, x)), Math.max(minY, Math.min(maxY, y)))
  }

  function loadBallOffset() {
    var o = root.ballOffsets[root.ballScreen]
    var p = o ? root.clampBallOffset(Number(o.x) || 0, Number(o.y) || 0) : Qt.point(0, 0)
    root.ballOffsetX = p.x
    root.ballOffsetY = p.y
  }

  function applyBallFile(content) {
    var parsed = null
    try {
      parsed = JSON.parse(String(content || ""))
    } catch (e) {
      return
    }
    if (!parsed || !parsed.screens || typeof parsed.screens !== "object") return
    root.ballOffsets = parsed.screens
    root.loadBallOffset()
  }

  function saveBallOffset() {
    if (root.ballScreen === "") return
    var next = Object.assign({}, root.ballOffsets)
    next[root.ballScreen] = { x: Math.round(root.ballOffsetX), y: Math.round(root.ballOffsetY) }
    root.ballOffsets = next
    ballFile.setText(JSON.stringify({ screens: next }, null, 2) + "\n")
  }

  function focusHud() {
    var fromTray = !root.opened
    var fromBar = fromTray || root.notchClosing || (root.notchMoving && root.notch < root.phase.nearRest)
    if (fromTray) root.pinHudScreen()
    // The column goes back to the top centre; the pill is still invisible here.
    root.ballHome = false
    ballAppearAnim.stop()
    root.ballAppear = 1
    plateFade.stop()
    heroFade.stop()
    if (root.heroOpacity < 1) root.heroOpacity = 1
    root.plateOpacity = 1
    root.closeFading = false
    root.departing = false
    root.compactAfterNotch = false
    root.opened = true
    root.focused = true
    root.focusPrimed = false
    if (alfred) {
      alfred.hudOpen = true
      alfred.hudFocused = true
      alfred.trayAway = true
    }
    if (fromBar) {
      pillFadeAnim.stop()
      root.pillFade = 1
      ballFlyAnim.stop()
      root.notchHold = false
      root.notchDocked = false
      if (fromTray) {
        root.dock = 0
        root.notch = 0
      }
      root.syncNotchFrame()
      root.runNotch(false)
    } else {
      // From the ball: the pill fades in place while the face flies to its row.
      pillFadeAnim.to = 1
      pillFadeAnim.restart()
      ballFlyAnim.to = 1
      ballFlyAnim.restart()
    }
    focusPrimeTimer.restart()
    grabFocusTimer.tries = 0
    grabFocusTimer.restart()
    if (alfred && typeof alfred.prefetchSlash === "function") alfred.prefetchSlash()
    Qt.callLater(root.syncSlash)
  }

  function submit() {
    var prompt = composerInput ? String(composerInput.text || "").trim() : ""
    if (!alfred || typeof alfred.sendPrompt !== "function") return
    if (alfred.sendPrompt(prompt)) {
      if (composerInput) composerInput.text = ""
    }
  }

  function sendText(text) {
    if (composerInput) composerInput.text = String(text || "")
    root.submit()
  }

  property var menuRows: []

  function closeMenus() {
    root.cancelCapture()
    root.menuKind = ""
    root.menuParent = ""
    root.menuRows = []
  }

  function menuTitle() {
    var titles = {
      attach: "ATTACH",
      voice: "VOICE",
      settings: "ALFRED",
      model: root.modelOptions.length === 0 ? "NO CACHED MODELS" : "MODEL",
      provider: "PROVIDER",
      effort: "REASONING",
      theme: "THEME",
      profile: "PROFILE",
      face: root.faceLabel !== "" ? root.faceLabel : "FACE",
      gateway: "GATEWAY",
      shortcuts: "KEYBOARD SHORTCUTS",
      sessions: root.gatewayKind === "local" ? "PREVIOUS SESSIONS" : "PREVIOUS SESSIONS · THIS DEVICE"
    }
    return titles[root.menuKind] || ""
  }

  function settingsSummary() {
    return AlfredModel.shortModelName(root.modelName) + " · " + AlfredModel.effortLabel(root.reasoningEffort)
  }

  function refreshMenuSource(kind) {
    if (!alfred) return
    if ((kind === "model" || kind === "provider") && typeof alfred.refreshModels === "function") alfred.refreshModels()
    if (kind === "theme" && typeof alfred.refreshPrefs === "function") alfred.refreshPrefs()
    if (kind === "effort" && typeof alfred.refreshEffort === "function") alfred.refreshEffort()
    if (kind === "gateway" && typeof alfred.refreshGateways === "function") alfred.refreshGateways()
    if (kind === "profile" && typeof alfred.refreshProfiles === "function") alfred.refreshProfiles()
    if (kind === "sessions" && typeof alfred.refreshSessions === "function") alfred.refreshSessions()
    if (kind === "shortcuts" && typeof alfred.refreshShortcuts === "function") alfred.refreshShortcuts()
  }

  function openSubmenu(kind) {
    root.closePicker()
    root.menuParent = "settings"
    root.menuKind = String(kind)
    root.refreshMenuSource(root.menuKind)
    root.rebuildMenu()
  }

  function menuBack() {
    root.cancelCapture()
    if (root.menuKind === "face") {
      root.menuKind = "profile"
      root.rebuildMenu()
      return
    }
    var parentKind = root.menuParent
    root.menuParent = ""
    root.menuKind = parentKind
    root.rebuildMenu()
  }

  function idleIndex(value) {
    var n = Number(value)
    if (!isFinite(n)) return 0
    return ((n % 3) + 3) % 3
  }

  function eyesFor(expression) {
    var expr = String(expression || "")
    if (expr === "colere" || expr === "mefiant") return "angry"
    if (expr === "blase" || expr === "somnolent" || expr === "triste") return "pause"
    return "soft"
  }

  function openFaceEditor(row) {
    var data = row || {}
    var key = String(data.key || data.id || "")
    if (key === "") return
    root.faceKey = key
    root.faceLabel = String(data.label || key)
    root.faceShape = String(data.shape || "cercle")
    root.faceFill = String(data.fill || "#0a0a0c").toLowerCase()
    root.faceExpression = String(data.expression || "neutre")
    root.faceIdle = root.idleIndex(data.idle)
    root.facePhase = Number(data.phase || 0)
    root.menuKind = "face"
    root.rebuildMenu()
  }

  function pickFace(kind, value) {
    var which = String(kind || "")
    var next = String(value || "")
    if (which === "shape") root.faceShape = next
    else if (which === "fill") root.faceFill = next.toLowerCase()
    else if (which === "expression") root.faceExpression = next
    else if (which === "idle") root.faceIdle = root.idleIndex(next)
  }

  function saveFace() {
    if (root.faceKey === "") return
    if (alfred && typeof alfred.setFace === "function")
      alfred.setFace(root.faceKey, root.faceShape, root.faceFill, root.faceExpression, root.faceIdle)
    root.menuBack()
  }

  function clearFace() {
    if (root.faceKey === "") return
    if (alfred && typeof alfred.resetFace === "function")
      alfred.resetFace(root.faceKey)
    root.menuBack()
  }

  function toggleSettings() {
    if (root.menuKind === "settings" || root.menuParent === "settings") root.closeMenus()
    else root.toggleMenu("settings")
  }

  function openSessions() {
    root.closeSlash()
    if (root.menuKind !== "sessions") root.toggleMenu("sessions")
  }

  function toggleSessions() {
    root.closeSlash()
    root.toggleMenu("sessions")
  }

  function focusComposerSoon() {
    grabFocusTimer.tries = 0
    grabFocusTimer.restart()
  }

  function newChat() {
    root.closeMenus()
    root.closeSlash()
    if (alfred && typeof alfred.newChat === "function") alfred.newChat()
    root.focusComposerSoon()
  }

  function switchChat(id) {
    root.closeMenus()
    if (alfred && typeof alfred.switchChat === "function") alfred.switchChat(id)
    root.focusComposerSoon()
  }

  function closeChat(id) {
    if (alfred && typeof alfred.closeChat === "function") alfred.closeChat(id)
    root.focusComposerSoon()
  }

  function chooseSession(id, title) {
    root.closeMenus()
    if (alfred && typeof alfred.openSession === "function") alfred.openSession(id, title)
    root.focusComposerSoon()
  }

  function togglePreview() {
    root.closeMenus()
    root.previewOpen = !root.previewOpen
    root.nowMs = Date.now()
  }

  function chatIsOpen(sessionId) {
    var ref = "id:" + String(sessionId || "")
    for (var i = 0; i < root.chats.length; i++) {
      if (String(root.chats[i].sessionRef || "") === ref) return true
    }
    return false
  }

  function localKeys(id) {
    for (var i = 0; i < root.shortcutsLocal.length; i++) {
      if (root.shortcutsLocal[i].id === id) return AlfredModel.normalizeCombo(root.shortcutsLocal[i].keys).toLowerCase()
    }
    return ""
  }

  function comboAllowed(combo) {
    if (!combo) return false
    if (/^F\d+$/.test(combo.key)) return true
    return combo.mods.filter(function(m) { return m !== "Shift" }).length > 0
  }

  function handleShortcut(event) {
    if (event.modifiers === Qt.NoModifier || event.modifiers === Qt.KeypadModifier) {
      if (event.key === Qt.Key_PageUp) return root.pageThread(-1)
      if (event.key === Qt.Key_PageDown) return root.pageThread(1)
    }
    var combo = AlfredModel.comboFromEvent(event.key, event.modifiers)
    if (!root.comboAllowed(combo)) return false
    var text = AlfredModel.comboText(combo).toLowerCase()
    var actions = {
      voice: function() { root.toggleVoice() },
      newChat: function() { root.newChat() },
      closeChat: function() { root.closeChat(root.activeChatId) },
      nextChat: function() { if (alfred && typeof alfred.cycleChat === "function") alfred.cycleChat(1) },
      prevChat: function() { if (alfred && typeof alfred.cycleChat === "function") alfred.cycleChat(-1) },
      sessions: function() { root.openSessions() },
      preview: function() { if (root.busy) root.togglePreview() }
    }
    for (var id in actions) {
      if (root.localKeys(id) === text) {
        actions[id]()
        return true
      }
    }
    for (var j = 0; j < root.shortcutsLocal.length; j++) {
      var sid = String(root.shortcutsLocal[j].id || "")
      if (sid.indexOf("profile:") === 0 && root.localKeys(sid) === text) {
        root.chooseProfile(sid.substring(8))
        return true
      }
    }
    return false
  }

  function startCapture(scope, id) {
    root.captureScope = String(scope)
    root.captureId = String(id)
  }

  function cancelCapture() {
    root.captureScope = ""
    root.captureId = ""
  }

  function saveShortcut(scope, id, keys) {
    if (alfred && typeof alfred.setShortcut === "function") alfred.setShortcut(scope, id, keys)
  }

  function handleCapture(event) {
    if (root.captureId === "") return false
    var scope = root.captureScope
    var id = root.captureId
    var bare = (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier)) === 0
    if (event.key === Qt.Key_Escape) {
      root.cancelCapture()
      return true
    }
    if (bare && (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete)) {
      root.cancelCapture()
      root.saveShortcut(scope, id, "")
      return true
    }
    var combo = AlfredModel.comboFromEvent(event.key, event.modifiers)
    if (!root.comboAllowed(combo)) return true
    root.cancelCapture()
    root.saveShortcut(scope, id, scope === "global" ? AlfredModel.comboHypr(combo) : AlfredModel.comboText(combo))
    return true
  }

  function closePicker() {
    root.pickerMode = ""
  }

  function closeSlash() {
    root.slashDraft = ""
    root.slashDismissed = false
    root.slashIndex = 0
    if (alfred && typeof alfred.clearSlash === "function") alfred.clearSlash()
  }

  function syncSlash() {
    if (!composerInput) return
    var q = AlfredModel.slashQueryFrom(composerInput.text)
    if (q !== root.slashDraft) {
      root.slashDismissed = false
      root.slashIndex = 0
    }
    root.slashDraft = q
    if (q === "" || root.slashDismissed || root.busy) {
      if (q === "" && alfred && typeof alfred.clearSlash === "function") alfred.clearSlash()
      return
    }
    root.closeMenus()
    if (alfred && typeof alfred.refreshSlash === "function")
      alfred.refreshSlash(String(composerInput.text || ""))
  }

  function moveSlash(delta) {
    var n = root.slashItems.length
    if (n === 0) return
    var next = root.slashIndex + delta
    if (next < 0) next = 0
    if (next > n - 1) next = n - 1
    root.slashIndex = next
  }

  function slashRowY(itemIndex) {
    var rows = root.slashViewRows
    var y = 0
    var i
    for (i = 0; i < rows.length; i++) {
      var h = rows[i].rowType === "header" ? root.px(22) : root.px(40)
      if (rows[i].itemIndex === itemIndex) return y
      y += h
    }
    return 0
  }

  function applySlashAt(index) {
    var items = root.slashItems
    if (index < 0 || index >= items.length) return
    var cmd = String(items[index].text || "")
    if (composerInput) {
      composerInput.text = AlfredModel.applySlashInsert(composerInput.text, cmd)
      composerInput.cursorPosition = String(composerInput.text || "").length
      composerInput.forceActiveFocus()
    }
    root.slashDismissed = true
    root.slashDraft = composerInput ? AlfredModel.slashQueryFrom(composerInput.text) : ""
  }

  function tryApplySlash() {
    if (!root.slashPanelOpen) return false
    if (root.slashItems.length === 0) return true
    root.applySlashAt(root.slashIndex)
    return true
  }

  function openPicker(mode) {
    root.closeMenus()
    root.pickerMode = String(mode || "files")
    grabFocusTimer.stop()
  }

  function rebuildMenu() {
    var rows = []
    var i
    if (root.menuKind === "attach") {
      rows = [
        { id: "files", icon: "file", label: "Files", checked: false },
        { id: "folder", icon: "folder", label: "Folder", checked: false },
        { id: "images", icon: "file-media", label: "Images", checked: false },
        { id: "paste", icon: "copy", label: "Paste image", checked: false }
      ]
    } else if (root.menuKind === "voice") {
      rows = [
        { id: "conversation", icon: "comment", label: "Start voice conversation", checked: false },
        { id: "dictate", icon: "mic", label: root.listening ? "Stop dictation" : "Voice dictation", checked: root.listening }
      ]
    } else if (root.menuKind === "settings") {
      rows = [
        { id: "model", icon: "pulse", label: "Model", value: AlfredModel.shortModelName(root.modelName), sub: true },
        { id: "provider", icon: "plug", label: "Provider", value: root.modelProviderLabel || root.modelProvider, sub: true },
        { id: "effort", icon: "lightbulb", label: "Reasoning", value: AlfredModel.effortLabel(root.reasoningEffort), sub: true },
        { id: "theme", icon: "symbol-color", label: "Theme", value: root.uiThemeLabel || Theme.themeLabel(root.uiTheme), sub: true },
        { id: "profile", icon: "account", label: "Profile", value: root.profileLabel, sub: true },
        { id: "gateway", icon: root.gatewayKind === "local" ? "server" : "plug", label: "Gateway", value: root.gatewayLabel, sub: true },
        { id: "shortcuts", icon: "keyboard", label: "Keyboard shortcuts", value: "", sub: true }
      ]
    } else if (root.menuKind === "shortcuts") {
      rows.push({ rowType: "header", label: "GLOBAL · HYPRLAND" })
      for (i = 0; i < root.shortcutsGlobal.length; i++)
        rows.push(Object.assign({ rowType: "item", scope: "global" }, root.shortcutsGlobal[i]))
      rows.push({ rowType: "header", label: "INSIDE THE PILL" })
      for (i = 0; i < root.shortcutsLocal.length; i++)
        rows.push(Object.assign({ rowType: "item", scope: "local" }, root.shortcutsLocal[i]))
    } else if (root.menuKind === "model") {
      for (i = 0; i < root.modelOptions.length; i++) {
        rows.push({
          id: String(root.modelOptions[i]),
          icon: "",
          label: String(root.modelOptions[i]),
          checked: String(root.modelOptions[i]) === root.modelName
        })
      }
    } else if (root.menuKind === "provider") {
      for (i = 0; i < root.providerOptions.length; i++) {
        var pv = root.providerOptions[i]
        rows.push({
          id: String(pv.id || ""),
          icon: "plug",
          label: String(pv.label || pv.id || ""),
          checked: String(pv.id || "") === root.modelProvider
        })
      }
    } else if (root.menuKind === "theme") {
      var themes = root.themeOptions.length > 0 ? root.themeOptions : [
        { id: "classic", label: "Classic" },
        { id: "glassy", label: "Glassy" }
      ]
      for (i = 0; i < themes.length; i++) {
        rows.push({
          id: String(themes[i].id || ""),
          icon: String(themes[i].id) === "glassy" ? "symbol-color" : "settings-gear",
          label: String(themes[i].label || themes[i].id || ""),
          checked: String(themes[i].id || "") === root.uiTheme
        })
      }
    } else if (root.menuKind === "effort") {
      for (i = 0; i < root.effortOptions.length; i++) {
        rows.push({
          id: String(root.effortOptions[i]),
          icon: "",
          label: AlfredModel.effortLabel(root.effortOptions[i]),
          checked: String(root.effortOptions[i]) === root.reasoningEffort
        })
      }
    } else if (root.menuKind === "gateway") {
      for (i = 0; i < root.gatewayOptions.length; i++) {
        var gw = root.gatewayOptions[i]
        rows.push({
          id: String(gw.id || ""),
          icon: String(gw.kind) === "local" ? "server" : "plug",
          label: String(gw.label || gw.id || ""),
          checked: String(gw.id || "") === root.gatewayConnectionId
        })
      }
    } else if (root.menuKind === "profile") {
      for (i = 0; i < root.profileOptions.length; i++) {
        var pf = root.profileOptions[i]
        rows.push({
          id: String(pf.id || ""),
          icon: "account",
          label: String(pf.label || pf.id || ""),
          checked: String(pf.id || "") === root.profileName
        })
      }
    }
    root.menuRows = rows
  }

  function toggleMenu(kind) {
    root.closePicker()
    root.menuParent = ""
    root.menuKind = root.menuKind === kind ? "" : kind
    if (root.menuKind === "") {
      root.menuRows = []
      return
    }
    root.refreshMenuSource(root.menuKind)
    root.rebuildMenu()
  }

  function activateMenuItem(item) {
    var id = item && item.id ? String(item.id) : ""
    if (root.menuKind === "settings") {
      root.openSubmenu(id)
      return
    }
    if (root.menuKind === "attach") {
      root.pickKind(id)
      return
    }
    if (root.menuKind === "voice") {
      if (id === "conversation" || id === "dictate") root.startListen()
      return
    }
    if (root.menuKind === "model") root.chooseModel(id)
    if (root.menuKind === "provider") root.chooseProvider(id)
    if (root.menuKind === "theme") root.chooseTheme(id)
    if (root.menuKind === "effort") root.chooseEffort(id)
    if (root.menuKind === "gateway") root.chooseGateway(id)
    if (root.menuKind === "profile") root.chooseProfile(id)
  }

  function copyText(value) {
    if (alfred && typeof alfred.copyText === "function") alfred.copyText(value)
  }

  function removeAttachment(path) {
    if (alfred && typeof alfred.removeAttachment === "function") alfred.removeAttachment(path)
  }

  function pickKind(kind) {
    var mode = String(kind || "files")
    root.closeMenus()
    if (mode === "paste") {
      if (alfred && typeof alfred.pickFiles === "function") alfred.pickFiles("paste")
      return
    }
    root.openPicker(mode)
  }

  function openDesktop() {
    root.hideHud()
    if (alfred && typeof alfred.launchDesktop === "function") alfred.launchDesktop()
  }

  function chooseModel(name) {
    root.closeMenus()
    if (alfred && typeof alfred.setModel === "function") alfred.setModel(name)
  }

  function chooseProvider(id) {
    root.closeMenus()
    if (alfred && typeof alfred.setProvider === "function") alfred.setProvider(id)
  }

  function chooseTheme(id) {
    root.closeMenus()
    if (alfred && typeof alfred.setUiTheme === "function") alfred.setUiTheme(id)
  }

  function chooseEffort(level) {
    root.closeMenus()
    if (alfred && typeof alfred.setEffort === "function") alfred.setEffort(level)
  }

  function chooseGateway(id) {
    root.closeMenus()
    if (alfred && typeof alfred.setGateway === "function") alfred.setGateway(id)
  }

  function chooseProfile(id) {
    root.closeMenus()
    if (alfred && typeof alfred.setProfile === "function") alfred.setProfile(id)
  }

  function setProfileVisibility(key, hide) {
    if (alfred && typeof alfred.setProfileVisibility === "function")
      alfred.setProfileVisibility(key, hide === true)
  }

  function startListen() {
    root.closeMenus()
    if (alfred && typeof alfred.startVoice === "function") alfred.startVoice()
    root.unfocusHud()
  }

  function stopListen() {
    if (alfred && typeof alfred.stopVoice === "function") alfred.stopVoice()
    root.focusHud()
  }

  function toggleVoice() {
    if (root.listening) root.stopListen()
    else root.startListen()
  }

  function handlePrimary() {
    if (root.showStop) {
      if (alfred && typeof alfred.abortSend === "function") alfred.abortSend()
      return
    }
    if (root.showVoicePrimary) {
      root.startListen()
      return
    }
    root.submit()
  }

  function handleEscape() {
    if (root.pickerOpen) {
      root.closePicker()
      grabFocusTimer.tries = 0
      grabFocusTimer.restart()
      return
    }
    if (root.slashPanelOpen) {
      root.slashDismissed = true
      if (alfred && typeof alfred.clearSlash === "function") alfred.clearSlash()
      return
    }
    if (root.menuOpen) {
      if (root.menuKind === "face" || root.menuParent !== "") root.menuBack()
      else root.closeMenus()
      return
    }
    if (root.busy) root.unfocusHud()
    else root.hideHud()
  }

  Timer {
    id: focusPrimeTimer
    interval: 75
    onTriggered: {
      if (!root.focused || root.departing) return
      root.focusPrimed = true
      if (root.busy) escScope.forceActiveFocus()
      else if (composerInput && !composerInput.activeFocus) composerInput.forceActiveFocus()
    }
  }

  NumberAnimation {
    id: dockAnim
    target: root
    property: "dock"
    duration: 340
    easing.type: Easing.BezierSpline
    easing.bezierCurve: [0.65, 0, 0.35, 1, 1, 1]
  }

  // The face's travel between the ball (0) and the pill row (1). Its curve gives
  // a soft start and a soft landing; placeHero draws the arc from it.
  NumberAnimation {
    id: ballFlyAnim
    target: root
    property: "dock"
    duration: root.phase.flyDuration
    easing.type: Easing.BezierSpline
    easing.bezierCurve: root.phase.flyCurve
    onFinished: {
      if (ballFlyAnim.to === 0) root.settleBall()
    }
  }

  // The pill fades in and out where it is; it never travels with the face.
  NumberAnimation {
    id: pillFadeAnim
    target: root
    property: "pillFade"
    duration: root.phase.pillFadeMs
    easing.type: Easing.OutCubic
  }

  NumberAnimation {
    id: ballAppearAnim
    target: root
    property: "ballAppear"
    to: 1
    duration: root.phase.ballAppearMs
    easing.type: Easing.OutCubic
  }

  // Slow off the bar, smooth through the middle, soft landing.
  // Same family as Coucou's close curve, held longer so the chin reads.
  NumberAnimation {
    id: notchOpenAnim
    target: root
    property: "notch"
    duration: 560
    easing.type: Easing.BezierSpline
    easing.bezierCurve: [0.4, 0.0, 0.2, 1.0, 1.0, 1.0]
    onFinished: {
      if (!root.notchArm || root.notchClosing) return
      if (root.notch < root.phase.settle) return
      root.finishNotch(false)
    }
  }

  // Coucou close: timingCurve(0.45, 0, 0.2, 1). No overshoot on the way home.
  NumberAnimation {
    id: notchCloseAnim
    target: root
    property: "notch"
    duration: 440
    easing.type: Easing.BezierSpline
    easing.bezierCurve: [0.45, 0.0, 0.2, 1.0, 1.0, 1.0]
    onFinished: {
      if (!root.notchArm || !root.notchClosing) return
      if (root.notch > root.phase.landed) return
      root.finishNotch(true)
    }
  }

  NumberAnimation {
    id: heroFade
    target: root
    property: "heroOpacity"
    duration: 160
    easing.type: Easing.OutCubic
    onFinished: {
      if (root.heroOpacity > 0.05) return
      // The chin is still landing; finishNotch(true) completes the reset.
      if (root.notchClosing) return
      root.finishHudClose()
    }
  }

  // Landing squash on the hero: a quick press, then a soft release with no overshoot.
  SequentialAnimation {
    id: heroPlop
    NumberAnimation {
      target: heroBlob
      property: "plop"
      to: 1
      duration: root.phase.plopUp
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: heroBlob
      property: "plop"
      to: 0
      duration: root.phase.plopDown
      easing.type: Easing.OutQuad
    }
  }

  NumberAnimation {
    id: plateFade
    target: root
    property: "plateOpacity"
    duration: 160
    easing.type: Easing.OutCubic
  }

  Timer {
    id: heroClock
    interval: 16
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: {
      if (root.notchMoving) root.syncNotchFrame()
      root.placeHero()
      root.updateHeroMotion()
      heroBlob.flightTarget = root.flightDirection()
    }
  }

  FileView {
    id: ballFile
    path: (Quickshell.env("HOME") || "") + "/.config/Hermes/alfred-ball.json"
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyBallFile(text())
  }

  onBallScreenChanged: root.loadBallOffset()

  FileView {
    id: trayWatch
    path: (Quickshell.env("HOME") || "") + "/.config/Hermes/alfred-tray.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyTrayFile(text())
    onFileChanged: reload()
  }

  function applyTrayFile(content) {
    var parsed = null
    try {
      parsed = JSON.parse(String(content || ""))
    } catch (e) {
      return
    }
    if (!parsed) return
    if (parsed.screens && typeof parsed.screens === "object") root.trayRects = parsed.screens
    root.noteTray(Number(parsed.x), Number(parsed.y), Number(parsed.s))
  }

  Timer {
    id: grabFocusTimer
    property int tries: 0
    interval: 50
    repeat: true
    onTriggered: {
      tries += 1
      if (root.focusPrimed) {
        stop()
        tries = 0
        return
      }
      if (root.opened && root.focused) {
        if (root.pickerOpen) {
          stop()
          tries = 0
          return
        }
        if (root.busy) escScope.forceActiveFocus()
        else if (composerInput) composerInput.forceActiveFocus()
      }
      var gotIt = root.busy ? escScope.activeFocus : (composerInput && composerInput.activeFocus)
      if (!root.focused || gotIt || tries >= 16) {
        stop()
        tries = 0
      }
    }
  }

  Connections {
    target: root.alfred
    function onFocusRequested() { root.pokeAndOpen() }
    function onCompactRequested() { root.unfocusHud() }
    function onHideRequested() { root.hideHud() }
    function onToolStarted() { Bloub.react(root.profileKey, "tool", Date.now()) }
    function onToolFailed() { Bloub.react(root.profileKey, "toolError", Date.now()) }
    function onUserTyped() { Bloub.react(root.profileKey, "typed", Date.now()) }
    function onAssistantAsked() { Bloub.react(root.profileKey, "question", Date.now()) }
    function onAssistantLaughed() { Bloub.react(root.profileKey, "laugh", Date.now()) }
    function onUserThanked() { Bloub.react(root.profileKey, "love", Date.now()) }
    function onMenuRequested(kind) {
      var name = String(kind || "settings")
      root.focusHud()
      root.closeSlash()
      if (name === "settings" || name === "sessions" || name === "attach") {
        root.menuKind = ""
        root.toggleMenu(name)
      } else {
        root.openSubmenu(name)
      }
    }
    function onVoiceRequested() {
      if (root.listening) {
        root.stopListen()
        return
      }
      if (!root.opened) root.pinHudScreen()
      root.startListen()
    }
    function onTranscriptReady(text) {
      var t = String(text || "").trim()
      if (composerInput && t !== "") {
        var cur = String(composerInput.text || "").trim()
        composerInput.text = cur === "" ? t : (cur + " " + t)
      }
      if (root.opened) root.focusHud()
    }
  }

  FontLoader {
    id: menuCodicon
    source: Qt.resolvedUrl("fonts/codicon.ttf")
  }

  component ActionChip: Rectangle {
    id: chip
    property string icon: ""
    property string label: ""
    property string tip: ""
    property bool opened: false
    signal activated()

    height: parent ? parent.height : root.px(28)
    width: chipRow.implicitWidth + root.px(20)
    radius: height / 2
    color: chip.opened ? Util.alpha(Color.accent, 0.20) : (chipHit.containsMouse ? Util.alpha(Color.foreground, 0.10) : root.sheet)
    border.width: 1
    border.color: chip.opened ? Util.alpha(Color.accent, 0.55) : Util.alpha(Color.accent, 0.16)

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: root.px(6)

      Text {
        textFormat: Text.PlainText
        text: Theme.glyph(chip.icon)
        color: chipHit.containsMouse || chip.opened ? root.foreground : root.dim
        font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
        font.pixelSize: root.px(Theme.iconPx())
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: chip.label
        color: chipHit.containsMouse || chip.opened ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: root.fontPx(Style.font.caption)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: chipHit
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      preventStealing: true
      onPressed: function(mouse) { mouse.accepted = true }
      onClicked: Qt.callLater(chip.activated)
    }

    QQC.ToolTip.visible: chip.tip !== "" && chipHit.containsMouse
    QQC.ToolTip.text: chip.tip
    QQC.ToolTip.delay: 400
  }

  readonly property var attachItems: [
    { action: "files", iconName: "file", rowLabel: "Files" },
    { action: "folder", iconName: "folder", rowLabel: "Folder" },
    { action: "images", iconName: "file-media", rowLabel: "Images" },
    { action: "paste", iconName: "copy", rowLabel: "Paste image" }
  ]

  onListeningChanged: {
    if (root.menuKind === "voice") root.rebuildMenu()
  }

  onModelOptionsChanged: {
    if (root.menuKind === "model") root.rebuildMenu()
  }

  onModelNameChanged: {
    if (root.menuKind === "model" || root.menuKind === "settings") root.rebuildMenu()
  }

  onProviderOptionsChanged: {
    if (root.menuKind === "provider") root.rebuildMenu()
  }

  onModelProviderChanged: {
    if (root.menuKind === "provider" || root.menuKind === "settings") root.rebuildMenu()
  }

  onModelProviderLabelChanged: {
    if (root.menuKind === "settings") root.rebuildMenu()
  }

  onThemeOptionsChanged: {
    if (root.menuKind === "theme") root.rebuildMenu()
  }

  onUiThemeChanged: {
    if (root.menuKind === "theme" || root.menuKind === "settings") root.rebuildMenu()
  }

  onUiThemeLabelChanged: {
    if (root.menuKind === "settings") root.rebuildMenu()
  }

  onEffortOptionsChanged: {
    if (root.menuKind === "effort") root.rebuildMenu()
  }

  onReasoningEffortChanged: {
    if (root.menuKind === "effort" || root.menuKind === "settings") root.rebuildMenu()
  }

  onGatewayOptionsChanged: {
    if (root.menuKind === "gateway") root.rebuildMenu()
  }

  onGatewayConnectionIdChanged: {
    if (root.menuKind === "gateway" || root.menuKind === "settings") root.rebuildMenu()
  }

  onGatewayLabelChanged: {
    if (root.menuKind === "settings") root.rebuildMenu()
  }

  onProfileOptionsChanged: {
    if (root.menuKind === "profile") root.rebuildMenu()
  }

  onProfileNameChanged: {
    if (root.menuKind === "profile" || root.menuKind === "settings") root.rebuildMenu()
  }

  onProfileLabelChanged: {
    if (root.menuKind === "settings") root.rebuildMenu()
  }

  onShortcutsGlobalChanged: {
    if (root.menuKind === "shortcuts") root.rebuildMenu()
  }

  onShortcutsLocalChanged: {
    if (root.menuKind === "shortcuts") root.rebuildMenu()
  }

  onActiveChatIdChanged: {
    root.closeSlash()
    Qt.callLater(root.scrollThreadToEnd)
  }

  onActivityChanged: Qt.callLater(root.scrollPreviewToEnd)
  onLiveTextChanged: Qt.callLater(root.scrollPreviewToEnd)

  function scrollThreadToEnd() {
    if (!bandFlick) return
    jumpAnim.stop()
    root.followThread = true
    bandFlick.contentY = Math.max(0, bandFlick.contentHeight - bandFlick.height)
  }

  function updateFollowThread() {
    if (bandFlick) root.followThread = bandFlick.distanceToEnd <= root.px(24)
  }

  function pageThread(direction) {
    if (!bandFlick || !root.showThread || !bandFlick.interactive) return false
    jumpAnim.stop()
    var maxY = Math.max(0, bandFlick.contentHeight - bandFlick.height)
    bandFlick.contentY = Math.max(0, Math.min(maxY, bandFlick.contentY + direction * bandFlick.height * 0.85))
    root.updateFollowThread()
    return true
  }

  function jumpThreadToEnd() {
    if (!bandFlick) return
    jumpAnim.stop()
    jumpAnim.to = Math.max(0, bandFlick.contentHeight - bandFlick.height)
    jumpAnim.start()
  }

  function scrollPreviewToEnd() {
    if (!previewFlick || !root.previewVisible) return
    previewFlick.contentY = Math.max(0, previewFlick.contentHeight - previewFlick.height)
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.previewVisible
    triggeredOnStart: true
    onTriggered: root.nowMs = Date.now()
  }

  onAwaitingPermissionChanged: {
    if (root.awaitingPermission && root.opened) root.unfocusHud()
  }

  onBusyChanged: {
    if (!root.focused) return
    if (root.busy) {
      grabFocusTimer.stop()
      escScope.forceActiveFocus()
    } else {
      grabFocusTimer.tries = 0
      grabFocusTimer.restart()
    }
  }

  onSlashItemsChanged: {
    if (root.slashIndex >= root.slashItems.length)
      root.slashIndex = Math.max(0, root.slashItems.length - 1)
  }

  onSlashIndexChanged: {
    if (!slashList || !root.slashOpen) return
    var y = root.slashRowY(root.slashIndex)
    var top = slashList.contentY
    var bottom = top + slashList.height
    var rowH = root.px(40)
    if (y < top) slashList.contentY = Math.max(0, y)
    else if (y + rowH > bottom) slashList.contentY = Math.max(0, y + rowH - slashList.height)
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.activeScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "kiwel-alfred"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive locks every pointer event on every monitor to this surface.
    // Prime it long enough for the field to take the keys, then OnDemand.
    // While the pill is open the mask is the whole screen, so a click
    // outside it still lands here and shrinks the face to the ball.
    WlrLayershell.keyboardFocus: root.focused && !root.departing
      ? (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
      : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: root.focused && !root.departing ? screenMask : pillMask

    Region {
      id: screenMask
      width: panel.width
      height: panel.height
    }

    Region {
      id: pillMask
      item: hudColumn
    }

    FocusScope {
      id: escScope
      anchors.fill: parent
      focus: root.focused
      Keys.onPressed: function(event) {
        if (root.handleCapture(event) || root.handleShortcut(event)) {
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Escape) {
          root.handleEscape()
          event.accepted = true
          return
        }
        if (event.matches(StandardKey.Copy)) {
          var fieldSel = composerInput ? String(composerInput.selectedText || "") : ""
          if (composerInput && composerInput.activeFocus && fieldSel !== "") return
          var payload = fieldSel !== "" ? fieldSel : root.lastReply
          if (payload === "" && root.lastError !== "") payload = root.lastError
          if (payload !== "") {
            root.copyText(payload)
            event.accepted = true
          }
        }
      }

    MouseArea {
      z: -1
      anchors.fill: parent
      enabled: root.focused && !root.departing
      hoverEnabled: false
      onPressed: function(mouse) {
        var p = mapToItem(hudColumn, mouse.x, mouse.y)
        if (p.x >= 0 && p.y >= 0 && p.x <= hudColumn.width && p.y <= hudColumn.height) {
          mouse.accepted = false
          return
        }
        mouse.accepted = true
        if (root.pickerOpen) {
          root.closePicker()
          return
        }
        if (root.menuOpen) {
          root.closeMenus()
          return
        }
        root.unfocusHud()
      }
    }

    Item {
      id: hero
      z: 8
      visible: root.opened && root.heroOpacity > 0.01
      opacity: root.heroOpacity * (1 - root.phase.ballAppearDim * (1 - root.ballAppear))
      scale: 1 - root.phase.ballAppearDip * (1 - root.ballAppear)
      width: root.ballFace
      height: root.ballFace

      ProfileBlob {
        id: heroBlob
        anchors.fill: parent
        visible: hero.visible
        themeSheet: root.surface
        agentId: root.profileKey
        slot: "lead"
        shape: root.profileShape
        fill: root.profileFill
        expression: root.profileExpression
        idleVariant: root.profileIdle
        phase: root.profilePhase
        eyes: root.profileEyes
        mood: root.mood
        flow: root.focused && !root.departing && (!root.notchMoving || root.notchShown > root.phase.contentShow) ? "open" : "compact"
        flight: root.flightPhase
        cursorX: root.alfred ? root.alfred.cursorX : NaN
        cursorY: root.alfred ? root.alfred.cursorY : NaN
        cursorAt: root.alfred ? root.alfred.cursorAt : 0
        // Only the hero looks while the HUD is open; the bar icon and chips do not.
        lookEnabled: root.opened
        stretch: root.heroStretch
        stretchAngle: root.heroStretchAngle
        plopDepth: root.phase.plopDepth
        selected: false
      }
    }

    Rectangle {
      id: notchPlate
      z: 1
      visible: root.opened && root.notchMoving
      opacity: root.plateOpacity
      antialiasing: true
      x: root.notchFx
      y: root.notchFy
      width: Math.max(1, root.notchFw)
      height: Math.max(1, root.notchFh)
      radius: root.notchFr
      color: root.surface
      border.width: root.notch > root.phase.rimShow ? 1 : 0
      border.color: root.rim
    }

    Column {
      id: hudColumn
      // Compact listening draws the meter and OK beside the ball. The input
      // mask is this column, so it has to be wide enough to contain them.
      // While the notch is travelling the composer stays hidden; the plate
      // behind this column is the only shape on screen.
      opacity: root.notchMoving ? root.notchShown : 1
      width: root.listening && !root.focused ? Math.max(root.pillWidth, voiceOkRow.implicitWidth) : root.pillWidth
      spacing: 0
      // Centred at the top for the pill. It moves to the ball only when ballHome
      // is set, with no easing: the face does the travelling, not the column.
      x: (parent.width - width) / 2 + root.ballShiftX
      y: root.hudTopY + root.ballShiftY
      z: 2

      Behavior on width {
        NumberAnimation {
          duration: 340
          easing.type: Easing.BezierSpline
          easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1]
        }
      }

      Item {
        id: pillSlot
        width: parent.width
        height: pill.height

      Rectangle {
        id: pill
        property real targetHeight: root.pillHeight
        property real shownHeight: 0
        property bool motionReady: false
        property bool closing: false
        property bool ringShown: false
        property real ringOpacity: 0
        property bool ringReady: false
        readonly property bool ringRunning: !root.compact && (root.listening || (root.working && !root.awaitingPermission))

        width: root.pillWidth
        // Same 340 ms ease as the column that holds it, so the mask and the
        // visible pill keep the same width while it grows or folds.
        Behavior on width {
          NumberAnimation {
            duration: 340
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1]
          }
        }
        anchors.horizontalCenter: parent.horizontalCenter
        height: motionReady ? shownHeight : targetHeight
        onTargetHeightChanged: {
          if (!motionReady) return
          closing = targetHeight + 0.5 < height
          shownHeight = targetHeight
        }
        onRingRunningChanged: {
          if (!ringReady) return
          if (ringRunning) ringShown = true
          ringOpacity = ringRunning ? 1 : 0
        }
        Component.onCompleted: {
          shownHeight = targetHeight
          motionReady = true
          if (ringRunning) ringShown = true
          ringOpacity = ringRunning ? 1 : 0
          ringReady = true
        }

        Behavior on height {
          enabled: pill.motionReady
          NumberAnimation {
            duration: pill.closing ? 260 : 340
            easing.type: Easing.BezierSpline
            easing.bezierCurve: pill.closing
              ? [0.4, 0, 0.2, 1, 1, 1]
              : [0.23, 1, 0.32, 1, 1, 1]
          }
        }

        // Fades and grows in place: the pill never travels with the face.
        opacity: root.pillFade
        scale: root.phase.pillScaleFrom + (1 - root.phase.pillScaleFrom) * root.pillFade
        radius: root.compact ? height / 2 : root.px(Theme.arcRadiusPx())
        color: (root.compact || root.notchMoving) ? "transparent" : root.surface

        Behavior on radius {
          NumberAnimation {
            duration: 340
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1]
          }
        }
        Behavior on color {
          enabled: !root.notchSnap
          ColorAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        border.width: (root.compact || root.notchMoving) ? 0 : 1
        border.color: root.rim
        clip: !root.compact

        GlowRing {
          anchors.fill: parent
          z: 0
          radius: pill.radius
          running: pill.ringShown
          opacity: pill.ringOpacity
          accent: root.listening ? Theme.moodRed() : root.foreground
          ringWidth: 1.5 * root.uiScale
          level: root.listening && alfred ? alfred.audioLevel : -1

          Behavior on opacity {
            enabled: pill.ringReady
            NumberAnimation {
              duration: 180
              easing.type: Easing.OutCubic
              onFinished: {
                if (!pill.ringRunning) pill.ringShown = false
              }
            }
          }
        }

        MouseArea {
          id: ballHit
          anchors.fill: parent
          z: 10
          enabled: root.compact && !root.notchMoving && root.ballHome
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          // Press and move past 6 px drags the ball; the release is not a click.
          property real pressX: 0
          property real pressY: 0
          property real pressOffX: 0
          property real pressOffY: 0
          property bool dragMoved: false
          onPressed: function(mouse) {
            var p = mapToItem(escScope, mouse.x, mouse.y)
            ballHit.pressX = p.x
            ballHit.pressY = p.y
            ballHit.pressOffX = root.ballOffsetX
            ballHit.pressOffY = root.ballOffsetY
            ballHit.dragMoved = false
          }
          onPositionChanged: function(mouse) {
            if (!ballHit.pressed) return
            var p = mapToItem(escScope, mouse.x, mouse.y)
            var dx = p.x - ballHit.pressX
            var dy = p.y - ballHit.pressY
            if (!ballHit.dragMoved) {
              if (Math.hypot(dx, dy) <= 6) return
              ballHit.dragMoved = true
              root.ballDragging = true
            }
            var c = root.clampBallOffset(ballHit.pressOffX + dx, ballHit.pressOffY + dy)
            root.ballOffsetX = c.x
            root.ballOffsetY = c.y
          }
          onReleased: {
            if (!ballHit.dragMoved) return
            root.ballDragging = false
            root.saveBallOffset()
          }
          onClicked: {
            if (ballHit.dragMoved) {
              ballHit.dragMoved = false
              return
            }
            if (root.listening) root.stopListen()
            else root.pokeAndOpen()
          }
        }

        Column {
          id: pillBody
          // Stay laid out while the face flies between the ball and the row,
          // so the chip slot has a real position. Opacity carries the fade.
          visible: root.opened && (root.focused || root.dock > 0.08 || root.departing)
          opacity: root.focused && !root.departing ? 1 : 0
          z: 4

          Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
          }
          anchors.fill: parent
          anchors.leftMargin: root.surfacePadX
          anchors.rightMargin: root.surfacePadX
          anchors.topMargin: root.surfacePadY
          anchors.bottomMargin: root.surfacePadY
          spacing: root.controlGap

          RowLayout {
            width: parent.width
            spacing: root.controlGap

            HudButton {
              uiScale: root.uiScale
              glassy: root.glassy

              icon: "add"
              Layout.alignment: root.rowAlign
              opened: root.menuKind === "attach"
              active: root.attachments.length > 0
              badge: root.attachments.length
              tooltipText: root.attachments.length > 0 ? root.attachments.length + " attached · click to add more" : "Attach"
              onClicked: root.toggleMenu("attach")
            }

            Flickable {
              id: composerFlick
              Layout.fillWidth: true
              Layout.preferredWidth: 0
              Layout.minimumWidth: root.px(Theme.inputMinPx())
              Layout.preferredHeight: root.composerTextHeight
              Layout.alignment: Qt.AlignVCenter
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.VerticalFlick
              interactive: contentHeight > height

              QQC.TextArea.flickable: QQC.TextArea {
                id: composerInput
                wrapMode: TextEdit.Wrap
                color: root.foreground
                selectionColor: Color.accent
                selectedTextColor: root.glassy ? root.foreground : Color.background
                placeholderText: root.busy ? (root.profileLabel + " is working…") : (root.transcribing ? "Transcribing…" : (root.listening ? "Listening…" : (root.gatewayActive ? ("Ask " + root.profileLabel) : "Gateway down")))
                placeholderTextColor: root.dim
                font.family: root.fontFamily
                font.pixelSize: root.fontPx(Style.font.body)
                font.weight: root.inkWeight
                font.hintingPreference: Font.PreferFullHinting
                background: Item {}
                leftPadding: root.px(4)
                rightPadding: root.px(4)
                topPadding: root.px(2)
                bottomPadding: root.px(2)
                readOnly: root.busy
                enabled: root.focused && !root.busy
                onTextChanged: root.syncSlash()
                onTextEdited: { if (root.alfred && root.alfred.noteTyped) root.alfred.noteTyped() }
                Keys.onPressed: function(event) {
                  if (root.handleCapture(event) || root.handleShortcut(event)) {
                    event.accepted = true
                    return
                  }
                  if (event.key === Qt.Key_Escape) {
                    root.handleEscape()
                    event.accepted = true
                    return
                  }
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (event.modifiers & Qt.ShiftModifier) return
                    if (!root.tryApplySlash()) root.submit()
                    event.accepted = true
                    return
                  }
                  if (!root.slashPanelOpen) return
                  if (event.key === Qt.Key_Down) {
                    root.moveSlash(1)
                    event.accepted = true
                    return
                  }
                  if (event.key === Qt.Key_Up) {
                    root.moveSlash(-1)
                    event.accepted = true
                    return
                  }
                  if (event.key === Qt.Key_Tab) {
                    root.tryApplySlash()
                    event.accepted = true
                  }
                }
              }
            }
          }

          RowLayout {
            width: parent.width
            spacing: root.controlGap

            Flickable {
              id: agentFlick
              Layout.fillWidth: true
              Layout.preferredWidth: 0
              Layout.preferredHeight: root.agentSize
              Layout.maximumHeight: root.agentSize
              Layout.alignment: Qt.AlignVCenter
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.HorizontalFlick
              interactive: contentWidth > width
              contentWidth: agentRow.implicitWidth
              contentHeight: root.agentSize

              Row {
                id: agentRow
                height: root.agentSize
                spacing: root.controlGap

                Repeater {
                  model: root.opened && (root.focused || root.dock > 0.08 || root.departing) ? root.visibleRoster : 0

                  Item {
                    id: profileChip
                    required property var modelData
                    readonly property bool current: String(modelData.key || modelData.id || "") === root.profileKey
                    width: root.agentSize
                    height: root.agentSize
                    Component.onCompleted: if (current) root.leadChip = profileChip
                    onCurrentChanged: {
                      if (current) root.leadChip = profileChip
                      else if (root.leadChip === profileChip) root.leadChip = null
                    }
                    Component.onDestruction: if (root.leadChip === profileChip) root.leadChip = null

                    ProfileBlob {
                      anchors.fill: parent
                      // The hero draws the current face, one player, so this
                      // copy would pop in on top of the flight.
                      visible: !profileChip.current
                      agentId: String(profileChip.modelData.key || profileChip.modelData.id || "")
                      slot: "chip"
                      cursorX: root.alfred ? root.alfred.cursorX : NaN
                      cursorY: root.alfred ? root.alfred.cursorY : NaN
                      cursorAt: root.alfred ? root.alfred.cursorAt : 0
                      shape: String(profileChip.modelData.shape || "cercle")
                      fill: String(profileChip.modelData.fill || "#0a0a0c")
                      expression: String(profileChip.modelData.expression || "")
                      idleVariant: Number(profileChip.modelData.idle || 0)
                      phase: Number(profileChip.modelData.phase || 0)
                      eyes: String(profileChip.modelData.eyes || "soft")
                      mood: profileChip.current ? root.mood : "idle"
                      flow: profileChip.current ? "open" : ""
                      selected: profileChip.current
                    }

                    MouseArea {
                      id: profileChipHit
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      preventStealing: true
                      onPressed: function(mouse) { mouse.accepted = true }
                      onClicked: {
                        var key = String(profileChip.modelData.key || profileChip.modelData.id || "")
                        Qt.callLater(function() { root.chooseProfile(key) })
                      }
                    }
                  }
                }
              }
            }

            HudButton {
              uiScale: root.uiScale
              glassy: root.glassy

              visible: root.busy
              icon: root.previewOpen ? "eye-closed" : "eye"
              Layout.alignment: root.rowAlign
              active: root.previewOpen
              tooltipText: root.previewOpen ? "Hide live preview (Ctrl+P)" : "Show what Alfred is doing (Ctrl+P)"
              onClicked: root.togglePreview()
            }

            HudButton {
              uiScale: root.uiScale
              glassy: root.glassy

              wide: true
              Layout.alignment: root.rowAlign
              icon: "settings-gear"
              trailingIcon: "chevron-down"
              label: root.settingsSummary()
              opened: root.menuKind === "settings" || root.menuParent === "settings"
              tooltipText: "Model, provider, theme, reasoning, profile, gateway and sessions"
              onClicked: root.toggleSettings()
            }

            HudButton {
              uiScale: root.uiScale
              glassy: root.glassy

              icon: root.listening ? "stop" : "mic"
              Layout.alignment: root.rowAlign
              active: root.listening
              tooltipText: root.listening ? "Stop dictation" : "Dictate"
              onClicked: root.toggleVoice()
            }

            HudButton {
              uiScale: root.uiScale
              glassy: root.glassy

              primary: !root.showVoicePrimary
              Layout.alignment: root.rowAlign
              icon: root.showVoicePrimary ? "comment" : (root.showStop ? "stop" : "arrow-up")
              enabled: root.showVoicePrimary || root.showStop || root.hasPayload
              tooltipText: root.showVoicePrimary ? "Start voice conversation" : (root.showStop ? "Stop" : "Send")
              onClicked: root.handlePrimary()
            }

            HudButton {
              uiScale: root.uiScale
              glassy: root.glassy

              icon: "screen-normal"
              Layout.alignment: root.rowAlign
              tooltipText: "Exit HUD"
              onClicked: root.openDesktop()
            }
          }
        }
      }
      }

      Item {
        id: chipWrap
        width: parent.width
        height: root.focused && root.attachments.length > 0 ? chipRow.implicitHeight + root.px(8) : 0
        clip: true
        opacity: height > 0 ? 1 : 0

        Behavior on height {
          NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        Flow {
          id: chipRow
          width: parent.width
          y: root.px(8)
          spacing: root.px(6)

          Repeater {
            model: root.attachments

            Rectangle {
              id: attachChip
              required property var modelData
              height: root.px(26)
              width: attachInner.implicitWidth + root.px(18)
              radius: height / 2
              color: attachChipHit.containsMouse ? Util.alpha(Color.accent, 0.24) : Util.alpha(Color.accent, 0.14)
              border.width: 1
              border.color: Util.alpha(Color.accent, 0.35)

              MouseArea {
                id: attachChipHit
                anchors.fill: parent
                hoverEnabled: true
              }

              QQC.ToolTip.visible: attachChipHit.containsMouse
              QQC.ToolTip.text: String(attachChip.modelData)
              QQC.ToolTip.delay: 500

              Row {
                id: attachInner
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: root.px(9)
                spacing: root.px(6)

                Text {
                  textFormat: Text.PlainText
                  text: Theme.glyph(AlfredModel.attachmentIcon(attachChip.modelData))
                  color: Color.accent
                  font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
                  font.pixelSize: root.px(13)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: AlfredModel.fileName(attachChip.modelData)
                  width: Math.min(implicitWidth, root.px(220))
                  elide: Text.ElideMiddle
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.fontPx(Style.font.caption)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: Theme.glyph("close")
                  color: chipClose.containsMouse ? Color.urgent : root.dim
                  font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
                  font.pixelSize: root.px(12)
                  anchors.verticalCenter: parent.verticalCenter

                  MouseArea {
                    id: chipClose
                    anchors.fill: parent
                    anchors.margins: -5
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true
                    onPressed: function(mouse) { mouse.accepted = true }
                    onClicked: {
                      var path = String(attachChip.modelData)
                      Qt.callLater(function() { root.removeAttachment(path) })
                    }
                  }
                }
              }
            }
          }

          Rectangle {
            visible: root.attachments.length > 1
            height: root.px(26)
            width: clearInner.implicitWidth + root.px(18)
            radius: height / 2
            color: clearHit.containsMouse ? Util.alpha(Color.urgent, 0.16) : "transparent"
            border.width: 1
            border.color: Util.alpha(Color.foreground, 0.14)

            Row {
              id: clearInner
              anchors.centerIn: parent
              spacing: root.px(6)

              Text {
                textFormat: Text.PlainText
                text: Theme.glyph("clear-all")
                color: clearHit.containsMouse ? Color.urgent : root.dim
                font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
                font.pixelSize: root.px(12)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                textFormat: Text.PlainText
                text: "Clear all"
                color: clearHit.containsMouse ? Color.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: root.fontPx(Style.font.caption)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            MouseArea {
              id: clearHit
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              preventStealing: true
              onPressed: function(mouse) { mouse.accepted = true }
              onClicked: Qt.callLater(function() { if (alfred && typeof alfred.clearAttachments === "function") alfred.clearAttachments() })
            }
          }
        }
      }

      Item {
        id: chatStripWrap
        width: parent.width
        height: root.showChatStrip ? root.px(34) : 0
        clip: true
        opacity: height > 0 ? 1 : 0
        z: 21

        Behavior on height {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Flickable {
          anchors.fill: parent
          anchors.topMargin: root.px(6)
          contentWidth: chatRow.implicitWidth
          contentHeight: height
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.HorizontalFlick
          interactive: contentWidth > width

          Row {
            id: chatRow
            height: parent.height
            spacing: root.px(6)

            ActionChip {
              icon: "add"
              label: "New chat"
              tip: "New chat (Ctrl+N)"
              onActivated: root.newChat()
            }

            ActionChip {
              icon: "history"
              label: "Previous sessions"
              tip: "Previous sessions (Ctrl+H)"
              opened: root.menuKind === "sessions"
              onActivated: root.toggleSessions()
            }

            Rectangle {
              visible: root.chats.length > 1
              width: 1
              height: parent.height - root.px(8)
              anchors.verticalCenter: parent.verticalCenter
              color: Util.alpha(root.dim, 0.35)
            }

            Repeater {
              model: root.chats.length > 1 ? root.chats : 0

              Rectangle {
                id: chatChip
                required property var modelData
                readonly property bool current: String(modelData.id) === root.activeChatId
                readonly property string chipState: modelData.busy === true
                  ? (modelData.awaitingPermission === true ? "permission" : "busy")
                  : (modelData.outcomeSeen === true ? "idle" : (String(modelData.lastOutcome || "") === "error" ? "error" : (String(modelData.lastOutcome || "") === "success" ? "success" : "idle")))
                height: chatRow.height
                width: chipInner.implicitWidth + root.px(18)
                radius: height / 2
                color: current ? Util.alpha(Color.accent, 0.20) : (chipHit.containsMouse ? Util.alpha(Color.foreground, 0.10) : root.sheet)
                border.width: 1
                border.color: current ? Util.alpha(Color.accent, 0.55) : Util.alpha(Color.accent, 0.16)

                MouseArea {
                  id: chipHit
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  preventStealing: true
                  onPressed: function(mouse) { mouse.accepted = true }
                  onClicked: {
                    var id = String(chatChip.modelData.id)
                    Qt.callLater(function() { root.switchChat(id) })
                  }
                }

                Row {
                  id: chipInner
                  anchors.centerIn: parent
                  spacing: root.px(6)

                  Rectangle {
                    visible: chatChip.chipState !== "idle"
                    width: root.px(7)
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: chatChip.chipState === "busy" ? Color.accent
                      : (chatChip.chipState === "permission" ? Theme.moodYellow()
                        : (chatChip.chipState === "error" ? Theme.moodRed() : Theme.moodGreen()))

                    SequentialAnimation on opacity {
                      running: chatChip.chipState === "busy"
                      loops: Animation.Infinite
                      alwaysRunToEnd: true
                      NumberAnimation { from: 1; to: 0.75; duration: 1400; easing.type: Easing.InOutSine }
                      NumberAnimation { from: 0.75; to: 1; duration: 1400; easing.type: Easing.InOutSine }
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: String(chatChip.modelData.title || "Chat")
                    width: Math.min(implicitWidth, root.px(150))
                    elide: Text.ElideRight
                    color: chatChip.current ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: root.fontPx(Style.font.caption)
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: Theme.glyph("close")
                    opacity: chatChip.current || chipHit.containsMouse || chatClose.containsMouse ? 1 : 0.35
                    color: chatClose.containsMouse ? Color.urgent : root.dim
                    font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
                    font.pixelSize: root.px(12)
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                      id: chatClose
                      anchors.fill: parent
                      anchors.margins: -4
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      preventStealing: true
                      onPressed: function(mouse) { mouse.accepted = true }
                      onClicked: {
                        var id = String(chatChip.modelData.id)
                        Qt.callLater(function() { root.closeChat(id) })
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      Item {
        visible: root.listening
        width: parent.width
        height: root.listening ? root.px(36) : 0

        Row {
          id: voiceOkRow
          anchors.horizontalCenter: parent.horizontalCenter
          width: implicitWidth
          height: parent.height
          spacing: root.px(8)

          VoiceMeter {
            width: root.px(188)
            height: parent.height
            uiScale: root.uiScale
            surface: root.glassy ? root.surface : "#141418"
            ink: root.foreground
            level: alfred ? alfred.audioLevel : 0
            capturing: alfred ? alfred.voiceCapturing : false
            hearing: alfred ? alfred.voiceHearing : false
            elapsedMs: alfred ? alfred.voiceElapsedMs : 0
          }

          Rectangle {
            width: root.px(64)
            height: parent.height
            radius: height / 2
            color: voiceOkHit.containsMouse ? Theme.moodRed() : Util.alpha(Theme.moodRed(), 0.88)

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "OK"
              color: "#1a120c"
              font.family: root.fontFamily
              font.pixelSize: root.fontPx(Style.font.caption)
              font.bold: true
            }

            MouseArea {
              id: voiceOkHit
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              preventStealing: true
              onPressed: function(mouse) { mouse.accepted = true }
              onClicked: root.stopListen()
            }
          }
        }
      }

      Item {
        id: menuWrap
        readonly property real targetHeight: root.focused && root.menuOpen && !root.pickerOpen && !root.slashPanelOpen ? Math.min(menuCol.implicitHeight + root.px(20), root.px(root.menuKind === "shortcuts" || root.menuKind === "profile" ? 420 : root.menuKind === "face" ? 560 : 320)) : 0
        property real shownHeight: 0
        property real shownOpacity: 0
        property real shownScale: 0.98
        property bool motionReady: false
        property bool closing: false
        width: parent.width
        height: motionReady ? shownHeight : targetHeight
        clip: true
        opacity: motionReady ? shownOpacity : (targetHeight > 0.5 ? 1 : 0)
        scale: motionReady ? shownScale : (targetHeight > 0.5 ? 1 : 0.98)
        transformOrigin: Item.Top
        z: 20
        onTargetHeightChanged: root.trackSheet(menuWrap)
        Component.onCompleted: root.armSheet(menuWrap)

        Behavior on height {
          enabled: menuWrap.motionReady
          SheetEase { closing: menuWrap.closing }
        }
        Behavior on opacity {
          enabled: menuWrap.motionReady
          SheetEase { closing: menuWrap.closing }
        }
        Behavior on scale {
          enabled: menuWrap.motionReady
          SheetEase { closing: menuWrap.closing }
        }

        Rectangle {
          anchors.fill: parent
          anchors.topMargin: root.px(6)
          radius: root.px(Theme.arcRadiusPx())
          color: root.sheet
          border.width: 1
          border.color: Util.alpha(Color.accent, 0.18)

          Flickable {
            id: menuFlick
            anchors.fill: parent
            anchors.margins: root.px(8)
            contentWidth: width
            contentHeight: menuCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height

          Column {
            id: menuCol
            width: menuFlick.width
            spacing: root.px(2)

            Item {
              width: parent.width
              height: root.px(22)

              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.px(4)

                Text {
                  visible: root.menuParent !== "" || root.menuKind === "face"
                  textFormat: Text.PlainText
                  text: Theme.glyph("chevron-left")
                  color: menuBackHit.containsMouse ? root.foreground : root.dim
                  font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
                  font.pixelSize: root.px(Theme.iconPx())
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.menuTitle()
                  color: menuBackHit.containsMouse ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: root.fontPx(Style.font.caption)
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.menuKind === "face" ? Math.min(implicitWidth, menuCol.width - root.px(56)) : implicitWidth
                  elide: Text.ElideRight
                }
              }

              ProfileBlob {
                id: faceDraftBlob
                visible: root.menuKind === "face" && root.faceKey !== ""
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: root.px(22)
                height: root.px(22)
                agentId: root.faceKey
                slot: "face-draft"
                shape: root.faceShape
                fill: root.faceFill
                expression: root.faceExpression
                idleVariant: root.faceIdle
                phase: root.facePhase
                eyes: root.eyesFor(root.faceExpression)
                mood: "idle"
                still: true
              }

              MouseArea {
                id: menuBackHit
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: root.menuKind === "face" ? faceDraftBlob.left : parent.right
                enabled: root.menuParent !== "" || root.menuKind === "face"
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                preventStealing: true
                onPressed: function(mouse) { mouse.accepted = true }
                onClicked: Qt.callLater(root.menuBack)
              }
            }

            Repeater {
              model: root.menuKind === "settings" ? root.menuRows : 0

              Rectangle {
                id: settingsRow
                required property var modelData
                width: menuCol.width
                height: root.px(30)
                radius: root.px(6)
                color: settingsHit.containsMouse ? Util.alpha(Color.foreground, 0.10) : "transparent"

                Row {
                  anchors.left: parent.left
                  anchors.leftMargin: root.px(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: root.px(8)

                  Text {
                    textFormat: Text.PlainText
                    text: Theme.glyph(String(settingsRow.modelData.icon || ""))
                    color: root.dim
                    font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
                    font.pixelSize: root.px(Theme.iconPx())
                    anchors.verticalCenter: parent.verticalCenter
                    font.weight: root.inkWeight
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: String(settingsRow.modelData.label || "")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: root.fontPx(Style.font.caption)
                    anchors.verticalCenter: parent.verticalCenter
                    font.weight: root.inkWeight
                  }
                }

                Row {
                  anchors.right: parent.right
                  anchors.rightMargin: root.px(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: root.px(6)

                  Text {
                    textFormat: Text.PlainText
                    text: String(settingsRow.modelData.value || "")
                    width: Math.min(implicitWidth, root.px(260))
                    elide: Text.ElideRight
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: root.fontPx(Style.font.caption)
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    visible: settingsRow.modelData.sub === true
                    textFormat: Text.PlainText
                    text: Theme.glyph("chevron-right")
                    color: root.dim
                    font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
                    font.pixelSize: root.px(Theme.iconPx())
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  id: settingsHit
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  preventStealing: true
                  onPressed: function(mouse) {
                    mouse.accepted = true
                    var row = settingsRow.modelData
                    Qt.callLater(function() { root.activateMenuItem(row) })
                  }
                }
              }
            }

            Text {
              visible: root.menuKind === "shortcuts" && (!root.shortcutsHooked || root.shortcutsError !== "")
              width: parent.width
              leftPadding: root.px(8)
              rightPadding: root.px(8)
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.shortcutsError !== "" ? root.shortcutsError
                : "Global keys are not active: add pcall(require, \"hypr.alfred\") to ~/.config/hypr/bindings.lua"
              color: root.shortcutsError !== "" ? Color.urgent : Theme.moodYellow()
              font.family: root.fontFamily
              font.pixelSize: root.fontPx(Style.font.caption)
            }

            Repeater {
              model: root.menuKind === "shortcuts" ? root.menuRows : 0

              Rectangle {
                id: shortcutRow
                required property var modelData
                readonly property bool header: modelData.rowType === "header"
                readonly property bool capturing: !header && root.captureScope === modelData.scope && root.captureId === modelData.id
                readonly property string keys: String(modelData.keys || "")
                readonly property bool custom: !header && keys !== String(modelData.defaultKeys || "")
                width: menuCol.width
                height: header ? root.px(24) : root.px(30)
                radius: root.px(6)
                color: capturing ? Util.alpha(Color.accent, 0.16)
                  : (!header && shortcutHit.containsMouse ? Util.alpha(Color.foreground, 0.10) : "transparent")

                Text {
                  visible: shortcutRow.header
                  anchors.left: parent.left
                  anchors.leftMargin: root.px(8)
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: root.px(4)
                  textFormat: Text.PlainText
                  text: String(shortcutRow.modelData.label || "")
                  color: root.dim
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: root.fontPx(Style.font.caption)
                  font.letterSpacing: 1
                }

                Text {
                  visible: !shortcutRow.header
                  anchors.left: parent.left
                  anchors.leftMargin: root.px(8)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: String(shortcutRow.modelData.label || "")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.fontPx(Style.font.caption)
                }

                Row {
                  visible: !shortcutRow.header
                  anchors.right: parent.right
                  anchors.rightMargin: root.px(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: root.px(8)

                  Text {
                    visible: shortcutRow.custom && !shortcutRow.capturing
                    textFormat: Text.PlainText
                    text: Theme.glyph("clear-all")
                    color: resetHit.containsMouse ? root.foreground : root.dim
                    font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
                    font.pixelSize: root.px(12)
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                      id: resetHit
                      anchors.fill: parent
                      anchors.margins: -4
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      preventStealing: true
                      onPressed: function(mouse) {
                        mouse.accepted = true
                        var row = shortcutRow.modelData
                        Qt.callLater(function() { root.saveShortcut(row.scope, row.id, "default") })
                      }
                    }
                  }

                  Rectangle {
                    height: root.px(20)
                    width: keyText.implicitWidth + root.px(14)
                    radius: root.px(5)
                    color: shortcutRow.capturing ? "transparent" : Util.alpha(Color.foreground, 0.08)
                    border.width: 1
                    border.color: shortcutRow.capturing ? Color.accent : Util.alpha(Color.foreground, 0.14)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      id: keyText
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: shortcutRow.capturing ? "Press keys…"
                        : (shortcutRow.keys !== "" ? shortcutRow.keys : "Off")
                      color: shortcutRow.capturing ? Color.accent
                        : (shortcutRow.keys !== "" ? root.foreground : root.dim)
                      font.family: root.fontFamily
                      font.pixelSize: root.fontPx(Style.font.caption)
                    }
                  }
                }

                MouseArea {
                  id: shortcutHit
                  anchors.fill: parent
                  z: -1
                  enabled: !shortcutRow.header
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  preventStealing: true
                  onPressed: function(mouse) {
                    mouse.accepted = true
                    var row = shortcutRow.modelData
                    Qt.callLater(function() {
                      if (shortcutRow.capturing) root.cancelCapture()
                      else root.startCapture(row.scope, row.id)
                      root.focusComposerSoon()
                    })
                  }
                }
              }
            }

            Text {
              visible: root.menuKind === "shortcuts"
              width: parent.width
              topPadding: root.px(6)
              leftPadding: root.px(8)
              rightPadding: root.px(8)
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.captureId !== "" ? "Press the new combination · Esc cancels · Backspace turns it off"
                : (root.shortcutsSaving ? "Saving…" : "Click a shortcut to change it · the reset icon restores the default")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: root.fontPx(Style.font.caption)
            }

            Text {
              visible: root.menuKind === "sessions" && root.sessionOptions.length === 0
              width: parent.width
              leftPadding: root.px(8)
              textFormat: Text.PlainText
              text: root.sessionsLoading ? "Loading sessions…" : (root.sessionsError !== "" ? root.sessionsError : "No previous sessions")
              color: root.sessionsError !== "" ? Color.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: root.fontPx(Style.font.caption)
            }

            Repeater {
              model: root.menuKind === "sessions" ? root.sessionOptions : 0

              Rectangle {
                id: sessionRow
                required property var modelData
                readonly property bool isOpen: root.chatIsOpen(modelData.id)
                width: menuCol.width
                height: root.px(40)
                radius: root.px(6)
                color: isOpen ? Util.alpha(Color.accent, 0.14) : (sessionHit.containsMouse ? Util.alpha(Color.foreground, 0.08) : "transparent")

                Column {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: root.px(8)
                  anchors.rightMargin: root.px(8)
                  spacing: root.px(1)

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: String(sessionRow.modelData.title || sessionRow.modelData.id)
                    elide: Text.ElideRight
                    color: sessionRow.isOpen ? Color.accent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: root.fontPx(Style.font.caption)
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: [String(sessionRow.modelData.source || ""), String(sessionRow.modelData.lastActive || ""), sessionRow.modelData.messageCount + " msgs"]
                      .filter(function(part) { return part !== "" }).join(" · ")
                    elide: Text.ElideRight
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: root.fontPx(Style.font.caption)
                  }
                }

                MouseArea {
                  id: sessionHit
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  preventStealing: true
                  onPressed: function(mouse) {
                    mouse.accepted = true
                    var id = String(sessionRow.modelData.id)
                    var title = String(sessionRow.modelData.title || "")
                    Qt.callLater(function() { root.chooseSession(id, title) })
                  }
                }
              }
            }

            Repeater {
              model: root.menuKind === "attach" ? 4 : 0

              Rectangle {
                required property int index
                readonly property var row: root.attachItems[index]
                width: menuCol.width
                height: root.px(30)
                radius: root.px(6)
                color: attachHit.containsMouse ? Util.alpha(Color.foreground, 0.10) : "transparent"

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: root.px(8)
                  anchors.rightMargin: root.px(8)
                  spacing: root.px(8)

                  Text {
                    textFormat: Text.PlainText
                    text: Theme.glyph(row.iconName)
                    color: root.dim
                    font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
                    font.pixelSize: root.px(Theme.iconPx())
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: String(row.rowLabel)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: root.fontPx(Style.font.caption)
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  id: attachHit
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  preventStealing: true
                  propagateComposedEvents: false
                  onPressed: function(mouse) {
                    mouse.accepted = true
                    var mode = String(row.action)
                    Qt.callLater(function() { root.pickKind(mode) })
                  }
                }
              }
            }

            Repeater {
              model: root.menuKind === "voice" ? root.menuRows : 0

              Rectangle {
                required property var modelData
                width: menuCol.width
                height: root.px(30)
                radius: root.px(6)
                color: voiceItemHit.containsMouse ? Util.alpha(Color.foreground, 0.10) : "transparent"

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: root.px(8)
                  anchors.rightMargin: root.px(8)
                  spacing: root.px(8)

                  Text {
                    textFormat: Text.PlainText
                    text: Theme.glyph(String(modelData.icon || "mic"))
                    color: String(modelData.tint || "") === "red" ? Theme.moodRed() : root.dim
                    font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
                    font.pixelSize: root.px(Theme.iconPx())
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: String(modelData.label || "")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: root.fontPx(Style.font.caption)
                    font.weight: root.inkWeight
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  id: voiceItemHit
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  preventStealing: true
                  onPressed: function(mouse) {
                    mouse.accepted = true
                    var row = modelData
                    Qt.callLater(function() { root.activateMenuItem(row) })
                  }
                }
              }
            }

            Repeater {
              model: root.menuKind === "model" ? root.modelOptions : 0

              Rectangle {
                required property var modelData
                width: menuCol.width
                height: root.px(28)
                radius: root.px(6)
                color: String(modelData) === root.modelName
                  ? Util.alpha(Color.accent, 0.18)
                  : (modelHit.containsMouse ? Util.alpha(Color.foreground, 0.08) : "transparent")

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: root.px(8)
                  anchors.right: parent.right
                  anchors.rightMargin: root.px(8)
                  textFormat: Text.PlainText
                  text: String(modelData)
                  elide: Text.ElideRight
                  color: String(modelData) === root.modelName ? Color.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.fontPx(Style.font.caption)
                }

                MouseArea {
                  id: modelHit
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  preventStealing: true
                  onPressed: function(mouse) {
                    mouse.accepted = true
                    var name = String(modelData)
                    Qt.callLater(function() { root.chooseModel(name) })
                  }
                }
              }
            }

            Repeater {
              model: root.menuKind === "provider" ? root.providerOptions : 0

              Rectangle {
                required property var modelData
                width: menuCol.width
                height: root.px(28)
                radius: root.px(6)
                color: String(modelData.id) === root.modelProvider
                  ? Util.alpha(Color.accent, 0.18)
                  : (providerHit.containsMouse ? Util.alpha(Color.foreground, 0.08) : "transparent")

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: root.px(8)
                  anchors.right: parent.right
                  anchors.rightMargin: root.px(8)
                  textFormat: Text.PlainText
                  text: String(modelData.label || modelData.id || "")
                  elide: Text.ElideRight
                  color: String(modelData.id) === root.modelProvider ? Color.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.fontPx(Style.font.caption)
                  font.weight: root.inkWeight
                }

                MouseArea {
                  id: providerHit
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  preventStealing: true
                  onPressed: function(mouse) {
                    mouse.accepted = true
                    var id = String(modelData.id || "")
                    Qt.callLater(function() { root.chooseProvider(id) })
                  }
                }
              }
            }

            Repeater {
              model: root.menuKind === "theme" ? (root.themeOptions.length > 0 ? root.themeOptions : [{ id: "classic", label: "Classic" }, { id: "glassy", label: "Glassy" }]) : 0

              Rectangle {
                required property var modelData
                width: menuCol.width
                height: root.px(28)
                radius: root.px(6)
                color: String(modelData.id) === root.uiTheme
                  ? Util.alpha(Color.accent, 0.18)
                  : (themeHit.containsMouse ? Util.alpha(Color.foreground, 0.08) : "transparent")

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: root.px(8)
                  anchors.right: parent.right
                  anchors.rightMargin: root.px(8)
                  textFormat: Text.PlainText
                  text: String(modelData.label || modelData.id || "")
                  elide: Text.ElideRight
                  color: String(modelData.id) === root.uiTheme ? Color.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.fontPx(Style.font.caption)
                  font.weight: root.inkWeight
                }

                MouseArea {
                  id: themeHit
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  preventStealing: true
                  onPressed: function(mouse) {
                    mouse.accepted = true
                    var id = String(modelData.id || "")
                    Qt.callLater(function() { root.chooseTheme(id) })
                  }
                }
              }
            }

            Repeater {
              model: root.menuKind === "effort" ? root.effortOptions : 0

              Rectangle {
                required property var modelData
                width: menuCol.width
                height: root.px(28)
                radius: root.px(6)
                color: String(modelData) === root.reasoningEffort
                  ? Util.alpha(Color.accent, 0.18)
                  : (effortHit.containsMouse ? Util.alpha(Color.foreground, 0.08) : "transparent")

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: root.px(8)
                  anchors.right: parent.right
                  anchors.rightMargin: root.px(8)
                  textFormat: Text.PlainText
                  text: AlfredModel.effortLabel(modelData)
                  elide: Text.ElideRight
                  color: String(modelData) === root.reasoningEffort ? Color.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.fontPx(Style.font.caption)
                }

                MouseArea {
                  id: effortHit
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  preventStealing: true
                  onPressed: function(mouse) {
                    mouse.accepted = true
                    var level = String(modelData)
                    Qt.callLater(function() { root.chooseEffort(level) })
                  }
                }
              }
            }

            Repeater {
              model: root.menuKind === "gateway" ? root.gatewayOptions : 0

              Rectangle {
                required property var modelData
                width: menuCol.width
                height: root.px(30)
                radius: root.px(6)
                color: String(modelData.id) === root.gatewayConnectionId
                  ? Util.alpha(Color.accent, 0.18)
                  : (gatewayHit.containsMouse ? Util.alpha(Color.foreground, 0.08) : "transparent")

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: root.px(8)
                  anchors.rightMargin: root.px(8)
                  spacing: root.px(8)

                  Text {
                    textFormat: Text.PlainText
                    text: Theme.glyph(String(modelData.kind) === "local" ? "server" : "plug")
                    color: root.dim
                    font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
                    font.pixelSize: root.px(Theme.iconPx())
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    width: parent.width - root.px(28)

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: String(modelData.label || modelData.id || "")
                      elide: Text.ElideRight
                      color: String(modelData.id) === root.gatewayConnectionId ? Color.accent : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: root.fontPx(Style.font.caption)
                    }

                    Text {
                      width: parent.width
                      visible: String(modelData.kind || "") !== "local" && String(modelData.url || "") !== ""
                      textFormat: Text.PlainText
                      text: String(modelData.url || "")
                      elide: Text.ElideMiddle
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: root.fontPx(Style.font.caption)
                    }
                  }
                }

                MouseArea {
                  id: gatewayHit
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  preventStealing: true
                  onPressed: function(mouse) {
                    mouse.accepted = true
                    var id = String(modelData.id || "")
                    Qt.callLater(function() { root.chooseGateway(id) })
                  }
                }
              }
            }

            Repeater {
              model: root.menuKind === "profile" ? root.profileMenuModel : 0

              Rectangle {
                id: profileRow
                required property var modelData
                readonly property bool header: String(modelData.rowType || "") === "header"
                readonly property bool parked: !header && modelData.hidden === true
                readonly property bool current: !header && String(modelData.key || modelData.id || "") === root.profileKey
                readonly property bool canToggle: header ? false : (parked || root.visibleRoster.length > 1)
                width: menuCol.width
                height: header ? root.px(24) : root.px(40)
                radius: root.px(6)
                color: header || profileRow.parked
                  ? "transparent"
                  : (profileRow.current
                    ? Util.alpha(Color.accent, 0.18)
                    : (profileHit.containsMouse ? Util.alpha(Color.foreground, 0.08) : "transparent"))

                Text {
                  visible: profileRow.header
                  anchors.left: parent.left
                  anchors.leftMargin: root.px(8)
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: root.px(4)
                  textFormat: Text.PlainText
                  text: String(profileRow.modelData.label || "")
                  color: root.dim
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: root.fontPx(Style.font.caption)
                  font.letterSpacing: 1
                }

                Row {
                  id: profileBody
                  visible: !profileRow.header
                  opacity: profileRow.parked ? 0.55 : 1
                  anchors.left: parent.left
                  anchors.right: hideToggle.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.leftMargin: root.px(8)
                  anchors.rightMargin: root.px(4)
                  spacing: root.px(8)

                  ProfileBlob {
                    id: profileFace
                    visible: !profileRow.header
                    width: root.px(22)
                    height: root.px(22)
                    anchors.verticalCenter: parent.verticalCenter
                    agentId: String(profileRow.modelData.key || profileRow.modelData.id || "")
                    slot: "menu"
                    shape: String(profileRow.modelData.shape || "cercle")
                    fill: String(profileRow.modelData.fill || "#0a0a0c")
                    expression: String(profileRow.modelData.expression || "")
                    idleVariant: Number(profileRow.modelData.idle || 0)
                    phase: Number(profileRow.modelData.phase || 0)
                    eyes: String(profileRow.modelData.eyes || "soft")
                    mood: "idle"
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    width: Math.max(0, profileBody.width - profileFace.width - root.px(8))

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: String(profileRow.modelData.label || profileRow.modelData.id || "")
                      elide: Text.ElideRight
                      color: profileRow.current ? Color.accent : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: root.fontPx(Style.font.caption)
                    }

                    Text {
                      width: parent.width
                      visible: text !== ""
                      textFormat: Text.PlainText
                      text: {
                        var bits = []
                        if (String(profileRow.modelData.gatewayLabel || "") !== "") bits.push(String(profileRow.modelData.gatewayLabel))
                        if (String(profileRow.modelData.shortcut || "") !== "") bits.push(String(profileRow.modelData.shortcut))
                        return bits.join(" · ")
                      }
                      elide: Text.ElideRight
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: root.fontPx(Style.font.caption)
                    }
                  }
                }

                Item {
                  id: hideToggle
                  z: 2
                  visible: !profileRow.header
                  width: profileRow.header ? 0 : root.px(28)
                  height: root.px(32)
                  anchors.right: faceEdit.left
                  anchors.verticalCenter: parent.verticalCenter
                  opacity: profileRow.canToggle ? 1 : 0.35

                  Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: Theme.glyph(profileRow.parked ? "eye" : "eye-closed")
                    color: hideHit.containsMouse && profileRow.canToggle ? root.foreground : root.dim
                    font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
                    font.pixelSize: root.px(Theme.iconPx())
                  }

                  MouseArea {
                    id: hideHit
                    anchors.fill: parent
                    enabled: profileRow.canToggle
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    preventStealing: true
                    onPressed: function(mouse) {
                      mouse.accepted = true
                      var id = String(profileRow.modelData.key || profileRow.modelData.id || "")
                      var hide = !profileRow.parked
                      Qt.callLater(function() { root.setProfileVisibility(id, hide) })
                    }
                  }

                  QQC.ToolTip {
                    visible: hideHit.containsMouse && profileRow.canToggle
                    delay: 400
                    text: profileRow.parked ? "Show in Alfred" : "Hide from Alfred"
                  }
                }

                Item {
                  id: faceEdit
                  z: 2
                  visible: !profileRow.header
                  width: profileRow.header ? 0 : root.px(32)
                  height: root.px(32)
                  anchors.right: parent.right
                  anchors.rightMargin: root.px(4)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: Theme.glyph("edit")
                    color: faceEditHit.containsMouse ? root.foreground : root.dim
                    font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
                    font.pixelSize: root.px(Theme.iconPx())
                  }

                  MouseArea {
                    id: faceEditHit
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true
                    onPressed: function(mouse) {
                      mouse.accepted = true
                      var data = profileRow.modelData
                      var snap = {
                        key: String(data.key || data.id || ""),
                        label: String(data.label || ""),
                        shape: String(data.shape || "cercle"),
                        fill: String(data.fill || "#0a0a0c"),
                        expression: String(data.expression || "neutre"),
                        idle: root.idleIndex(data.idle),
                        phase: Number(data.phase || 0)
                      }
                      Qt.callLater(function() { root.openFaceEditor(snap) })
                    }
                  }
                }

                MouseArea {
                  id: profileHit
                  z: 1
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.right: hideToggle.left
                  enabled: !profileRow.header && !profileRow.parked
                  hoverEnabled: enabled
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  preventStealing: true
                  onPressed: function(mouse) {
                    mouse.accepted = true
                    if (profileRow.header || profileRow.parked) return
                    var id = String(profileRow.modelData.key || profileRow.modelData.id || "")
                    Qt.callLater(function() { root.chooseProfile(id) })
                  }
                }
              }
            }

            Column {
              id: faceEditor
              visible: root.menuKind === "face"
              width: parent.width
              spacing: 0

              function pick(kind, value) {
                Qt.callLater(function() { root.pickFace(kind, value) })
              }

              // Resolved here, where root is in scope. Delegates only read modelData.
              readonly property var swatchModel: {
                var shape = String(root.faceShape || "cercle")
                var fill = String(root.faceFill || "#0a0a0c")
                var expr = String(root.faceExpression || "neutre")
                var key = String(root.faceKey || "")
                var idle = root.faceIdle | 0
                var phase = Number(root.facePhase) || 0
                var size = root.px(76)
                var blob = root.px(22)
                var radius = root.px(6)
                var gap = root.px(4)
                var inset = root.px(8)
                var labelSize = root.fontPx(Style.font.caption)
                var labelColor = root.dim
                var labelFont = root.fontFamily
                var rowSpacing = root.px(4)
                var below = root.px(10)
                var groups = [
                  { caption: "Shape", kind: "shape", options: root.faceShapes, labels: root.faceShapeLabels },
                  { caption: "Color", kind: "fill", options: root.faceColors, labels: root.faceColorLabels },
                  { caption: "Expression", kind: "expression", options: root.faceExpressions, labels: root.faceExpressionLabels },
                  { caption: "Idle", kind: "idle", options: root.faceIdles, labels: root.faceIdleLabels }
                ]
                var rows = []
                var g
                for (g = 0; g < groups.length; g++) {
                  var group = groups[g]
                  var options = group.options || []
                  var swatches = []
                  var i
                  for (i = 0; i < options.length; i++) {
                    var value = String(options[i] || "")
                    var names = group.labels || options
                    var itemShape = group.kind === "shape" ? value : shape
                    var itemFill = group.kind === "fill" ? value : fill
                    var itemExpr = group.kind === "expression" ? value : expr
                    var itemIdle = group.kind === "idle" ? root.idleIndex(value) : idle
                    var chosen = false
                    if (group.kind === "shape") chosen = shape === value
                    else if (group.kind === "fill") chosen = fill.toLowerCase() === value.toLowerCase()
                    else if (group.kind === "idle") chosen = idle === itemIdle
                    else chosen = expr === value
                    swatches.push({
                      kind: group.kind,
                      value: value,
                      label: String(names[i] || value),
                      labelSize: labelSize,
                      labelFont: labelFont,
                      labelColor: labelColor,
                      still: group.kind !== "idle",
                      shape: itemShape,
                      fill: itemFill,
                      expression: itemExpr,
                      eyes: root.eyesFor(itemExpr),
                      agentId: key + ":" + group.kind + ":" + value,
                      chosen: chosen,
                      idle: itemIdle,
                      phase: phase,
                      size: size,
                      blob: blob,
                      radius: radius
                    })
                  }
                  rows.push({
                    caption: group.caption,
                    swatches: swatches,
                    gap: gap,
                    inset: inset,
                    labelColor: labelColor,
                    labelFont: labelFont,
                    labelSize: labelSize,
                    rowSpacing: rowSpacing,
                    below: below
                  })
                }
                return rows
              }

              Repeater {
                model: faceEditor.swatchModel
                delegate: FaceRow {
                  required property var modelData
                  caption: modelData.caption
                  swatches: modelData.swatches
                  gap: modelData.gap
                  inset: modelData.inset
                  labelColor: modelData.labelColor
                  labelFont: modelData.labelFont
                  labelSize: modelData.labelSize
                  rowSpacing: modelData.rowSpacing
                  below: modelData.below
                }
                onItemAdded: function(index, item) {
                  if (item.wired) return
                  item.wired = true
                  item.picked.connect(function(kind, value) { faceEditor.pick(kind, value) })
                }
              }

              Row {
                x: root.px(8)
                spacing: root.px(6)

                Rectangle {
                  width: Math.max(root.px(72), faceSaveLabel.implicitWidth + root.px(24))
                  height: root.px(28)
                  radius: root.px(6)
                  color: faceSaveHit.containsMouse ? Util.alpha(Color.accent, 0.28) : Util.alpha(Color.accent, 0.18)

                  Text {
                    id: faceSaveLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "Save"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: root.fontPx(Style.font.caption)
                  }

                  MouseArea {
                    id: faceSaveHit
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true
                    onPressed: function(mouse) { mouse.accepted = true }
                    onClicked: Qt.callLater(root.saveFace)
                  }
                }

                Rectangle {
                  width: Math.max(root.px(72), faceResetLabel.implicitWidth + root.px(24))
                  height: root.px(28)
                  radius: root.px(6)
                  color: faceResetHit.containsMouse ? Util.alpha(Color.foreground, 0.10) : "transparent"

                  Text {
                    id: faceResetLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "Reset"
                    color: faceResetHit.containsMouse ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: root.fontPx(Style.font.caption)
                  }

                  MouseArea {
                    id: faceResetHit
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true
                    onPressed: function(mouse) { mouse.accepted = true }
                    onClicked: Qt.callLater(root.clearFace)
                  }
                }
              }
            }
          }
          }
        }
      }

      Item {
        id: slashWrap
        readonly property real targetHeight: root.slashPanelOpen ? root.px(280) : 0
        property real shownHeight: 0
        property real shownOpacity: 0
        property real shownScale: 0.98
        property bool motionReady: false
        property bool closing: false
        width: parent.width
        height: motionReady ? shownHeight : targetHeight
        clip: true
        opacity: motionReady ? shownOpacity : (targetHeight > 0.5 ? 1 : 0)
        scale: motionReady ? shownScale : (targetHeight > 0.5 ? 1 : 0.98)
        transformOrigin: Item.Top
        z: 20
        onTargetHeightChanged: root.trackSheet(slashWrap)
        Component.onCompleted: root.armSheet(slashWrap)

        Behavior on height {
          enabled: slashWrap.motionReady
          SheetEase { closing: slashWrap.closing }
        }
        Behavior on opacity {
          enabled: slashWrap.motionReady
          SheetEase { closing: slashWrap.closing }
        }
        Behavior on scale {
          enabled: slashWrap.motionReady
          SheetEase { closing: slashWrap.closing }
        }

        Rectangle {
          anchors.fill: parent
          anchors.topMargin: root.px(6)
          radius: root.px(Theme.arcRadiusPx())
          color: root.sheet
          border.width: 1
          border.color: Util.alpha(Color.accent, 0.18)

          Flickable {
            id: slashList
            anchors.fill: parent
            anchors.margins: root.px(8)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: slashCol.implicitHeight
            flickableDirection: Flickable.VerticalFlick

            Column {
              id: slashCol
              width: slashList.width
              spacing: 0

              Text {
                width: parent.width
                visible: root.slashItems.length === 0
                height: visible ? root.px(22) : 0
                textFormat: Text.PlainText
                text: root.slashLoading ? "Loading commands and skills…" : "No matching commands"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: root.fontPx(Style.font.caption)
              }

              Repeater {
                model: root.slashViewRows

                Item {
                  required property var modelData
                  width: slashCol.width
                  height: modelData.rowType === "header" ? root.px(22) : root.px(40)

                  Text {
                    visible: modelData.rowType === "header"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: root.px(8)
                    textFormat: Text.PlainText
                    text: String(modelData.group || "").toUpperCase()
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: root.fontPx(Style.font.caption)
                    font.bold: true
                  }

                  Rectangle {
                    visible: modelData.rowType === "item"
                    anchors.fill: parent
                    radius: root.px(6)
                    color: modelData.itemIndex === root.slashIndex
                      ? Util.alpha(Color.accent, 0.18)
                      : (slashHit.containsMouse ? Util.alpha(Color.foreground, 0.08) : "transparent")

                    Column {
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: root.px(8)
                      anchors.rightMargin: root.px(8)
                      spacing: root.px(1)

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: String(modelData.display || modelData.text || "")
                        elide: Text.ElideRight
                        color: String(modelData.kind) === "skill" ? Color.accent : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: root.fontPx(Style.font.caption)
                      }

                      Text {
                        width: parent.width
                        visible: String(modelData.meta || "") !== ""
                        textFormat: Text.PlainText
                        text: String(modelData.meta || "")
                        elide: Text.ElideRight
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: root.fontPx(Style.font.caption)
                      }
                    }

                    MouseArea {
                      id: slashHit
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      preventStealing: true
                      onEntered: {
                        if (modelData.itemIndex >= 0) root.slashIndex = modelData.itemIndex
                      }
                      onPressed: function(mouse) {
                        mouse.accepted = true
                        var idx = modelData.itemIndex
                        Qt.callLater(function() { root.applySlashAt(idx) })
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      Item {
        id: pickerWrap
        readonly property real targetHeight: root.focused && root.pickerOpen ? root.px(280) : 0
        property real shownHeight: 0
        property real shownOpacity: 0
        property real shownScale: 0.98
        property bool motionReady: false
        property bool closing: false
        width: parent.width
        height: motionReady ? shownHeight : targetHeight
        clip: true
        opacity: motionReady ? shownOpacity : (targetHeight > 0.5 ? 1 : 0)
        scale: motionReady ? shownScale : (targetHeight > 0.5 ? 1 : 0.98)
        transformOrigin: Item.Top
        z: 20
        onTargetHeightChanged: root.trackSheet(pickerWrap)
        Component.onCompleted: root.armSheet(pickerWrap)

        Behavior on height {
          enabled: pickerWrap.motionReady
          SheetEase { closing: pickerWrap.closing }
        }
        Behavior on opacity {
          enabled: pickerWrap.motionReady
          SheetEase { closing: pickerWrap.closing }
        }
        Behavior on scale {
          enabled: pickerWrap.motionReady
          SheetEase { closing: pickerWrap.closing }
        }

        FilePicker {
          uiScale: root.uiScale
          ink: root.foreground
          dim: root.dim
          surface: root.sheet
          inkWeight: root.inkWeight

          anchors.fill: parent
          anchors.topMargin: root.px(6)
          visible: root.pickerOpen
          mode: root.pickerMode !== "" ? root.pickerMode : "files"
          onAccepted: function(paths) {
            if (alfred && typeof alfred.addAttachments === "function") alfred.addAttachments(paths)
            root.closePicker()
            grabFocusTimer.tries = 0
            grabFocusTimer.restart()
          }
          onCancelled: {
            root.closePicker()
            grabFocusTimer.tries = 0
            grabFocusTimer.restart()
          }
        }
      }

      Item {
        id: previewWrap
        readonly property real targetHeight: root.previewVisible ? Math.min(previewCol.implicitHeight + root.px(28), root.px(340)) : 0
        property real shownHeight: 0
        property real shownOpacity: 0
        property real shownScale: 0.98
        property bool motionReady: false
        property bool closing: false
        width: parent.width
        height: motionReady ? shownHeight : targetHeight
        clip: true
        opacity: motionReady ? shownOpacity : (targetHeight > 0.5 ? 1 : 0)
        scale: motionReady ? shownScale : (targetHeight > 0.5 ? 1 : 0.98)
        transformOrigin: Item.Top
        onTargetHeightChanged: root.trackSheet(previewWrap)
        Component.onCompleted: root.armSheet(previewWrap)

        Behavior on height {
          enabled: previewWrap.motionReady
          SheetEase { closing: previewWrap.closing }
        }
        Behavior on opacity {
          enabled: previewWrap.motionReady
          SheetEase { closing: previewWrap.closing }
        }
        Behavior on scale {
          enabled: previewWrap.motionReady
          SheetEase { closing: previewWrap.closing }
        }

        Rectangle {
          anchors.fill: parent
          anchors.topMargin: root.px(8)
          radius: root.px(18)
          color: root.sheet
          border.width: 1
          border.color: Util.alpha(Color.accent, 0.28)

          Flickable {
            id: previewFlick
            anchors.fill: parent
            anchors.margins: root.px(12)
            contentWidth: width
            contentHeight: previewCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height

            Column {
              id: previewCol
              width: previewFlick.width
              spacing: root.px(4)

              Item {
                width: parent.width
                height: root.px(22)

                Row {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: root.px(6)

                  Text {
                    textFormat: Text.PlainText
                    text: Theme.glyph(root.awaitingPermission ? "lock" : "pulse")
                    color: root.awaitingPermission ? Theme.moodYellow() : Color.accent
                    font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
                    font.pixelSize: root.px(Theme.iconPx())
                    anchors.verticalCenter: parent.verticalCenter

                    SequentialAnimation on opacity {
                      running: root.previewVisible && !root.awaitingPermission
                      loops: Animation.Infinite
                      alwaysRunToEnd: true
                      NumberAnimation { from: 1; to: 0.75; duration: 1400; easing.type: Easing.InOutSine }
                      NumberAnimation { from: 0.75; to: 1; duration: 1400; easing.type: Easing.InOutSine }
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: (root.awaitingPermission ? "WAITING FOR APPROVAL" : "LIVE")
                      + (root.busyStartedAt > 0 ? " · " + AlfredModel.formatDuration(root.nowMs - root.busyStartedAt) : "")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: root.fontPx(Style.font.caption)
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Text {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.activity.length === 1 ? "1 step" : (root.activity.length + " steps")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: root.fontPx(Style.font.caption)
                }
              }

              Text {
                visible: root.activity.length === 0 && root.liveText === ""
                width: parent.width
                textFormat: Text.PlainText
                text: root.gatewayKind === "local" ? "Waiting for the first step…" : "Remote gateways only report the final reply."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: root.fontPx(Style.font.caption)
              }

              Repeater {
                model: root.activity

                Item {
                  id: stepRow
                  required property var modelData
                  required property int index
                  readonly property string status: String(modelData.status || "")
                  readonly property color tint: status === "error" ? Theme.moodRed() : (status === "running" ? Color.accent : root.dim)
                  width: previewCol.width
                  height: stepText.implicitHeight + root.px(8)

                  Rectangle {
                    visible: stepRow.index < root.activity.length - 1
                    x: root.px(7)
                    y: root.px(20)
                    width: 1
                    height: parent.height - root.px(16)
                    color: Util.alpha(root.dim, 0.35)
                  }

                  Text {
                    id: stepIcon
                    x: 0
                    y: root.px(4)
                    width: root.px(15)
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    text: Theme.glyph(stepRow.status === "error" ? "error" : String(stepRow.modelData.icon || "tools"))
                    color: stepRow.tint
                    font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
                    font.pixelSize: root.px(Theme.iconPx())

                    SequentialAnimation on opacity {
                      running: stepRow.status === "running"
                      loops: Animation.Infinite
                      alwaysRunToEnd: true
                      NumberAnimation { from: 1; to: 0.75; duration: 1400; easing.type: Easing.InOutSine }
                      NumberAnimation { from: 0.75; to: 1; duration: 1400; easing.type: Easing.InOutSine }
                    }
                  }

                  Column {
                    id: stepText
                    anchors.left: stepIcon.right
                    anchors.leftMargin: root.px(8)
                    anchors.right: stepMeta.left
                    anchors.rightMargin: root.px(8)
                    y: root.px(3)
                    spacing: 0

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: String(stepRow.modelData.name || "tool")
                      elide: Text.ElideRight
                      color: stepRow.status === "running" ? root.foreground : Util.alpha(root.foreground, 0.8)
                      font.family: root.fontFamily
                      font.pixelSize: root.fontPx(Style.font.caption)
                      font.bold: true
                    }

                    Text {
                      visible: text !== ""
                      width: parent.width
                      textFormat: Text.PlainText
                      text: String(stepRow.modelData.summary || "")
                      elide: Text.ElideMiddle
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: root.fontPx(Style.font.caption)
                    }

                    Text {
                      visible: stepRow.status === "error" && text !== ""
                      width: parent.width
                      textFormat: Text.PlainText
                      text: String(stepRow.modelData.output || "")
                      wrapMode: Text.Wrap
                      maximumLineCount: 2
                      elide: Text.ElideRight
                      color: Theme.moodRed()
                      font.family: root.fontFamily
                      font.pixelSize: root.fontPx(Style.font.caption)
                    }
                  }

                  Text {
                    id: stepMeta
                    anchors.right: parent.right
                    y: root.px(4)
                    textFormat: Text.PlainText
                    text: stepRow.status === "running"
                      ? AlfredModel.formatDuration(Math.max(0, root.nowMs - Number(stepRow.modelData.startedAt || root.nowMs)))
                      : AlfredModel.formatDuration(stepRow.modelData.durationMs)
                    color: stepRow.tint
                    font.family: root.fontFamily
                    font.pixelSize: root.fontPx(Style.font.caption)
                  }
                }
              }

              Column {
                visible: root.liveText !== ""
                width: parent.width
                spacing: root.px(2)
                topPadding: root.px(4)

                Text {
                  textFormat: Text.PlainText
                  text: "WRITING"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: root.fontPx(Style.font.caption)
                  font.bold: true
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.liveText
                  wrapMode: Text.Wrap
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.fontPx(Style.font.caption)
                }
              }
            }
          }
        }
      }

      Item {
        id: bandWrap
        readonly property real targetHeight: root.showThread ? Math.min(bandColumn.implicitHeight + root.px(24), root.bandMaxHeight) : 0
        property real shownHeight: 0
        property real shownOpacity: 0
        property real shownScale: 0.98
        property bool motionReady: false
        property bool closing: false
        width: parent.width
        height: motionReady ? shownHeight : targetHeight
        clip: true
        opacity: motionReady ? shownOpacity : (targetHeight > 0.5 ? 1 : 0)
        scale: motionReady ? shownScale : (targetHeight > 0.5 ? 1 : 0.98)
        transformOrigin: Item.Top
        onTargetHeightChanged: root.trackSheet(bandWrap)
        Component.onCompleted: root.armSheet(bandWrap)

        Behavior on height {
          enabled: bandWrap.motionReady
          SheetEase { closing: bandWrap.closing }
        }
        Behavior on opacity {
          enabled: bandWrap.motionReady
          SheetEase { closing: bandWrap.closing }
        }
        Behavior on scale {
          enabled: bandWrap.motionReady
          SheetEase { closing: bandWrap.closing }
        }

        Rectangle {
          id: band
          anchors.fill: parent
          anchors.topMargin: root.px(8)
          radius: root.px(18)
          color: root.sheet
          border.width: 1
          border.color: Util.alpha(Color.accent, 0.18)

          Flickable {
            id: bandFlick
            anchors.fill: parent
            anchors.margins: root.px(14)
            contentWidth: width
            contentHeight: bandColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height
            pressDelay: 180
            readonly property real distanceToEnd: contentHeight - height - contentY
            onContentHeightChanged: {
              if (root.followThread && !jumpAnim.running) contentY = Math.max(0, contentHeight - height)
            }
            onHeightChanged: {
              if (root.followThread && !jumpAnim.running) contentY = Math.max(0, contentHeight - height)
            }
            onMovementEnded: root.updateFollowThread()
            onContentYChanged: {
              if (moving || bandScroll.pressed) root.updateFollowThread()
            }

            NumberAnimation {
              id: jumpAnim
              target: bandFlick
              property: "contentY"
              duration: 260
              easing.type: Easing.OutCubic
              onFinished: root.followThread = true
            }

            QQC.ScrollBar.vertical: QQC.ScrollBar {
              id: bandScroll
              policy: bandFlick.contentHeight > bandFlick.height ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff
              width: root.px(6)
              padding: 0
              background: Item {}
              contentItem: Rectangle {
                implicitWidth: root.px(4)
                radius: width / 2
                color: Util.alpha(root.foreground, bandScroll.pressed ? 0.55 : (bandScroll.hovered ? 0.40 : 0.22))
              }
            }

            Column {
              id: bandColumn
              width: bandFlick.width - root.px(6)
              spacing: root.px(8)

              TextEdit {
                visible: root.lastError !== ""
                width: parent.width
                height: contentHeight
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                color: Color.urgent
                text: root.lastError
                font.family: root.fontFamily
                font.pixelSize: root.fontPx(Style.font.caption)
                textFormat: TextEdit.PlainText
              }

              Repeater {
                model: root.messages

                Column {
                  required property var modelData
                  width: bandColumn.width
                  spacing: root.px(2)

                  Row {
                    spacing: root.px(8)
                    Text {
                      textFormat: Text.PlainText
                      text: modelData.role === "user" ? "You" : "Alfred"
                      color: modelData.role === "user" ? Color.accent : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: root.fontPx(Style.font.caption)
                      font.bold: true
                      anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                      visible: String(modelData.text || "") !== ""
                      textFormat: Text.PlainText
                      text: Theme.glyph("copy")
                      color: copyHit.containsMouse ? root.foreground : root.dim
                      font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
                      font.pixelSize: root.px(Theme.iconPx())
                      anchors.verticalCenter: parent.verticalCenter
                      z: 4
                      MouseArea {
                        id: copyHit
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        preventStealing: true
                        onPressed: function(mouse) {
                          mouse.accepted = true
                          grabFocusTimer.stop()
                        }
                        onClicked: root.copyText(modelData.text)
                      }
                    }
                  }

                  TextEdit {
                    width: parent.width
                    height: contentHeight
                    readOnly: true
                    selectByMouse: true
                    selectByKeyboard: true
                    persistentSelection: true
                    wrapMode: TextEdit.Wrap
                    color: root.foreground
                    selectedTextColor: root.glassy ? root.foreground : Color.background
                    selectionColor: Color.accent
                    text: modelData.text || ""
                    font.family: root.fontFamily
                    font.pixelSize: root.fontPx(Style.font.body)
                    font.weight: root.inkWeight
                    font.hintingPreference: Font.PreferFullHinting
                    textFormat: TextEdit.PlainText
                    activeFocusOnPress: true
                    Keys.onPressed: function(event) {
                      if (event.matches(StandardKey.Copy)) {
                        root.copyText(selectedText !== "" ? selectedText : text)
                        event.accepted = true
                      }
                    }
                    onActiveFocusChanged: {
                      if (activeFocus) grabFocusTimer.stop()
                    }
                  }
                }
              }

              Text {
                visible: root.messages.length === 0 && root.lastError === ""
                width: parent.width
                textFormat: Text.PlainText
                text: root.busy ? "Thinking…" : "Ready."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: root.fontPx(Style.font.caption)
              }
            }
          }
        }
      }

      Item {
        id: jumpWrap
        readonly property bool shown: root.showThread && bandFlick.interactive && bandFlick.distanceToEnd > root.px(24)
        width: parent.width
        height: shown ? root.px(36) : 0
        clip: true
        opacity: shown ? 1 : 0

        Behavior on height {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          height: root.px(28)
          width: jumpInner.implicitWidth + root.px(22)
          radius: height / 2
          color: jumpHit.containsMouse ? Qt.darker(root.sheet, 0.85) : root.sheet
          border.width: 1
          border.color: Util.alpha(Color.accent, jumpHit.containsMouse ? 0.45 : 0.22)

          Row {
            id: jumpInner
            anchors.centerIn: parent
            spacing: root.px(6)

            Text {
              textFormat: Text.PlainText
              text: Theme.glyph("arrow-down")
              color: jumpHit.containsMouse ? root.foreground : root.dim
              font.family: menuCodicon.name !== "" ? menuCodicon.name : "codicon"
              font.pixelSize: root.px(12)
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              textFormat: Text.PlainText
              text: "Jump to latest"
              color: root.foreground
              opacity: jumpHit.containsMouse ? 1 : 0.8
              font.family: root.fontFamily
              font.pixelSize: root.fontPx(Style.font.caption)
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          MouseArea {
            id: jumpHit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            preventStealing: true
            onPressed: function(mouse) { mouse.accepted = true }
            onClicked: Qt.callLater(root.jumpThreadToEnd)
          }
        }
      }
    }
    }
  }

  onMessagesChanged: Qt.callLater(root.scrollThreadToEnd)

  Component.onCompleted: {
    if (alfred && typeof alfred.refreshStatus === "function") alfred.refreshStatus()
    if (alfred && typeof alfred.refreshModels === "function") alfred.refreshModels()
  }
}
