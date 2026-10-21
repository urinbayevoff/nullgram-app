// Nullgram. Pages go on and off as Telegram-iOS's navigation does
// (Display/NavigationTransitionCoordinator.swift): the new page from the right,
// the one under it 0.3 of the width to the left and dimmed to 0.15, a shadow at
// the new page's edge; 0.5 s on the iOS 26 spring. A page is made, filled and
// laid out before it moves (it says so with `ready`), so the motion has nothing
// to wait for. The motion is Animators: they run on the render thread.
import QtQuick
import QtCore

Rectangle {
    id: root
    width: 360; height: 760
    color: Theme.bg

    Store { id: store }

    // iOS 26's spring (CASpringAnimation mass 1, stiffness 555, damping 47.1: 1 - (1 + wt)e^(-wt),
    // w = 23.56/s) over 0.5 s as two bezier segments, within 0.3 % of it
    readonly property var spring: [0.0744, 0.0298, 0.1307, 0.7931, 0.3680, 0.9301,
                                   0.4409, 0.9722, 0.4273, 0.9999, 1.0, 1.0]
    readonly property var easeInOut: [0.42, 0.0, 0.58, 1.0, 1.0, 1.0]

    property var pages: []              // bottom first
    property Item topPage: pages.length ? pages[pages.length - 1] : null
    property Item underPage: pages.length > 1 ? pages[pages.length - 2] : null
    property bool moving: motion.running

    Component { id: loginPage; LoginPage {} }
    Component { id: chatsPage; HomePage {} }

    // the night theme and the other choices, kept (~/.config/OmonullOS/Nullgram.conf)
    Settings {
        id: prefs
        property bool dark: false
        property bool autoGif: true
        property bool autoVoice: true
    }
    Component.onCompleted: {
        Theme.dark = prefs.dark
        Prefs.autoGif = prefs.autoGif
        Prefs.autoVoice = prefs.autoVoice
    }
    Connections { target: Theme; function onDarkChanged() { prefs.dark = Theme.dark } }
    Connections {
        target: Prefs
        function onAutoGifChanged() { prefs.autoGif = Prefs.autoGif }
        function onAutoVoiceChanged() { prefs.autoVoice = Prefs.autoVoice }
    }

    // the first page: the sign-in until Telegram says we are in, then the chats
    property string base: store.auth === "Ready" ? "chats" : store.auth === "" ? "" : "login"
    onBaseChanged: {
        for (const p of pages)
            p.destroy()
        pages = []
        if (base)
            pages = [(base === "chats" ? chatsPage : loginPage).createObject(stack, { store: store, nav: root })]
    }

    Item { id: stack; anchors.fill: parent }

    Rectangle {          // over the page under, darker as the new one covers it
        id: dim
        parent: stack
        anchors.fill: parent
        color: "black"
        opacity: 0
        visible: opacity > 0
        z: 1.5
    }

    // a new page in from the right, as soon as it has what it shows (or after 0.7 s anyway)
    function push(component, props) {
        if (moving)
            return
        props.store = store
        props.nav = root
        const p = component.createObject(stack, props)
        p.x = root.width
        p.z = 2
        if (underPage)
            underPage.visible = false
        topPage.z = 1
        pages = pages.concat([p])
        const go = () => { if (topPage === p && !p.started) { p.started = true; slide(1, 500, spring) } }
        if (p.ready)
            Qt.callLater(go)
        else {
            p.readyChanged.connect(go)
            wait.callback = go
            wait.restart()
        }
    }

    // the shell's back: a menu or the like on the page closes first
    function back() {
        if (!(topPage && topPage.dismiss && topPage.dismiss()))
            pop()
    }

    function pop() {
        if (pages.length > 1 && !moving) {
            underPage.visible = true
            slide(0, 500, spring)
        }
    }

    Timer {
        id: wait
        interval: 700
        property var callback: null
        onTriggered: if (callback) callback()
    }

    // progress p: 0 the page under alone, 1 the top page over it
    function place(p) {
        topPage.x = root.width * (1 - p)
        underPage.x = -root.width * 0.3 * p
        dim.opacity = 0.15 * p
    }

    property real _target: 1
    function slide(p, ms, curve) {
        motion.stop()
        // the page goes: its keyboard with it, not after it is gone (IMG_0086; Qt's text input
        // tells the shell only when the field is destroyed)
        if (p === 0 && osk.h > 0)
            osk.hide()
        for (const a of [toTop, toUnder, toDim]) {
            a.duration = ms
            a.easing.bezierCurve = curve
        }
        toTop.target = topPage
        toUnder.target = underPage
        toTop.to = root.width * (1 - p)
        toUnder.to = -root.width * 0.3 * p
        toDim.to = 0.15 * p
        _target = p
        motion.start()
    }

    ParallelAnimation {
        id: motion
        XAnimator { id: toTop; easing.type: Easing.BezierSpline }
        XAnimator { id: toUnder; easing.type: Easing.BezierSpline }
        OpacityAnimator { id: toDim; target: dim; easing.type: Easing.BezierSpline }
        onFinished: {
            if (root._target === 0) {         // popped: the top page goes
                const p = root.topPage
                root.pages = root.pages.slice(0, -1)
                p.destroy()
                root.topPage.z = 2
                root.topPage.x = 0
            } else if (root.underPage) {
                root.underPage.visible = false   // covered: nothing to draw under the top page
            }
        }
    }

    // the left edge of a pushed page pulls it back: let go past half (or flung) it goes
    // in distance/velocity clamped to 0.05..0.2 s, else it comes back in 0.1 s
    MouseArea {          // (below the header: its back button is under the left edge too)
        y: 56
        width: 20; height: parent.height - y
        z: 10
        enabled: root.pages.length > 1 && !root.moving
        property real lastX: 0
        property real lastT: 0
        property real velocity: 0
        onPressed: (m) => {
            lastX = m.x; lastT = Date.now(); velocity = 0
            root.underPage.visible = true
        }
        onPositionChanged: (m) => {
            const t = Date.now()
            if (t > lastT)
                velocity = 0.6 * velocity + 0.4 * (m.x - lastX) * 1000 / (t - lastT)
            root.place(1 - Math.max(0, Math.min(root.width, root.topPage.x + m.x - lastX)) / root.width)
            lastX = m.x; lastT = t
        }
        onReleased: {
            if (root.topPage.x > root.width / 2 || velocity > 500)
                root.slide(0, 1000 * Math.max(0.05, Math.min(0.2, (root.width - root.topPage.x) / Math.max(1, Math.abs(velocity)))),
                           root.easeInOut)
            else
                root.slide(1, 100, root.easeInOut)
        }
    }

    // the shell's back button (it sends Escape). A shortcut, not Keys on this item: those only
    // hear it while nothing under them has the focus, and the field or a page soon takes it
    Shortcut {
        sequences: ["Esc", "Back"]
        context: Qt.ApplicationShortcut
        onActivated: root.back()
    }
}
