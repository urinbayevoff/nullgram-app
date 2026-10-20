// The search over the chat list, as Telegram-iOS's: the box at the top with "Bekor", and under
// it the chats whose name has it (ours at once, then TDLib's and the server's), public ones
// ("Global qidiruv") and messages in every chat. Latin and Cyrillic find each other (Store.fold).
// A chat found opens; a message found opens its chat at that message, lit up.
import QtQuick

Rectangle {
    id: view
    property var store
    property bool open: false
    signal picked(var chatId, var messageId)

    color: Theme.bg
    opacity: 0
    visible: opacity > 0
    NumberAnimation on opacity { id: fade; duration: 160; running: false }      // (an Animator would set it only at the end, and visible goes by it)

    property var chatIds: []
    property var globalIds: []
    property var found: []
    property int now: Date.now() / 1000

    function show() {
        open = true
        now = Date.now() / 1000
        field.text = ""
        results.clear()
        fade.from = opacity; fade.to = 1; fade.restart()
        field.forceActiveFocus()
    }
    function close() {
        open = false
        field.focus = false
        Qt.inputMethod.hide()
        fade.from = opacity; fade.to = 0; fade.restart()
    }

    Timer { id: later; interval: 250; onTriggered: view.run(field.text.trim()) }

    function run(q) {
        chatIds = []; globalIds = []; found = []
        if (!q) {
            rebuild()
            return
        }
        store.searchChats(q, (kind, ids) => {
            if (kind === "chats")
                view.chatIds = ids
            else
                view.globalIds = ids
            view.rebuild()
        })
        if (q.length >= 2)
            store.searchMessages(q, (msgs) => { view.found = msgs; view.rebuild() })
    }

    function rebuild() {
        results.clear()
        const chatRow = (id, sub) => {
            const c = store.chats[id]
            results.append({ kind: "chat", chatId: id, msgId: 0, title: store.title(c), sub: sub, time: "",
                             photo: store.photoPath(c), letters: store.letters(c.title),
                             tint: store.tints[Math.abs(id) % store.tints.length] })
        }
        if (chatIds.length) {
            results.append({ kind: "head", title: "Chatlar" })
            for (const id of chatIds)
                chatRow(id, store.status(store.chats[id], now))
        }
        if (globalIds.length) {
            results.append({ kind: "head", title: "Global qidiruv" })
            for (const id of globalIds.slice(0, 5))       // (a few, as iOS shows them: the messages follow)
                chatRow(id, username(store.chats[id]) || store.status(store.chats[id], now))
        }
        if (found.length) {
            results.append({ kind: "head", title: "Xabarlar" })
            for (const m of found) {
                const c = store.chats[m.chat_id]
                if (!c)
                    continue
                results.append({ kind: "message", chatId: m.chat_id, msgId: m.id, title: store.title(c),
                                 sub: store.preview(m.content).replace(/\s+/g, " "), time: store.stamp(m.date),
                                 photo: store.photoPath(c), letters: store.letters(c.title),
                                 tint: store.tints[Math.abs(m.chat_id) % store.tints.length] })
            }
        }
    }

    function username(c) {
        let names = null
        if (c.type["@type"] === "chatTypeSupergroup") {
            const g = store.groups["s" + c.type.supergroup_id]
            names = g && g.usernames
        } else if (c.type["@type"] === "chatTypePrivate") {
            const u = store.users[c.type.user_id]
            names = u && u.usernames
        }
        return names && names.active_usernames.length ? "@" + names.active_usernames[0] : ""
    }

    ListModel { id: results }

    MouseArea { anchors.fill: parent }      // nothing under it is touched while it is up

    Item {
        id: top
        width: parent.width; height: 60
        Rectangle {
            x: 14; y: 12
            width: parent.width - x - cancel.width - 28; height: 38; radius: 19
            color: Theme.dark ? Qt.rgba(0.46, 0.46, 0.5, 0.24) : Qt.rgba(0.46, 0.46, 0.5, 0.12)
            Icon {
                x: 12; anchors.verticalCenter: parent.verticalCenter
                name: "search"; width: 18; height: 18; color: Theme.grey
            }
            TextInput {
                id: field
                x: 38; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - 12
                color: Theme.text
                selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 16
                clip: true
                inputMethodHints: Qt.ImhNoPredictiveText
                onTextChanged: later.restart()
                Text {
                    visible: !field.text
                    text: "Qidiruv"
                    color: Theme.grey
                    font: field.font
                }
            }
        }
        Text {
            id: cancel
            anchors.right: parent.right; anchors.rightMargin: 16
            y: 21
            text: "Bekor"
            color: Theme.accent
            font.family: Theme.font; font.pixelSize: 16
            MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: view.close() }
        }
    }

    ListView {
        id: list
        y: top.height
        width: parent.width; height: parent.height - y
        clip: true
        model: results
        maximumFlickVelocity: 6000
        flickDeceleration: 2200
        onMovementStarted: Qt.inputMethod.hide()        // looking through them: the keyboard goes

        delegate: Rectangle {
            id: row
            required property string kind
            required property var chatId
            required property var msgId
            required property string title
            required property string sub
            required property string time
            required property string photo
            required property string letters
            required property string tint
            width: list.width
            height: kind === "head" ? 34 : kind === "message" ? 66 : 58
            color: kind === "head" ? (Theme.dark ? "#1c1c1d" : "#f2f2f7") : tap.pressed ? Theme.highlight : Theme.bg

            Text {
                visible: row.kind === "head"
                x: 16; anchors.verticalCenter: parent.verticalCenter
                text: row.title.toUpperCase()
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13
            }
            Avatar {
                visible: row.kind !== "head"
                x: 14; anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 44
                source: row.kind !== "head" ? row.photo : ""
                letters: row.letters; tint: row.tint
            }
            Text {
                visible: row.kind !== "head"
                x: 70; y: row.kind === "message" ? 10 : 9
                width: parent.width - x - stamp.width - 20
                text: row.title
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            Text {
                id: stamp
                visible: row.kind === "message"
                anchors.right: parent.right; anchors.rightMargin: 14
                y: 12
                text: row.kind === "message" ? row.time : ""
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13
            }
            Text {
                visible: row.kind !== "head"
                x: 70; y: row.kind === "message" ? 33 : 31
                width: parent.width - x - 14
                text: row.sub
                elide: Text.ElideRight
                maximumLineCount: 1
                textFormat: Text.PlainText
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 14
            }
            Rectangle {
                visible: row.kind !== "head"
                x: 70; y: parent.height - 0.5
                width: parent.width - x; height: 0.5
                color: Theme.separator
            }
            MouseArea {
                id: tap
                anchors.fill: parent
                enabled: row.kind !== "head"
                onClicked: {
                    Qt.inputMethod.hide()
                    view.picked(row.chatId, row.msgId)
                }
            }
        }
    }

    Text {
        visible: view.open && field.text.trim() !== "" && results.count === 0 && !later.running
        y: 140; anchors.horizontalCenter: parent.horizontalCenter
        text: "Hech narsa topilmadi"
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 15
    }
}
