// A page opened from the settings: ‹ and its title over a grouped list (iOS's grouped background).
import QtQuick

Page {
    id: sub
    property string title: ""
    default property alias content: column.data
    color: Theme.grouped

    Flickable {
        anchors.fill: parent
        anchors.topMargin: bar.height
        contentHeight: column.height + 40
        Column {
            id: column
            y: 16
            width: parent.width
            spacing: 22
        }
    }
    Rectangle {
        id: bar
        width: parent.width; height: 56
        color: Theme.grouped
        Text {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            text: "‹"
            color: Theme.accent
            opacity: backHit.pressed ? 0.4 : 1
            font.family: Theme.font; font.pixelSize: 34
        }
        MouseArea { id: backHit; width: 72; height: parent.height; onClicked: sub.nav.pop() }
        Text {
            anchors.centerIn: parent
            text: sub.title
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
        }
    }
}
