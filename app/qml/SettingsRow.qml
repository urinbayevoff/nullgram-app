// A row of a settings group, as Telegram-iOS lists them: an icon on a coloured square, the
// name, a value in grey, the chevron (when it opens something) or a switch.
import QtQuick

Item {
    id: row
    property string icon: ""
    property color tint: Theme.accent
    property string text: ""
    property string value: ""
    property bool chevron: true
    property bool toggle: false         // a switch instead of the chevron
    property bool on: false
    property bool danger: false
    property bool last: false           // no line under it
    signal clicked()
    width: parent ? parent.width : 300
    height: 46

    Rectangle {
        anchors.fill: parent
        color: Theme.highlight
        visible: hit.pressed && !row.toggle
    }
    Rectangle {
        id: square
        visible: row.icon !== ""
        x: 14; anchors.verticalCenter: parent.verticalCenter
        width: 29; height: 29; radius: 7
        color: row.tint
        Icon { anchors.centerIn: parent; width: 19; height: 19; name: row.icon; color: "white" }
    }
    Text {
        id: label
        x: row.icon ? 56 : 16
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - (valueText.visible ? valueText.implicitWidth + 12 : 0) - (row.toggle ? 76 : 40)
        elide: Text.ElideRight
        text: row.text
        color: row.danger ? Theme.danger : Theme.text
        font.family: Theme.font; font.pixelSize: 16
    }
    Text {
        id: valueText
        visible: row.value !== ""
        anchors.right: parent.right; anchors.rightMargin: row.chevron ? 32 : row.toggle ? 76 : 16
        anchors.verticalCenter: parent.verticalCenter
        text: row.value
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 16
    }
    Text {
        visible: row.chevron && !row.toggle
        anchors.right: parent.right; anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: "›"
        color: Theme.dark ? "#5a5a5e" : "#c4c4c7"
        font.family: Theme.font; font.pixelSize: 24
    }
    Switch {
        visible: row.toggle
        anchors.right: parent.right; anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        on: row.on
    }
    Rectangle {
        visible: !row.last
        x: label.x; anchors.bottom: parent.bottom
        width: parent.width - x; height: 0.5
        color: Theme.separator
    }
    MouseArea { id: hit; anchors.fill: parent; onClicked: row.clicked() }
}
