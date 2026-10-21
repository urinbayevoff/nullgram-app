// Telegram's spoiler: the hidden words' places full of dust that drifts and twinkles, two layers
// of dots (image://dust, the words' colour) going different ways on the render thread. `gone`
// blows it off: it swells a little and fades, the words under it already shown.
import QtQuick
import QtQuick.Window

Item {
    id: dust
    property var rects: []          // [{ x, y, w, h }] in this item
    property color ink
    property bool gone: false
    property bool live: true        // on the screen: off it, nothing moves (nor keeps the window drawn)
    readonly property real d: Screen.devicePixelRatio
    readonly property int tile: 64  // points a tile
    readonly property string hex: {
        const s = ink.toString()
        return s.length === 9 ? s.slice(3) : s.slice(1)
    }

    opacity: gone ? 0 : 1
    scale: gone ? 1.12 : 1
    Behavior on opacity { OpacityAnimator { duration: 320; easing.type: Easing.OutCubic } }
    Behavior on scale { ScaleAnimator { duration: 320; easing.type: Easing.OutCubic } }

    Repeater {
        model: dust.rects
        Item {
            required property var modelData
            x: modelData.x; y: modelData.y
            width: modelData.w; height: modelData.h
            clip: true
            Repeater {
                model: 2
                Item {          // drawn in pixels and scaled down (as the bubbles are), so a dot is a pixel's size
                    id: layer
                    required property int index
                    readonly property int span: dust.tile * Math.ceil(Math.max(parent.width, parent.height) / dust.tile + 1)
                    width: span * dust.d; height: span * dust.d
                    scale: 1 / dust.d
                    transformOrigin: Item.TopLeft
                    Image {
                        x: -dust.tile * dust.d; y: -dust.tile * dust.d
                        width: (layer.span + dust.tile) * dust.d; height: (layer.span + dust.tile) * dust.d
                        fillMode: Image.Tile
                        smooth: false
                        source: "image://dust/" + dust.hex + "/" + layer.index + "/" + Math.round(dust.tile * dust.d)
                        // a tile's way and back to the start: seamless, slow (Telegram's drift)
                        XAnimator on x {
                            from: layer.index ? -dust.tile * dust.d : 0; to: layer.index ? 0 : -dust.tile * dust.d
                            duration: layer.index ? 9000 : 7000; loops: Animation.Infinite
                            running: dust.live
                        }
                        YAnimator on y {
                            from: 0; to: -dust.tile * dust.d
                            duration: layer.index ? 11000 : 13000; loops: Animation.Infinite
                            running: dust.live
                        }
                        SequentialAnimation on opacity {      // the twinkle: one layer bright as the other dims
                            loops: Animation.Infinite
                            running: dust.live
                            OpacityAnimator { from: layer.index ? 0.35 : 1; to: layer.index ? 1 : 0.35; duration: 700; easing.type: Easing.InOutSine }
                            OpacityAnimator { from: layer.index ? 1 : 0.35; to: layer.index ? 0.35 : 1; duration: 700; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }
        }
    }
}
