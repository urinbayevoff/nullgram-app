// A file in its bubble (Telegram-iOS's ChatMessageInteractiveFileNode): a coloured square with
// its kind, or its picture when it has one, the name, the size (how far, while it comes).
import QtQuick

Item {
    id: row
    property bool out: false
    property string name: ""
    property real size: 0
    property real got: -1
    property bool here: false
    property string thumb: ""           // a local picture of it, if any
    width: Math.min(260, Math.max(200, nameText.implicitWidth + 64)); height: 50

    readonly property string ext: {
        const dot = name.lastIndexOf(".")
        return dot > 0 && name.length - dot <= 5 ? name.slice(dot + 1).toUpperCase() : ""
    }
    readonly property color ink: out ? Theme.voiceOut : Theme.accent

    Rectangle {
        id: square
        y: 3
        width: 44; height: 44; radius: 10
        color: row.ink
        clip: true
        Image {
            anchors.fill: parent
            visible: row.thumb !== ""
            asynchronous: true
            sourceSize: Qt.size(44, 44)
            source: row.thumb ? "image://pic/10/44/" + row.thumb : ""
        }
        Text {
            visible: row.got < 0 && row.here && !row.thumb
            anchors.centerIn: parent
            text: row.ext || "FAYL"
            color: row.out ? Theme.bubbleOut : "white"
            font.family: Theme.font; font.pixelSize: row.ext.length > 3 ? 11 : 13; font.weight: Font.Bold
        }
        Icon {
            visible: row.got < 0 && !row.here
            anchors.centerIn: parent
            width: 22; height: 22
            name: "down"
            color: row.out ? Theme.bubbleOut : "white"
        }
        Ring {
            visible: row.got >= 0
            anchors.centerIn: parent
            width: 38; height: 38
            value: row.got
            color: row.out ? Theme.bubbleOut : "white"
        }
    }
    Text {
        id: nameText
        x: 56; y: 5
        width: row.width - 56
        elide: Text.ElideMiddle
        text: row.name || "Fayl"
        color: row.out ? Theme.outText : Theme.inText
        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
    }
    Text {
        x: 56; y: 26
        text: row.got >= 0 ? bytes(row.got * row.size) + " / " + bytes(row.size) : bytes(row.size)
        function bytes(n) {       // (as Store.size)
            return n < 1024 ? Math.round(n) + " B" : n < 1048576 ? Math.round(n / 1024) + " KB"
                 : n < 1073741824 ? (n / 1048576).toFixed(1) + " MB" : (n / 1073741824).toFixed(2) + " GB"
        }
        color: row.out ? Theme.outMeta : Theme.inMeta
        font.family: Theme.font; font.pixelSize: 13
    }
}
