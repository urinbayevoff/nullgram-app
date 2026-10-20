// One chat: the messages from the bottom up, a header over them and the field
// under them. It is `ready` once its newest messages are laid out, so the push
// moves a finished page. A long press on a message opens its menu (MessageMenu):
// reply, copy, edit, delete.
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

    property var flying: null       // the text just sent and where it was: its bubble starts there
    property bool lift: false
    NumberAnimation {
        id: scroll
        target: list; property: "contentY"; duration: 300
        easing.type: Easing.BezierSpline; easing.bezierCurve: [0.19919, 0.01064, 0.27921, 0.91025, 1.0, 1.0]
        onFinished: list.down = list.atYBeginning
    }
    Timer { id: landed; interval: 320; onTriggered: page.lift = false }
    property int now: Date.now() / 1000      // "N minutes ago" moves on by itself
    Timer { interval: 30000; repeat: true; running: true; onTriggered: page.now = Date.now() / 1000 }

    property var replying: null     // { id, name, text }: the next message answers this one
    property var editing: null      // { id }: the field holds this message's text to change
    property var quotes: ({})       // message id -> { name, text }, what a reply to it shows
    property var asked: ({})        // quotes asked of TDLib (not among the loaded messages)

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
            page.add(got)
            page.ready = true
            page.read(got)
        })
    }
    Component.onDestruction: store.send({ "@type": "closeChat", chat_id: chatId })

    // older messages at the end; their quotes first, so a reply within the batch needs no request
    function add(got) {
        for (const m of got)
            remember(m)
        for (const m of got)
            messages.append(row(m))
    }

    function remember(m) {
        quotes[m.id] = { name: m.is_outgoing ? "Siz" : store.senderName(m.sender_id, false) || (chat ? chat.title : ""),
                         text: store.preview(m.content) }
    }

    readonly property var pictured: ["messagePhoto", "messageVideo", "messageAnimation", "messageSticker", "messageVideoNote"]

    function shown(content) {
        const t = content["@type"]
        return {
            text: t === "messageText" ? content.text.text : (content.caption ? content.caption.text : ""),
            kind: t === "messageText" || pictured.indexOf(t) >= 0 ? ""
                : store.kinds[t] || "Bu turdagi xabar hali yo'q"
        }
    }

    // a still picture TDLib can give for a thumbnail (not an animation or a video)
    function still(th) {
        const f = th && th.format["@type"]
        return f === "thumbnailFormatJpeg" || f === "thumbnailFormatWebp" || f === "thumbnailFormatPng" || f === "thumbnailFormatGif"
            ? th.file : null
    }

    // what a message shows as a picture: its kind, size, Telegram's tiny preview, and the file
    // to show (the photo's size nearest 640 px, else a video's or a sticker's still)
    property var files: ({})         // message id -> the picture's file
    function media(c) {
        const t = c["@type"]
        const r = { picKind: "", picW: 1, picH: 1, mini: "", dur: 0, file: null }
        if (t === "messagePhoto" && c.photo.sizes.length) {
            const sizes = c.photo.sizes      // small to big
            let best = sizes[sizes.length - 1]
            for (const z of sizes)
                if (z.width >= 640) {
                    best = z
                    break
                }
            Object.assign(r, { picKind: "photo", picW: best.width, picH: best.height, file: best.photo,
                               mini: c.photo.minithumbnail ? c.photo.minithumbnail.data : "" })
        } else if (t === "messageVideo" || t === "messageAnimation") {
            const v = t === "messageVideo" ? c.video : c.animation
            Object.assign(r, { picKind: t === "messageVideo" ? "video" : "gif", picW: v.width || 1, picH: v.height || 1,
                               dur: v.duration, file: still(v.thumbnail), mini: v.minithumbnail ? v.minithumbnail.data : "" })
        } else if (t === "messageSticker") {
            const st = c.sticker
            Object.assign(r, { picKind: "sticker", picW: st.width || 1, picH: st.height || 1,
                               file: st.format["@type"] === "stickerFormatWebp" ? st.sticker : still(st.thumbnail) })
        } else if (t === "messageVideoNote") {
            const v = c.video_note
            Object.assign(r, { picKind: "round", picW: 1, picH: 1, dur: v.duration, file: still(v.thumbnail),
                               mini: v.minithumbnail ? v.minithumbnail.data : "" })
        }
        return r
    }

    function loadPic(id) {
        const f = files[id]
        if (f)
            store.fetch(f, 1, (path) => {
                const i = page.indexOf(id)
                if (i >= 0)
                    messages.setProperty(i, "pic", path)
            })
    }

    function row(m) {
        const s = shown(m.content)
        const p = media(m.content)
        if (p.file)
            files[m.id] = p.file
        const r = m.reply_to && m.reply_to["@type"] === "messageReplyToMessage" ? m.reply_to : null
        let quote = null
        if (r && r.chat_id === chatId) {
            quote = quotes[r.message_id]
            if (!quote)
                want(r.message_id)
        } else if (r && r.content) {        // a reply to a message in another chat comes with it
            quote = { name: "", text: store.preview(r.content) }
        }
        return {
            msgId: m.id, out: m.is_outgoing, date: m.date, text: s.text, kind: s.kind,
            sender: page.group && !m.is_outgoing ? store.senderName(m.sender_id, false) : "",
            senderKey: JSON.stringify(m.sender_id), sending: !!m.sending_state,
            tint: store.tints[Math.abs(m.sender_id.user_id || m.sender_id.chat_id || 0) % store.tints.length],
            time: Qt.formatTime(new Date(m.date * 1000), "HH:mm"),
            views: m.interaction_info ? m.interaction_info.view_count : 0,
            edited: m.edit_date > 0,
            replyId: r ? r.message_id : 0,
            quoteName: quote ? quote.name : "", quoteText: quote ? quote.text : (r ? "..." : ""),
            picKind: p.picKind, picW: p.picW, picH: p.picH, mini: p.mini, dur: p.dur,
            pic: p.file && p.file.local.is_downloading_completed ? p.file.local.path : ""
        }
    }

    // a replied message not loaded here: ask for it, then fill the replies to it
    function want(id) {
        if (asked[id])
            return
        asked[id] = true
        store.send({ "@type": "getMessage", chat_id: chatId, message_id: id }, (m) => {
            if (m["@type"] === "message")
                page.remember(m)
            else
                page.quotes[id] = { name: "", text: "O'chirilgan xabar" }
            page.requote(id)
        })
    }

    function requote(id) {
        const q = quotes[id]
        for (let i = 0; i < messages.count; i++)
            if (messages.get(i).replyId === id) {
                messages.setProperty(i, "quoteName", q.name)
                messages.setProperty(i, "quoteText", q.text)
            }
    }

    function indexOf(id) {
        for (let i = 0; i < messages.count; i++)
            if (messages.get(i).msgId === id)
                return i
        return -1
    }

    function otherDay(other, date) {
        return !other || new Date(other.date * 1000).toDateString() !== new Date(date * 1000).toDateString()
    }

    readonly property var months: ["yanvar", "fevral", "mart", "aprel", "may", "iyun", "iyul", "avgust",
                                   "sentabr", "oktabr", "noyabr", "dekabr"]
    function dayName(unix) {
        const d = new Date(unix * 1000), now = new Date()
        if (d.toDateString() === now.toDateString())
            return "Bugun"
        if (d.toDateString() === new Date(now - 86400000).toDateString())
            return "Kecha"
        return d.getDate() + "-" + months[d.getMonth()] + (d.getFullYear() !== now.getFullYear() ? " " + d.getFullYear() : "")
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
            page.add(got)
            page.more = got.length > 0
            page.loading = false
        })
    }

    // the replied message, if it is loaded
    function jump(id) {
        const i = indexOf(id)
        if (i >= 0)
            list.positionViewAtIndex(i, ListView.Center)
    }

    // ---- the menu ------------------------------------------------------------
    function openMenu(item) {
        const m = { id: item.msgId, text: item.text, kind: item.kind, out: item.out,
                    name: item.out ? "Siz" : item.sender || (chat ? chat.title : "") }
        store.send({ "@type": "getMessageProperties", chat_id: chatId, message_id: m.id }, (p) => {
            const ok = p["@type"] === "messageProperties"
            const acts = []
            if (ok && p.can_be_replied && !page.channel)
                acts.push({ text: "Javob berish", glyph: "↩", run: () => page.reply(m) })
            if (m.text)
                acts.push({ text: "Nusxa olish", glyph: "⧉", run: () => page.copy(m.text) })
            if (ok && p.can_be_edited && !m.kind)
                acts.push({ text: "Tahrirlash", glyph: "✎", run: () => page.edit(m) })
            if (ok && p.can_be_deleted_only_for_self && p.can_be_deleted_for_all_users) {
                acts.push({ text: "Men uchun o'chirish", glyph: "✕", danger: true,
                            run: () => store.deleteMessages(page.chatId, [m.id], false) })
                acts.push({ text: "Hamma uchun o'chirish", glyph: "✕", danger: true,
                            run: () => store.deleteMessages(page.chatId, [m.id], true) })
            } else if (ok && (p.can_be_deleted_only_for_self || p.can_be_deleted_for_all_users)) {
                acts.push({ text: "O'chirish", glyph: "✕", danger: true,
                            run: () => store.deleteMessages(page.chatId, [m.id], p.can_be_deleted_for_all_users) })
            }
            const i = page.indexOf(m.id)
            const it = i >= 0 ? list.itemAtIndex(i) : null
            if (it && acts.length)
                menu.show(it.face, m.out, acts)
        })
    }

    function reply(m) {
        editing = null
        replying = { id: m.id, name: m.name, text: m.text || m.kind }
        field.forceActiveFocus()
    }

    function edit(m) {
        replying = null
        editing = { id: m.id }
        field.text = m.text
        field.cursorPosition = field.length
        field.forceActiveFocus()
    }

    function copy(text) {
        clip.text = text
        clip.selectAll()
        clip.copy()
    }

    function cancelCompose() {
        if (editing)
            field.text = ""
        editing = null
        replying = null
    }

    // the back button: the menu first, then a reply or edit being written (Main asks)
    function dismiss() {
        if (menu.open) {
            menu.close()
            return true
        }
        if (replying || editing) {
            cancelCompose()
            return true
        }
        return false
    }

    TextEdit { id: clip; visible: false }      // the clipboard's way in

    Connections {
        target: store
        function onMessage(m) {
            if (m.chat_id !== page.chatId)
                return
            for (let i = 0; i < Math.min(messages.count, 20); i++)
                if (messages.get(i).msgId === m.id)
                    return
            const from = m.is_outgoing && page.flying && m.content["@type"] === "messageText" &&
                         m.content.text.text === page.flying.text ? page.flying : null
            const bottom = list.atYBeginning || from
            const was = list.contentY
            page.remember(m)
            messages.insert(0, page.row(m))
            if (bottom) {            // keep the newest in sight: scroll to it on the sent bubble's vertical curve
                list.positionViewAtBeginning()
                const to = list.contentY
                list.contentY = was
                scroll.to = to
                scroll.restart()
                if (from) {
                    page.flying = null
                    const it = list.itemAtIndex(0)
                    if (it)
                        it.flyFrom(from)
                }
            }
            if (!m.is_outgoing)
                page.read([m])
        }
        function onMessageChanged(chatId, oldId, m) {
            if (chatId !== page.chatId)
                return
            for (let i = 0; i < Math.min(messages.count, 50); i++)
                if (messages.get(i).msgId === oldId) {
                    page.remember(m)
                    messages.set(i, page.row(m))
                    return
                }
        }
        function onMessageContent(chatId, id, content) {
            if (chatId !== page.chatId)
                return
            const i = page.indexOf(id)
            if (i >= 0) {
                const s = page.shown(content)
                messages.setProperty(i, "text", s.text)
                messages.setProperty(i, "kind", s.kind)
                const p = page.media(content)
                if (p.file && p.file.id !== (page.files[id] || {}).id) {
                    page.files[id] = p.file
                    messages.setProperty(i, "pic", "")
                    page.loadPic(id)
                }
            }
            if (page.quotes[id]) {
                page.quotes[id].text = store.preview(content)
                page.requote(id)
            }
        }
        function onMessageEdited(chatId, id, date) {
            if (chatId !== page.chatId)
                return
            const i = page.indexOf(id)
            if (i >= 0)
                messages.setProperty(i, "edited", true)
        }
        function onMessagesDeleted(chatId, ids) {
            if (chatId !== page.chatId)
                return
            for (let i = messages.count - 1; i >= 0; i--)
                if (ids.indexOf(messages.get(i).msgId) >= 0)
                    messages.remove(i)
            if (page.editing && ids.indexOf(page.editing.id) >= 0)
                page.cancelCompose()
            if (page.replying && ids.indexOf(page.replying.id) >= 0)
                page.replying = null
        }
    }

    Item {               // the chat itself: what the menu blurs
        id: content
        anchors.fill: parent

        Image {              // the wallpaper: a small picture of the gradient, drawn large
            anchors.fill: parent
            source: "image://wall/" + Theme.wall
            smooth: true
        }

        ListView {
            id: list
            anchors.fill: parent
            z: page.lift ? 2 : 0        // over the field while a sent bubble leaves it (the header stays over all)
            model: messages
            verticalLayoutDirection: ListView.BottomToTop
            cacheBuffer: 800
            maximumFlickVelocity: 6000
            flickDeceleration: 2200
            header: Item { width: 1; height: input.height + 10 }
            footer: Item { width: 1; height: bar.height + 8 }
            onAtYEndChanged: if (atYEnd) page.older()       // the top, in a bottom-to-top list
            // whether it stands at the newest: then it stays there when the field grows or shrinks
            property bool down: true
            onMovementEnded: down = atYBeginning

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
                required property bool edited
                required property var replyId
                required property string quoteName
                required property string quoteText
                required property string picKind
                required property int picW
                required property int picH
                required property string mini
                required property string pic
                required property int dur
                readonly property Item face: bubble
                // a picture: photo, video or GIF in the bubble; sticker and round video without one
                readonly property bool media: picKind !== ""
                readonly property bool bare: picKind === "sticker" || picKind === "round"
                readonly property real aspect: picH / picW
                readonly property real pw: picKind === "round" ? 200 : picKind === "sticker" ? 160 * Math.min(1, 1 / aspect)
                                         : aspect * wide > 360 ? Math.max(150, 360 / aspect) : wide
                readonly property real ph: picKind === "round" ? 200 : picKind === "sticker" ? 160 * Math.min(1, aspect)
                                         : Math.max(110, Math.min(360, aspect * wide))
                readonly property real wide: Math.min(width * 0.72, 270)
                readonly property bool overlaid: media && text === ""     // the time over the picture
                Component.onCompleted: if (media && !pic) page.loadPic(msgId)
                // a run: one sender's messages within 10 minutes of each other. Its first (the
                // top) has the name and more space over it, its last (the bottom) the tail.
                readonly property bool first: page.apart(messages.get(index + 1), senderKey, date)
                readonly property bool last: page.apart(messages.get(index - 1), senderKey, date)
                readonly property real most: width * 0.78
                // the first message of a day has the day over it
                readonly property bool newDay: page.otherDay(messages.get(index + 1), date)
                readonly property real above: (newDay ? 38 : 0) + (first ? 8 : 2)
                width: list.width
                height: bubble.height + above

                Rectangle {
                    visible: item.newDay
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 10
                    width: dayText.implicitWidth + 16; height: 22; radius: 11
                    color: Theme.dayPill
                    Text {
                        id: dayText
                        anchors.centerIn: parent
                        text: item.newDay ? page.dayName(item.date) : ""
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                }

                // a message just sent flies here from where its text was in the field: it starts
                // there (moved by mover's x, y) and comes to rest on Telegram-iOS's two curves
                // (ChatMessageTransitionNode.swift), on the render thread
                Item {
                    id: mover
                    width: item.width; height: item.height
                    Item {
                        id: bubble
                        y: item.above
                        x: item.out ? item.width - width - 8 - 6 : 8 + 6
                        // the time goes in the last line's corner when it fits there, else under it
                        readonly property real stampRoom: stamp.implicitWidth + 8
                        readonly property bool stampUnder: !item.overlaid && body.last + stampRoom > (item.media ? width : item.most) - 24
                        width: item.bare ? item.pw : item.media ? item.pw + 6
                             : Math.min(item.most, Math.max(body.implicitWidth, who.implicitWidth, quote.visible ? quote.wants : 0,
                                                            stampUnder ? stamp.implicitWidth : body.last + stampRoom) + 24)
                        height: item.overlaid ? picture.y + item.ph + (item.bare ? 0 : 3)
                              : body.y + body.height + (stampUnder ? 24 : 8)

                        Rectangle {     // while the stretched picture loads
                            anchors.fill: parent
                            visible: !item.bare && shape.status !== Image.Ready
                            radius: 17
                            color: item.out ? Theme.bubbleOut : Theme.bubbleIn
                        }
                        BorderImage {   // the bubble, stretched from a small picture (tepegram.py Bubble), drawn
                            id: shape       // in device pixels and scaled down: then its borders come out right
                            readonly property real d: Screen.devicePixelRatio
                            x: item.out ? 0 : -6
                            width: (parent.width + 6) * d; height: parent.height * d
                            scale: 1 / d; transformOrigin: Item.TopLeft
                            border { left: (item.out ? 17 : 23) * d; right: (item.out ? 23 : 17) * d; top: 17 * d; bottom: 17 * d }
                            source: "image://bubble/" + (item.out ? "out/" : "in/") + (item.first ? "b/" : "s/") + (item.last ? "t/" : "s/")
                                    + String(item.out ? Theme.bubbleOut : Theme.bubbleIn).slice(1) + "/" + Screen.devicePixelRatio
                            smooth: true
                            visible: !item.bare
                        }

                        // a long press lifts it into the menu; while pressed it sinks a little (iOS)
                        MouseArea {
                            id: hold
                            anchors.fill: parent
                            pressAndHoldInterval: 350
                            onPressed: { rise.stop(); sink.restart() }
                            onReleased: { sink.stop(); rise.restart() }
                            onCanceled: { sink.stop(); rise.restart() }
                            onPressAndHold: page.openMenu(item)
                        }
                        ScaleAnimator { id: sink; target: bubble; to: 0.96; duration: 350; easing.type: Easing.OutQuad }
                        ScaleAnimator { id: rise; target: bubble; to: 1; duration: 150; easing.type: Easing.OutQuad }

                        Text {
                            id: who
                            visible: item.sender !== "" && item.first
                            x: 12; y: 7
                            text: item.sender
                            color: item.tint
                            font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        }
                        Rectangle {     // what it answers: a bar, the name, a line of the text; a tap goes there
                            id: quote
                            visible: item.replyId !== 0
                            readonly property color ink: item.out ? Theme.check : Theme.accent
                            readonly property real wants: Math.max(quoteWho.implicitWidth, Math.min(quoteWhat.implicitWidth, 220)) + 22
                            x: 8
                            y: who.visible ? who.y + who.height + 4 : 8
                            width: bubble.width - 16
                            height: visible ? 40 : 0
                            radius: 6
                            color: Qt.rgba(ink.r, ink.g, ink.b, 0.12)
                            clip: true
                            Rectangle { width: 3; height: parent.height; color: quote.ink }
                            Text {
                                id: quoteWho
                                x: 11; y: 3
                                width: parent.width - 16
                                elide: Text.ElideRight
                                text: item.quoteName
                                color: quote.ink
                                font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                            }
                            Text {
                                id: quoteWhat
                                x: 11; y: 20
                                width: parent.width - 16
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                textFormat: Text.PlainText
                                text: item.quoteText.replace(/\s+/g, " ")
                                color: item.out ? Theme.outText : Theme.inText
                                font.family: Theme.font; font.pixelSize: 14
                            }
                            MouseArea { anchors.fill: parent; onClicked: page.jump(item.replyId) }
                        }
                        Item {          // the picture: Telegram's blurred preview at once, the picture over it when here
                            id: picture
                            visible: item.media
                            x: item.bare ? 0 : 3
                            y: item.bare ? 0 : quote.visible ? quote.y + quote.height + 4 : who.visible ? who.y + who.height + 4 : 3
                            width: item.pw; height: visible ? item.ph : 0
                            readonly property string corner: item.picKind === "round" ? "-1" : item.bare ? "0" : "14"
                            Image {
                                anchors.fill: parent
                                visible: item.mini !== "" && full.status !== Image.Ready
                                asynchronous: true
                                // (in points: Qt asks the provider for these times the pixel ratio)
                                sourceSize: Qt.size(12, 12 * item.ph / item.pw)     // blurred: small is enough
                                source: item.mini ? "image://pic/" + picture.corner + "/" + Math.round(item.pw) + "/mini/" + item.mini : ""
                                smooth: true
                            }
                            Image {
                                id: full
                                anchors.fill: parent
                                asynchronous: true
                                sourceSize: Qt.size(Math.round(item.pw), Math.round(item.ph))
                                source: item.pic ? "image://pic/" + picture.corner + "/" + Math.round(item.pw) + "/" + item.pic : ""
                                opacity: status === Image.Ready ? 1 : 0
                                Behavior on opacity { OpacityAnimator { duration: 150 } }
                            }
                            Rectangle {     // a video or a GIF: play over it, its length in the corner
                                visible: item.picKind === "video" || item.picKind === "gif"
                                anchors.centerIn: parent
                                width: 44; height: 44; radius: 22
                                color: Qt.rgba(0, 0, 0, 0.45)
                                Text { anchors.centerIn: parent; anchors.horizontalCenterOffset: 2; text: "▶"; color: "white"; font.pixelSize: 18 }
                            }
                            Rectangle {
                                visible: item.picKind === "video" || item.picKind === "gif" || item.picKind === "round"
                                x: 6; y: item.picKind === "round" ? parent.height - 26 : 6
                                width: len.implicitWidth + 12; height: 20; radius: 10
                                color: Qt.rgba(0, 0, 0, 0.45)
                                Text {
                                    id: len
                                    anchors.centerIn: parent
                                    text: item.picKind === "gif" ? "GIF" : Math.floor(item.dur / 60) + ":" + String(item.dur % 60).padStart(2, "0")
                                    color: "white"
                                    font.family: Theme.font; font.pixelSize: 12
                                }
                            }
                        }
                        Text {
                            id: body
                            visible: !item.overlaid
                            x: 12
                            y: item.media ? picture.y + picture.height + 5
                             : quote.visible ? quote.y + quote.height + 4 : who.visible ? who.y + who.height + 2 : 8
                            width: item.media ? bubble.width - 24 : Math.min(implicitWidth, item.most - 24)
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            property real last: 0       // the last line's width
                            onLineLaidOut: (line) => { if (line.isLast) last = line.implicitWidth }
                            text: (item.kind ? "[" + item.kind + "] " : "") + item.text
                            color: item.out ? Theme.outText : Theme.inText
                            font.family: Theme.font; font.pixelSize: 16
                        }
                        Rectangle {     // under the time when it is over a picture
                            visible: item.overlaid
                            anchors.fill: stamp; anchors.margins: -3; anchors.leftMargin: -6; anchors.rightMargin: -6
                            radius: height / 2
                            color: Qt.rgba(0, 0, 0, 0.4)
                        }
                        Text {
                            id: stamp
                            anchors.right: parent.right; anchors.rightMargin: item.overlaid ? (item.bare ? 8 : 12) : 10
                            anchors.bottom: parent.bottom; anchors.bottomMargin: item.overlaid ? (item.bare ? 6 : 10) : 6
                            textFormat: Text.StyledText
                            text: (item.views ? item.views + " · " : "") + (item.edited ? "tahrirlandi " : "") + item.time +
                                  (item.out ? (item.sending ? " ◷" : " <font color='" + (item.overlaid ? "white" : Theme.check) + "'>✓</font>") : "")
                            color: item.overlaid ? "white" : item.out ? Theme.outMeta : Theme.inMeta
                            font.family: Theme.font; font.pixelSize: 12
                        }
                    }
                }
                XAnimator { id: flyX; target: mover; to: 0; duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0] }
                YAnimator { id: flyY; target: mover; to: 0; duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.19919, 0.01064, 0.27921, 0.91025, 1.0, 1.0] }
                // start where the text was in the field. Called before the list scrolls to this on
                // the same vertical curve: the two together make one path from there to rest.
                function flyFrom(from) {
                    const here = body.mapToItem(page, 0, 0)
                    mover.x = from.x - here.x
                    mover.y = from.y - here.y
                    page.lift = true
                    landed.restart()
                    flyX.start()
                    flyY.start()
                }
            }
        }

        Rectangle {          // the header: back, the name and what it is
            id: bar
            z: 3
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

        Rectangle {          // the field, with what it answers or edits over it
            id: input
            z: 1
            visible: !page.channel
            anchors.bottom: parent.bottom
            width: parent.width
            height: visible ? compose.height + Math.max(52, field.contentHeight + 26) : 0
            color: Theme.bar
            onHeightChanged: if (list.down && !scroll.running) Qt.callLater(list.positionViewAtBeginning)
            Item {
                id: compose
                width: parent.width
                height: page.replying || page.editing ? 46 : 0
                visible: height > 0
                Rectangle { x: 14; y: 8; width: 2; height: 32; color: Theme.accent }
                Text {
                    x: 26; y: 7
                    width: parent.width - 80
                    elide: Text.ElideRight
                    text: page.editing ? "Tahrirlash" : page.replying ? "Javob: " + page.replying.name : ""
                    color: Theme.accent
                    font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                }
                Text {
                    x: 26; y: 25
                    width: parent.width - 80
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    textFormat: Text.PlainText
                    text: page.replying ? page.replying.text.replace(/\s+/g, " ") : ""
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 14
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    text: "✕"
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 18
                    MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: page.cancelCompose() }
                }
            }
            Rectangle {
                x: 10; y: compose.height + 8
                width: parent.width - 66; height: parent.height - compose.height - 16
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
                Text { anchors.centerIn: parent; text: page.editing ? "✓" : "↑"; color: "white"; font.pixelSize: 20; font.weight: Font.Bold }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -6
                    onClicked: {
                        const t = field.text.trim()
                        if (!t)
                            return
                        if (page.editing) {
                            store.editText(page.chatId, page.editing.id, t)
                            page.editing = null
                            field.text = ""
                            return
                        }
                        const at = field.mapToItem(page, 0, 0)
                        page.flying = { text: t, x: at.x, y: at.y }
                        store.sendText(page.chatId, t, page.replying ? page.replying.id : 0)
                        page.replying = null
                        field.text = ""
                        list.positionViewAtBeginning()
                    }
                }
            }
        }
    }

    MessageMenu {
        id: menu
        behind: content
        ceiling: bar.height
        floor: page.height
    }
}
