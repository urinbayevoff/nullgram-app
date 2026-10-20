// Tepegram "next": does Qt Quick stay smooth on the phone while Python is busy?
// A list of 1000 chats; a tap pushes a chat page as Telegram-iOS does
// (Display/NavigationTransitionCoordinator.swift): the new page from the
// right, the one under it 0.3 of the width to the left, dimmed to 0.15, a
// 16 pt shadow at the new page's edge; 0.5 s on iOS's spring. A drag from the
// left edge pulls it back: let go past half (or flung) it finishes in
// distance/velocity clamped to 0.05..0.2 s ease-in-out, else it returns in 0.1 s.
//
// The motion is Animators (XAnimator, OpacityAnimator): they run on Qt Quick's
// render thread, as Core Animation runs outside the app on iOS -- the UI
// thread's Python may be busy and the frames still come.
import QtQuick

Rectangle {
    id: root
    width: 360; height: 760
    color: "black"

    property int pushed: 0
    // iOS's spring (CASpringAnimation mass 3, stiffness 1000, damping 500) as
    // Telegram-iOS approximates it (Display/ListViewAnimation.swift)
    readonly property var spring: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0]
    readonly property var easeInOut: [0.42, 0.0, 0.58, 1.0, 1.0, 1.0]

    ListView {
        id: chats
        width: root.width; height: root.height
        model: 1000
        cacheBuffer: 400
        delegate: Item {
            width: chats.width; height: 72
            Rectangle {
                x: 12; y: 12; width: 48; height: 48; radius: 24
                color: ["#0050ef", "#00bcd4", "#00aa08", "#f0a30a", "#f472d0", "#aa00ff", "#fa6800", "#fbc02d"][index % 8]
                Text { anchors.centerIn: parent; text: "C" + (index % 10); color: "white"; font.pixelSize: 18; font.bold: true }
            }
            Text { x: 72; y: 12; text: "Chat " + index; color: "white"; font.pixelSize: 21 }
            Text { x: 72; y: 42; width: parent.width - 84; elide: Text.ElideRight; color: "#999999"; font.pixelSize: 15
                   text: "Oxirgi xabar matni, bu yerda biroz uzunroq bo'ladi " + index }
            MouseArea { anchors.fill: parent; onClicked: { root.pushed = index; nav.go(1, 500, root.spring) } }
        }
    }

    Rectangle {      // over the page under: it dims as the new one covers it
        id: dim
        anchors.fill: parent
        color: "black"
        opacity: 0
        visible: opacity > 0
    }

    Item {
        id: chat
        width: root.width; height: root.height
        x: root.width
        visible: x < root.width

        Image {      // the shadow left of its edge
            x: -16; width: 16; height: parent.height
            source: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='16' height='1'><defs><linearGradient id='g'><stop offset='0' stop-opacity='0'/><stop offset='1' stop-opacity='0.45'/></linearGradient></defs><rect width='16' height='1' fill='url(%23g)'/></svg>"
            fillMode: Image.Stretch
        }
        Rectangle { anchors.fill: parent; color: "#0e1621" }
        ListView {
            anchors.fill: parent
            model: 200
            verticalLayoutDirection: ListView.BottomToTop
            delegate: Item {
                width: ListView.view.width; height: bubble.height + 8
                Rectangle {
                    id: bubble
                    x: index % 3 ? 12 : parent.width - width - 12
                    width: Math.min(250, msg.implicitWidth + 20); height: msg.height + 18; radius: 12
                    color: index % 3 ? "#182533" : "#2b5278"
                    Text { id: msg; x: 10; y: 9; width: 230; wrapMode: Text.Wrap; color: "white"; font.pixelSize: 16
                           text: "Xabar " + index + (index % 4 ? " — salom, qalaysiz?" : " — bu uzunroq xabar, bir necha qatorga o'tadi va pufakcha kattalashadi") }
                }
            }
        }
        Text { x: 16; y: 16; text: "‹ Chat " + root.pushed; color: "white"; font.pixelSize: 20
               MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: nav.go(0, 500, root.spring) } }

        MouseArea {      // the left edge pulls the page back
            width: 24; height: parent.height
            property real lastX: 0
            property real lastT: 0
            property real velocity: 0       // points per second, + to the right
            onPressed: (m) => { nav.stop(); lastX = mapToItem(root, m.x, 0).x; lastT = Date.now(); velocity = 0 }
            onPositionChanged: (m) => {
                const x = mapToItem(root, m.x, 0).x, t = Date.now()
                if (t > lastT)
                    velocity = 0.6 * velocity + 0.4 * (x - lastX) * 1000 / (t - lastT)
                nav.place(1 - Math.max(0, Math.min(root.width, chat.x + x - lastX)) / root.width)
                lastX = x; lastT = t
            }
            onReleased: {
                if (chat.x > root.width / 2 || velocity > 500) {
                    const ms = 1000 * Math.max(0.05, Math.min(0.2, (root.width - chat.x) / Math.max(1, Math.abs(velocity))))
                    nav.go(0, ms, root.easeInOut)
                } else {
                    nav.go(1, 100, root.easeInOut)
                }
            }
        }
    }

    function toggle() { nav.go(chat.x < root.width / 2 ? 0 : 1, 500, root.spring) }   // proto.py --auto

    QtObject {
        id: nav
        // progress p: 0 the list alone, 1 the chat over it
        function place(p) {
            chat.x = root.width * (1 - p)
            chats.x = -root.width * 0.3 * p
            dim.opacity = 0.15 * p
        }
        function stop() { motion.stop() }
        function go(p, ms, curve) {
            motion.stop()
            for (const a of [toChat, toList, toDim]) {
                a.duration = ms
                a.easing.bezierCurve = curve
            }
            toChat.to = root.width * (1 - p)
            toList.to = -root.width * 0.3 * p
            toDim.to = 0.15 * p
            motion.start()
        }
    }

    ParallelAnimation {
        id: motion
        XAnimator { id: toChat; target: chat; easing.type: Easing.BezierSpline }
        XAnimator { id: toList; target: chats; easing.type: Easing.BezierSpline }
        OpacityAnimator { id: toDim; target: dim; easing.type: Easing.BezierSpline }
    }
}
