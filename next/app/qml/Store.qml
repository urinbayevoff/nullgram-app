// Everything Telegram tells us, kept the way TDLib's own clients keep it:
// updates build the state (chats, users, the main list's order), requests
// answer through "@extra". JavaScript on the UI thread -- no Python.
import QtQuick

QtObject {
    id: store

    property string auth: ""            // TDLib's authorizationState, without the prefix: "WaitPhoneNumber", "Ready", ...
    property string qrLink: ""          // tg://login?token=... while it waits for a scan
    property string passwordHint: ""
    property string error: ""
    property string connection: ""      // "" when connected, else what it is doing ("ulanmoqda...")
    property var me: null

    readonly property ListModel chatList: ListModel {}     // the main list in Telegram's order
    property var chats: ({})
    property var users: ({})
    property var groups: ({})           // "b" + basic group id, "s" + supergroup id
    property var actions: ({})          // chat id -> sender -> what they are doing (TDLib cancels them itself)
    property int seen: 0                // users, groups or actions changed: what reads them binds to this
    property int acting: 0              // actions alone (the chat list binds to this: statuses come often)
    property var _calls: ({})
    property int _seq: 0
    property var _fileChats: ({})       // a chat photo's file id -> chat ids showing it

    signal message(var msg)             // a new message in any chat
    signal messageChanged(var chatId, var oldId, var msg)   // sent: its id is final now
    signal messagesDeleted(var chatId, var ids)
    signal readOutbox(var chatId, var lastRead)

    // ---- talking to TDLib ----------------------------------------------------
    function send(req, done) {
        if (done) {
            _seq += 1
            req["@extra"] = String(_seq)
            _calls[req["@extra"]] = done
        }
        td.send(JSON.stringify(req))
    }

    property Connections _td: Connections {
        target: td
        function onReceived(text) { store.receive(JSON.parse(text)) }
    }

    function receive(u) {
        const extra = u["@extra"]
        if (extra !== undefined) {
            const done = _calls[extra]
            delete _calls[extra]
            if (done)
                done(u)
            return
        }
        const f = handlers[u["@type"]]
        if (f)
            f(u)
    }

    // ---- updates -------------------------------------------------------------
    readonly property var handlers: ({
        updateAuthorizationState: (u) => store.authorization(u.authorization_state),
        updateConnectionState: (u) => {
            const s = u.state["@type"]
            store.connection = s === "connectionStateReady" ? ""
                : s === "connectionStateUpdating" ? "yangilanmoqda..."
                : s === "connectionStateWaitingForNetwork" ? "tarmoq kutilmoqda..." : "ulanmoqda..."
        },
        updateUser: (u) => { store.users[u.user.id] = u.user; store.seen++ },
        updateUserStatus: (u) => {
            const user = store.users[u.user_id]
            if (user) {
                user.status = u.status
                store.seen++
            }
        },
        updateBasicGroup: (u) => { store.groups["b" + u.basic_group.id] = u.basic_group; store.seen++ },
        updateSupergroup: (u) => { store.groups["s" + u.supergroup.id] = u.supergroup; store.seen++ },
        updateChatAction: (u) => {
            const acts = store.actions[u.chat_id] || {}
            const key = JSON.stringify(u.sender_id)
            if (u.action["@type"] === "chatActionCancel")
                delete acts[key]
            else
                acts[key] = { sender: u.sender_id, action: u.action["@type"] }
            store.actions[u.chat_id] = acts
            store.acting++
            store.seen++
        },
        updateNewChat: (u) => {
            const c = u.chat
            c.positions = c.positions || []
            store.chats[c.id] = c
            store.watchPhoto(c)
            store.place(c)
        },
        updateChatTitle: (u) => store.change(u.chat_id, { title: u.title }),
        updateChatPhoto: (u) => {
            store.change(u.chat_id, { photo: u.photo })
            store.watchPhoto(store.chats[u.chat_id])
        },
        updateChatLastMessage: (u) => {
            store.change(u.chat_id, { last_message: u.last_message })
            for (const p of u.positions)
                store.position(u.chat_id, p)
        },
        updateChatPosition: (u) => store.position(u.chat_id, u.position),
        updateChatReadInbox: (u) => store.change(u.chat_id, { unread_count: u.unread_count,
                                                               last_read_inbox_message_id: u.last_read_inbox_message_id }),
        updateChatReadOutbox: (u) => {
            store.change(u.chat_id, { last_read_outbox_message_id: u.last_read_outbox_message_id })
            store.readOutbox(u.chat_id, u.last_read_outbox_message_id)
        },
        updateChatNotificationSettings: (u) => store.change(u.chat_id, { notification_settings: u.notification_settings }),
        updateChatDraftMessage: (u) => {
            store.change(u.chat_id, { draft_message: u.draft_message })
            for (const p of u.positions)
                store.position(u.chat_id, p)
        },
        updateNewMessage: (u) => store.message(u.message),
        updateMessageSendSucceeded: (u) => store.messageChanged(u.message.chat_id, u.old_message_id, u.message),
        updateDeleteMessages: (u) => { if (u.is_permanent) store.messagesDeleted(u.chat_id, u.message_ids) },
        updateFile: (u) => store.file(u.file),
    })

    function authorization(s) {
        auth = s["@type"].replace("authorizationState", "")
        error = ""
        if (auth === "WaitTdlibParameters") {
            send({ "@type": "setTdlibParameters", use_test_dc: td.testDc,
                   database_directory: td.dataDir + "/db", files_directory: td.dataDir + "/files",
                   use_file_database: true, use_chat_info_database: true, use_message_database: true,
                   api_id: td.apiId, api_hash: td.apiHash, system_language_code: "uz",
                   device_model: "OmonullOS", system_version: "ztOS", application_version: "0.7-next" }, check)
        } else if (auth === "WaitPhoneNumber") {
            send({ "@type": "requestQrCodeAuthentication" }, check)
        } else if (auth === "WaitOtherDeviceConfirmation") {
            qrLink = s.link
        } else if (auth === "WaitPassword") {
            passwordHint = s.password_hint || ""
        } else if (auth === "Ready") {
            qrLink = ""
            send({ "@type": "getMe" }, (m) => { store.me = m })
            send({ "@type": "loadChats", chat_list: { "@type": "chatListMain" }, limit: 200 })
        }
    }

    function check(r) {
        if (r["@type"] === "error")
            error = r.message
    }

    function change(id, fields) {
        const c = chats[id]
        if (!c)
            return
        for (const k in fields)
            c[k] = fields[k]
        refresh(c)
    }

    function position(id, p) {
        const c = chats[id]
        if (!c || p.list["@type"] !== "chatListMain")
            return
        c.positions = c.positions.filter((q) => q.list["@type"] !== "chatListMain")
        if (p.order !== "0")
            c.positions.push(p)
        place(c)
    }

    function mainPosition(c) {
        for (const p of c.positions)
            if (p.list["@type"] === "chatListMain")
                return p
        return null
    }

    // orders are int64 written as text: longer is bigger, else compare the text
    function before(a, b) {
        return a.length !== b.length ? a.length > b.length : a > b
    }

    function rowIndex(id) {
        for (let i = 0; i < chatList.count; i++)
            if (chatList.get(i).chatId === id)
                return i
        return -1
    }

    // put a chat where its order says (or out of the list when it has none)
    function place(c) {
        const p = mainPosition(c)
        const at = rowIndex(c.id)
        if (!p) {
            if (at >= 0)
                chatList.remove(at)
            return
        }
        c.order = p.order
        c.pinned = p.is_pinned
        let to = 0
        while (to < chatList.count) {
            const other = chatList.get(to).chatId
            if (other !== c.id && before(c.order, chats[other].order))
                break
            to++
        }
        if (at < 0) {
            chatList.insert(to, row(c))
            return
        }
        if (to > at)
            to--
        if (to !== at)
            chatList.move(at, to, 1)
        chatList.set(to, row(c))
    }

    function refresh(c) {
        const at = rowIndex(c.id)
        if (at >= 0)
            chatList.set(at, row(c))
    }

    // ---- what a row shows ----------------------------------------------------
    function row(c) {
        const m = c.last_message
        let text = m ? preview(m.content) : ""
        let who = ""
        const draft = c.draft_message && c.draft_message.content
        if (draft && draft["@type"] === "draftMessageContentText" && draft.text.text) {
            who = "Qoralama"
            text = draft.text.text
        } else if (m && m.is_outgoing && c.type["@type"] !== "chatTypePrivate") {
            who = "Siz"
        } else if (m && (c.type["@type"] === "chatTypeBasicGroup" ||
                         (c.type["@type"] === "chatTypeSupergroup" && !c.type.is_channel))) {
            who = senderName(m.sender_id, true)
        }
        const muted = c.notification_settings && c.notification_settings.mute_for > 0
        return {
            chatId: c.id, title: c.title, who: who, preview: text.replace(/\s+/g, " "),
            time: m ? stamp(m.date) : "", unread: c.unread_count || 0, muted: muted, pinned: !!c.pinned,
            photo: photoPath(c), letters: letters(c.title), tint: tints[Math.abs(c.id) % tints.length],
            outgoing: !!(m && m.is_outgoing), read: !!(m && m.is_outgoing && m.id <= (c.last_read_outbox_message_id || 0))
        }
    }

    readonly property var tints: ["#ff516a", "#ffa85c", "#a685ff", "#54cb68", "#28c9b7", "#2a9ef1", "#d669ed"]

    function letters(title) {
        const w = (title || "").trim().split(/\s+/)
        return ((w[0] || "").charAt(0) + (w.length > 1 ? w[1].charAt(0) : "")).toUpperCase()
    }

    function senderName(sender, short) {
        if (!sender)
            return ""
        if (sender["@type"] === "messageSenderUser") {
            const u = users[sender.user_id]
            return u ? (short ? u.first_name : (u.first_name + " " + u.last_name).trim()) : ""
        }
        const c = chats[sender.chat_id]
        return c ? c.title : ""
    }

    readonly property var doing: ({
        chatActionTyping: "yozmoqda", chatActionRecordingVoiceNote: "ovozli xabar yozmoqda",
        chatActionUploadingVoiceNote: "ovozli xabar yubormoqda", chatActionRecordingVideoNote: "video xabar yozmoqda",
        chatActionUploadingVideoNote: "video xabar yubormoqda", chatActionRecordingVideo: "video yozmoqda",
        chatActionUploadingVideo: "video yubormoqda", chatActionUploadingPhoto: "rasm yubormoqda",
        chatActionUploadingDocument: "fayl yubormoqda", chatActionChoosingSticker: "stiker tanlamoqda",
        chatActionChoosingLocation: "joylashuv tanlamoqda", chatActionChoosingContact: "kontakt tanlamoqda",
        chatActionStartPlayingGame: "o'ynamoqda", chatActionWatchingAnimations: "ko'rmoqda"
    })

    // the line under a chat's name: what someone is doing in it, else whether the person is
    // online and when they were, or how many are in the group; `now` in seconds
    function status(c, now) {
        if (!c)
            return ""
        const busy = activity(c)
        if (busy)
            return busy
        const t = c.type["@type"]
        if (t === "chatTypeBasicGroup") {
            const g = groups["b" + c.type.basic_group_id]
            return g ? count(g.member_count) + " a'zo" : "guruh"
        }
        if (t === "chatTypeSupergroup") {
            const g = groups["s" + c.type.supergroup_id]
            const what = c.type.is_channel ? "obunachi" : "a'zo"
            return g && g.member_count ? count(g.member_count) + " " + what : c.type.is_channel ? "kanal" : "guruh"
        }
        if (t !== "chatTypePrivate")
            return ""
        const u = users[c.type.user_id]
        if (!u || (me && u.id === me.id))
            return ""
        if (u.id === 777000)
            return "xizmat xabarlari"
        if (u.type["@type"] === "userTypeBot")
            return "bot"
        const s = u.status["@type"]
        if (s === "userStatusOnline")
            return u.status.expires > now ? "onlayn" : lastSeen(u.status.expires, now)
        if (s === "userStatusOffline")
            return lastSeen(u.status.was_online, now)
        return s === "userStatusRecently" ? "yaqinda bo'lgan"
             : s === "userStatusLastWeek" ? "shu hafta bo'lgan"
             : s === "userStatusLastMonth" ? "shu oy bo'lgan" : "anchadan beri bo'lmagan"
    }

    // "yozmoqda...", "Ali yozmoqda...", "2 kishi yozmoqda..." or ""
    function activity(c) {
        const acts = Object.values(c && actions[c.id] || {})
        if (!acts.length)
            return ""
        const what = (doing[acts[0].action] || "yozmoqda") + "..."
        if (c.type["@type"] === "chatTypePrivate")
            return what
        return (acts.length > 1 ? acts.length + " kishi" : senderName(acts[0].sender, true)) + " " + what
    }

    function lastSeen(unix, now) {
        if (now - unix < 60)
            return "hozirgina bo'lgan"
        if (now - unix < 3600)
            return Math.floor((now - unix) / 60) + " daqiqa oldin bo'lgan"
        const d = new Date(unix * 1000), today = new Date(now * 1000)
        if (d.toDateString() === today.toDateString())
            return "bugun " + Qt.formatTime(d, "HH:mm") + " da bo'lgan"
        if (d.toDateString() === new Date(now * 1000 - 86400000).toDateString())
            return "kecha " + Qt.formatTime(d, "HH:mm") + " da bo'lgan"
        return Qt.formatDate(d, "dd.MM.yy") + " da bo'lgan"
    }

    // 12345 -> "12 345"
    function count(n) {
        return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ")
    }

    readonly property var kinds: ({
        messagePhoto: "Rasm", messageVideo: "Video", messageVoiceNote: "Ovozli xabar", messageAudio: "Musiqa",
        messageSticker: "Stiker", messageAnimation: "GIF", messageDocument: "Fayl", messageContact: "Kontakt",
        messageLocation: "Joylashuv", messageVenue: "Joy", messagePoll: "So'rovnoma", messageVideoNote: "Video xabar",
        messageStory: "Hikoya", messageDice: "O'yin", messageCall: "Qo'ng'iroq", messageGame: "O'yin",
        messageInvoice: "To'lov", messageChatAddMembers: "a'zo qo'shildi", messageChatJoinByLink: "guruhga qo'shildi",
        messageChatDeleteMember: "guruhdan chiqdi", messagePinMessage: "xabar qadaldi", messageChatChangeTitle: "nom o'zgardi",
        messageChatChangePhoto: "rasm o'zgardi", messageBasicGroupChatCreate: "guruh yaratildi",
        messageSupergroupChatCreate: "guruh yaratildi", messageContactRegistered: "Telegram'ga qo'shildi"
    })

    // the text a message shows in the list (and a bubble without a picture)
    function preview(content) {
        const t = content["@type"]
        if (t === "messageText")
            return content.text.text
        const caption = content.caption ? content.caption.text : ""
        if (t === "messageSticker" && content.sticker.emoji)
            return content.sticker.emoji + " Stiker"
        const kind = kinds[t] || "Bu turdagi xabar hali yo'q"
        return caption ? kind + ", " + caption : kind
    }

    function stamp(unix) {
        const d = new Date(unix * 1000), now = new Date()
        if (d.toDateString() === now.toDateString())
            return Qt.formatTime(d, "HH:mm")
        if (now - d < 6 * 86400000)
            return ["Yak", "Dush", "Sesh", "Chor", "Pay", "Jum", "Shan"][d.getDay()]
        return Qt.formatDate(d, d.getFullYear() === now.getFullYear() ? "dd.MM" : "dd.MM.yy")
    }

    // ---- pictures --------------------------------------------------------------
    function photoPath(c) {
        const f = c.photo && c.photo.small
        return f && f.local.is_downloading_completed ? "file://" + f.local.path : ""
    }

    function watchPhoto(c) {
        const f = c && c.photo && c.photo.small
        if (!f || f.local.is_downloading_completed)
            return
        const ids = _fileChats[f.id] || []
        if (ids.indexOf(c.id) < 0)
            ids.push(c.id)
        _fileChats[f.id] = ids
        send({ "@type": "downloadFile", file_id: f.id, priority: 1, offset: 0, limit: 0, synchronous: false })
    }

    function file(f) {
        const ids = _fileChats[f.id]
        if (!ids || !f.local.is_downloading_completed)
            return
        delete _fileChats[f.id]
        for (const id of ids) {
            const c = chats[id]
            if (c && c.photo && c.photo.small.id === f.id) {
                c.photo.small = f
                refresh(c)
            }
        }
    }

    // ---- messages --------------------------------------------------------------
    // up to `limit` messages before `from` (0: the newest), newest first. TDLib answers
    // from its database at once and may give fewer: ask again until there are enough.
    function history(chatId, from, limit, done, got) {
        got = got || []
        send({ "@type": "getChatHistory", chat_id: chatId, from_message_id: from, offset: 0,
               limit: limit - got.length, only_local: false }, (r) => {
            const msgs = r.messages || []
            got = got.concat(msgs)
            if (msgs.length === 0 || got.length >= limit)
                done(got)
            else
                store.history(chatId, msgs[msgs.length - 1].id, limit, done, got)
        })
    }

    function sendText(chatId, text) {
        send({ "@type": "sendMessage", chat_id: chatId,
               input_message_content: { "@type": "inputMessageText",
                                        text: { "@type": "formattedText", text: text } } }, check)
    }
}
