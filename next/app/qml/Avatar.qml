// A round picture (cut round once, off the UI thread: image://round/ in tepegram.py),
// over the initials on the chat's colour until it comes.
import QtQuick

Item {
    id: av
    property string source: ""          // a local file's path
    property string letters: ""
    property color tint: "#2a9ef1"
    width: 56; height: 56

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: av.tint
        visible: pic.status !== Image.Ready
        Text {
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
        source: av.source ? "image://round/" + av.source : ""
        sourceSize.width: av.width * 4
        sourceSize.height: av.height * 4
        asynchronous: true
        smooth: true
    }
}
