// A piece of Telegram-iOS 26's glass over the chat (the header's capsules, the pinned message's
// panel): light and see-through with a hairline edge and a soft shadow. No blur, as the tab bar:
// the list under it moves every frame and a blurred copy would be drawn again each time.
import QtQuick
import QtQuick.Effects

Rectangle {
    radius: height / 2
    color: Theme.glass
    border.color: Theme.glassEdge; border.width: 0.5
    RectangularShadow {
        z: -1
        anchors.fill: parent
        radius: parent.radius
        blur: 16; offset.y: 2
        color: Qt.rgba(0, 0, 0, Theme.dark ? 0.4 : 0.08)
    }
}
