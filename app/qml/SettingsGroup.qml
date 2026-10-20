// A group of settings rows on a rounded card, with a note under it if there is one.
import QtQuick

Column {
    id: group
    default property alias rows: card.data
    property string note: ""
    property string title: ""
    x: 16; width: parent ? parent.width - 32 : 300
    spacing: 6
    Text {
        visible: group.title !== ""
        x: 16
        text: group.title.toUpperCase()
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 13
    }
    Rectangle {
        width: parent.width
        height: card.height
        radius: 12
        color: Theme.card
        clip: true
        Column { id: card; width: parent.width }
    }
    Text {
        visible: group.note !== ""
        x: 16; width: parent.width - 32
        wrapMode: Text.Wrap
        text: group.note
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 13
    }
}
