// How far a file has come: an arc round a circle that keeps turning, as Telegram-iOS's
// SemanticStatusNode draws a download; a cross in it stops it.
import QtQuick
import QtQuick.Shapes

Item {
    id: ring
    property real value: 0              // 0..1
    property color color: "white"
    property real thickness: 2.2
    property bool cross: true
    width: 44; height: 44

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        RotationAnimator on rotation { from: 0; to: 360; duration: 1600; loops: Animation.Infinite; running: ring.visible }
        ShapePath {
            fillColor: "transparent"
            strokeColor: ring.color
            strokeWidth: ring.thickness
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: ring.width / 2; centerY: ring.height / 2
                radiusX: ring.width / 2 - ring.thickness - 1; radiusY: radiusX
                startAngle: -90
                sweepAngle: 360 * Math.max(0.04, Math.min(1, ring.value))
            }
        }
    }
    Icon {
        visible: ring.cross
        anchors.centerIn: parent
        width: ring.width * 0.42; height: width
        name: "cross"
        color: ring.color
    }
}
