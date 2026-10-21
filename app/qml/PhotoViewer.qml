// A picture full screen, the way Telegram-iOS's gallery opens one: it grows out of its
// bubble while the black comes up behind it, a drag up or down sends it back there, two
// fingers zoom it (and one then moves it). Motion is Animators (render thread): the picture
// keeps its full-screen size and moves by x, y and scale. A video plays in the same frame
// (with its sound), a tap shows or hides its controls; ↓ saves either to ~/Downloads. A wide
// video turns a quarter round to fill the screen (the phone held sideways), its controls with it.
// Given the chat (store, chatId) and the message, a sideways drag pages to the chat's next or
// earlier picture or video, as Telegram's gallery does: the newer ones to the right, 20 pt apart.
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
    property bool turned: false         // the wide video across the screen
    property bool sideways: false       // the controls laid out for it (once the turn is over)
    readonly property bool wide: video !== "" && aspect < 0.9
    signal save()
    signal paged(var id)                // another message's picture shows now

    // paging: the chat, the slide shown (Store.slide; only its id for the first one) and its neighbours
    property var store: null
    property var chatId: 0
    property var thread: 0
    property var locate: null           // id -> the Item showing that message's picture now, or null
    property var current: null
    property var older: null
    property var newer: null
    property bool waiting: false        // a paged-to video coming down
    readonly property real gap: 20
    property var curve: [0.0744, 0.0298, 0.1307, 0.7931, 0.3680, 0.9301, 0.4409, 0.9722, 0.4273, 0.9999, 1.0, 1.0]

    // the picture fitted to the screen
    readonly property real fitW: Math.min(width, height / aspect)
    readonly property real fitH: fitW * aspect
    readonly property real fitX: (width - fitW) / 2
    readonly property real fitY: (height - fitH) / 2
    // turned: how much bigger it then is (its height across the screen's width)
    readonly property real turnScale: Math.min(width / fitH, height / fitW)

    function show(item, aspect, source, video, id) {
        if (open)
            return
        from = item
        current = id && store && chatId ? { id: id } : null
        older = newer = null
        neighbours()
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
        frame.opacity = 1
        back.opacity = 0
        turned = sideways = false
        turn.rotation = 0
        turn.scale = 1
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
        turning.stop()
        paging.stop()
        side.visible = false
        turned = sideways = false
        const r = start()
        backX.to = r.x; backY.to = r.y; backScale.to = r.s; backBack.to = 0
        fade.to = from ? 1 : 0
        going.restart()
    }

    // where the bubble's picture is: the fitted picture scaled to cover it, centred on it
    // (a paged-to one not on the page: it shrinks a little where it is and fades)
    function start() {
        if (!from)
            return { s: 0.8, x: frame.x + fitW * 0.1, y: frame.y + fitH * 0.1 }
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

    function turnOver() {
        turned = !turned
        if (frame.scale > 1.02)
            recentre()
        turnTo.to = turned ? 90 : 0
        turnBy.to = turned ? turnScale : 1
        turning.restart()
    }

    Item {                  // turns (about the screen's middle) and grows the picture for a wide video
        id: turn
        anchors.fill: parent
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
        Item {              // the neighbour coming in while paging
            id: side
            visible: false
            property var slide: null
            property string src: ""
            readonly property real w: slide ? Math.min(viewer.width, viewer.height / slide.aspect) : 1
            width: w; height: slide ? w * slide.aspect : 1
            y: (viewer.height - height) / 2
            Image {
                anchors.fill: parent
                source: side.src
                asynchronous: true
                sourceSize: Qt.size(side.width, side.height)
            }
        }
    }
    Ring {                  // a paged-to video coming down
        anchors.centerIn: parent
        visible: viewer.waiting && viewer.open
        value: 0.3
        cross: false
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
            if (paging.running)
                return
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
        enabled: !viewer.turned
        minimumScale: 1
        maximumScale: 5
        onActiveChanged: if (!active && frame.scale < 1.02) viewer.recentre()
    }
    DragHandler {           // zoomed: one finger moves the picture
        target: frame
        enabled: frame.scale > 1.02 && !viewer.turned
    }
    DragHandler {           // not zoomed: up or down drags it away to close, sideways pages
        id: away
        target: null
        enabled: frame.scale <= 1.02 && !viewer.turned && !paging.running
        property int axis: 0            // 1 sideways, 2 up or down: the first clear move decides
        property point moved            // (translation is back at 0 by the time it lets go)
        onTranslationChanged: if (active && viewer.open) {
            const t = translation
            moved = t
            if (!axis) {
                if (Math.abs(t.x) < 10 && Math.abs(t.y) < 10)
                    return
                axis = viewer.current && Math.abs(t.x) > Math.abs(t.y) ? 1 : 2
            }
            if (axis === 1) {
                viewer.slideBy(t.x)
                return
            }
            frame.y = viewer.fitY + t.y
            back.opacity = 1 - Math.min(0.7, Math.abs(t.y) / 400)
        }
        onActiveChanged: if (!active && viewer.open) {
            const was = axis
            axis = 0
            if (was === 1)
                viewer.slideEnd(moved.x, centroid.velocity.x)
            else if (was === 2 && (Math.abs(moved.y) > 90 || Math.abs(centroid.velocity.y) > 900))
                viewer.close()
            else
                viewer.recentre()
        }
    }

    // ---- paging ----
    function neighbours() {
        const s = current
        if (!s)
            return
        store.besides(chatId, thread, s.id, (o, n) => {
            if (current !== s)
                return
            older = o
            newer = n
            for (const x of [o, n])
                if (x)
                    prepare(x)
        })
    }
    // its picture for now: Telegram's tiny one at once, its small size once here
    function prepare(s) {
        const w = Math.round(Math.min(width, height / s.aspect))
        s.src = s.mini ? "image://pic/0/" + w + "/mini/" + s.mini : ""
        if (s.small)
            store.fetch(s.small, 1, (path) => {
                s.src = "image://pic/0/" + w + "/" + path
                if (side.slide === s)
                    side.src = s.src
            })
    }
    function sideAt(dir) {       // where the neighbour stands (dir 1: the newer, on the right)
        return (width - side.w) / 2 + dir * (width + gap)
    }
    function slideBy(dx) {
        const s = dx < 0 ? newer : older
        frame.x = fitX + (s ? dx : dx / 3)          // nothing there: it gives a little
        if (!s) {
            side.visible = false
            return
        }
        if (side.slide !== s) {
            side.slide = s
            side.src = s.src
        }
        side.x = sideAt(dx < 0 ? 1 : -1) + dx
        side.visible = true
    }
    function slideEnd(dx, vx) {
        const dir = dx < 0 ? 1 : -1
        const s = dir > 0 ? newer : older
        const go = s && (Math.abs(dx) > width / 3 || (Math.abs(vx) > 400 && vx * dx > 0))
        pageX.to = go ? fitX - dir * (width + gap) : fitX
        sideX.to = sideAt(go ? 0 : dir)
        paging.landing = go ? s : null
        paging.restart()
    }
    // the neighbour now the one shown: its bigger picture, or its video, comes in
    function land(s) {
        if (from)
            from.opacity = 1
        player.stop()
        player.source = ""
        video = ""
        big.source = ""
        turned = sideways = false
        current = s
        aspect = s.aspect
        source = side.src
        frame.x = fitX
        frame.y = fitY
        side.visible = false
        side.slide = null
        from = locate ? locate(s.id) : null
        if (from)
            from.opacity = 0
        chrome = true
        waiting = !!s.video
        if (s.big)
            store.fetch(s.big, 32, (path) => { if (current === s && open) big.source = "file://" + path })
        if (s.video)
            store.fetch(s.video, 32, (path) => {
                if (current !== s || !open)
                    return
                waiting = false
                video = path
                player.source = "file://" + path
                player.play()
                hide.restart()
            })
        older = newer = null
        neighbours()
        paged(s.id)
    }

    function recentre() {
        settleX.to = fitX; settleY.to = fitY; settleScale.to = 1
        settle.restart()
    }

    // the controls, on the screen as the video is (they go while it turns and come back laid out for it)
    Item {
        anchors.centerIn: parent
        width: viewer.sideways ? parent.height : parent.width
        height: viewer.sideways ? parent.width : parent.height
        rotation: viewer.sideways ? 90 : 0
        visible: viewer.open
        opacity: viewer.chrome && !turning.running ? 1 : 0
        Behavior on opacity { OpacityAnimator { duration: 200 } }
        // the video's: play or pause in the middle, where it is and a bar to move it at the foot
        Item {
            anchors.fill: parent
            visible: viewer.video !== ""
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
                Item {          // ⤢: turn a wide one across the screen, or back
                    id: turnButton
                    anchors.right: parent.right
                    y: 18; height: 40
                    width: viewer.wide ? 44 : 4
                    visible: viewer.wide
                    Icon { anchors.centerIn: parent; width: 22; height: 22; name: "expand"; color: "white" }
                    MouseArea { anchors.fill: parent; onClicked: viewer.turnOver() }
                }
                Text {
                    id: total
                    anchors.right: turnButton.left; anchors.rightMargin: 10; y: 30
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
            anchors.right: parent.right; anchors.rightMargin: 14
            y: 14
            width: 40; height: 40; radius: 20
            color: Qt.rgba(0, 0, 0, 0.45)
            Icon { anchors.centerIn: parent; width: 22; height: 22; name: "down"; color: "white" }
            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: viewer.save() }
        }
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
        OpacityAnimator { id: fade; target: frame; duration: 250 }
        RotationAnimator { target: turn; to: 0; duration: 300; easing.type: Easing.OutCubic }
        ScaleAnimator { target: turn; to: 1; duration: 300; easing.type: Easing.OutCubic }
        onFinished: {
            if (viewer.from)
                viewer.from.opacity = 1
            viewer.from = null
            viewer.visible = false
            big.source = ""
            viewer.video = ""
            player.source = ""
            viewer.current = viewer.older = viewer.newer = null
            viewer.waiting = false
            side.slide = null
            frame.opacity = 1
        }
    }
    ParallelAnimation {     // to the neighbour, or back (a paging scroll view's settle)
        id: paging
        property var landing: null
        XAnimator { id: pageX; target: frame; duration: 300; easing.type: Easing.OutCubic }
        XAnimator { id: sideX; target: side; duration: 300; easing.type: Easing.OutCubic }
        onFinished: {
            if (landing && viewer.open)
                viewer.land(landing)
            else
                side.visible = false
            landing = null
        }
    }
    ParallelAnimation {
        id: settle
        XAnimator { id: settleX; target: frame; duration: 250; easing.type: Easing.OutCubic }
        YAnimator { id: settleY; target: frame; duration: 250; easing.type: Easing.OutCubic }
        ScaleAnimator { id: settleScale; target: frame; duration: 250; easing.type: Easing.OutCubic }
        OpacityAnimator { target: back; to: 1; duration: 200 }
    }
    ParallelAnimation {     // a wide video across the screen, or back
        id: turning
        RotationAnimator { id: turnTo; target: turn; duration: 450; easing.type: Easing.BezierSpline; easing.bezierCurve: viewer.curve }
        ScaleAnimator { id: turnBy; target: turn; duration: 450; easing.type: Easing.BezierSpline; easing.bezierCurve: viewer.curve }
        onFinished: {
            viewer.sideways = viewer.turned
            viewer.chrome = true
            hide.restart()
        }
    }
}
