// Where to forward a message: Saved Messages first (as Telegram-iOS has it), then the chats in
// their order, from the foot (as AttachSheet comes); a tap sends it there at once and says so.
import QtQuick

Item {
    id: sheet
    anchors.fill: parent
    visible: false
    z: 15

    property var store
    property bool open: false
    signal picked(var chatId, string title)

    function show() {
        if (open)
            return
        open = true
        visible = true
        rows.positionViewAtBeginning()
        panel.y = height
        rise.to = height - panel.height
        rise.restart()
        shade.restart()
    }
    function close() {
        if (!open)
            return
        open = false
        rise.stop()
        down.to = height
        fall.restart()
    }

    Rectangle {
        id: dim
        anchors.fill: parent
        color: "black"
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: sheet.close() }
    }
    OpacityAnimator { id: shade; target: dim; from: 0; to: 0.4; duration: 300 }

    Rectangle {
        id: panel
        width: parent.width
        height: Math.round(parent.height * 0.7)
        radius: 14
        color: Theme.bg
        MouseArea { anchors.fill: parent }
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 6; width: 36; height: 5; radius: 2.5; color: Theme.separator }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 20
            text: "Kimga uzatish"
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
        }
        Icon {
            anchors.right: parent.right; anchors.rightMargin: 16
            y: 20
            width: 22; height: 22
            name: "cross"
            color: Theme.grey
            MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: sheet.close() }
        }
        ListView {
            id: rows
            y: 56
            width: parent.width; height: parent.height - y
            clip: true
            model: sheet.store ? sheet.store.chatList : null
            header: Rectangle {
                width: rows.width; height: sheet.store && sheet.store.me ? 56 : 0
                visible: height > 0
                color: savedHit.pressed ? Theme.highlight : "transparent"
                Avatar { x: 14; anchors.verticalCenter: parent.verticalCenter; width: 42; height: 42; saved: true }
                Text {
                    x: 68; anchors.verticalCenter: parent.verticalCenter
                    text: "Saqlangan xabarlar"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16
                }
                Rectangle { x: 68; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
                MouseArea {
                    id: savedHit
                    anchors.fill: parent
                    onClicked: sheet.store.chatWith(sheet.store.me.id, (id) => {
                        sheet.close()
                        sheet.picked(id, "Saqlangan xabarlar")
                    })
                }
            }
            delegate: Rectangle {
                required property var chatId
                required property string title
                required property bool saved
                required property string photo
                required property string letters
                required property string tint
                width: rows.width; height: saved ? 0 : 56      // (Saved Messages is the header)
                visible: !saved
                color: hit.pressed ? Theme.highlight : "transparent"
                Avatar {
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    width: 42; height: 42
                    source: parent.photo; letters: parent.letters; tint: parent.tint; saved: parent.saved
                }
                Text {
                    x: 68; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - 16
                    elide: Text.ElideRight
                    text: parent.title
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16
                }
                Rectangle { x: 68; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
                MouseArea {
                    id: hit
                    anchors.fill: parent
                    onClicked: {
                        const id = parent.chatId, t = parent.title
                        sheet.close()
                        sheet.picked(id, t)
                    }
                }
            }
        }
    }

    YAnimator {
        id: rise
        target: panel
        duration: 450
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.0744, 0.0298, 0.1307, 0.7931, 0.3680, 0.9301, 0.4409, 0.9722, 0.4273, 0.9999, 1.0, 1.0]
    }
    ParallelAnimation {
        id: fall
        YAnimator { id: down; target: panel; duration: 250; easing.type: Easing.InCubic }
        OpacityAnimator { target: dim; to: 0; duration: 250 }
        onFinished: sheet.visible = false
    }
}
