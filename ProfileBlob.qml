import QtQuick
import QtQuick.Shapes
import qs.Commons
import "BloubEngine.js" as Bloub

// One bloub per agent. Paths stay in the engine's viewBox and a single matrix
// maps them onto this item, so the eyes and the body share one scale. The
// face is drawn into a supersampled layer: at chip size the curve renderer
// alone leaves stair-steps on the rim.
//
// The rim is painted after the fill. A stroke drawn underneath is half-covered
// by the fill, which is why the outline used to disappear. Satellite dots
// (the side balls of `thinking`) get the same fill and rim as the body.
Item {
  id: root

  layer.enabled: width > 2 && height > 2
  layer.textureSize: Qt.size(Math.ceil(width * root.supersample), Math.ceil(height * root.supersample))
  layer.smooth: true
  layer.mipmap: true

  property string agentId: ""
  property string slot: "face"
  property string shape: "cercle"
  property color fill: "#0a0a0c"
  property string expression: ""
  property string eyes: "soft"
  property int idleVariant: 0
  property real phase: 0
  property string mood: "idle"
  // Engine pose, when it should not follow `mood`. The tray stays on the
  // agent's silhouette while a task runs: the thinking dots are smaller than
  // the rim at icon size, so they collapse into one pale blob.
  property string pose: ""
  property bool selected: false
  // "" = free-running mood cycle; "compact" / "open" = follow the agent's
  // state flow (working, outcome x3, notification, end).
  property string flow: ""
  // Editor draft and swatches. The pose stays on the idle face at clock 0.
  property bool still: false
  property real supersample: 5

  readonly property string playerId: (agentId !== "" ? agentId : shape + fill) + "/" + slot
  readonly property real unit: Math.min(width, height) / 316
  readonly property bool voice: mood === "listening"
  readonly property bool marching: mood === "busy" || mood === "working" || mood === "listening"
    || mood === "success" || mood === "error" || mood === "attention" || mood === "permission"
  readonly property color paper: "#f6f3ec"
  // Outcome tints the whole rim. Working keeps the cream hairline and lets
  // the traveling segment carry the motion.
  readonly property color rimColor: {
    if (root.mood === "success") return "#3dd68c"
    if (root.mood === "attention" || root.mood === "permission") return "#e5a00d"
    if (root.mood === "error" || root.mood === "listening") return "#ff3b3b"
    return "#f6f3ec"
  }
  readonly property color marchColor: {
    if (root.mood === "success") return "#d8ffe9"
    if (root.mood === "attention" || root.mood === "permission") return "#ffe7a3"
    if (root.mood === "error" || root.mood === "listening") return "#ffd0d1"
    return "#ffffff"
  }
  // Screen pixels. About a fifth under the previous 1.7 / 1.45 / 1.2.
  // Below 36px the factor falls with width (26px → width/45, 16px sits on
  // the 0.54 floor) so the chips and the tray lose a little more than the
  // large face. The floor keeps the stroke visible. The traveling segment
  // sits on that rim.
  readonly property real rimPx: {
    var base = root.voice ? 1.36 : (root.marching ? 1.16 : 0.96)
    if (root.width < 36) return base * Math.max(0.54, root.width / 45)
    return base
  }
  readonly property real rimStroke: root.rimPx / Math.max(root.unit, 0.02)
  readonly property real marchStroke: root.rimStroke
  // Soft lift under the rim. Several copies of the body step down-right and
  // fade, in this same supersampled pass: a child blur is clipped by the
  // layer. The ink follows the surface behind the blob. A light surface gets
  // a near-black crescent at high opacity; a dark surface gets a cream
  // crescent at a lower opacity, so the shape still separates.
  //
  // The surface is the first opaque ancestor paint (the pill, the menu
  // sheet), else the shell window color (the bar). A Wayland layer does not
  // expose the pixels behind a transparent window, so a fully transparent
  // bar or the compact ball falls back to the theme: Color.bar.background
  // on the tray, and the pill's Qt.darker(Color.background, 1.45) everywhere
  // else. That fallback is the theme surface, not a sample of the wallpaper.
  property int groundTick: 0
  readonly property color themeTray: Color.bar.background
  readonly property color themeSheet: Qt.darker(Color.background, 1.45)
  readonly property color windowPaint: root.readWindowColor()
  readonly property color ground: {
    var _tick = root.groundTick
    var _win = root.windowPaint
    var _tray = root.themeTray
    var _sheet = root.themeSheet
    return root.resolveGround()
  }
  readonly property real groundLuminance: root.lumaOf(root.ground)
  // Gamma-encoded luma, not linear. 0.5 is a mid gray.
  readonly property bool groundLight: root.groundLuminance >= 0.5
  readonly property color shadowColor: root.groundLight ? "#000000" : "#f4efe6"
  readonly property var shadowWeightsOnLight: [0.58, 0.42, 0.30, 0.22, 0.15, 0.10, 0.065, 0.04]
  readonly property var shadowWeightsOnDark: [0.42, 0.30, 0.22, 0.16, 0.11, 0.07, 0.045, 0.028]
  readonly property var shadowWeights: root.groundLight ? root.shadowWeightsOnLight : root.shadowWeightsOnDark
  readonly property real shadowReach: root.width < 22 ? 2.85 : (root.width < 36 ? 3.4 : 5.0)
  readonly property real haloPx: root.width < 36 ? 0.7 : 1.05
  readonly property real haloStroke: root.haloPx / Math.max(root.unit, 0.02)
  readonly property real bodyLoop: Math.max(8, (root.frame.span || 620) / Math.max(root.marchStroke, 0.5))
  property real march: 0
  // Linear lap, plus a small speed swell. Position and velocity match at the
  // seam, so the dash keeps moving when the loop wraps.
  readonly property real marchPhase: root.march + 0.03 * Math.sin(root.march * 2 * Math.PI)

  function asColor(value) {
    if (value === undefined || value === null) return null
    if (typeof value === "string") {
      if (value.length < 1) return null
      return Qt.color(value)
    }
    if (typeof value === "object" && value.r !== undefined && value.g !== undefined
        && value.b !== undefined && value.a !== undefined)
      return value
    return null
  }

  function opaqueEnough(color) {
    return color && color.a >= 0.55
  }

  function lumaOf(value) {
    var color = root.asColor(value)
    if (!color) return 0
    return 0.299 * color.r + 0.587 * color.g + 0.114 * color.b
  }

  // Rectangle.color, a shell `background` color, or Overlay's `surface`.
  // Qt Quick Controls expose `background` as an item; those are ignored.
  function paintOf(node) {
    if (!node) return null
    var keys = ["color", "background", "surface"]
    var i
    for (i = 0; i < keys.length; i++) {
      var key = keys[i]
      if (!(key in node)) continue
      var color = root.asColor(node[key])
      if (root.opaqueEnough(color)) return color
    }
    return null
  }

  function readWindowColor() {
    var win = null
    try {
      if (root.QsWindow && root.QsWindow.window) win = root.QsWindow.window
    } catch (e) {
      win = null
    }
    if (!win) {
      try {
        if (root.Window && root.Window.window) win = root.Window.window
      } catch (e2) {
        win = null
      }
    }
    if (!win) return "transparent"
    try {
      if (win.color === undefined || win.color === null) return "transparent"
      return win.color
    } catch (e3) {
      return "transparent"
    }
  }

  function resolveGround() {
    var node = root.parent
    var guard = 0
    while (node && guard < 32) {
      var paint = root.paintOf(node)
      if (paint) return paint
      node = node.parent
      guard++
    }
    var win = root.asColor(root.windowPaint)
    if (root.opaqueEnough(win)) return win
    if (root.slot === "tray") return root.themeTray
    return root.themeSheet
  }

  function shadowMatrix(index) {
    var steps = root.shadowWeights.length
    var t = (index + 1) / steps
    var u = Math.max(root.unit, 0.02)
    var reach = root.shadowReach
    return root.mapOf(1, 0, 0, 1, reach * 0.28 * t / u, reach * t / u)
  }
  property var frame: ({
    body: "",
    alpha: 1,
    eyes: [],
    arcsBack: [],
    arcsFront: [],
    dots: [],
    dotsBehind: false,
    span: 620,
    notif: ""
  })

  implicitWidth: 26
  implicitHeight: 26

  // viewBox (x, y) -> pixels. ma..mf is the engine matrix (identity for the body).
  function mapOf(ma, mb, mc, md, me, mf) {
    var s = root.unit
    return Qt.matrix4x4(
      s * ma, s * mc, 0, s * me + root.width / 2,
      s * mb, s * md, 0, s * mf + root.height / 2,
      0, 0, 1, 0,
      0, 0, 0, 1
    )
  }

  // Extra scale baked into a dot matrix (the "!" tear is ×100). The stroke
  // has to shrink by the same factor or the rim blows up.
  function xformScale(dot) {
    if (!dot) return 1
    return Math.max(0.01, Math.hypot(Number(dot.ma || 1), Number(dot.mb || 0)))
  }

  function inkDot(dot) {
    return dot && dot.depth === undefined
  }

  function dotLoop(dot) {
    var span = dot && dot.span > 0 ? dot.span : 104
    var width = root.marchStroke / root.xformScale(dot)
    return Math.max(6, span / Math.max(width, 0.05))
  }

  function sample() {
    root.frame = Bloub.tick(
      root.playerId,
      root.still ? 0 : Date.now(),
      root.shape,
      root.voice ? "attentif" : root.expression,
      root.pose !== "" ? root.pose : root.mood,
      root.idleVariant,
      root.still ? 0 : root.phase,
      String(root.fill),
      root.eyes,
      root.still ? "still" : root.flow
    )
  }

  // A picked face has to redraw, but the pose must not march forward.
  function sampleStill() {
    if (!root.still || !root.visible || root.width <= 2 || root.height <= 2) return
    root.sample()
  }

  NumberAnimation on march {
    from: 0
    to: 1
    duration: 1400
    loops: Animation.Infinite
    easing.type: Easing.Linear
    running: !root.still && root.marching && root.visible && root.width > 2
  }

  Timer {
    interval: 16
    repeat: true
    running: !root.still && root.visible && root.width > 2 && root.height > 2
    triggeredOnStart: true
    onTriggered: root.sample()
  }

  // Ancestor paint is read from JS, which does not always subscribe to a
  // color that appears later (a Loader, the compact pill turning opaque).
  // The theme colors and the window color are real bindings; this tick
  // covers the rest. still:true keeps the pose pinned and only refreshes
  // the ground.
  Timer {
    interval: 240
    repeat: true
    running: root.visible && root.width > 2 && root.height > 2
    triggeredOnStart: true
    onTriggered: root.groundTick = root.groundTick + 1
  }

  onShapeChanged: root.sampleStill()
  onFillChanged: root.sampleStill()
  onExpressionChanged: root.sampleStill()
  onEyesChanged: root.sampleStill()
  onWidthChanged: root.sampleStill()
  onHeightChanged: root.sampleStill()
  onStillChanged: root.sampleStill()
  onVisibleChanged: root.sampleStill()
  Component.onCompleted: root.sampleStill()

  Component.onDestruction: Bloub.release(root.playerId)

  Repeater {
    model: 6
    Shape {
      required property int index
      property var arc: index < root.frame.arcsBack.length ? root.frame.arcsBack[index] : null
      visible: arc !== null && arc.opacity > 0.02 && arc.path !== ""
      anchors.fill: parent
      antialiasing: true
      transformOrigin: Item.TopLeft
      preferredRendererType: Shape.CurveRenderer
      opacity: arc ? arc.opacity : 0
      transform: Matrix4x4 { matrix: root.mapOf(1, 0, 0, 1, 0, 0) }
      ShapePath {
        strokeColor: arc ? arc.color : "transparent"
        strokeWidth: arc ? arc.width : 1
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: arc && arc.path ? arc.path : "M0 0" }
      }
    }
  }

  Repeater {
    model: 8
    Shape {
      required property int index
      property var dot: index < root.frame.dots.length ? root.frame.dots[index] : null
      visible: root.frame.dotsBehind && dot !== null && dot.opacity > 0.02
      anchors.fill: parent
      antialiasing: true
      transformOrigin: Item.TopLeft
      preferredRendererType: Shape.CurveRenderer
      opacity: dot ? dot.opacity * root.frame.alpha : 0
      transform: Matrix4x4 {
        matrix: dot
          ? root.mapOf(dot.ma, dot.mb, dot.mc, dot.md, dot.me, dot.mf)
          : root.mapOf(1, 0, 0, 1, 0, 0)
      }
      ShapePath {
        fillColor: dot ? dot.color : "transparent"
        strokeColor: "transparent"
        PathSvg { path: dot && dot.path ? dot.path : "M0 0" }
      }
    }
  }

  Repeater {
    model: root.shadowWeights.length
    Shape {
      required property int index
      anchors.fill: parent
      antialiasing: true
      transformOrigin: Item.TopLeft
      preferredRendererType: Shape.CurveRenderer
      opacity: root.shadowWeights[index] * root.frame.alpha
      transform: Matrix4x4 { matrix: root.shadowMatrix(index) }
      ShapePath {
        fillColor: root.shadowColor
        strokeColor: "transparent"
        PathSvg { path: root.frame.body || "M0 0" }
      }
    }
  }

  Shape {
    anchors.fill: parent
    antialiasing: true
    transformOrigin: Item.TopLeft
    preferredRendererType: Shape.CurveRenderer
    opacity: root.frame.alpha
    transform: Matrix4x4 { matrix: root.mapOf(1, 0, 0, 1, 0, 0) }
    ShapePath {
      fillColor: root.fill
      strokeColor: "transparent"
      PathSvg { path: root.frame.body || "M0 0" }
    }
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.rimColor
      strokeWidth: root.rimStroke
      joinStyle: ShapePath.RoundJoin
      capStyle: ShapePath.RoundCap
      PathSvg { path: root.frame.body || "M0 0" }
    }
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.marching ? root.marchColor : "transparent"
      strokeWidth: root.marching ? root.marchStroke : 0
      strokeStyle: ShapePath.DashLine
      dashPattern: [root.bodyLoop * 0.36, root.bodyLoop * 0.64]
      dashOffset: -root.marchPhase * root.bodyLoop
      joinStyle: ShapePath.RoundJoin
      capStyle: ShapePath.RoundCap
      PathSvg { path: root.frame.body || "M0 0" }
    }
  }

  Repeater {
    model: 2
    Shape {
      required property int index
      property var eye: index < root.frame.eyes.length ? root.frame.eyes[index] : null
      visible: eye !== null && eye.alpha > 0.02
      anchors.fill: parent
      antialiasing: true
      transformOrigin: Item.TopLeft
      preferredRendererType: Shape.CurveRenderer
      opacity: eye ? eye.alpha * root.frame.alpha : 0
      transform: Matrix4x4 {
        matrix: eye
          ? root.mapOf(eye.ma, eye.mb, eye.mc, eye.md, eye.me, eye.mf)
          : root.mapOf(1, 0, 0, 1, 0, 0)
      }
      ShapePath {
        fillColor: root.paper
        strokeColor: "transparent"
        PathSvg { path: eye && eye.path ? eye.path : "M0 0" }
      }
    }
  }

  Repeater {
    model: 8
    Shape {
      required property int index
      property var dot: index < root.frame.dots.length ? root.frame.dots[index] : null
      readonly property bool ink: root.inkDot(dot)
      readonly property real loop: root.dotLoop(dot)
      visible: !root.frame.dotsBehind && dot !== null && dot.opacity > 0.02
      anchors.fill: parent
      antialiasing: true
      transformOrigin: Item.TopLeft
      preferredRendererType: Shape.CurveRenderer
      // The pulse used to fade the side balls down to 0.55, which hid the
      // dark fill on a dark bar. Keep the size pulse; hold the ink opaque.
      opacity: dot ? (ink ? Math.max(dot.opacity, 0.92) : dot.opacity) * root.frame.alpha : 0
      transform: Matrix4x4 {
        matrix: dot
          ? root.mapOf(dot.ma, dot.mb, dot.mc, dot.md, dot.me, dot.mf)
          : root.mapOf(1, 0, 0, 1, 0, 0)
      }
      ShapePath {
        fillColor: ink ? "#80000000" : "transparent"
        strokeColor: ink ? "#80000000" : "transparent"
        strokeWidth: ink ? root.haloStroke / root.xformScale(dot) : 0
        joinStyle: ShapePath.RoundJoin
        capStyle: ShapePath.RoundCap
        PathSvg { path: dot && dot.path ? dot.path : "M0 0" }
      }
      ShapePath {
        fillColor: dot ? (ink ? root.fill : dot.color) : "transparent"
        strokeColor: "transparent"
        PathSvg { path: dot && dot.path ? dot.path : "M0 0" }
      }
      ShapePath {
        fillColor: "transparent"
        strokeColor: ink ? root.rimColor : "transparent"
        strokeWidth: ink ? root.rimStroke / root.xformScale(dot) : 0
        joinStyle: ShapePath.RoundJoin
        capStyle: ShapePath.RoundCap
        PathSvg { path: dot && dot.path ? dot.path : "M0 0" }
      }
      ShapePath {
        fillColor: "transparent"
        strokeColor: ink && root.marching ? root.marchColor : "transparent"
        strokeWidth: ink && root.marching ? root.marchStroke / root.xformScale(dot) : 0
        strokeStyle: ShapePath.DashLine
        dashPattern: [loop * 0.42, loop * 0.58]
        dashOffset: -root.marchPhase * loop
        joinStyle: ShapePath.RoundJoin
        capStyle: ShapePath.RoundCap
        PathSvg { path: dot && dot.path ? dot.path : "M0 0" }
      }
    }
  }

  Repeater {
    model: 6
    Shape {
      required property int index
      property var arc: index < root.frame.arcsFront.length ? root.frame.arcsFront[index] : null
      visible: arc !== null && arc.opacity > 0.02 && arc.path !== ""
      anchors.fill: parent
      antialiasing: true
      transformOrigin: Item.TopLeft
      preferredRendererType: Shape.CurveRenderer
      opacity: arc ? arc.opacity : 0
      transform: Matrix4x4 { matrix: root.mapOf(1, 0, 0, 1, 0, 0) }
      ShapePath {
        strokeColor: arc ? arc.color : "transparent"
        strokeWidth: arc ? arc.width : 1
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: arc && arc.path ? arc.path : "M0 0" }
      }
    }
  }

  Shape {
    anchors.fill: parent
    visible: root.frame.notif !== ""
    antialiasing: true
    transformOrigin: Item.TopLeft
    preferredRendererType: Shape.CurveRenderer
    opacity: root.frame.alpha
    transform: Matrix4x4 { matrix: root.mapOf(1, 0, 0, 1, 0, 0) }
    ShapePath {
      fillColor: "#2496e8"
      strokeColor: "transparent"
      PathSvg { path: root.frame.notif || "M0 0" }
    }
  }
}
