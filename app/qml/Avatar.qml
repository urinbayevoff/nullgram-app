// A round picture (cut round once, off the UI thread: image://round/ in nullgram.py),
// over the initials on the chat's colour until it comes.
import QtQuick

Item {
    id: av
    property string source: ""          // a local file's path
    property string letters: ""
    property color tint: "#2a9ef1"
    property bool saved: false          // Saved Messages: the bookmark on blue, no picture
    width: 56; height: 56

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: av.saved ? "#2a9ef1" : av.tint
        visible: av.saved || pic.status !== Image.Ready
        Icon {
            visible: av.saved
            anchors.centerIn: parent
            width: av.width * 0.5; height: width
            name: "bookmark"
            color: "white"
        }
        Text {
            visible: !av.saved
            anchors.centerIn: parent
            text: av.letters
            color: "white"
            font.family: Theme.font
            font.pixelSize: Math.round(av.width * 0.38)
            font.weight: Font.DemiBold
        }
    }
    Image {
        id: pic
        anchors.fill: parent
        visible: !av.saved
        source: av.source && !av.saved ? "image://round/" + av.source : ""
        sourceSize.width: av.width * 4
        sourceSize.height: av.height * 4
        asynchronous: true
        smooth: true
    }
}
