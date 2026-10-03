import QtQuick
import QtQuick.Shapes
import "BloubEngine.js" as Bloub

// One bloub per agent. Paths stay in the engine's viewBox and a single matrix
// maps them onto this item, so the eyes and the body share one scale. The
// whole face is drawn into a 4x layer and mipmapped down: at chip size the
// curve renderer alone leaves stair-steps on the rim.
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
  property bool selected: false
  // "" = free-running mood cycle; "compact" / "open" = follow the agent's
  // state flow (start, start-work, working, outcome x3, notification, end).
  property string flow: ""
  property real supersample: 4

  readonly property string playerId: (agentId !== "" ? agentId : shape + fill) + "/" + slot
  readonly property real unit: Math.min(width, height) / 316
  readonly property bool voice: mood === "listening"
  readonly property color paper: "#f6f3ec"
  readonly property color rimColor: voice ? "#ff3b3b" : "#f3f0ea"
  readonly property real rimPx: voice ? 2.35 : 1.15
  property var frame: ({
    body: "",
    alpha: 1,
    eyes: [],
    arcsBack: [],
    arcsFront: [],
    dots: [],
    dotsBehind: false,
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
        root.mood,
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
    opacity: root.frame.alpha
    transform: Matrix4x4 { matrix: root.mapOf(1, 0, 0, 1, 0, 0) }
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.rimColor
      strokeWidth: root.rimPx / Math.max(root.unit, 0.02)
      joinStyle: ShapePath.RoundJoin
      capStyle: ShapePath.RoundCap
      PathSvg { path: root.frame.body || "M0 0" }
    }
    ShapePath {
      fillColor: root.fill
      strokeColor: "transparent"
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
      visible: !root.frame.dotsBehind && dot !== null && dot.opacity > 0.02
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
