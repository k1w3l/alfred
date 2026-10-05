import QtQuick
import QtQuick.Shapes
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
  // Screen pixels. The 26px chips in the pill lost their fill under a 2px stroke,
  // so the rim thins further below 36px. The traveling segment sits on that rim.
  readonly property real rimPx: {
    var base = root.voice ? 1.7 : (root.marching ? 1.45 : 1.2)
    if (root.width < 36) return base * Math.max(0.62, root.width / 42)
    return base
  }
  readonly property real rimStroke: root.rimPx / Math.max(root.unit, 0.02)
  readonly property real marchStroke: root.rimStroke
  // Drop shadow just outside the rim. Scaled with the face so the small chips
  // keep a crescent without the halo swallowing the body.
  readonly property real shadowPx: root.width < 36 ? 0.85 : 1.35
  readonly property real shadowSpread: (root.shadowPx * 1.5) / Math.max(root.unit, 0.02)
  readonly property real shadowShift: (root.shadowPx * 0.9) / Math.max(root.unit, 0.02)
  readonly property real bodyLoop: Math.max(8, (root.frame.span || 620) / Math.max(root.marchStroke, 0.5))
  property real march: 0
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

  NumberAnimation on march {
    from: 0
    to: 1
    duration: 1400
    loops: Animation.Infinite
    easing.type: Easing.Linear
    running: root.marching && root.visible && root.width > 2
  }

  Timer {
    interval: 16
    repeat: true
    running: root.visible && root.width > 2 && root.height > 2
    triggeredOnStart: true
    onTriggered: {
      root.frame = Bloub.tick(
        root.playerId,
        Date.now(),
        root.shape,
        root.voice ? "attentif" : root.expression,
        root.pose !== "" ? root.pose : root.mood,
        root.idleVariant,
        root.phase,
        String(root.fill),
        root.eyes,
        root.flow
      )
    }
  }

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

  Shape {
    anchors.fill: parent
    antialiasing: true
    transformOrigin: Item.TopLeft
    preferredRendererType: Shape.CurveRenderer
    opacity: 0.5 * root.frame.alpha
    transform: Matrix4x4 { matrix: root.mapOf(1, 0, 0, 1, root.shadowShift, root.shadowShift * 1.35) }
    ShapePath {
      fillColor: "#000000"
      strokeColor: "#000000"
      strokeWidth: root.shadowSpread
      joinStyle: ShapePath.RoundJoin
      capStyle: ShapePath.RoundCap
      PathSvg { path: root.frame.body || "M0 0" }
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
      dashOffset: -root.march * root.bodyLoop
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
        strokeWidth: ink ? root.shadowSpread / root.xformScale(dot) : 0
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
        dashOffset: -root.march * loop
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
