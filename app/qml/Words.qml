// A message's words as Telegram draws them. Plain words are one Text; formatted ones (Store.rich's
// parts) a column: words as StyledText (bold, italic, links a tap opens), a quote a tinted block with
// a bar down its left and „ in its corner (one that folds shows three lines and ⌄ until tapped),
// code a block of its own in a fixed-width face.
import QtQuick

Item {
    id: words
    property string text            // the plain words, when there are no parts
    property string parts           // Store.rich's JSON, "" for none
    property color ink
    property color tint             // the links, a quote's bar and its tint
    property int size: 16
    property bool open: false       // a folding quote shown whole
    signal link(string url)
    signal fold()                   // a folding quote tapped

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
                    MouseArea {
                        enabled: part.q === "fold"
                        anchors.fill: parent
                        onClicked: words.fold()
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
                        width: parent.width - part.padL - part.padR
                        wrapMode: part.q === "pre" ? Text.WrapAnywhere : Text.Wrap
                        maximumLineCount: part.q === "fold" && !words.open ? 3 : 100000
                        elide: Text.ElideRight
                        // links, code and bold as RichText: StyledText underlines every link (Telegram
                        // does not), knows no font face and its bold is 700 (Telegram-iOS's is semibold).
                        // RichText tells no line's width: the last part's comes from a StyledText twin.
                        readonly property bool fancy: /<a |monospace|<b>/.test(part.modelData.h)
                        textFormat: fancy ? Text.RichText : Text.StyledText
                        property real laid: 0
                        readonly property real last: !fancy ? laid : twin.item ? twin.item.laid : width
                        onLineLaidOut: (line) => { if (line.isLast) laid = line.implicitWidth }
                        text: fancy ? part.modelData.h.replace(/<a href="spoiler"/g, "<a style='color:" + words.ink + ";text-decoration:none' href=\"spoiler\"")
                                                          .replace(/<a href=/g, "<a style='color:" + words.tint + ";text-decoration:none' href=")
                                                          .replace(/<b>/g, "<span style='font-weight:600'>").replace(/<\/b>/g, "</span>")
                                    : part.modelData.h
                        color: words.ink
                        linkColor: words.tint
                        font.family: part.q === "pre" ? "monospace" : Theme.font
                        font.pixelSize: part.q === "pre" ? words.size - 2 : words.size
                        onLinkActivated: (url) => words.link(url)
                    }
                    Loader {
                        id: twin
                        active: t.fancy && part.index === words.list.length - 1     // (RichText's lineCount is not told)
                        sourceComponent: Text {
                            visible: false
                            width: t.width
                            wrapMode: t.wrapMode
                            textFormat: Text.StyledText
                            font: t.font
                            text: part.modelData.h.replace(/<\/?a[^>]*>/g, "")
                            property real laid: 0
                            onLineLaidOut: (line) => { if (line.isLast) laid = line.implicitWidth }
                        }
                    }

                }
            }
        }
    }
}
