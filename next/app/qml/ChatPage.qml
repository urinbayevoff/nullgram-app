// One chat: the messages from the bottom up, a header over them and the field
// under them. It is `ready` once its newest messages are laid out, so the push
// moves a finished page.
import QtQuick
import QtQuick.Window

Page {
    id: page
    required property var chatId
    readonly property var chat: store.chats[chatId]
    readonly property bool group: chat && (chat.type["@type"] === "chatTypeBasicGroup" ||
                                           (chat.type["@type"] === "chatTypeSupergroup" && !chat.type.is_channel))
    readonly property bool channel: chat && chat.type["@type"] === "chatTypeSupergroup" && chat.type.is_channel
    ready: false
    property bool loading: false
    property bool more: true

    ListModel { id: messages }       // newest first: the list runs bottom to top

    property int now: Date.now() / 1000      // "N minutes ago" moves on by itself
    Timer { interval: 30000; repeat: true; running: true; onTriggered: page.now = Date.now() / 1000 }

    Image {              // the wallpaper: a small picture of the gradient, drawn large
        anchors.fill: parent
        source: "image://wall/" + Theme.wall
        smooth: true
    }

    Component.onCompleted: {
        store.send({ "@type": "openChat", chat_id: chatId })
        if (chat && chat.type["@type"] === "chatTypeSupergroup") {   // its update may not have the count
            const g = store.groups["s" + chat.type.supergroup_id]
            if (!g || !g.member_count)
                store.send({ "@type": "getSupergroupFullInfo", supergroup_id: chat.type.supergroup_id }, (r) => {
                    const g = store.groups["s" + page.chat.type.supergroup_id]
                    if (g && r.member_count) {
                        g.member_count = r.member_count
                        store.seen++
                    }
                })
        }
        store.history(chatId, 0, 30, (got) => {
            for (const m of got)
                messages.append(page.row(m))
            page.ready = true
            page.read(got)
        })
    }
    Component.onDestruction: store.send({ "@type": "closeChat", chat_id: chatId })

    function row(m) {
        const t = m.content["@type"]
        const pic = t !== "messageText" ? (store.kinds[t] || "") : ""
        return {
            msgId: m.id, out: m.is_outgoing, date: m.date,
            text: t === "messageText" ? m.content.text.text : (m.content.caption ? m.content.caption.text : ""),
            kind: t === "messageText" ? "" : (t === "messageSticker" && m.content.sticker.emoji ? m.content.sticker.emoji + " Stiker" : pic || "Bu turdagi xabar hali yo'q"),
            sender: page.group && !m.is_outgoing ? store.senderName(m.sender_id, false) : "",
            senderKey: JSON.stringify(m.sender_id), sending: !!m.sending_state,
            tint: store.tints[Math.abs(m.sender_id.user_id || m.sender_id.chat_id || 0) % store.tints.length],
            time: Qt.formatTime(new Date(m.date * 1000), "HH:mm"),
            views: m.interaction_info ? m.interaction_info.view_count : 0
        }
    }

    function apart(other, senderKey, date) {
        return !other || other.senderKey !== senderKey || Math.abs(other.date - date) > 600
    }

    function read(msgs) {
        if (msgs.length)
            store.send({ "@type": "viewMessages", chat_id: chatId, message_ids: msgs.map((m) => m.id), force_read: true })
    }

    function older() {
        if (loading || !more || !messages.count)
            return
        loading = true
        store.history(chatId, messages.get(messages.count - 1).msgId, 40, (got) => {
            for (const m of got)
                messages.append(page.row(m))
            page.more = got.length > 0
            page.loading = false
        })
    }

    Connections {
        target: store
        function onMessage(m) {
            if (m.chat_id !== page.chatId)
                return
            for (let i = 0; i < Math.min(messages.count, 20); i++)
                if (messages.get(i).msgId === m.id)
                    return
            messages.insert(0, page.row(m))
            if (!m.is_outgoing)
                page.read([m])
        }
        function onMessageChanged(chatId, oldId, m) {
            if (chatId !== page.chatId)
                return
            for (let i = 0; i < Math.min(messages.count, 50); i++)
                if (messages.get(i).msgId === oldId) {
                    messages.set(i, page.row(m))
                    return
                }
        }
        function onMessagesDeleted(chatId, ids) {
            if (chatId !== page.chatId)
                return
            for (let i = messages.count - 1; i >= 0; i--)
                if (ids.indexOf(messages.get(i).msgId) >= 0)
                    messages.remove(i)
        }
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.topMargin: 0
        model: messages
        verticalLayoutDirection: ListView.BottomToTop
        cacheBuffer: 800
        maximumFlickVelocity: 6000
        flickDeceleration: 2200
        header: Item { width: 1; height: input.height + 10 }
        footer: Item { width: 1; height: bar.height + 8 }
        onAtYEndChanged: if (atYEnd) page.older()       // the top, in a bottom-to-top list

        delegate: Item {
            id: item
            required property int index
            required property var msgId
            required property bool out
            required property string text
            required property string kind
            required property string sender
            required property string senderKey
            required property string tint
            required property string time
            required property bool sending
            required property int views
            required property int date
            // a run: one sender's messages within 10 minutes of each other. Its first (the
            // top) has the name and more space over it, its last (the bottom) the tail.
            readonly property bool first: page.apart(messages.get(index + 1), senderKey, date)
            readonly property bool last: page.apart(messages.get(index - 1), senderKey, date)
            width: list.width
            height: bubble.height + (first ? 8 : 2)

            Item {
                id: bubble
                y: item.first ? 8 : 2
                x: item.out ? item.width - width - 8 - 6 : 8 + 6
                width: Math.min(item.width * 0.78, Math.max(body.implicitWidth, who.implicitWidth, stamp.implicitWidth + 10) + 24)
                height: (who.visible ? who.height + 2 : 0) + body.height + 16

                Rectangle {     // while the stretched picture loads
                    anchors.fill: parent
                    visible: shape.status !== Image.Ready
                    radius: 17
                    color: item.out ? Theme.bubbleOut : Theme.bubbleIn
                }
                BorderImage {   // the bubble, stretched from a small picture (tepegram.py Bubble)
                    id: shape
                    anchors.fill: parent
                    anchors.leftMargin: item.out ? 0 : -6
                    anchors.rightMargin: item.out ? -6 : 0
                    border { left: item.out ? 17 : 23; right: item.out ? 23 : 17; top: 17; bottom: 17 }
                    source: "image://bubble/" + (item.out ? "out/" : "in/") + (item.first ? "b/" : "s/") + (item.last ? "t/" : "s/")
                            + String(item.out ? Theme.bubbleOut : Theme.bubbleIn).slice(1) + "/" + Screen.devicePixelRatio
                    smooth: true
                }

                Text {
                    id: who
                    visible: item.sender !== "" && item.first
                    x: 12; y: 7
                    text: item.sender
                    color: item.tint
                    font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                }
                Text {
                    id: body
                    x: 12
                    y: who.visible ? who.y + who.height + 2 : 8
                    width: Math.min(implicitWidth, item.width * 0.78 - 24)
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    // the time sits in the last line's corner: room for it after the text
                    text: (item.kind ? "[" + item.kind + "] " : "") + item.text + "    "
                    color: item.out ? Theme.outText : Theme.inText
                    font.family: Theme.font; font.pixelSize: 16
                }
                Text {
                    id: stamp
                    anchors.right: parent.right; anchors.rightMargin: 10
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                    textFormat: Text.StyledText
                    text: (item.views ? item.views + " · " : "") + item.time +
                          (item.out ? (item.sending ? " ◷" : " <font color='" + Theme.check + "'>✓</font>") : "")
                    color: item.out ? Theme.outMeta : Theme.inMeta
                    font.family: Theme.font; font.pixelSize: 12
                }
            }
        }
    }

    Rectangle {          // the header: back, the name and what it is
        id: bar
        width: parent.width; height: 56
        color: Theme.bar
        Text {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            text: "‹"
            color: Theme.accent
            font.family: Theme.font; font.pixelSize: 34
            MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: page.nav.pop() }
        }
        Column {
            anchors.centerIn: parent
            width: parent.width - 120
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: page.chat ? page.chat.title : ""
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: store.seen, page.now, store.status(page.chat, page.now)     // (re-read when either changes)
                visible: text !== ""
                color: text === "onlayn" || text.endsWith("...") ? Theme.accent : Theme.grey
                font.family: Theme.font; font.pixelSize: 13
            }
        }
        Avatar {
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 38; height: 38
            source: page.chat ? store.photoPath(page.chat) : ""
            letters: page.chat ? store.letters(page.chat.title) : ""
            tint: store.tints[Math.abs(page.chatId) % store.tints.length]
        }
    }

    Rectangle {          // the field
        id: input
        visible: !page.channel
        anchors.bottom: parent.bottom
        width: parent.width
        height: visible ? Math.max(52, field.contentHeight + 26) : 0
        color: Theme.bar
        Rectangle {
            x: 10; y: 8
            width: parent.width - 66; height: parent.height - 16
            radius: 18
            color: Theme.field
            border.color: Theme.fieldBorder; border.width: 0.5
            TextEdit {
                id: field
                x: 14; y: 8
                width: parent.width - 28
                wrapMode: TextEdit.Wrap
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16
                Text {
                    visible: !field.text && !field.preeditText
                    text: "Xabar"
                    color: Theme.grey
                    font: field.font
                }
            }
        }
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.bottom: parent.bottom; anchors.bottomMargin: 10
            width: 36; height: 36; radius: 18
            color: field.text.trim() ? Theme.accent : Theme.mutedBadge
            Text { anchors.centerIn: parent; text: "↑"; color: "white"; font.pixelSize: 20; font.weight: Font.Bold }
            MouseArea {
                anchors.fill: parent; anchors.margins: -6
                onClicked: {
                    const t = field.text.trim()
                    if (!t)
                        return
                    store.sendText(page.chatId, t)
                    field.text = ""
                    list.positionViewAtBeginning()
                }
            }
        }
    }
}
