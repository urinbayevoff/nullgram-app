// One picture of an album's mosaic (ChatPage): its message's photo or video in its place, its
// outer corners round as the bubble's, the inner ones nearly square (Telegram-iOS). It answers to
// what ChatPage asks of a message's picture (tapMedia, view, openMedia, the viewer's flight).
import QtQuick

Item {
    id: tile
    property var msgId: 0
    property var cell: null             // ChatPage.cellOf: its row's media, copied
    property string corner: "14"        // Pic's radii: "tl,tr,br,bl"
    property bool live: true            // on the screen (a spoiler's dust moves only then)
    signal unveiled()                   // its spoiler blown off (the page keeps it off)

    readonly property string picKind: cell ? cell.picKind : ""
    readonly property string rowKind: ""
    readonly property bool media: true
    readonly property string pic: cell ? cell.pic : ""
    readonly property string mini: cell ? cell.mini : ""
    readonly property real got: cell ? cell.got : -1
    readonly property string path: cell ? cell.path : ""
    readonly property bool sending: cell ? cell.sending : false
    readonly property int dur: cell ? cell.dur : 0
    readonly property real fileSize: cell ? cell.fileSize : 0
    readonly property bool veiled: cell ? !!cell.veiled : false        // a spoiler, until tapped
    function blow(x, y) {
        if (veil.item)
            veil.item.blow(x === undefined ? width / 2 : x, y === undefined ? height / 2 : y)
    }
    readonly property real aspect: cell ? cell.picH / Math.max(cell.picW, 1) : 1     // its own shape, full screen
    readonly property real pw: width
    readonly property Item picFace: tile
    readonly property Item face: tile

    Image {
        anchors.fill: parent
        visible: tile.mini !== "" && full.status !== Image.Ready
        asynchronous: true
        sourceSize: Qt.size(12, 12 * tile.height / Math.max(tile.width, 1))
        source: tile.mini ? "image://pic/" + tile.corner + "/" + Math.round(tile.width) + "/mini/" + tile.mini : ""
        smooth: true
    }
    Image {
        id: full
        anchors.fill: parent
        asynchronous: true
        sourceSize: Qt.size(Math.round(tile.width), Math.round(tile.height))
        source: tile.pic ? "image://pic/" + tile.corner + "/" + Math.round(tile.width) + "/" + tile.pic : ""
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { OpacityAnimator { duration: 150 } }
    }
    Loader {            // a spoiler: blurred under its dust until tapped, each picture its own
        id: veil
        anchors.fill: parent
        active: tile.veiled
        sourceComponent: Veil {
            corner: tile.corner
            mini: tile.mini
            pic: tile.pic
            live: tile.live
            onGone: tile.unveiled()
        }
    }
    Rectangle {         // a video: play over it, the ring while it comes
        visible: tile.picKind === "video" || tile.got >= 0
        anchors.centerIn: parent
        readonly property real d: Math.min(44, tile.width - 12, tile.height - 12)
        width: d; height: d; radius: d / 2
        color: Qt.rgba(0, 0, 0, 0.45)
        Icon {
            visible: tile.got < 0
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 1.5
            width: parent.d * 0.5; height: width
            name: "play"
            color: "white"
        }
        Ring {
            visible: tile.got >= 0
            anchors.fill: parent
            value: tile.got
        }
    }
    Rectangle {         // a video's length
        visible: tile.picKind === "video" && tile.width > 60
        x: 6; y: 6
        width: len.implicitWidth + 12; height: 20; radius: 10
        color: Qt.rgba(0, 0, 0, 0.45)
        Text {
            id: len
            anchors.centerIn: parent
            text: Math.floor(tile.dur / 60) + ":" + String(tile.dur % 60).padStart(2, "0")
            color: "white"
            font.family: Theme.font; font.pixelSize: 12
        }
    }
}
