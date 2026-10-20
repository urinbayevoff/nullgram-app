// A message's menu the way Telegram-iOS opens it (ContextControllerExtractedPresentationNode.swift,
// NOTES.md): the chat behind blurs, the bubble is lifted out of it and springs to where its
// actions fit under it, the actions grow from the bubble with a small overshoot. Everything
// that moves is an Animator (render thread); the blur is one picture taken as it opens.
import QtQuick
import QtQuick.Effects

Item {
    id: menu
    anchors.fill: parent
    visible: false
    z: 10

    property Item behind                // what blurs (the chat without this menu)
    property real ceiling: 0            // the lifted bubble keeps below this (the header)
    property real floor: height         // and the actions above this
    property bool open: false
    property Item bubble: null
    property var actions: []            // [{ text, glyph, danger, run }]

    readonly property real rowHeight: 46
    readonly property real boxWidth: 240
    property real homeX: 0              // where the bubble is in the chat
    property real homeY: 0

    // the bubble and its actions: lift it out of `item`, put the menu up
    function show(item, ours, actions) {
        if (open)
            return
        bubble = item
        menu.actions = actions
        const at = item.mapToItem(menu, 0, 0)
        homeX = at.x; homeY = at.y
        const h = item.height
        const boxH = actions.length * rowHeight
        // as low as it is, but with room for the actions under it and under the header
        const restY = Math.max(ceiling + 8, Math.min(homeY, floor - 16 - boxH - 8 - h))
        lifted.x = homeX - 8
        lifted.y = homeY
        box.y = Math.min(restY + h + 8, floor - 16 - boxH)
        box.x = ours ? Math.min(width - 12, homeX + item.width) - boxWidth : Math.max(12, homeX)
        box.transformOrigin = ours ? Item.TopRight : Item.TopLeft
        shot.scheduleUpdate()
        open = true
        visible = true
        shut.stop()
        liftY.to = restY
        opening.restart()
    }

    function close() {
        if (!open)
            return
        open = false
        opening.stop()
        dropY.to = homeY
        shut.restart()
    }

    function done() {
        visible = false
        bubble = null
        actions = []
    }

    ShaderEffectSource {        // the chat as it was when the menu opened (the bubble left out)
        id: shot
        anchors.fill: parent
        sourceItem: menu.behind
        live: false
        visible: false
    }
    MultiEffect {
        id: blurred
        anchors.fill: parent
        source: shot
        blurEnabled: true
        blurMax: 40
        blur: 1.0
        brightness: Theme.dark ? -0.15 : -0.04
        saturation: 0.15
        opacity: 0
    }
    MouseArea {
        anchors.fill: parent
        onClicked: menu.close()
    }

    ShaderEffectSource {        // the bubble itself, lifted (8 pt either side for the tail)
        id: lifted
        width: (menu.bubble ? menu.bubble.width : 0) + 16
        height: menu.bubble ? menu.bubble.height : 0
        sourceItem: menu.bubble
        sourceRect: Qt.rect(-8, 0, width, height)
        hideSource: menu.visible
        live: true
    }

    Rectangle {
        id: box
        width: menu.boxWidth
        height: menu.actions.length * menu.rowHeight
        radius: 20
        color: Theme.menu
        opacity: 0
        scale: 0.5
        clip: true
        Column {
            anchors.fill: parent
            Repeater {
                model: menu.actions
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: box.width; height: menu.rowHeight
                    color: hit.pressed ? Theme.highlight : "transparent"
                    Text {
                        x: 16; anchors.verticalCenter: parent.verticalCenter
                        text: modelData.text
                        color: modelData.danger ? Theme.danger : Theme.text
                        font.family: Theme.font; font.pixelSize: 16
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.glyph || ""
                        color: modelData.danger ? Theme.danger : Theme.text
                        font.family: Theme.font; font.pixelSize: 17
                    }
                    Rectangle {
                        visible: index > 0
                        width: parent.width; height: 0.5
                        color: Theme.separator
                    }
                    MouseArea {
                        id: hit
                        anchors.fill: parent
                        onClicked: {
                            const run = modelData.run
                            menu.close()
                            run()
                        }
                    }
                }
            }
        }
    }

    // in: the blur fades in, the bubble springs up (duration 0.42, damping ratio ~0.78: an
    // overshoot of a few percent), the actions grow from it and show in 0.15 s
    ParallelAnimation {
        id: opening
        OpacityAnimator { target: blurred; from: 0; to: 1; duration: 200; easing.type: Easing.OutQuad }
        YAnimator { id: liftY; target: lifted; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.6 }
        ScaleAnimator { target: box; from: 0.5; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.6 }
        OpacityAnimator { target: box; from: 0; to: 1; duration: 150 }
    }
    // out: back where it was, quicker
    ParallelAnimation {
        id: shut
        OpacityAnimator { target: blurred; to: 0; duration: 220; easing.type: Easing.OutQuad }
        YAnimator { id: dropY; target: lifted; duration: 260; easing.type: Easing.OutCubic }
        ScaleAnimator { target: box; to: 0.6; duration: 180; easing.type: Easing.InQuad }
        OpacityAnimator { target: box; to: 0; duration: 150 }
        onFinished: menu.done()
    }
}
