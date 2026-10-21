// Our own line-art icons, drawn as paths on a 24-point grid (no icon font: the
// emoji ones come in colour and in another style): person, chats, settings, search, and the
// media ones (play, pause, down, cross, mic, clip, expand). Those in `lines` are strokes, not fills.
import QtQuick
import QtQuick.Window
import "Icons.js" as Icons

Item {
    id: icon
    property string name: ""
    property color color: Theme.text
    width: 24; height: 24

    // an SVG picture (Icons.uri), made only once it shows: a list's rows have a dozen icons, most of
    // them hidden; drawn as shapes, each was six objects and a draw call of its own
    Image {
        anchors.fill: parent
        source: icon.visible && icon.name !== "" ? Icons.uri(icon.name, icon.color) : ""
        sourceSize: Qt.size(Math.ceil(icon.width * Screen.devicePixelRatio), Math.ceil(icon.height * Screen.devicePixelRatio))
        smooth: true
    }
}
