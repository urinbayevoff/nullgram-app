// A voice note or a song in its bubble, as Telegram-iOS's ChatMessageInteractiveFileNode lays
// them out: the round button (down, the ring while it comes, play, pause), then the waveform
// (a voice note) or the title and the performer (a song), the time under them.
import QtQuick

Item {
    id: row
    property string kind: "voice"       // voice | audio
    property bool out: false
    property string wave: ""            // Telegram's waveform: 5-bit values packed, base64
    property int dur: 0                 // seconds
    property string title: ""
    property string sub: ""
    property real got: -1               // coming down: how far (else -1)
    property bool here: false           // downloaded
    property bool playing: false        // this one is the page's sound, playing
    property bool current: false        // this one is the page's sound (playing or paused)
    property real at: 0                 // where it is, ms (while current)
    width: 230; height: 50

    readonly property color ink: out ? Theme.voiceOut : Theme.accent
    readonly property color faint: out ? Theme.voiceOutFaint : Theme.voiceInFaint

    Rectangle {
        id: button
        y: 3
        width: 44; height: 44; radius: 22
        color: row.ink
        Icon {
            visible: row.got < 0
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: name === "play" ? 1.5 : 0
            width: 22; height: 22
            name: !row.here ? "down" : row.playing ? "pause" : "play"
            color: row.out ? Theme.bubbleOut : "white"
        }
        Ring {
            visible: row.got >= 0
            anchors.fill: parent
            value: row.got
            color: row.out ? Theme.bubbleOut : "white"
        }
    }

    // 5-bit values out of the packed bytes, then as many bars as fit, each the loudest of its part
    readonly property var levels: {
        const raw = wave ? Qt.atob(wave) : ""
        const all = []
        const n = Math.floor(raw.length * 8 / 5)
        for (let i = 0; i < n; i++) {
            const bit = i * 5, b = bit >> 3, s = bit & 7
            const v = ((raw.charCodeAt(b) | ((b + 1 < raw.length ? raw.charCodeAt(b + 1) : 0) << 8)) >> s) & 31
            all.push(v)
        }
        const bars = Math.floor((width - 56) / 4)
        const out = []
        for (let k = 0; k < bars; k++) {
            let top = 0
            for (let i = Math.floor(k * all.length / bars); i < Math.max(Math.floor((k + 1) * all.length / bars), Math.floor(k * all.length / bars) + 1); i++)
                top = Math.max(top, all[i] || 0)
            out.push(top)
        }
        return out
    }
    readonly property real played: current && dur ? Math.min(1, at / (dur * 1000)) : 0

    Row {
        visible: row.kind === "voice"
        x: 56; y: 8
        height: 18
        spacing: 1.5
        Repeater {
            model: row.levels
            Rectangle {
                required property int index
                required property var modelData
                anchors.bottom: parent.bottom
                width: 2.5; radius: 1.25
                height: 2.5 + 15.5 * modelData / 31
                color: index < row.played * row.levels.length ? row.ink : row.faint
            }
        }
    }
    Text {
        visible: row.kind === "audio"
        x: 56; y: 4
        width: row.width - 56
        elide: Text.ElideRight
        text: row.title
        color: row.out ? Theme.outText : Theme.inText
        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
    }
    Text {
        x: 56; y: row.kind === "voice" ? 30 : 25
        width: row.width - 56
        elide: Text.ElideRight
        readonly property int secs: row.current ? Math.floor(row.at / 1000) : row.dur
        text: (row.kind === "audio" && row.sub ? row.sub + " · " : "") + Math.floor(secs / 60) + ":" + String(secs % 60).padStart(2, "0")
        color: row.out ? Theme.outMeta : Theme.inMeta
        font.family: Theme.font; font.pixelSize: 13
    }
}
