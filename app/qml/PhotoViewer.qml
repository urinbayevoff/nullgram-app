// A picture full screen, the way Telegram-iOS's gallery opens one: it grows out of its
// bubble while the black comes up behind it, a drag up or down sends it back there, two
// fingers zoom it (and one then moves it). Motion is Animators (render thread): the picture
// keeps its full-screen size and moves by x, y and scale. A video plays in the same frame
// (with its sound), a tap shows or hides its controls; ↓ saves either to ~/Downloads.
import QtQuick
import QtMultimedia

Item {
    id: viewer
    anchors.fill: parent
    visible: false
    z: 20

    property bool open: false
    property Item from: null            // the picture in the bubble: it hides while this shows
    property real aspect: 1             // height / width
    property string source: ""          // what shows (the bubble's own, then a bigger one)
    property string video: ""           // a video's local path: it plays over the picture
    property bool chrome: true          // the video's controls show
    signal save()
    property var curve: [0.0744, 0.0298, 0.1307, 0.7931, 0.3680, 0.9301, 0.4409, 0.9722, 0.4273, 0.9999, 1.0, 1.0]

    // the picture fitted to the screen
    readonly property real fitW: Math.min(width, height / aspect)
    readonly property real fitH: fitW * aspect
    readonly property real fitX: (width - fitW) / 2
    readonly property real fitY: (height - fitH) / 2

    function show(item, aspect, source, video) {
        if (open)
            return
        from = item
        viewer.video = video || ""
        chrome = true
        if (viewer.video) {
            player.source = "file://" + viewer.video
            player.play()
            hide.restart()
        }
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
        player.stop()
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
        VideoOutput {
            id: screen
            anchors.fill: parent
            visible: viewer.video !== ""
        }
    }
    MediaPlayer {
        id: player
        videoOutput: screen
        audioOutput: AudioOutput {}
        onPlaybackStateChanged: if (playbackState !== MediaPlayer.PlayingState) viewer.chrome = true
    }
    Timer { id: hide; interval: 3000; onTriggered: if (player.playbackState === MediaPlayer.PlayingState) viewer.chrome = false }

    TapHandler {
        onTapped: {
            if (!viewer.video) {
                viewer.close()
                return
            }
            viewer.chrome = !viewer.chrome
            if (viewer.chrome)
                hide.restart()
        }
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

    // the video's controls: play or pause in the middle, where it is and a bar to move it at the foot
    Item {
        anchors.fill: parent
        visible: viewer.open && viewer.video !== ""
        opacity: viewer.chrome ? 1 : 0
        Behavior on opacity { OpacityAnimator { duration: 200 } }
        Rectangle {
            anchors.centerIn: parent
            width: 64; height: 64; radius: 32
            color: Qt.rgba(0, 0, 0, 0.5)
            Icon {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: name === "play" ? 2 : 0
                width: 30; height: 30
                name: player.playbackState === MediaPlayer.PlayingState ? "pause" : "play"
                color: "white"
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (player.playbackState === MediaPlayer.PlayingState)
                        player.pause()
                    else
                        player.play()
                    hide.restart()
                }
            }
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width; height: 70
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.6) }
            }
            Text {
                id: now
                x: 14; y: 30
                text: viewer.clock(player.position)
                color: "white"
                font.family: Theme.font; font.pixelSize: 13
            }
            Text {
                id: total
                anchors.right: parent.right; anchors.rightMargin: 14; y: 30
                text: viewer.clock(player.duration)
                color: "white"
                font.family: Theme.font; font.pixelSize: 13
            }
            Item {
                id: track
                anchors.left: now.right; anchors.leftMargin: 12
                anchors.right: total.left; anchors.rightMargin: 12
                y: 26; height: 24
                Rectangle { y: 10; width: parent.width; height: 3; radius: 1.5; color: Qt.rgba(1, 1, 1, 0.35) }
                Rectangle { y: 10; width: parent.width * (player.duration ? player.position / player.duration : 0); height: 3; radius: 1.5; color: "white" }
                Rectangle {
                    x: parent.width * (player.duration ? player.position / player.duration : 0) - 7; y: 4.5
                    width: 14; height: 14; radius: 7; color: "white"
                }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -10
                    function seek(m) {
                        player.position = Math.max(0, Math.min(1, (m.x - 10) / track.width)) * player.duration
                        hide.restart()
                    }
                    onPressed: (m) => seek(m)
                    onPositionChanged: (m) => seek(m)
                }
            }
        }
    }
    Rectangle {          // ↓: into ~/Downloads
        visible: viewer.open
        opacity: viewer.chrome ? 1 : 0
        anchors.right: parent.right; anchors.rightMargin: 14
        y: 14
        width: 40; height: 40; radius: 20
        color: Qt.rgba(0, 0, 0, 0.45)
        Icon { anchors.centerIn: parent; width: 22; height: 22; name: "down"; color: "white" }
        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: viewer.save() }
    }

    function clock(ms) {
        const s = Math.floor(ms / 1000)
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
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
            viewer.video = ""
            player.source = ""
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
