// «Tanlash»'s mark on one of an album's pictures or files, as Telegram-iOS puts one on each
// (GridMessageSelectionNode, FileMessageSelectionNode): a ring, filled and ticked once picked. It pops
// in and out with picking (scale 0.2 → 1, on the render thread).
import QtQuick

Item {
    id: check
    property bool on: false             // picking: it shows
    property bool checked: false
    property color hollow: Qt.rgba(0, 0, 0, 0.3)    // unpicked: within the ring
    property color ring: "white"
    property color ringChecked: "white"
    width: 26; height: 26
    // shown once made (Behaviors move nothing until the row it is in is complete)
    property bool shown: false
    Component.onCompleted: Qt.callLater(() => shown = Qt.binding(() => check.on))
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.2
    visible: opacity > 0
    // (iOS 26's spring, as the pages' push)
    Behavior on scale { ScaleAnimator { duration: 450; easing.type: Easing.BezierSpline
                                        easing.bezierCurve: [0.0744, 0.0298, 0.1307, 0.7931, 0.3680, 0.9301, 0.4409, 0.9722, 0.4273, 0.9999, 1.0, 1.0] } }
    Behavior on opacity { OpacityAnimator { duration: 250 } }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: check.checked ? Theme.accent : check.hollow
        border.color: check.checked ? check.ringChecked : check.ring
        border.width: 1.5
    }
    Icon {
        visible: check.checked
        anchors.centerIn: parent
        width: Math.round(check.width * 0.7); height: width
        name: "check"
        color: "white"
    }
}
