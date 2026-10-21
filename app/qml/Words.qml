// A message's words as Telegram draws them. Plain words are one Text; formatted ones (Store.rich's
// parts) a column: words as StyledText (bold, italic, links a tap opens), a quote a tinted block with
// a bar down its left and „ in its corner (one that folds shows three lines and ⌄ until tapped),
// code a block of its own in a fixed-width face, a spoiler's letters hidden under Dust until tapped.
import QtQuick

Item {
    id: words
    property string text            // the plain words, when there are no parts
    property string parts           // Store.rich's JSON, "" for none
    property color ink
    property color tint             // the links, a quote's bar and its tint
    property int size: 16
    // the most it may be across: formatted words are laid out at that from the start (laid out at
    // their own width, they were laid out at none first, a word a line, then again: a long post
    // took 0.1 s to make while scrolling). Left-aligned, they look the same either way.
    property real room: width
    property bool open: false       // a folding quote shown whole
    property bool shown: false      // the spoilers tapped: their dust blows off, then link("spoiler")
    onPartsChanged: shown = false
    property bool live: true        // on the screen (a spoiler's dust moves only then)
    signal link(string url)
    signal fold()                   // a folding quote tapped
    // formatted words take the touch themselves (a link would keep a long press from the bubble):
    // a tap on a link or a folding quote is theirs, the rest is the bubble's as if on it
    signal touched(bool down)
    signal held()
    signal tapped()

    readonly property var list: parts ? JSON.parse(parts) : []
    // the last line's width: where the time may go
    readonly property real last: list.length ? (column.item ? column.item.last : 0) : plain.last
    implicitWidth: list.length ? (column.item ? column.item.wants : 0) : plain.implicitWidth
    implicitHeight: list.length ? (column.item ? column.item.height : 0) : plain.implicitHeight

    Text {
        id: plain
        visible: !words.list.length
        width: words.width
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        property real last: 0
        onLineLaidOut: (line) => { if (line.isLast) last = line.implicitWidth }
        text: visible ? words.text : ""
        color: words.ink
        font.family: Theme.font; font.pixelSize: words.size
    }

    MouseArea {
        z: 1
        enabled: words.list.length > 0
        anchors.fill: parent
        pressAndHoldInterval: 350
        onPressed: words.touched(true)
        onReleased: words.touched(false)
        onCanceled: words.touched(false)
        onPressAndHold: words.held()
        onClicked: (mouse) => {
            const what = column.item ? column.item.hit(mouse.x, mouse.y) : ""
            if (what === "fold")
                words.fold()
            else if (what === "spoiler") {
                if (!words.shown) {
                    words.shown = true
                    blown.start()
                }
            }
            else if (what)
                words.link(what)
            else
                words.tapped()
        }
    }

    Timer {
        id: blown
        interval: 340
        onTriggered: words.link("spoiler")
    }

    Loader {
        id: column
        active: words.list.length > 0
        width: words.width
        sourceComponent: Column {
            spacing: 5
            property real wants: 0
            readonly property real last: {
                const it = parts.count ? parts.itemAt(parts.count - 1) : null
                return it ? it.last : 0
            }
            // what is under a tap: a link's address, "fold" for a folding quote, "" for nothing
            function hit(x, y) {
                for (let i = 0; i < parts.count; i++) {
                    const it = parts.itemAt(i)
                    if (it && y >= it.y && y < it.y + it.height)
                        return it.hit(x, y - it.y)
                }
                return ""
            }
            function measure() {
                let w = 0
                for (let i = 0; i < parts.count; i++)
                    if (parts.itemAt(i))
                        w = Math.max(w, parts.itemAt(i).wants)
                wants = w
            }
            Repeater {
                id: parts
                model: words.list
                onItemAdded: parent.measure()
                Item {
                    id: part
                    required property var modelData
                    required property int index
                    readonly property string q: modelData.q
                    readonly property bool block: q !== ""
                    readonly property bool folds: q === "fold" && (words.open ? true : t.truncated)
                    readonly property real padL: block ? 10 : 0
                    readonly property real padR: q === "pre" ? 8 : block ? 22 : 0
                    readonly property real wants: t.implicitWidth + padL + padR
                    onWantsChanged: if (parent && parent.measure) parent.measure()
                    readonly property real last: block ? width : t.last
                    width: words.width
                    height: t.height + (block ? 8 : 0)
                    Rectangle {
                        visible: part.block
                        anchors.fill: parent
                        radius: 6
                        color: Qt.rgba(words.tint.r, words.tint.g, words.tint.b, 0.12)
                        clip: true
                        Rectangle { visible: part.q !== "pre"; width: 3; height: parent.height; color: words.tint }
                    }
                    // the part as RichText: links in the tint, not underlined; a spoiler's letters unseen
                    readonly property string rich: modelData.h
                        .replace(/<a href="spoiler"/g, "<a style='color:" + (words.shown ? words.ink : "transparent") + ";text-decoration:none' href=\"spoiler\"")
                        .replace(/<a href=/g, "<a style='color:" + words.tint + ";text-decoration:none' href=")
                    function hit(x, y) {
                        let url = ""
                        if (t.fancy)
                            url = t.linkAt(x - t.x, y - t.y)
                        else if (modelData.h.indexOf("<a ") >= 0) {
                            const probe = prober.createObject(part)
                            url = probe.linkAt(x - t.x, y - t.y)
                            probe.destroy()
                        }
                        return url ? url : q === "fold" ? "fold" : ""
                    }
                    Component {
                        id: prober      // laid out as t is (bold 700 as StyledText's), only for a tap
                        TextEdit {
                            visible: false
                            readOnly: true
                            width: t.width
                            wrapMode: t.wrapMode
                            textFormat: TextEdit.RichText
                            font: t.font
                            text: part.rich
                        }
                    }
                    Icon {
                        visible: part.q === "quote" || part.q === "fold" && !part.folds
                        anchors.right: parent.right; anchors.rightMargin: 4; y: 4
                        width: 14; height: 14
                        name: "quote"; color: words.tint
                    }
                    Icon {
                        visible: part.folds
                        anchors.right: parent.right; anchors.rightMargin: 3; anchors.bottom: parent.bottom; anchors.bottomMargin: 3
                        width: 18; height: 18
                        rotation: words.open ? 180 : 0
                        name: "chevron"; color: words.tint
                    }
                    Text {
                        id: t
                        x: part.padL; y: part.block ? 4 : 0
                        width: Math.max(words.room, 1) - part.padL - part.padR
                        wrapMode: part.q === "pre" ? Text.WrapAnywhere : Text.Wrap
                        maximumLineCount: part.q === "fold" && !words.open ? 3 : 100000
                        elide: Text.ElideRight
                        // StyledText, 4–5 times quicker to lay out than RichText (a long post as RichText
                        // took 0.05 s to make, a stutter in a flick). It underlines links (Telegram does
                        // not), so links are coloured words here and a tap finds them in a RichText
                        // probe (hit). Inline code wants a face, which only RichText knows: such a
                        // part is RichText, the last one's last line measured by a TextEdit twin.
                        readonly property bool fancy: part.modelData.h.indexOf("monospace") >= 0
                        textFormat: fancy ? Text.RichText : Text.StyledText
                        property real laid: 0
                        readonly property real last: !fancy ? laid : twin.item ? twin.item.laid : width
                        onLineLaidOut: (line) => { if (line.isLast) laid = line.implicitWidth }
                        text: fancy ? part.rich
                                    : part.modelData.h.replace(/<a href="spoiler">/g, "<font color='" + (words.shown ? words.ink : "transparent") + "'>")
                                                      .replace(/<a href="[^"]*">/g, "<font color='" + words.tint + "'>").replace(/<\/a>/g, "</font>")
                        color: words.ink
                        linkColor: words.tint
                        font.family: part.q === "pre" ? "monospace" : Theme.font
                        font.pixelSize: part.q === "pre" ? words.size - 2 : words.size
                    }
                    // a spoiler: where its letters are, line by line, from a TextEdit twin (which tells
                    // each letter's place and link), and the dust over them
                    Loader {
                        id: spy
                        active: part.modelData.h.indexOf("href=\"spoiler\"") >= 0
                        sourceComponent: TextEdit {
                            visible: false
                            readOnly: true
                            width: t.width
                            wrapMode: t.wrapMode
                            textFormat: TextEdit.RichText
                            font: t.font
                            text: part.rich
                            readonly property var rects: (contentHeight, width, places())
                            function places() {
                                const out = []
                                let cur = null
                                for (let p = 0; p < length; p++) {
                                    const r = positionToRectangle(p)
                                    if (linkAt(r.x + 1, r.y + r.height / 2) !== "spoiler") {
                                        cur = null
                                        continue
                                    }
                                    const n = positionToRectangle(p + 1)
                                    const right = n.y === r.y && n.x > r.x ? n.x : r.x + font.pixelSize * 0.5
                                    if (cur && cur.y === r.y && Math.abs(cur.x + cur.w - r.x) < 1)
                                        cur.w = right - cur.x
                                    else {
                                        cur = { x: r.x, y: r.y, w: right - r.x, h: r.height }
                                        out.push(cur)
                                    }
                                }
                                return out
                            }
                        }
                    }
                    Dust {
                        visible: spy.active
                        x: t.x; y: t.y
                        width: t.width; height: t.height
                        rects: spy.item ? spy.item.rects : []
                        ink: words.ink
                        gone: words.shown
                        live: words.live
                    }
                    Loader {
                        id: twin
                        active: t.fancy && part.index === words.list.length - 1     // (RichText's lineCount is not told)
                        // the same RichText in a TextEdit, which tells where its last letter ends
                        sourceComponent: TextEdit {
                            visible: false
                            readOnly: true
                            width: t.width
                            wrapMode: t.wrapMode
                            textFormat: TextEdit.RichText
                            font: t.font
                            text: t.text
                            readonly property real laid: length, contentWidth, positionToRectangle(length).x
                        }
                    }

                }
            }
        }
    }
}
