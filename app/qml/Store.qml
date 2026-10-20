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
    property int unreadChats: 0         // the main list's chats with unread messages, not muted

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
    signal messageContent(var chatId, var id, var content)
    signal messageEdited(var chatId, var id, var date)
    signal readOutbox(var chatId, var lastRead)
    signal chatChanged(var chatId)      // fields of a chat changed (an open chat page reads them again)
    signal fileUpdated(var f)           // a file is coming or going: how far, or done

    // ---- talking to TDLib ----------------------------------------------------
    function send(req, done) {
        if (done) {
            _seq += 1
            req["@extra"] = String(_seq)
            _calls[req["@extra"]] = done
        }
        if (td)         // (gone while the app quits)
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
        updateMessageContent: (u) => store.messageContent(u.chat_id, u.message_id, u.new_content),
        updateMessageEdited: (u) => store.messageEdited(u.chat_id, u.message_id, u.edit_date),
        updateDeleteMessages: (u) => { if (u.is_permanent) store.messagesDeleted(u.chat_id, u.message_ids) },
        updateFile: (u) => store.file(u.file),
        updateUnreadChatCount: (u) => {
            if (u.chat_list["@type"] === "chatListMain")
                store.unreadChats = u.unread_unmuted_count
        },
    })

    function authorization(s) {
        auth = s["@type"].replace("authorizationState", "")
        error = ""
        if (auth === "WaitTdlibParameters") {
            send({ "@type": "setTdlibParameters", use_test_dc: td.testDc,
                   database_directory: td.dataDir + "/db", files_directory: td.dataDir + "/files",
                   use_file_database: true, use_chat_info_database: true, use_message_database: true,
                   api_id: td.apiId, api_hash: td.apiHash, system_language_code: "uz",
                   device_model: "OmonullOS", system_version: "ztOS", application_version: "Nullgram 0.8" }, check)
        } else if (auth === "WaitPhoneNumber" && td.testPhone) {
            send({ "@type": "setAuthenticationPhoneNumber", phone_number: td.testPhone }, check)
        } else if (auth === "WaitCode" && td.testPhone) {
            send({ "@type": "checkAuthenticationCode",
                   code: td.testPhone.charAt(5).repeat(s.code_info.type.length || 5) }, check)
        } else if (auth === "WaitRegistration" && td.testPhone) {
            send({ "@type": "registerUser", first_name: "Sinov", last_name: td.testPhone.slice(-4) }, check)
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
        chatChanged(id)
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
        return userStatus(users[c.type.user_id], now)
    }

    // a person's: "onlayn", "bugun 14:05 da bo'lgan", "bot", ...
    function userStatus(u, now) {
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
        messageSupergroupChatCreate: "guruh yaratildi", messageContactRegistered: "Telegram'ga qo'shildi",
        messageChatDeletePhoto: "rasm o'chirildi", messageChatJoinByRequest: "guruhga qo'shildi",
        messageChatUpgradeTo: "superguruhga aylandi", messageChatUpgradeFrom: "superguruhga aylandi",
        messageChatSetMessageAutoDeleteTime: "avto-o'chirish o'zgardi", messageScreenshotTaken: "skrinshot olindi",
        messageChatSetTheme: "mavzu o'zgardi", messageChatSetBackground: "fon o'zgardi",
        messageForumTopicCreated: "mavzu yaratildi", messageForumTopicEdited: "mavzu o'zgardi",
        messageVideoChatStarted: "video chat boshlandi", messageVideoChatEnded: "video chat tugadi",
        messageVideoChatScheduled: "video chat rejalashtirildi", messageInviteVideoChatParticipants: "video chatga taklif",
        messageExpiredPhoto: "Rasm muddati tugadi", messageExpiredVideo: "Video muddati tugadi",
        messageExpiredVoiceNote: "Ovozli xabar muddati tugadi", messageExpiredVideoNote: "Video xabar muddati tugadi",
        messagePaidMedia: "Pullik media", messageGift: "Sovg'a", messageUpgradedGift: "Sovg'a", messageRefundedUpgradedGift: "Sovg'a",
        messageGiftedPremium: "Premium sovg'a", messagePremiumGiftCode: "Premium sovg'a", messageGiftedStars: "Yulduzlar sovg'a",
        messageGiveaway: "Konkurs", messageGiveawayCreated: "Konkurs", messageGiveawayCompleted: "Konkurs yakunlandi",
        messageGiveawayWinners: "Konkurs g'oliblari", messageChatBoost: "Kanal kuchaytirildi",
        messagePaymentSuccessful: "To'lov qilindi", messageProximityAlertTriggered: "Yaqinlashdi",
        messageSuggestProfilePhoto: "Profil rasmi taklifi", messageCustomServiceAction: "Xizmat xabari",
        messageBotWriteAccessAllowed: "botga ruxsat berildi", messageWebAppDataSent: "ilova ma'lumot yubordi",
        messageUsersShared: "Kontakt ulashildi", messageChatShared: "Chat ulashildi", messageChecklist: "Ro'yxat",
        messageUnsupported: "Bu Telegram versiyasida ochilmaydi", messageManagedBotCreated: "bot yaratildi"
    })

    // the text of a message that is text: plain, one emoji alone (TDLib makes it messageAnimatedEmoji),
    // or a rich message (its blocks' words, a paragraph a line); null for the rest
    function plain(content) {
        const t = content["@type"]
        if (t === "messageText")
            return content.text.text
        if (t === "messageAnimatedEmoji")
            return content.emoji
        if (t === "messageRichMessage") {
            const lines = []
            for (const b of content.message.blocks) {
                const words = []
                words_of(b, words)
                if (words.length)
                    lines.push(words.join(""))
            }
            return lines.join("\n")
        }
        return null
    }
    // every richTextPlain's string under a page block, in order
    function words_of(v, out) {
        if (Array.isArray(v)) {
            for (const x of v)
                words_of(x, out)
        } else if (v && typeof v === "object") {
            if (v["@type"] === "richTextPlain")
                out.push(v.text)
            else
                for (const k in v)
                    if (k !== "@type")
                        words_of(v[k], out)
        }
    }

    // a kind we have no word for yet: said once in the log, so it can be added
    property var _unknown: ({})
    function kindOf(t) {
        if (kinds[t])
            return kinds[t]
        if (!_unknown[t]) {
            _unknown[t] = true
            console.warn("nullgram: no word for", t)
        }
        return "Bu turdagi xabar hali yo'q"
    }

    // the text a message shows in the list (and a bubble without a picture)
    function preview(content) {
        const t = content["@type"]
        const words = plain(content)
        if (words !== null)
            return words
        const caption = content.caption ? content.caption.text : ""
        if (t === "messageSticker" && content.sticker.emoji)
            return content.sticker.emoji + " Stiker"
        const kind = kindOf(t)
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
        return f && f.local.is_downloading_completed ? f.local.path : ""	// a path: image://round/ takes it as one
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

    // a file's local path to `done`, now or once TDLib has it (one download however many ask)
    property var _waiters: ({})
    function fetch(f, priority, done) {
        if (f.local.is_downloading_completed) {
            done(f.local.path)
            return
        }
        const w = _waiters[f.id] || []
        w.push(done)
        _waiters[f.id] = w
        if (w.length === 1)
            send({ "@type": "downloadFile", file_id: f.id, priority: priority, offset: 0, limit: 0, synchronous: false })
    }

    function file(f) {
        fileUpdated(f)
        const w = _waiters[f.id]
        if (w && f.local.is_downloading_completed) {
            delete _waiters[f.id]
            for (const done of w)
                done(f.local.path)
        }
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

    // how far a file is, 0..1, while it comes down or goes up; -1 when neither
    function progress(f) {
        const all = f.size || f.expected_size
        if (f.local.is_downloading_active)
            return all ? f.local.downloaded_size / all : 0
        if (f.remote.is_uploading_active)
            return all ? f.remote.uploaded_size / all : 0
        return -1
    }

    function stopFile(f) {
        delete _waiters[f.id]
        send({ "@type": "cancelDownloadFile", file_id: f.id, only_if_pending: false })
    }

    // 1234567 -> "1.2 MB"
    function size(n) {
        return n < 1024 ? n + " B" : n < 1048576 ? Math.round(n / 1024) + " KB"
             : n < 1073741824 ? (n / 1048576).toFixed(1) + " MB" : (n / 1073741824).toFixed(2) + " GB"
    }

    // ---- messages --------------------------------------------------------------
    // up to `limit` messages before `from` (0: the newest), newest first. TDLib answers
    // from its database at once and may give fewer: ask again until there are enough.
    // `failed`: TDLib said no (offline, too many asks) -- that is not the beginning of the chat
    function history(chatId, from, limit, done, got) {
        got = got || []
        send({ "@type": "getChatHistory", chat_id: chatId, from_message_id: from, offset: 0,
               limit: limit - got.length, only_local: false }, (r) => {
            if (r["@type"] === "error") {
                console.warn("nullgram: getChatHistory", chatId, from, r.code, r.message)
                done(got, true)
                return
            }
            const msgs = r.messages || []
            got = got.concat(msgs)
            if (msgs.length === 0 || got.length >= limit)
                done(got, false)
            else
                store.history(chatId, msgs[msgs.length - 1].id, limit, done, got)
        })
    }

    function sendText(chatId, text, replyTo) {
        const req = { "@type": "sendMessage", chat_id: chatId,
                      input_message_content: { "@type": "inputMessageText",
                                               text: { "@type": "formattedText", text: text } } }
        if (replyTo)
            req.reply_to = { "@type": "inputMessageReplyToMessage", message_id: replyTo }
        send(req, check)
    }

    // files from the phone (td.recent's): pictures and videos together as an album when there are
    // several, the rest one by one; the field's words go under the first
    function sendFiles(chatId, files, caption, replyTo) {
        const text = { "@type": "formattedText", text: caption || "" }
        const contents = files.map((f, k) => {
            const local = { "@type": "inputFileLocal", path: f.path }
            const c = k === 0 ? text : null
            if (f.kind === "photo" && !f.path.toLowerCase().endsWith(".gif"))
                return { "@type": "inputMessagePhoto", photo: local, width: f.w, height: f.h, caption: c }
            if (f.kind === "video") {
                const v = td.probe(f.path)
                return { "@type": "inputMessageVideo", video: local, duration: v.duration, width: v.width,
                         height: v.height, supports_streaming: true, caption: c }
            }
            if (f.kind === "audio")
                return { "@type": "inputMessageAudio", audio: local, duration: td.probe(f.path).duration, caption: c }
            return { "@type": "inputMessageDocument", document: local, caption: c }
        })
        const reply = replyTo ? { "@type": "inputMessageReplyToMessage", message_id: replyTo } : null
        const album = contents.filter((c) => c["@type"] === "inputMessagePhoto" || c["@type"] === "inputMessageVideo")
        const rest = contents.filter((c) => album.indexOf(c) < 0)
        if (album.length > 1) {
            for (let k = 0; k < album.length; k += 10)
                send({ "@type": "sendMessageAlbum", chat_id: chatId, reply_to: k ? null : reply,
                       input_message_contents: album.slice(k, k + 10) }, check)
        } else {
            rest.unshift(...album)
        }
        for (const c of rest)
            send({ "@type": "sendMessage", chat_id: chatId, reply_to: reply, input_message_content: c }, check)
    }

    function sendVoice(chatId, path, duration, waveform, replyTo) {
        send({ "@type": "sendMessage", chat_id: chatId,
               reply_to: replyTo ? { "@type": "inputMessageReplyToMessage", message_id: replyTo } : null,
               input_message_content: { "@type": "inputMessageVoiceNote",
                                        voice_note: { "@type": "inputFileLocal", path: path },
                                        duration: duration, waveform: waveform } }, check)
    }

    // a text that is one to three emoji and nothing else: how many (it shows big, without a
    // bubble, as Telegram does), else 0
    function emojiCount(t) {
        if (!t || t.length > 48)
            return 0
        let n = 0, joined = false, flags = 0
        for (const ch of t) {
            const c = ch.codePointAt(0)
            if (c === 0x200d) {
                joined = true
                continue
            }
            if (c === 0xfe0f || c === 0xfe0e || c === 0x20e3 || (c >= 0x1f3fb && c <= 0x1f3ff) || (c >= 0xe0020 && c <= 0xe007f))
                continue
            if (c >= 0x1f1e6 && c <= 0x1f1ff) {     // a flag is two of these
                if (flags++ % 2 === 0)
                    n++
                continue
            }
            if (!pictograph(c))
                return 0
            if (!joined)
                n++
            joined = false
        }
        return n <= 3 ? n : 0
    }
    function pictograph(c) {
        return (c >= 0x1f000 && c <= 0x1faff) || (c >= 0x2600 && c <= 0x27bf) || (c >= 0x2300 && c <= 0x23ff)
            || (c >= 0x2b00 && c <= 0x2bff) || (c >= 0x2190 && c <= 0x21ff) || (c >= 0x25a0 && c <= 0x25ff)
            || [0xa9, 0xae, 0x203c, 0x2049, 0x2122, 0x2139, 0x24c2, 0x3030, 0x303d, 0x3297, 0x3299].indexOf(c) >= 0
    }

    function editText(chatId, messageId, text) {
        send({ "@type": "editMessageText", chat_id: chatId, message_id: messageId,
               input_message_content: { "@type": "inputMessageText",
                                        text: { "@type": "formattedText", text: text } } }, check)
    }

    function deleteMessages(chatId, ids, everyone) {
        send({ "@type": "deleteMessages", chat_id: chatId, message_ids: ids, revoke: everyone }, check)
    }

    // ---- search ----------------------------------------------------------------
    // Uzbek Cyrillic as its Latin, so "Шавкат" is found by "shavkat" and the other way round;
    // small letters, no apostrophes (o'/oʻ/o` all one)
    readonly property var _latin: ({
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo", "ж": "j", "з": "z", "и": "i",
        "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t",
        "у": "u", "ф": "f", "х": "x", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sh", "ъ": "", "ы": "i", "ь": "",
        "э": "e", "ю": "yu", "я": "ya", "ў": "o", "қ": "q", "ғ": "g", "ҳ": "h",
        "'": "", "`": "", "ʻ": "", "ʼ": "", "‘": "", "’": ""
    })
    function fold(text) {
        let out = ""
        for (const ch of (text || "").toLowerCase()) {
            const l = _latin[ch]
            out += l === undefined ? ch : l
        }
        return out
    }

    // chats for a query, as fast as each comes: ours by name from what is loaded (at once), then
    // TDLib's (its database, then the server's), then public ones; `done(kind, ids)` each time,
    // kind "chats" or "global". A newer query makes the older answers be dropped (by `asked`).
    property int _query: 0
    function searchChats(q, done) {
        const asked = ++_query
        const f = fold(q)
        const local = []
        for (const id in chats) {
            const c = chats[id]
            const u = c.type["@type"] === "chatTypePrivate" ? users[c.type.user_id] : null
            const names = fold(c.title) + " " + (u && u.usernames ? fold(u.usernames.active_usernames.join(" ")) : "")
            if (c.positions.length && names.indexOf(f) >= 0)
                local.push(c.id)
        }
        local.sort((a, b) => before(chats[a].order || "0", chats[b].order || "0") ? -1 : 1)
        done("chats", local.slice(0, 50))
        const mine = local.slice()
        const more = (r) => {
            if (asked !== _query || !r.chat_ids)
                return
            for (const id of r.chat_ids)
                if (mine.indexOf(id) < 0 && chats[id])
                    mine.push(id)
            done("chats", mine.slice(0, 50))
        }
        send({ "@type": "searchChats", query: q, limit: 50 }, more)
        send({ "@type": "searchChatsOnServer", query: q, limit: 50 }, more)
        if (q.replace(/^@/, "").length >= 4)
            send({ "@type": "searchPublicChats", query: q.replace(/^@/, "") }, (r) => {
                if (asked === _query && r.chat_ids)
                    done("global", r.chat_ids.filter((id) => mine.indexOf(id) < 0 && chats[id]))
            })
    }

    // messages with the query in every chat, newest first: `done(messages)`
    function searchMessages(q, done) {
        const asked = _query
        send({ "@type": "searchMessages", chat_list: null, query: q, offset: "", limit: 40,
               filter: null, chat_type_filter: null, min_date: 0, max_date: 0 }, (r) => {
            if (asked === _query)
                done(r.messages || [])
        })
    }

    // ---- contacts --------------------------------------------------------------
    // the contacts, by name: `done([user])` (users not yet known are asked for first)
    function contacts(done) {
        send({ "@type": "getContacts" }, (r) => {
            const ids = r.user_ids || []
            let left = 0
            const finish = () => {
                const list = ids.map((id) => users[id]).filter((u) => u)
                list.sort((a, b) => fold(a.first_name + " " + a.last_name) < fold(b.first_name + " " + b.last_name) ? -1 : 1)
                done(list)
            }
            for (const id of ids)
                if (!users[id]) {
                    left++
                    send({ "@type": "getUser", user_id: id }, (u) => {
                        if (u["@type"] === "user")
                            users[u.id] = u
                        if (--left === 0)
                            finish()
                    })
                }
            if (left === 0)
                finish()
        })
    }

    // a person's chat (made if there is none yet): `done(chatId)`
    function chatWith(userId, done) {
        send({ "@type": "createPrivateChat", user_id: userId, force: false }, (c) => {
            if (c["@type"] === "chat") {
                if (!chats[c.id]) {
                    c.positions = c.positions || []
                    chats[c.id] = c
                }
                done(c.id)
            }
        })
    }

    // a user's small picture's path, now or later: `done(path)`
    function userPhoto(u, done) {
        if (u && u.profile_photo && u.profile_photo.small)
            fetch(u.profile_photo.small, 1, done)
    }
}
