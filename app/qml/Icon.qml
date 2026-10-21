// Our own line-art icons, drawn as paths on a 24-point grid (no icon font: the
// emoji ones come in colour and in another style): person, chats, settings, search, and the
// media ones (play, pause, down, cross, mic, clip, expand). Those in `lines` are strokes, not fills.
import QtQuick
import QtQuick.Shapes

Item {
    id: icon
    property string name: ""
    property color color: Theme.text
    width: 24; height: 24

    // a cog: `teeth` blocks round a ring, with the hole in the middle drawn by evenodd fill
    function gear() {
        const cx = 12, cy = 12, r1 = 7.2, r2 = 9.6, teeth = 8, hole = 3.2
        let d = ""
        for (let i = 0; i < teeth; i++) {
            const a = i * 2 * Math.PI / teeth, w = Math.PI / teeth * 0.55
            const pts = [[r1, a - w * 1.25], [r2, a - w * 0.8], [r2, a + w * 0.8], [r1, a + w * 1.25]]
            for (let k = 0; k < pts.length; k++) {
                const x = cx + pts[k][0] * Math.cos(pts[k][1]), y = cy + pts[k][0] * Math.sin(pts[k][1])
                d += (i === 0 && k === 0 ? "M" : "L") + x.toFixed(2) + " " + y.toFixed(2) + " "
            }
        }
        d += "Z M" + (cx + hole) + " " + cy + " A" + hole + " " + hole + " 0 1 0 " + (cx - hole) + " " + cy +
             " A" + hole + " " + hole + " 0 1 0 " + (cx + hole) + " " + cy + " Z"
        return d
    }

    readonly property var paths: ({
        person: "M12 3.2a4.3 4.3 0 1 1 0 8.6a4.3 4.3 0 1 1 0-8.6Z M3.6 20.6c0.6-4.2 4.1-6.6 8.4-6.6s7.8 2.4 8.4 6.6Z",
        chats: "M12 3.4c5 0 9 3.3 9 7.6s-4 7.6-9 7.6c-0.9 0-1.8-0.1-2.6-0.3l-4.6 2.5l1.1-4.2C4.1 15.2 3 13.2 3 11c0-4.3 4-7.6 9-7.6Z",
        settings: gear(),
        search: "M10.5 3.5a7 7 0 1 1 0 14a7 7 0 1 1 0-14Z M10.5 5.5a5 5 0 1 0 0 10a5 5 0 1 0 0-10Z M15.4 16.8l1.4-1.4l4.6 4.6l-1.4 1.4Z",
        play: "M8.2 5.2c0-0.8 0.9-1.3 1.6-0.9l9.4 6.8c0.6 0.4 0.6 1.3 0 1.7l-9.4 6.8c-0.7 0.5-1.6 0-1.6-0.9Z",
        pause: "M6.8 5h3.4v14H6.8Z M13.8 5h3.4v14h-3.4Z",
        down: "M10.9 4h2.2v10.6l3.9-3.9l1.6 1.6L12 18.9L5.4 12.3L7 10.7l3.9 3.9Z",
        cross: "M6.3 4.9L12 10.6l5.7-5.7l1.4 1.4L13.4 12l5.7 5.7l-1.4 1.4L12 13.4l-5.7 5.7l-1.4-1.4L10.6 12L4.9 6.3Z",
        bookmark: "M7 3.5h10a1 1 0 0 1 1 1v16l-6-4l-6 4v-16a1 1 0 0 1 1-1Z",
        laptop: "M5 5h14a1 1 0 0 1 1 1v9H4V6a1 1 0 0 1 1-1Z M6.3 7.2v5.6h11.4V7.2Z M2.5 16.3h19v1.2a1.5 1.5 0 0 1-1.5 1.5H4a1.5 1.5 0 0 1-1.5-1.5Z",
        folder: "M3.5 6.5A1.5 1.5 0 0 1 5 5h4.6l2 2.1H19a1.5 1.5 0 0 1 1.5 1.5v8.9A1.5 1.5 0 0 1 19 19H5a1.5 1.5 0 0 1-1.5-1.5Z",
        bell: "M12 3a5.5 5.5 0 0 1 5.5 5.5v4.2l1.8 2.8a0.8 0.8 0 0 1-0.7 1.2H5.4a0.8 0.8 0 0 1-0.7-1.2l1.8-2.8V8.5A5.5 5.5 0 0 1 12 3Z M9.5 18.3h5a2.5 2.5 0 0 1-5 0Z",
        lock: "M7.5 10V8a4.5 4.5 0 0 1 9 0v2h0.5a1.5 1.5 0 0 1 1.5 1.5v7A1.5 1.5 0 0 1 17 20H7a1.5 1.5 0 0 1-1.5-1.5v-7A1.5 1.5 0 0 1 7 10Z M9.5 10h5V8a2.5 2.5 0 0 0-5 0Z",
        data: "M12 3.5c4.1 0 7 1.3 7 3v11c0 1.7-2.9 3-7 3s-7-1.3-7-3v-11c0-1.7 2.9-3 7-3Z",
        halfmoon: "M12 3.5a8.5 8.5 0 1 1 0 17a8.5 8.5 0 1 1 0-17Z M12 5.3v13.4a6.7 6.7 0 0 0 0-13.4Z",
        moon: "M14.5 3.6a8.5 8.5 0 1 0 5.9 11.6A7 7 0 0 1 14.5 3.6Z",
        info: "M12 3.5a8.5 8.5 0 1 1 0 17a8.5 8.5 0 1 1 0-17Z M11 10.5h2v6.5h-2Z M12 6.8a1.2 1.2 0 1 1 0 2.4a1.2 1.2 0 1 1 0-2.4Z",
        globe: "M12 3.5a8.5 8.5 0 1 1 0 17a8.5 8.5 0 1 1 0-17Z M12 5.3c-1.2 1.5-2 3.9-2.1 5.9h4.2c-0.1-2-0.9-4.4-2.1-5.9Z M9.9 12.8c0.1 2 0.9 4.4 2.1 5.9c1.2-1.5 2-3.9 2.1-5.9Z M7.9 11.2c0.1-1.9 0.6-3.8 1.4-5.2a6.7 6.7 0 0 0-4 5.2Z M5.3 12.8a6.7 6.7 0 0 0 4 5.2c-0.8-1.4-1.3-3.3-1.4-5.2Z M16.1 11.2h2.6a6.7 6.7 0 0 0-4-5.2c0.8 1.4 1.3 3.3 1.4 5.2Z M18.7 12.8h-2.6c-0.1 1.9-0.6 3.8-1.4 5.2a6.7 6.7 0 0 0 4-5.2Z",
        forward: "M13.5 5.2l7 6.3a0.7 0.7 0 0 1 0 1L13.5 18.8v-3.9c-4.6 0-7.7 1.3-10 4.6c0.9-4.8 3.6-9.1 10-10V5.2Z",
        eye: "M12 5.5c-4.8 0-8.6 4-9.6 6.5c1 2.5 4.8 6.5 9.6 6.5s8.6-4 9.6-6.5c-1-2.5-4.8-6.5-9.6-6.5Z M12 8a4 4 0 1 1 0 8a4 4 0 1 1 0-8Z M12 9.8a2.2 2.2 0 1 0 0 4.4a2.2 2.2 0 1 0 0-4.4Z",
        reply: "M10.5 5.2l-7 6.3a0.7 0.7 0 0 0 0 1l7 6.3v-3.9c4.6 0 7.7 1.3 10 4.6c-0.9-4.8-3.6-9.1-10-10V5.2Z",
        pin: "M14.6 3.4l6 6l-1.4 1.4l-1.2-0.6l-3.1 3.1l0.4 3.5l-1.4 1.4l-3.2-3.2l-4.5 4.5l-1.4 0l0-1.4l4.5-4.5l-3.2-3.2l1.4-1.4l3.5 0.4l3.1-3.1l-0.6-1.2Z",
        mic: "M12 2.8a3.4 3.4 0 0 1 3.4 3.4v5.6a3.4 3.4 0 0 1-6.8 0V6.2A3.4 3.4 0 0 1 12 2.8Z M5.6 11h1.8a4.6 4.6 0 0 0 9.2 0h1.8a6.4 6.4 0 0 1-5.5 6.3v2.9h-1.8v-2.9A6.4 6.4 0 0 1 5.6 11Z"
    })
    readonly property var lines: ({
        expand: "M4.5 9.5v-5h5 M14.5 4.5h5v5 M19.5 14.5v5h-5 M9.5 19.5h-5v-5",
        clip: "M17.2 8.6l-6.9 6.9a1.9 1.9 0 0 1-2.7-2.7l7.4-7.4a3.4 3.4 0 0 1 4.8 4.8l-7.8 7.8a4.9 4.9 0 0 1-6.9-6.9l7.2-7.2"
    })

    Shape {
        width: 24; height: 24           // the grid, scaled to the icon's size
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { xScale: icon.width / 24; yScale: icon.height / 24 }
        ShapePath {
            fillColor: icon.color
            fillRule: ShapePath.OddEvenFill
            strokeColor: "transparent"
            PathSvg { path: icon.paths[icon.name] || "" }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: icon.lines[icon.name] ? icon.color : "transparent"
            strokeWidth: 1.9
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: icon.lines[icon.name] || "" }
        }
    }
}
