// How it looks: the night theme (Telegram-iOS's dark one), kept.
import QtQuick

SubPage {
    id: page
    title: "Ko'rinish"

    SettingsGroup {
        title: "Mavzu"
        SettingsRow { icon: "moon"; tint: "#5856d6"; text: "Tungi rejim"; toggle: true; on: Theme.dark; last: true; onClicked: Theme.dark = !Theme.dark }
    }
    Row {           // the two side by side: how a chat looks in each
        x: 16; spacing: 12
        Repeater {
            model: [false, true]
            Rectangle {
                required property bool modelData
                width: (page.width - 44) / 2; height: 150; radius: 12
                color: modelData ? "#0f1712" : "#dbe6c9"
                border.color: Theme.dark === modelData ? Theme.accent : "transparent"; border.width: 2
                Rectangle { x: 12; y: 18; width: 90; height: 26; radius: 13; color: parent.modelData ? "#1d1d1d" : "white" }
                Rectangle { anchors.right: parent.right; anchors.rightMargin: 12; y: 56; width: 80; height: 26; radius: 13
                            color: parent.modelData ? "#3e88f7" : "#e1ffc7" }
                Rectangle { x: 12; y: 94; width: 70; height: 26; radius: 13; color: parent.modelData ? "#1d1d1d" : "white" }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: -24
                    text: parent.modelData ? "Tungi" : "Kunduzgi"
                    color: Theme.dark === parent.modelData ? Theme.accent : Theme.grey
                    font.family: Theme.font; font.pixelSize: 14
                }
                MouseArea { anchors.fill: parent; onClicked: Theme.dark = parent.modelData }
            }
        }
    }
    Item { width: 1; height: 20 }
}
