// A picture full screen, the way Telegram-iOS's gallery opens one: it grows out of its
// bubble while the black comes up behind it, a drag up or down sends it back there, two
// fingers zoom it (and one then moves it). Motion is Animators (render thread): the picture
// keeps its full-screen size and moves by x, y and scale.
import QtQuick

Item {
    id: viewer
    anchors.fill: parent
    visible: false
    z: 20

    property bool open: false
    property Item from: null            // the picture in the bubble: it hides while this shows
    property real aspect: 1             // height / width
    property string source: ""          // what shows (the bubble's own, then a bigger one)
    property var curve: [0.0744, 0.0298, 0.1307, 0.7931, 0.3680, 0.9301, 0.4409, 0.9722, 0.4273, 0.9999, 1.0, 1.0]

    // the picture fitted to the screen
    readonly property real fitW: Math.min(width, height / aspect)
    readonly property real fitH: fitW * aspect
    readonly property real fitX: (width - fitW) / 2
    readonly property real fitY: (height - fitH) / 2

    function show(item, aspect, source) {
        if (open)
            return
        from = item
        viewer.aspect = aspect
        viewer.source = source
        open = true
        visible = true
        const r = start()
        frame.scale = r.s
        frame.x = r.x
        frame.y = r.y
        back.opacity = 0
        item.opacity = 0
        going.stop()
        toX.to = fitX; toY.to = fitY; toScale.to = 1; toBack.to = 1
        coming.restart()
    }

    function close() {
        if (!open)
            return
        open = false
        coming.stop()
        settle.stop()
        const r = start()
        backX.to = r.x; backY.to = r.y; backScale.to = r.s; backBack.to = 0
        going.restart()
    }

    // where the bubble's picture is: the fitted picture scaled to cover it, centred on it
    function start() {
        const at = from.mapToItem(viewer, 0, 0)
        const s = Math.max(from.width / fitW, from.height / fitH)
        return { s: s, x: at.x + from.width / 2 - fitW * s / 2, y: at.y + from.height / 2 - fitH * s / 2 }
    }

    // a better picture than the bubble's, once it is here
    function better(path) {
        if (open)
            big.source = "file://" + path
    }

    Rectangle {
        id: back
        anchors.fill: parent
        color: "black"
        opacity: 0
    }

    Item {
        id: frame
        width: viewer.fitW; height: viewer.fitH
        transformOrigin: Item.TopLeft
        Image {
            anchors.fill: parent
            source: viewer.source
            asynchronous: true
            sourceSize: Qt.size(viewer.fitW, viewer.fitH)
            visible: big.status !== Image.Ready
        }
        Image {
            id: big
            anchors.fill: parent
            asynchronous: true
            sourceSize: Qt.size(viewer.fitW * 2, viewer.fitH * 2)     // room to zoom
        }
    }

    TapHandler {
        onTapped: viewer.close()
    }
    PinchHandler {
        id: pinch
        target: frame
        minimumScale: 1
        maximumScale: 5
        onActiveChanged: if (!active && frame.scale < 1.02) viewer.recentre()
    }
    DragHandler {           // zoomed: one finger moves the picture
        target: frame
        enabled: frame.scale > 1.02
    }
    DragHandler {           // not zoomed: drag it away to close
        id: away
        target: null
        enabled: frame.scale <= 1.02
        yAxis.enabled: true
        xAxis.enabled: false
        onTranslationChanged: if (active && viewer.open) {
            frame.y = viewer.fitY + translation.y
            back.opacity = 1 - Math.min(0.7, Math.abs(translation.y) / 400)
        }
        onActiveChanged: if (!active && viewer.open) {
            if (Math.abs(translation.y) > 90 || Math.abs(centroid.velocity.y) > 900)
                viewer.close()
            else
                viewer.recentre()
        }
    }

    function recentre() {
        settleX.to = fitX; settleY.to = fitY; settleScale.to = 1
        settle.restart()
    }

    ParallelAnimation {     // out of the bubble: the iOS 26 spring, as pages move (Main.qml)
        id: coming
        XAnimator { id: toX; target: frame; duration: 450; easing.type: Easing.BezierSpline; easing.bezierCurve: viewer.curve }
        YAnimator { id: toY; target: frame; duration: 450; easing.type: Easing.BezierSpline; easing.bezierCurve: viewer.curve }
        ScaleAnimator { id: toScale; target: frame; duration: 450; easing.type: Easing.BezierSpline; easing.bezierCurve: viewer.curve }
        OpacityAnimator { id: toBack; target: back; duration: 250 }
    }
    ParallelAnimation {     // back into it
        id: going
        XAnimator { id: backX; target: frame; duration: 300; easing.type: Easing.OutCubic }
        YAnimator { id: backY; target: frame; duration: 300; easing.type: Easing.OutCubic }
        ScaleAnimator { id: backScale; target: frame; duration: 300; easing.type: Easing.OutCubic }
        OpacityAnimator { id: backBack; target: back; duration: 250 }
        onFinished: {
            if (viewer.from)
                viewer.from.opacity = 1
            viewer.from = null
            viewer.visible = false
            big.source = ""
        }
    }
    ParallelAnimation {
        id: settle
        XAnimator { id: settleX; target: frame; duration: 250; easing.type: Easing.OutCubic }
        YAnimator { id: settleY; target: frame; duration: 250; easing.type: Easing.OutCubic }
        ScaleAnimator { id: settleScale; target: frame; duration: 250; easing.type: Easing.OutCubic }
        OpacityAnimator { target: back; to: 1; duration: 200 }
    }
}
