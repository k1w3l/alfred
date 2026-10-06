import QtQuick
import QtQuick.Shapes
import qs.Commons

// Traveling arc on the composer pill, from Hermes `.arc-border.arc-composer`
// (winding stadium, 160deg gradient). The lap matches ProfileBlob's rim
// (1400ms) and the bright segment fades in and out, so the pill and the face
// share one tempo instead of a harder, slower ring.
//
// CSS origin: 2px mask-composite exclude; ::before is 300%×300% linear-gradient
// at 160deg, translate(-10%,-10%) → (-50%,-50%). QML fills a winding stadium
// (same trick as Omarchy BorderOverlay) — no Canvas, no 2px mask.
Item {
  id: root

  property bool running: false
  property color accent: Color.foreground
  property real ringWidth: 1.5
  // < 0 keeps the decorative busy ring. >= 0 follows mic amplitude: a silent
  // mic stays dim and thin, a live one brightens and thickens.
  property real level: -1
  // Corner radius of the surface the ring hugs; values >= height/2 give a stadium.
  property real radius: height / 2

  visible: running
  enabled: false
  z: 0

  readonly property real amplitude: level < 0 ? 1 : Math.max(0.16, Math.min(1, 0.16 + level * 0.84))
  readonly property real drawnWidth: level < 0 ? ringWidth : ringWidth * (0.7 + Math.min(1, Math.max(0, level)) * 1.1)
  readonly property color c1: Qt.rgba(accent.r, accent.g, accent.b, amplitude)
  readonly property color c2: Qt.rgba(accent.r, accent.g, accent.b, amplitude * 0.45)

  property real travel: 0
  // Same seam-safe swell as ProfileBlob.marchPhase.
  readonly property real travelPhase: root.travel + 0.03 * Math.sin(root.travel * 2 * Math.PI)

  readonly property real boxW: Math.max(1, width) * 3
  readonly property real boxH: Math.max(1, height) * 3
  readonly property real ox: -(0.10 + travelPhase * 0.40) * boxW
  readonly property real oy: -(0.10 + travelPhase * 0.40) * boxH
  // CSS 160deg → math 70deg (0° = east), same span formula as BorderGeometry.
  readonly property real dx: Math.cos(70 * Math.PI / 180)
  readonly property real dy: Math.sin(70 * Math.PI / 180)
  readonly property real span: (Math.abs(boxW * dx) + Math.abs(boxH * dy)) / 2
  readonly property real gcx: ox + boxW / 2
  readonly property real gcy: oy + boxH / 2
  readonly property string ringPath: root.running ? roundedRing(width, height, drawnWidth, radius) : ""

  function roundedLoop(w, h, inset, radius, clockwise) {
    var r = Math.max(0.5, Math.min(radius - inset, h / 2 - inset, w / 2 - inset))
    var l = inset
    var t = inset
    var rt = w - inset
    var b = h - inset
    var rs = r + " " + r
    if (clockwise) {
      return "M " + (l + r) + " " + t
        + " L " + (rt - r) + " " + t
        + " A " + rs + " 0 0 1 " + rt + " " + (t + r)
        + " L " + rt + " " + (b - r)
        + " A " + rs + " 0 0 1 " + (rt - r) + " " + b
        + " L " + (l + r) + " " + b
        + " A " + rs + " 0 0 1 " + l + " " + (b - r)
        + " L " + l + " " + (t + r)
        + " A " + rs + " 0 0 1 " + (l + r) + " " + t
        + " Z"
    }
    return "M " + (l + r) + " " + t
      + " A " + rs + " 0 0 0 " + l + " " + (t + r)
      + " L " + l + " " + (b - r)
      + " A " + rs + " 0 0 0 " + (l + r) + " " + b
      + " L " + (rt - r) + " " + b
      + " A " + rs + " 0 0 0 " + rt + " " + (b - r)
      + " L " + rt + " " + (t + r)
      + " A " + rs + " 0 0 0 " + (rt - r) + " " + t
      + " L " + (l + r) + " " + t
      + " Z"
  }

  function roundedRing(w, h, rw, radius) {
    if (!isFinite(w) || !isFinite(h) || w < 8 || h < 8) return ""
    var outer = 0.5
    var inner = outer + Math.max(1, rw)
    if (inner >= h / 2 - 0.5) inner = h / 2 - 1
    var r = Math.max(1, Math.min(isFinite(radius) ? radius : h / 2, h / 2))
    return roundedLoop(w, h, outer, r, true) + " " + roundedLoop(w, h, inner, r, false)
  }

  onRunningChanged: {
    travel = 0
    if (running) travelAnim.restart()
  }

  NumberAnimation {
    id: travelAnim
    target: root
    property: "travel"
    from: 0
    to: 1
    duration: 1400
    loops: Animation.Infinite
    easing.type: Easing.Linear
    running: root.running && root.visible && root.width >= 8 && root.height >= 8
  }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    antialiasing: true
    visible: root.ringPath !== ""

    ShapePath {
      fillRule: ShapePath.WindingFill
      strokeWidth: 0
      fillGradient: LinearGradient {
        x1: root.gcx - root.dx * root.span
        y1: root.gcy - root.dy * root.span
        x2: root.gcx + root.dx * root.span
        y2: root.gcy + root.dy * root.span

        GradientStop { position: 0.00; color: "transparent" }
        GradientStop { position: 0.08; color: "transparent" }
        GradientStop { position: 0.16; color: root.c2 }
        GradientStop { position: 0.23; color: root.c1 }
        GradientStop { position: 0.30; color: root.c2 }
        GradientStop { position: 0.42; color: "transparent" }
        GradientStop { position: 0.50; color: "transparent" }
        GradientStop { position: 0.58; color: root.c2 }
        GradientStop { position: 0.65; color: root.c1 }
        GradientStop { position: 0.72; color: root.c2 }
        GradientStop { position: 0.86; color: "transparent" }
        GradientStop { position: 1.00; color: "transparent" }
      }

      PathSvg { path: root.ringPath }
    }
  }
}
