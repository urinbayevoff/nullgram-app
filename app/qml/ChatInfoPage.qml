// About a chat (Telegram-iOS's PeerInfoScreen): its picture, name and status, buttons for its
// sound and a search in it, what is known of it (the number, the username, the bio; a group's or
// a channel's description and link), then a group's members (a tap opens a chat with one) and what
// was sent there by kind: pictures and videos in a grid (a tap shows one full screen), files, links,
// voice notes (a tap goes back to the chat, at it).
import QtQuick

SubPage {
    id: page
    title: ""
    property var chatId: 0
    property Item chatPage: null        // the chat under this page (its search, its messages)
    property int changed: 0             // the chat changed (TDLib changes it in place)
    readonly property var chat: (changed, store.seen, store.chats[chatId])
    readonly property string kind: chat ? chat.type["@type"] : ""
    readonly property var user: kind === "chatTypePrivate" ? store.users[chat.type.user_id] : null
    readonly property var group: !chat ? null
        : kind === "chatTypeSupergroup" ? store.groups["s" + chat.type.supergroup_id]
        : kind === "chatTypeBasicGroup" ? store.groups["b" + chat.type.basic_group_id] : null
    property var full: null             // userFullInfo, supergroupFullInfo or basicGroupFullInfo
    property string photo: ""
    property real now: Date.now() / 1000
    readonly property bool saved: store.isSaved(chat)
    readonly property bool isGroup: kind === "chatTypeBasicGroup" || (kind === "chatTypeSupergroup" && !chat.type.is_channel)
    readonly property bool muted: (changed, !!chat && chat.notification_settings.mute_for > 0)
    Connections {
        target: store
        function onChatChanged(id) { if (id === page.chatId) page.changed++ }
    }

    Component.onCompleted: {
        if (!chat)
            return
        const big = chat.photo && chat.photo.big
        if (big)
            store.fetch(big, 8, (path) => page.photo = path)
        const want = user ? { "@type": "getUserFullInfo", user_id: user.id }
            : kind === "chatTypeSupergroup" ? { "@type": "getSupergroupFullInfo", supergroup_id: chat.type.supergroup_id }
            : kind === "chatTypeBasicGroup" ? { "@type": "getBasicGroupFullInfo", basic_group_id: chat.type.basic_group_id } : null
        if (want)
            store.send(want, (r) => { if (r["@type"] !== "error") page.full = r })
        for (const t of tabs)
            if (t.filter)
                count(t)
        load(tabs[0])
        overlay = overlayMaker.createObject(page)
    }
    Timer { interval: 30000; repeat: true; running: true; onTriggered: page.now = Date.now() / 1000 }

    function mute() {
        const n = Object.assign({}, chat.notification_settings)
        n["@type"] = "chatNotificationSettings"
        n.use_default_mute_for = false
        n.mute_for = muted ? 0 : 2147483647
        store.send({ "@type": "setChatNotificationSettings", chat_id: chatId, notification_settings: n }, store.check)
    }
    // back to the chat: searching in it, or at a message
    function search() {
        nav.pop()
        if (chatPage) {
            chatPage.searching = true
            chatPage.focusFind()
        }
    }
    function toMessage(id) {
        nav.pop()
        if (chatPage)
            chatPage.goTo(id)
    }

    // ---- a group's members, then what was sent there by kind ----
    readonly property var tabs: (isGroup ? [{ key: "members", name: "A'zolar" }] : []).concat([
        { key: "media", name: "Media", filter: "searchMessagesFilterPhotoAndVideo" },
        { key: "files", name: "Fayllar", filter: "searchMessagesFilterDocument" },
        { key: "links", name: "Havolalar", filter: "searchMessagesFilterUrl" },
        { key: "voice", name: "Ovozli", filter: "searchMessagesFilterVoiceNote" },
        { key: "music", name: "Musiqa", filter: "searchMessagesFilterAudio" }
    ])
    property var counts: ({})           // tab key -> how many
    property string tab: "media"
    property var found: []              // the shown tab's messages, newest first (members: the online first)
    property bool more: false           // older ones not yet asked
    property bool loading: false
    readonly property var shownTabs: tabs.filter((t) => counts[t.key] > 0)

    function count(t) {
        store.send({ "@type": "getChatMessageCount", chat_id: chatId, filter: { "@type": t.filter },
                     topic_id: null, return_local: false }, (r) => {
            if (r["@type"] === "count")
                page.counted(t.key, r.count)
        })
    }
    function counted(key, n) {
        const c = Object.assign({}, counts)
        c[key] = n
        counts = c
        if (counts[tab] === 0) {        // the first one with something in it
            const first = shownTabs[0]
            if (first)
                load(first)
        }
    }
    function load(t) {
        tab = t.key
        found = []
        more = true
        loading = false
        older()
    }
    function older() {
        if (loading || !more)
            return
        loading = true
        if (tab === "members") {
            moreMembers()
            return
        }
        const t = tabs.find((x) => x.key === tab)
        const from = found.length ? found[found.length - 1].id : 0
        store.send({ "@type": "searchChatMessages", chat_id: chatId, topic_id: null, query: "", sender_id: null,
                     from_message_id: from, offset: 0, limit: 60, filter: { "@type": t.filter } }, (r) => {
            if (page.tab !== t.key)
                return
            if (r["@type"] !== "foundChatMessages")
                console.warn("nullgram: info", t.key, JSON.stringify(r))
            page.loading = false
            const got = (r.messages || []).filter((m) => !page.found.some((f) => f.id === m.id))
            page.found = page.found.concat(got)
            page.more = got.length > 0 && !!r.next_from_message_id && page.found.length < (page.counts[t.key] || Infinity)
        })
    }

    // a supergroup's members 200 at a time (its count comes with them), a basic group's all at once
    function moreMembers() {
        const basic = kind === "chatTypeBasicGroup"
        store.send(basic ? { "@type": "getBasicGroupFullInfo", basic_group_id: chat.type.basic_group_id }
                         : { "@type": "getSupergroupMembers", supergroup_id: chat.type.supergroup_id,
                             filter: { "@type": "supergroupMembersFilterRecent" }, offset: found.length, limit: 200 }, (r) => {
            if (page.tab !== "members")
                return
            page.loading = false
            if (r["@type"] === "error") {       // hidden from us
                console.warn("nullgram: members", r.code, r.message)
                page.more = false
                page.counted("members", 0)
                return
            }
            const key = (m) => m.member_id.user_id || m.member_id.chat_id
            const got = (r.members || []).filter((m) => !page.found.some((f) => key(f) === key(m)))
            page.found = page.found.concat(got).sort((a, b) => page.seenRank(b) - page.seenRank(a))
            const total = basic ? page.found.length : r.total_count
            page.more = !basic && got.length > 0 && page.found.length < total
            page.counted("members", total)
        })
    }
    // the order Telegram lists members in: I, those online, then by when they were last here
    function seenRank(m) {
        const u = m.member_id["@type"] === "messageSenderUser" ? store.users[m.member_id.user_id] : null
        if (!u)
            return 0
        if (store.me && u.id === store.me.id)
            return 4e9
        const s = u.status
        switch (s["@type"]) {
        case "userStatusOnline": return s.expires > now ? 3e9 : s.expires
        case "userStatusOffline": return s.was_online
        case "userStatusRecently": return 3
        case "userStatusLastWeek": return 2
        case "userStatusLastMonth": return 1
        }
        return 0
    }
    property Component chatPageMaker: null
    function chatWith(userId) {
        store.chatWith(userId, (id) => {
            if (!page.chatPageMaker)
                page.chatPageMaker = Qt.createComponent("ChatPage.qml")
            page.nav.push(page.chatPageMaker, { chatId: id })
        })
    }

    // a message's picture for the grid: the smallest size not under the cell, else a video's still
    function cellFile(m) {
        const c = m.content
        if (c["@type"] === "messagePhoto") {
            const sizes = c.photo.sizes
            for (const z of sizes)
                if (z.width >= 240)
                    return z.photo
            return sizes.length ? sizes[sizes.length - 1].photo : null
        }
        const v = c.video
        return v && v.thumbnail && v.thumbnail.format["@type"] === "thumbnailFormatJpeg" ? v.thumbnail.file : null
    }
    function mini(m) {
        const c = m.content
        const t = c["@type"] === "messagePhoto" ? c.photo.minithumbnail : c.video ? c.video.minithumbnail : null
        return t ? t.data : ""
    }
    function clock(s) {
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }
    // the text's first link (a link entity, else one written out)
    function link(m) {
        const t = m.content.text || m.content.caption
        if (!t)
            return ""
        for (const e of t.entities || []) {
            if (e.type["@type"] === "textEntityTypeTextUrl")
                return e.type.url
            if (e.type["@type"] === "textEntityTypeUrl")
                return t.text.substr(e.offset, e.length)
        }
        const w = m.content.link_preview
        return w ? w.url : ""
    }

    // ---- one of the grid full screen (Telegram's gallery) ----
    property Item overlay: null         // the viewer and its note, over the page (not in its list)
    property var shown: null            // what the viewer shows: { file, name } (its ↓ saves it)
    function view(cell) {
        const m = cell.modelData, c = m.content, v = overlay.viewer
        const side = Math.round(grid.side), small = mini(m)
        const src = cell.path ? "image://pic/0/" + side + "/" + cell.path
                  : small ? "image://pic/0/" + side + "/mini/" + small : ""
        if (c["@type"] === "messagePhoto") {
            const big = c.photo.sizes[c.photo.sizes.length - 1]
            shown = { file: big.photo, name: "photo_" + m.id + ".jpg" }
            v.show(cell, big.height / big.width, src, "", m.id)
            store.fetch(big.photo, 32, (path) => { if (page && v.open) v.better(path) })
            return
        }
        const video = c.video
        if (!video || cell.loading)
            return
        shown = { file: video.video, name: video.file_name || "video_" + m.id + ".mp4" }
        const aspect = video.width ? video.height / video.width : 9 / 16
        cell.loading = !video.video.local.is_downloading_completed
        store.fetch(video.video, 32, (path) => {
            cell.loading = false
            if (page && page.nav.topPage === page)
                v.show(cell, aspect, src, path, m.id)
        })
    }
    function save() {
        const s = overlay.viewer.current
        const f = s && s.file ? { file: s.file, name: s.name } : shown
        if (f)
            store.fetch(f.file, 32, (path) => {
                const to = td.save(path, f.name)
                if (page)
                    page.overlay.say(to ? "Saqlandi: Downloads/" + to.split("/").pop() : "Saqlab bo'lmadi")
            })
    }
    // the shell's back: the viewer closes first
    function dismiss() {
        if (overlay && overlay.viewer.open) {
            overlay.viewer.close()
            return true
        }
        return false
    }
    Component {
        id: overlayMaker
        Item {
            anchors.fill: parent
            z: 20
            readonly property alias viewer: viewer
            function say(text) {
                note.text = text
                noteBox.opacity = 1
                noteAway.restart()
            }
            PhotoViewer {
                id: viewer
                store: page.store
                chatId: page.chatId
                locate: (id) => {           // a paged-to one's cell, when it is in the grid
                    const i = page.found.findIndex((m) => m.id === id)
                    return i >= 0 && grid.visible ? cells.itemAt(i) : null
                }
                onSave: page.save()
            }
            Rectangle {
                id: noteBox
                z: 25
                anchors.horizontalCenter: parent.horizontalCenter
                y: 68
                width: Math.min(parent.width - 40, note.implicitWidth + 28); height: note.implicitHeight + 16
                radius: height / 2
                color: Qt.rgba(0, 0, 0, 0.75)
                opacity: 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                Text {
                    id: note
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.parent.width - 68)
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 14
                }
            }
            Timer { id: noteAway; interval: 2200; onTriggered: noteBox.opacity = 0 }
        }
    }

    // ---- the head: picture, name, status ----
    Item {
        width: parent.width; height: 178
        Avatar {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 100; height: 100
            source: page.photo || (page.chat ? store.photoPath(page.chat) : "")
            letters: page.chat ? store.letters(page.chat.title) : ""
            tint: store.tints[Math.abs(page.chatId) % store.tints.length]
            saved: page.saved
        }
        Text {
            x: 20; width: parent.width - 40
            y: 112
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: store.title(page.chat)
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 23; font.weight: Font.DemiBold
        }
        Text {
            x: 20; width: parent.width - 40
            y: 146
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            // (a group's full info counts its members better than the group itself)
            text: page.saved ? "" : page.full && page.full.member_count && !store.activity(page.chat)
                  ? store.count(page.full.member_count) + (page.chat.type.is_channel ? " obunachi" : " a'zo")
                  : (store.seen, store.status(page.chat, page.now))
            color: text === "onlayn" ? Theme.accent : Theme.grey
            font.family: Theme.font; font.pixelSize: 15
        }
    }

    // ---- the buttons ----
    Row {
        x: 16; width: parent.width - 32
        spacing: 8
        Repeater {
            id: buttons
            model: (page.saved ? [] : [{ icon: "bell", name: page.muted ? "ovozni yoqish" : "ovozsiz", act: "mute" }])
                   .concat([{ icon: "search", name: "qidiruv", act: "search" }])
            Rectangle {
                required property var modelData
                width: (parent.width - 8 * (buttons.count - 1)) / buttons.count; height: 58
                radius: 12
                color: hit.pressed ? Theme.highlight : Theme.card
                Icon { anchors.horizontalCenter: parent.horizontalCenter; y: 8; name: parent.modelData.icon; color: Theme.accent }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter; y: 35
                    text: parent.modelData.name
                    color: Theme.accent
                    font.family: Theme.font; font.pixelSize: 12
                }
                MouseArea {
                    id: hit
                    anchors.fill: parent
                    onClicked: parent.modelData.act === "mute" ? page.mute() : page.search()
                }
            }
        }
    }

    // ---- what is known of it ----
    SettingsGroup {
        visible: facts.count > 0
        Repeater {
            id: facts
            model: {
                const out = []
                if (page.saved)
                    return out
                const u = page.user, f = page.full, g = page.group
                if (u && u.phone_number)
                    out.push({ k: "telefon", v: "+" + u.phone_number })
                const names = u ? u.usernames : g ? g.usernames : null
                if (names && names.active_usernames && names.active_usernames.length)
                    out.push(u ? { k: "foydalanuvchi nomi", v: "@" + names.active_usernames.join(", @") }
                               : { k: "havola", v: "t.me/" + names.active_usernames[0] })
                if (f && f.bio && f.bio.text)
                    out.push({ k: "bio", v: f.bio.text })
                if (f && f.description)
                    out.push({ k: "ma'lumot", v: f.description })
                if (f && !(names && names.active_usernames && names.active_usernames.length) && f.invite_link)
                    out.push({ k: "taklif havolasi", v: f.invite_link.invite_link })
                return out
            }
            Item {
                required property var modelData
                required property int index
                width: parent.width; height: value.y + value.height + 10
                Text {
                    x: 16; y: 9
                    text: parent.modelData.k
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 14
                }
                Text {
                    id: value
                    x: 16; y: 29
                    width: parent.width - 32
                    wrapMode: Text.Wrap
                    text: parent.modelData.v
                    color: Theme.accent
                    font.family: Theme.font; font.pixelSize: 16
                }
                Rectangle {
                    visible: parent.index < facts.count - 1
                    x: 16; anchors.bottom: parent.bottom; width: parent.width - 16; height: 0.5; color: Theme.separator
                }
            }
        }
    }

    // ---- what was sent: a tab for each kind there is ----
    Column {
        width: parent.width
        visible: page.shownTabs.length > 0
        spacing: 0
        Flickable {         // the tabs (more than fit: they slide)
            x: 16; width: parent.width - 32; height: 34
            contentWidth: tabRow.width
            clip: true
            Row {
                id: tabRow
                spacing: 6
                Repeater {
                    model: page.shownTabs
                    Rectangle {
                        required property var modelData
                        readonly property bool on: page.tab === modelData.key
                        width: tabText.width + 26; height: 30
                        radius: 15
                        color: on ? Theme.accent : Theme.card
                        Text {
                            id: tabText
                            anchors.centerIn: parent
                            text: parent.modelData.name + "  " + store.count(page.counts[parent.modelData.key])
                            color: parent.on ? "white" : Theme.text
                            font.family: Theme.font; font.pixelSize: 14; font.weight: parent.on ? Font.DemiBold : Font.Normal
                        }
                        MouseArea { anchors.fill: parent; onClicked: if (!parent.on) page.load(parent.modelData) }
                    }
                }
            }
        }
        Item { width: 1; height: 10 }

        Grid {              // pictures and videos, three across
            id: grid
            visible: page.tab === "media"
            width: parent.width
            columns: 3
            spacing: 1.5
            readonly property real side: (width - 2 * spacing) / 3
            Repeater {
                id: cells
                model: grid.visible ? page.found : []
                Item {
                    id: cell
                    required property var modelData
                    width: grid.side; height: grid.side
                    property string path: ""
                    Component.onCompleted: {
                        const f = page.cellFile(modelData)
                        if (f)
                            store.fetch(f, 4, (p) => cell.path = p)
                    }
                    Rectangle { anchors.fill: parent; color: Theme.highlight }
                    Image {
                        anchors.fill: parent
                        visible: full.status !== Image.Ready
                        asynchronous: true
                        sourceSize: Qt.size(12, 12)
                        readonly property string m: page.mini(cell.modelData)
                        source: m ? "image://pic/0/" + Math.round(grid.side) + "/mini/" + m : ""
                    }
                    Image {
                        id: full
                        anchors.fill: parent
                        asynchronous: true
                        sourceSize: Qt.size(Math.round(grid.side), Math.round(grid.side))
                        source: cell.path ? "image://pic/0/" + Math.round(grid.side) + "/" + cell.path : ""
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { OpacityAnimator { duration: 150 } }
                    }
                    Rectangle {     // a video's length
                        visible: cell.modelData.content["@type"] === "messageVideo"
                        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 5
                        width: len.width + 10; height: 18; radius: 9
                        color: Qt.rgba(0, 0, 0, 0.5)
                        Text {
                            id: len
                            anchors.centerIn: parent
                            text: visible && cell.modelData.content.video ? page.clock(cell.modelData.content.video.duration) : ""
                            color: "white"
                            font.family: Theme.font; font.pixelSize: 11
                        }
                    }
                    Rectangle {     // a video coming down before it plays
                        anchors.fill: parent
                        visible: cell.loading
                        color: Qt.rgba(0, 0, 0, 0.35)
                    }
                    property bool loading: false
                    MouseArea { anchors.fill: parent; onClicked: page.view(cell) }
                }
            }
        }

        SettingsGroup {     // a group's members: a picture, the name, when last here, owner or admin
            visible: page.tab === "members" && page.found.length > 0
            Repeater {
                id: people
                model: page.tab === "members" ? page.found : []
                Rectangle {
                    id: person
                    required property var modelData
                    required property int index
                    readonly property var who: modelData.member_id
                    readonly property var u: who["@type"] === "messageSenderUser" ? store.users[who.user_id] : null
                    readonly property bool mine: !!u && !!store.me && u.id === store.me.id
                    readonly property string name: store.senderName(who, false) || "O'chirilgan hisob"
                    readonly property string role: {
                        const s = modelData.status
                        return s["@type"] === "chatMemberStatusCreator" ? s.custom_title || "egasi"
                             : s["@type"] === "chatMemberStatusAdministrator" ? s.custom_title || "admin" : ""
                    }
                    width: parent.width; height: 56
                    color: personHit.pressed ? Theme.highlight : "transparent"
                    property string photo: ""
                    Component.onCompleted: {
                        if (u)
                            store.userPhoto(u, (p) => person.photo = p)
                        else if (store.chats[who.chat_id] && store.chats[who.chat_id].photo)
                            store.fetch(store.chats[who.chat_id].photo.small, 1, (p) => person.photo = p)
                    }
                    Avatar {
                        x: 14; y: 8
                        width: 40; height: 40
                        source: person.photo
                        letters: store.letters(person.name)
                        tint: store.tints[Math.abs(person.who.user_id || person.who.chat_id) % store.tints.length]
                    }
                    Text {
                        x: 66; y: 8
                        width: parent.width - x - roleText.width - 24
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignLeft     // (an Arabic name too, as Telegram lists it)
                        text: person.name
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                    }
                    Text {
                        x: 66; y: 30
                        width: parent.width - x - 14
                        elide: Text.ElideRight
                        text: person.mine ? "onlayn" : (store.seen, store.userStatus(person.u, page.now))
                        color: text === "onlayn" ? Theme.accent : Theme.grey
                        font.family: Theme.font; font.pixelSize: 14
                    }
                    Text {
                        id: roleText
                        anchors.right: parent.right; anchors.rightMargin: 14; y: 10
                        text: person.role
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 14
                    }
                    Rectangle {
                        visible: person.index < people.count - 1
                        x: 66; anchors.bottom: parent.bottom; width: parent.width - 66; height: 0.5; color: Theme.separator
                    }
                    MouseArea {
                        id: personHit
                        anchors.fill: parent
                        enabled: !!person.u && !person.mine
                        onClicked: page.chatWith(person.u.id)
                    }
                }
            }
        }

        SettingsGroup {     // files, links, voice notes, music: a row each
            visible: page.tab !== "media" && page.tab !== "members" && page.found.length > 0
            Repeater {
                id: rows
                model: page.tab !== "media" && page.tab !== "members" ? page.found : []
                Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property var c: modelData.content
                    width: parent.width; height: 60
                    color: rowHit.pressed ? Theme.highlight : "transparent"
                    readonly property var parts: {
                        const t = c["@type"]
                        if (t === "messageDocument")
                            return [c.document.file_name || "Fayl", store.size(c.document.document.size)]
                        if (t === "messageVoiceNote")
                            return [store.origin(modelData.forward_info) || (modelData.is_outgoing ? "Siz"
                                    : store.senderName(modelData.sender_id, false) || store.title(page.chat)),
                                    "Ovozli xabar · " + page.clock(c.voice_note.duration)]
                        if (t === "messageAudio")
                            return [c.audio.title || c.audio.file_name || "Musiqa", (c.audio.performer || "") + (c.audio.performer ? " · " : "") + page.clock(c.audio.duration)]
                        const text = c.text || c.caption
                        return [page.link(modelData) || "havola", text ? text.text.replace(/\s+/g, " ") : ""]
                    }
                    Text {
                        x: 16; y: 10; width: parent.width - 90
                        elide: Text.ElideMiddle
                        text: row.parts[0]
                        color: page.tab === "links" ? Theme.accent : Theme.text
                        font.family: Theme.font; font.pixelSize: 16
                    }
                    Text {
                        x: 16; y: 33; width: parent.width - 32
                        elide: Text.ElideRight
                        text: row.parts[1]
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 13
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 14; y: 12
                        text: store.stamp(row.modelData.date)
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 13
                    }
                    Rectangle {
                        visible: row.index < rows.count - 1
                        x: 16; anchors.bottom: parent.bottom; width: parent.width - 16; height: 0.5; color: Theme.separator
                    }
                    MouseArea { id: rowHit; anchors.fill: parent; onClicked: page.toMessage(row.modelData.id) }
                }
            }
        }
        Text {
            visible: page.more
            width: parent.width; height: 44
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            text: page.loading ? "yuklanmoqda..." : "Yana"
            color: Theme.accent
            font.family: Theme.font; font.pixelSize: 15
            MouseArea { anchors.fill: parent; onClicked: page.older() }
        }
    }
}
