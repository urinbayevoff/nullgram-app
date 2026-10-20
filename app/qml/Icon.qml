// Our own line-art icons, drawn as paths on a 24-point grid (no icon font: the
// emoji ones come in colour and in another style): person, chats, settings, search.
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
        search: "M10.5 3.5a7 7 0 1 1 0 14a7 7 0 1 1 0-14Z M10.5 5.5a5 5 0 1 0 0 10a5 5 0 1 0 0-10Z M15.4 16.8l1.4-1.4l4.6 4.6l-1.4 1.4Z"
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
    }
}
