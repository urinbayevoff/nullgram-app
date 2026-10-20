// The tabs at the foot, floating over the list, as Telegram-iOS 26 draws them (IMG_0296,
// TabBarComponent / GlassBackgroundComponent): a capsule of tabs, the selected one under a
// light lens. A tap swaps the page at once and only the lens moves (an Animator: the render
// thread). Glass without the blur: a blurred copy of the moving list behind it would be drawn
// again every frame, and smoothness comes first here.
import QtQuick
import QtQuick.Effects

Item {
    id: bar
    property int current: 1
    property var tabs: [{ icon: "person", text: "Kontaktlar" }, { icon: "chats", text: "Chatlar" },
                        { icon: "settings", text: "Sozlamalar" }]
    property var badges: [0, 0, 0]
    signal picked(int index)

    height: 64
    readonly property real tabWidth: (capsule.width - 8) / tabs.length

    RectangularShadow {
        anchors.fill: capsule
        radius: capsule.radius
        blur: 24
        offset.y: 4
        color: Qt.rgba(0, 0, 0, Theme.dark ? 0.5 : 0.12)
    }
    Rectangle {
        id: capsule
        anchors.fill: parent
        radius: height / 2
        color: Theme.dark ? Qt.rgba(0.12, 0.12, 0.13, 0.94) : Qt.rgba(0.98, 0.98, 0.98, 0.94)
        border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)
        border.width: 0.5

        Rectangle {          // the lens under the selected tab
            id: lens
            y: 4; height: parent.height - 8
            width: bar.tabWidth; radius: height / 2
            x: 4 + bar.current * bar.tabWidth
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.07)
            Behavior on x {
                XAnimator { duration: 300; easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.0744, 0.0298, 0.1307, 0.7931, 0.3680, 0.9301,
                                                 0.4409, 0.9722, 0.4273, 0.9999, 1.0, 1.0] }
            }
        }

        Repeater {
            model: bar.tabs
            delegate: Item {
                required property var modelData
                required property int index
                x: 4 + index * bar.tabWidth; y: 4
                width: bar.tabWidth; height: capsule.height - 8
                readonly property bool on: index === bar.current
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 6
                    width: 26; height: 26
                    name: modelData.icon
                    color: parent.on ? Theme.accent : Theme.text
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 34
                    text: modelData.text
                    color: parent.on ? Theme.accent : Theme.text
                    font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                }
                Rectangle {          // what is new on that tab
                    visible: bar.badges[index] > 0
                    x: parent.width / 2 + 6; y: 2
                    width: Math.max(18, n.implicitWidth + 8); height: 18; radius: 9
                    color: Theme.danger
                    Text {
                        id: n
                        anchors.centerIn: parent
                        text: bar.badges[index] > 999 ? Math.floor(bar.badges[index] / 1000) + "K" : bar.badges[index]
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: bar.picked(index)
                }
            }
        }
    }
}
