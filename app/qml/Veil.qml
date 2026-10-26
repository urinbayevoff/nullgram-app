// A picture's spoiler (a photo, video or GIF sent with has_spoiler), as Telegram-iOS draws one
// (ChatMessageInteractiveMediaNode's ExtendedMediaOverlayNode): the picture blurred past telling what it
// is (image://pic/.../blur/...), white dust drifting and twinkling over it (Dust, its media density).
// blow(x, y) takes it off from under the finger: the dust swells away from there and fades as the blur
// goes, the picture under it already there; then `gone` (the page keeps it off).
import QtQuick

Item {
    id: veil
    property string corner: "14"        // the picture's corners (Pic's radii)
    property string mini: ""            // Telegram's tiny preview: blurred, it is all a veil needs
    property string pic: ""             // else the picture itself
    property bool live: true            // on the screen: the dust moves only then
    readonly property bool blowing: off.running
    signal gone()
    clip: true                          // (the dust swelling off stays over the picture)

    function blow(x, y) {
        if (off.running)
            return
        swell.x = Math.max(0, Math.min(width, x)) - width       // its middle under the finger
        swell.y = Math.max(0, Math.min(height, y)) - height
        off.start()
    }

    Image {
        id: blur
        anchors.fill: parent
        asynchronous: true
        sourceSize: Qt.size(Math.round(veil.width), Math.round(veil.height))
        source: veil.width > 0 && (veil.mini || veil.pic)
                ? "image://pic/" + veil.corner + "/" + Math.round(veil.width) + "/blur/" + (veil.mini ? "mini/" + veil.mini : veil.pic) : ""
        smooth: true
    }
    Item {              // twice the veil, its middle where it swells from (the veil's own until a tap)
        id: swell
        x: -veil.width / 2; y: -veil.height / 2
        width: veil.width * 2; height: veil.height * 2
        Dust {
            x: -swell.x; y: -swell.y        // over the picture wherever swell stands
            width: veil.width; height: veil.height
            // a little in from the edges: none in the round corners over the bubble
            rects: [{ x: 4, y: 4, w: Math.max(0, veil.width - 8), h: Math.max(0, veil.height - 8) }]
            ink: "white"
            live: veil.live
        }
    }
    ParallelAnimation {
        id: off
        ScaleAnimator { target: swell; to: 1.3; duration: 400; easing.type: Easing.OutCubic }
        OpacityAnimator { target: swell; to: 0; duration: 400; easing.type: Easing.OutCubic }
        OpacityAnimator { target: blur; to: 0; duration: 320; easing.type: Easing.OutCubic }
        onFinished: veil.gone()
    }
}
