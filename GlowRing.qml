import QtQuick
import QtQuick.Shapes
import qs.Commons

// Faithful port of Hermes Desktop HUD `.arc-border.arc-composer`
// (NousResearch/hermes-agent apps/desktop/src/styles.css + composer/index.tsx:
// `{hudMode && busy && <span className="arc-border arc-composer" />}`).
//
// CSS: 2px ring via mask-composite exclude; ::before is 300%×300% linear-gradient
// at 160deg, transform translate(-10%,-10%) → (-50%,-50%) in 2.23s linear.
// QML: winding stadium ring (same trick as Omarchy BorderOverlay) filled with
// that moving gradient — no Canvas, no MultiEffect 2px mask.
Item {
  id: root

  property bool running: false
  property color accent: Color.foreground
  property real ringWidth: 2
  // Corner radius of the surface the ring hugs; values >= height/2 give a stadium.
  property real radius: height / 2

  visible: running
  enabled: false
  z: 0

  readonly property color c1: accent
  readonly property color c2: Qt.rgba(accent.r, accent.g, accent.b, 0.45)

  property real travel: 0

  readonly property real boxW: Math.max(1, width) * 3
  readonly property real boxH: Math.max(1, height) * 3
  readonly property real ox: -(0.10 + travel * 0.40) * boxW
  readonly property real oy: -(0.10 + travel * 0.40) * boxH
  // CSS 160deg → math 70deg (0° = east), same span formula as BorderGeometry.
  readonly property real dx: Math.cos(70 * Math.PI / 180)
  readonly property real dy: Math.sin(70 * Math.PI / 180)
  readonly property real span: (Math.abs(boxW * dx) + Math.abs(boxH * dy)) / 2
  readonly property real gcx: ox + boxW / 2
  readonly property real gcy: oy + boxH / 2
  readonly property string ringPath: root.running ? roundedRing(width, height, ringWidth, radius) : ""

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
    duration: 2230
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
        GradientStop { position: 0.15; color: "transparent" }
        GradientStop { position: 0.20; color: root.c1 }
        GradientStop { position: 0.25; color: root.c2 }
        GradientStop { position: 0.35; color: "transparent" }
        GradientStop { position: 0.40; color: "transparent" }
        GradientStop { position: 0.55; color: "transparent" }
        GradientStop { position: 0.60; color: root.c1 }
        GradientStop { position: 0.65; color: root.c2 }
        GradientStop { position: 0.75; color: "transparent" }
        GradientStop { position: 0.80; color: "transparent" }
        GradientStop { position: 0.95; color: "transparent" }
        GradientStop { position: 1.00; color: root.c1 }
      }

      PathSvg { path: root.ringPath }
    }
  }
}
