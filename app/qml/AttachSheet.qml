// What to send from the phone, the way Telegram-iOS's attach sheet comes up from the foot:
// the pictures and videos (newest first, three a row), or every file; a tap picks one (its
// number in the corner), "Yuborish" sends them. The files are td.recent's (nullgram.py).
import QtQuick

Item {
    id: sheet
    anchors.fill: parent
    visible: false
    z: 15

    property bool open: false
    property var files: []
    property var chosen: []             // paths, in the order picked
    property string tab: "media"
    signal send(var picked)

    readonly property var media: files.filter((f) => f.kind === "photo" || f.kind === "video")
    readonly property var others: files.filter((f) => f.kind !== "photo" && f.kind !== "video")

    function show() {
        if (open)
            return
        files = td.recent()
        chosen = []
        tab = media.length || !others.length ? "media" : "files"
        open = true
        visible = true
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
        fall.to = height
        fall.restart()
    }

    function toggle(path) {
        const k = chosen.indexOf(path)
        chosen = k >= 0 ? chosen.filter((p) => p !== path) : chosen.concat([path])
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
        height: Math.round(parent.height * 0.64)
        radius: 14
        color: Theme.bg
        MouseArea { anchors.fill: parent }         // (taps here stay here)

        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 6; width: 36; height: 5; radius: 2.5; color: Theme.separator }
        Row {               // the two kinds
            anchors.horizontalCenter: parent.horizontalCenter
            y: 18
            spacing: 6
            Repeater {
                model: [{ key: "media", text: "Galereya" }, { key: "files", text: "Fayllar" }]
                Rectangle {
                    required property var modelData
                    width: label.implicitWidth + 28; height: 32; radius: 16
                    color: sheet.tab === modelData.key ? Theme.accent : Theme.highlight
                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: parent.modelData.text
                        color: sheet.tab === parent.modelData.key ? "white" : Theme.text
                        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                    MouseArea { anchors.fill: parent; onClicked: sheet.tab = parent.modelData.key }
                }
            }
        }
        Icon {
            anchors.right: parent.right; anchors.rightMargin: 16
            y: 22
            width: 22; height: 22
            name: "cross"
            color: Theme.grey
            MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: sheet.close() }
        }

        GridView {
            id: grid
            visible: sheet.tab === "media"
            y: 60
            width: parent.width; height: parent.height - y
            clip: true
            cellWidth: width / 3; cellHeight: cellWidth
            model: sheet.media
            footer: Item { width: 1; height: 80 }
            delegate: Item {
                required property var modelData
                width: grid.cellWidth; height: grid.cellHeight
                readonly property int picked: sheet.chosen.indexOf(modelData.path)
                Rectangle { anchors.fill: parent; anchors.margins: 1; color: Theme.highlight }
                Image {
                    anchors.fill: parent; anchors.margins: 1
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(width, height)
                    source: "image://thumb/" + parent.modelData.path
                    scale: parent.picked >= 0 ? 0.9 : 1
                    Behavior on scale { ScaleAnimator { duration: 150 } }
                }
                Rectangle {
                    visible: parent.modelData.kind === "video"
                    x: 6; anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                    width: 26; height: 18; radius: 9
                    color: Qt.rgba(0, 0, 0, 0.5)
                    Icon { anchors.centerIn: parent; width: 12; height: 12; name: "play"; color: "white" }
                }
                Rectangle {     // picked: its number; else an empty circle
                    anchors.right: parent.right; anchors.rightMargin: 6
                    y: 6
                    width: 24; height: 24; radius: 12
                    color: parent.picked >= 0 ? Theme.accent : Qt.rgba(0, 0, 0, 0.2)
                    border.color: "white"; border.width: 1.5
                    Text {
                        anchors.centerIn: parent
                        visible: parent.parent.picked >= 0
                        text: parent.parent.picked + 1
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: sheet.toggle(parent.modelData.path) }
            }
        }

        ListView {
            id: rows
            visible: sheet.tab === "files"
            y: 60
            width: parent.width; height: parent.height - y
            clip: true
            model: sheet.tab === "files" ? sheet.files : []
            footer: Item { width: 1; height: 80 }
            delegate: Item {
                required property var modelData
                width: rows.width; height: 60
                readonly property bool picked: sheet.chosen.indexOf(modelData.path) >= 0
                FileRow {
                    x: 16; y: 5
                    width: parent.width - 70
                    name: parent.modelData.name
                    size: parent.modelData.size
                    here: true
                    thumb: parent.modelData.kind === "photo" ? parent.modelData.path : ""
                }
                MouseArea { anchors.fill: parent; onClicked: sheet.toggle(parent.modelData.path) }
                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24; radius: 12
                    color: parent.picked ? Theme.accent : "transparent"
                    border.color: parent.picked ? Theme.accent : Theme.separator; border.width: 1.5
                    Text { anchors.centerIn: parent; visible: parent.parent.picked; text: "✓"; color: "white"; font.pixelSize: 14 }
                }
                Rectangle { x: 72; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: (sheet.tab === "media" ? sheet.media : sheet.files).length === 0
            width: parent.width - 60
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: "Hech narsa topilmadi.\nRasm va fayllar ~/Pictures, ~/Downloads, ~/Videos, ~/Music papkalaridan olinadi."
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 15
        }

        Rectangle {          // send what is picked
            visible: sheet.chosen.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 16
            width: parent.width - 32; height: 50; radius: 25
            color: Theme.accent
            Text {
                anchors.centerIn: parent
                text: "Yuborish (" + sheet.chosen.length + ")"
                color: "white"
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    const picked = sheet.chosen.map((p) => sheet.files.find((f) => f.path === p)).filter((f) => f)
                    sheet.close()
                    sheet.send(picked)
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
        property alias to: down.to
        YAnimator { id: down; target: panel; duration: 250; easing.type: Easing.InCubic }
        OpacityAnimator { target: dim; to: 0; duration: 250 }
        onFinished: sheet.visible = false
    }
}
