// One chat: the messages from the bottom up, a header over them and the field
// under them. It is `ready` once its newest messages are laid out, so the push
// moves a finished page. A long press on a message opens its menu (MessageMenu):
// reply, copy, edit, save, delete. Media: a GIF plays in its bubble, a video full screen
// (PhotoViewer), a voice note or a song with the page's one player, a file comes down with a
// ring round it; the clip sends pictures and files (AttachSheet), the mic held records a voice note.
import QtQuick
import QtQuick.Window
import QtMultimedia

Page {
    id: page
    required property var chatId
    property var target: 0              // open at this message (found by search) and light it up
    property var flashId: 0
    readonly property var chat: store.chats[chatId]
    readonly property bool group: chat && (chat.type["@type"] === "chatTypeBasicGroup" ||
                                           (chat.type["@type"] === "chatTypeSupergroup" && !chat.type.is_channel))
    readonly property bool channel: chat && chat.type["@type"] === "chatTypeSupergroup" && chat.type.is_channel
    // a channel we may write in (its owner, or an admin who posts); the others have its bar instead of the field
    readonly property bool canPost: {
        if (outside)
            return false
        if (!channel)
            return true
        const g = (store.seen, store.groups["s" + chat.type.supergroup_id])
        const st = g ? g.status : null
        return !!st && (st["@type"] === "chatMemberStatusCreator" ||
                        (st["@type"] === "chatMemberStatusAdministrator" && st.rights.can_post_messages))
    }
    // a channel or a group we are not in (opened by a link): «Qo'shilish» in the bar
    readonly property bool outside: {
        if (!chat || thread || chat.type["@type"] !== "chatTypeSupergroup")
            return false
        const g = (store.seen, store.groups["s" + chat.type.supergroup_id])
        return !!g && g.status["@type"] === "chatMemberStatusLeft"
    }
    // a post's comments: chatId is then the channel's discussion group and this its thread there
    property var thread: 0
    readonly property real foot: selecting ? pickBar.height : searching ? findBar.height : input.visible ? input.height : chanBar.height    // what is under the messages
    function isMuted() {
        const n = chat ? chat.notification_settings : null
        return !!n && n.mute_for > 0
    }
    property bool muted: isMuted()
    // a channel's posts without a sound for its subscribers (the field's 🔔, kept per channel as Telegram does)
    readonly property bool silent: channel && Prefs.silent.split(",").indexOf(String(chatId)) >= 0
    function setSilent(on) {
        const ids = Prefs.silent.split(",").filter((x) => x && x !== String(chatId))
        if (on)
            ids.push(String(chatId))
        Prefs.silent = ids.join(",")
        toast(on ? "Obunachilar xabarni ovozsiz oladi" : "Obunachilar xabarni ovoz bilan oladi")
    }
    // who asked to join by a link that needs an admin (the panel under the header; × hides it until more ask)
    readonly property var asking: chat && chat.pending_join_requests && chat.pending_join_requests.total_count > 0
                                  ? chat.pending_join_requests : null
    property int askingHidden: 0
    // the field's ⏱: messages here go by themselves after a while (setChatMessageAutoDeleteTime); in a
    // private chat anyone sets it, in a group or channel its owner or an admin who may change its info
    readonly property int autoDelete: chat ? chat.message_auto_delete_time || 0 : 0
    readonly property bool canAutoDelete: {
        if (!chat || thread)
            return false
        const t = chat.type["@type"]
        if (t === "chatTypePrivate")
            return !store.isSaved(chat)
        const g = (store.seen, store.groups[(t === "chatTypeBasicGroup" ? "b" + chat.type.basic_group_id : "s" + chat.type.supergroup_id)])
        const st = g ? g.status : null
        return !!st && (st["@type"] === "chatMemberStatusCreator" ||
                        (st["@type"] === "chatMemberStatusAdministrator" && st.rights.can_change_info))
    }
    // the chat in Uzbek (the panel's "O'zbek tiliga tarjima qilish", Telegram-iOS's whole-chat translation):
    // each message as its row is made (only what is in sight is asked for), back as it was when turned off
    readonly property bool translatable: !!chat && !!chat.is_translatable && !thread
    property bool translating: false
    property var originals: ({})        // message id -> its own words { text, rich }, while shown translated
    property var translations: ({})     // message id -> the Uzbek { text, rich }, asked once
    property var ones: ({})             // message id -> true: that one alone in Uzbek (its menu's "Tarjima qilish")
    function translateId(id) {
        const i = indexOf(id)
        const one = !!ones[id]
        if (i < 0 || !(translating || one))
            return
        const done = translations[id]
        if (done === null) {
            if (one && !translating) {
                delete ones[id]
                toast("Bu xabar o'zbekcha")
            }
            return
        }
        if (done !== undefined) {
            if (originals[id] === undefined)
                originals[id] = { text: messages.get(i).text, rich: messages.get(i).rich }
            if (done.text !== undefined)
                put(i, done)
            return
        }
        if (!messages.get(i).text)
            return
        translations[id] = {}       // (asked: not again while it comes)
        store.send({ "@type": "translateMessageText", chat_id: chatId, message_id: id, to_language_code: "uz" }, (r) => {
            if (r["@type"] !== "formattedText") {
                delete page.translations[id]
                if (page.ones[id] && !page.translating) {
                    delete page.ones[id]
                    page.toast("Tarjima qilib bo'lmadi" + (r.message ? ": " + r.message : ""))
                } else if (page.translating) {
                    page.translating = false
                    page.untranslate()
                    page.toast("Tarjima qilib bo'lmadi" + (r.message ? ": " + r.message : ""))
                }
                return
            }
            if (!r.text.trim()) {       // (Telegram sends nothing back for what is in Uzbek already)
                page.translations[id] = null
                page.translateId(id)
                return
            }
            // (the translator sometimes leaves the original's markup in the words: **, </b>; where it
            // has formatting of its own the words stay, its places in them would move)
            page.translations[id] = r.entities.length ? { text: r.text, rich: store.rich(r, false) }
                : { text: r.text.replace(/<\/?(b|i|u|s|code|pre)>/g, "").replace(/\*\*|__/g, ""), rich: "" }
            page.translateId(id)
        })
    }
    function put(i, words) {
        messages.setProperty(i, "text", words.text)
        messages.setProperty(i, "rich", words.rich)
    }
    function untranslateOne(id) {
        delete ones[id]
        const i = indexOf(id)
        if (i >= 0 && originals[id] !== undefined)
            put(i, originals[id])
        delete originals[id]
    }
    function untranslate() {
        ones = {}
        for (const id in originals) {
            const i = indexOf(Number(id))
            if (i >= 0)
                put(i, originals[id])
        }
        originals = {}
    }
    function setTranslating(on) {
        translating = on
        if (!on)
            untranslate()
        // (on: each row in sight asks for its own, see the delegate's translated)
    }
    function setAutoDelete(secs) {
        store.send({ "@type": "setChatMessageAutoDeleteTime", chat_id: chatId, message_auto_delete_time: secs }, (r) => {
            if (r["@type"] === "error")
                toast("O'zgartirib bo'lmadi")
            else
                toast(secs ? "Yangi xabarlar " + store.lasting(secs) + "dan keyin o'chadi" : "Avtomatik o'chirish o'chirildi")
        })
    }
    readonly property bool askingShown: !!asking && asking.total_count !== askingHidden && !thread
    property string threadOf: ""        // the channel's name, under "Izohlar"
    property var threadRoot: []         // the post itself (its copy in the group): over the oldest comment
    // the post under the comments once they have all come (TDLib's thread history leaves it out)
    function withRoot(got, done) {
        if (!thread || !done)
            return got
        const root = threadRoot.filter((m) => !got.some((g) => g.id === m.id))
        threadRoot = []
        return got.concat(root)
    }
    ready: false
    property bool loading: false
    property bool more: true
    // opened at the first unread message: the newest are not loaded yet (they come as it is
    // scrolled down, or all at once from ↓), and new ones wait for them
    property bool gap: false
    property bool newering: false
    property var firstUnread: 0         // the "O'qilmagan xabarlar" bar goes over this message
    property var readTo: 0              // the newest message TDLib was told is seen
    property int unread: chat ? chat.unread_count : 0
    property bool away: false           // the newest are out of sight (↓ shows)

    ListModel { id: messages }       // newest first: the list runs bottom to top

    // the keyboard's height over us: the messages and the field go up with it, the header stays
    // (the shell moves the keyboard in that time and curve, and leaves the window where it is).
    // Moved, not resized: a list laid out again each frame could not keep up with it.
    property real kb: osk.h
    Behavior on kb { NumberAnimation { duration: osk.ms; easing.type: Easing.OutExpo } }

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

    // the newest pinned message, in a bar under the header (a tap goes to it)
    property var pinned: null           // { id, text }
    function loadPinned() {
        if (thread)         // (the discussion group's pinned message is not the post's)
            return
        store.send({ "@type": "getChatPinnedMessage", chat_id: chatId }, (m) => {
            if (page)
                page.pinned = m["@type"] === "message" ? { id: m.id, text: store.preview(m.content) } : null
        })
    }

    Component.onCompleted: {
        store.openChat = chatId
        loadPinned()
        if (td.devOpen)
            console.warn("nullgram: chat translatable", chat ? chat.is_translatable : "?", "premium", store.me ? store.me.is_premium : "?")
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
        readTo = chat ? chat.last_read_inbox_message_id : 0
        if (target)
            openAt(target, false)
        else if (chat && chat.unread_count > 0 && readTo && !thread)
            openAt(readTo, true)
        else
            fresh()
    }

    // the newest messages, the list at the bottom
    function fresh() {
        messages.clear()
        gap = false
        more = true
        list.down = true
        store.history(chatId, 0, 30, (got, failed) => {
            if (!page)          // closed before TDLib answered
                return
            page.add(page.withRoot(got, !failed && got.length < 30))
            // one that came meanwhile (sent as it opened) is laid out again with neighbours now, and
            // had scrolled to where the newest was before these: lay out, stop that, then go down
            list.forceLayout()
            scroll.stop()
            list.positionViewAtBeginning()
            page.ready = true
            Qt.callLater(page.seen)
            Qt.callLater(page.nearTop)          // a screen not yet full: more at once
        }, null, thread)
    }

    // as Telegram opens a chat with unread messages: around the last one read, the first unread
    // under the bar at the top of the screen; or (`unread` false) around a message found, in the middle
    function openAt(id, unread) {
        store.send({ "@type": "getChatHistory", chat_id: chatId, from_message_id: id, offset: unread ? -30 : -20,
                     limit: unread ? 50 : 40, only_local: false }, (r) => {
            if (!page)
                return
            const got = r.messages || []
            if (!got.length) {
                page.fresh()
                return
            }
            const last = page.chat && page.chat.last_message
            page.gap = !(last && got[0].id >= last.id)
            if (unread)
                for (let k = got.length - 1; k >= 0; k--)
                    if (got[k].id > page.readTo && !got[k].is_outgoing) {
                        page.firstUnread = got[k].id
                        break
                    }
            page.add(got)
            if (!unread) {
                const t = page.indexOf(id)
                if (t >= 0)
                    page.centre(t)
                page.flashId = id
                unflash.restart()
            }
            const i = unread ? page.indexOf(page.firstUnread) : -1
            if (i >= 0) {
                list.positionViewAtIndex(i, ListView.End)      // (the end of a bottom-to-top list: its top)
                list.contentY = Math.max(list.originY, list.contentY - bar.height)   // not under the header
            }
            list.down = false
            page.ready = true
            Qt.callLater(page.seen)
            Qt.callLater(page.nearTop)
            Qt.callLater(page.nearBottom)
        })
    }
    Component.onDestruction: {
        store.send({ "@type": "closeChat", chat_id: chatId })
        if (store.openChat === chatId)
            store.openChat = 0
    }

    // older messages at the end; their quotes first, so a reply within the batch needs no request
    function add(got) {
        const k = messages.count - 1
        // one that came as an update while these were asked for is here already
        const have = {}
        for (let i = 0; i < messages.count; i++)
            have[messages.get(i).msgId] = true
        got = got.filter((m) => !have[m.id])
        for (const m of got)
            remember(m)
        for (const m of got)
            messages.append(row(m))
        // the one that was the oldest has neighbours now: its day and run are worked out again
        if (k >= 0 && got.length)
            messages.setProperty(k, "edge", messages.get(k).edge + 1)
    }

    function remember(m) {
        quotes[m.id] = { name: m.is_outgoing ? "Siz" : store.senderName(m.sender_id, false) || (chat ? chat.title : ""),
                         text: store.preview(m.content) }
    }

    readonly property var pictured: ["messagePhoto", "messageVideo", "messageAnimation", "messageSticker", "messageVideoNote",
                                     "messageVoiceNote", "messageAudio", "messageDocument"]

    // its words and, when they are formatted, Store.rich's parts (a spoiler ░ until tapped: `bare`)
    property var spoilers: ({})      // message id -> the formatted text with a spoiler in it
    property var bared: ({})         // message id -> true: its spoilers shown
    property var unfolded: ({})      // message id -> true: its folding quotes shown whole
    function shown(content, id) {
        const t = content["@type"]
        const words = store.plain(content)
        const ft = store.formatted(content)
        if (store.hasSpoiler(ft))
            spoilers[id] = ft
        return {
            rich: store.rich(ft, !!bared[id]),
            text: words !== null ? words : (content.caption ? content.caption.text : ""),
            kind: words !== null || pictured.indexOf(t) >= 0 ? ""
                : store.kindOf(t)
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
    property var bigFiles: ({})      // message id -> the photo's biggest size (full screen)
    function media(c) {
        const t = c["@type"]
        const r = { picKind: "", picW: 1, picH: 1, mini: "", dur: 0, file: null, main: null, rowKind: "",
                    fileName: "", wave: "", title: "", sub: "", anim: false, auto: false }
        if (t === "messagePhoto" && c.photo.sizes.length) {
            const sizes = c.photo.sizes      // small to big
            let best = sizes[sizes.length - 1]
            for (const z of sizes)
                if (z.width >= 640) {
                    best = z
                    break
                }
            Object.assign(r, { picKind: "photo", picW: best.width, picH: best.height, file: best.photo,
                               big: sizes[sizes.length - 1].photo, main: sizes[sizes.length - 1].photo,
                               mini: c.photo.minithumbnail ? c.photo.minithumbnail.data : "" })
        } else if (t === "messageVideo" || t === "messageAnimation") {
            const v = t === "messageVideo" ? c.video : c.animation
            Object.assign(r, { picKind: t === "messageVideo" ? "video" : "gif", picW: v.width || 1, picH: v.height || 1,
                               dur: v.duration, file: still(v.thumbnail), mini: v.minithumbnail ? v.minithumbnail.data : "",
                               main: t === "messageVideo" ? v.video : v.animation, fileName: v.file_name || "",
                               auto: t === "messageAnimation" && Prefs.autoGif && (v.animation.size || v.animation.expected_size) < 8e6 })
        } else if (t === "messageSticker") {
            const st = c.sticker
            const webm = st.format["@type"] === "stickerFormatWebm"
            Object.assign(r, { picKind: "sticker", picW: st.width || 1, picH: st.height || 1,
                               file: st.format["@type"] === "stickerFormatWebp" ? st.sticker : still(st.thumbnail),
                               main: webm ? st.sticker : null, anim: webm, auto: webm && Prefs.autoGif })
        } else if (t === "messageVideoNote") {
            const v = c.video_note
            Object.assign(r, { picKind: "round", picW: 1, picH: 1, dur: v.duration, file: still(v.thumbnail),
                               mini: v.minithumbnail ? v.minithumbnail.data : "", main: v.video, auto: Prefs.autoVoice })
        } else if (t === "messageVoiceNote") {
            const v = c.voice_note
            Object.assign(r, { rowKind: "voice", dur: v.duration, wave: v.waveform || "", main: v.voice, auto: Prefs.autoVoice })
        } else if (t === "messageAudio") {
            const a = c.audio
            Object.assign(r, { rowKind: "audio", dur: a.duration, main: a.audio, fileName: a.file_name || "",
                               title: a.title || a.file_name || "Musiqa", sub: a.performer || "" })
        } else if (t === "messageDocument") {
            const d = c.document
            Object.assign(r, { rowKind: "file", main: d.document, fileName: d.file_name || "", file: still(d.thumbnail) })
        }
        return r
    }

    // a photo full screen, out of its bubble; the biggest size comes in when downloaded
    function view(item) {
        const src = item.pic ? "image://pic/0/" + Math.round(item.pw) + "/" + item.pic
                  : item.mini ? "image://pic/0/" + Math.round(item.pw) + "/mini/" + item.mini : ""
        viewer.show(item.picFace, item.aspect, src, "", item.msgId)
        const f = bigFiles[item.msgId]
        if (f)
            store.fetch(f, 32, (path) => { if (page) viewer.better(path) })
    }

    // the message's own file (the video, the voice, the document...): how far it has come, and
    // its path once here. `mains` by message, `fileMsgs` the other way (updateFile names files)
    property var mains: ({})
    property var fileMsgs: ({})
    property var wantOpen: 0            // a tap asked for this one: it opens (plays) when it is here
    function own(id, f) {
        mains[id] = f
        const ids = fileMsgs[f.id] || []
        if (ids.indexOf(id) < 0)
            ids.push(id)
        fileMsgs[f.id] = ids
    }

    function download(id, open) {
        const f = mains[id]
        if (!f)
            return
        if (open)
            wantOpen = id
        const i = indexOf(id)
        if (i >= 0 && messages.get(i).got < 0)
            messages.setProperty(i, "got", 0)
        store.fetch(f, open ? 32 : 1, () => {})
    }

    function stop(id) {
        const f = mains[id]
        if (wantOpen === id)
            wantOpen = 0
        if (f)
            store.stopFile(f)
        const i = indexOf(id)
        if (i >= 0)
            messages.setProperty(i, "got", -1)
    }

    // a tap on a message's media: open, play, or bring it down first (a second tap stops that)
    function tapMedia(item) {
        const k = item.rowKind || item.picKind
        if (k === "photo") {
            view(item)
            return
        }
        if (!mains[item.msgId])
            return
        if (item.got >= 0 && !item.path && !item.sending) {
            stop(item.msgId)
            return
        }
        if (!item.path) {
            download(item.msgId, true)
            return
        }
        openMedia(item)
    }

    function openMedia(item) {
        const k = item.rowKind || item.picKind
        const mime = (mains[item.msgId] && fileMime[item.msgId]) || ""
        if (k === "video" || k === "gif" || (k === "file" && mime.startsWith("video/"))) {
            const src = item.pic ? "image://pic/0/" + Math.round(item.pw) + "/" + item.pic
                      : item.mini ? "image://pic/0/" + Math.round(item.pw) + "/mini/" + item.mini : ""
            viewer.show(item.media ? item.picFace : item.face, item.media ? item.aspect : 9 / 16, src, item.path,
                        k === "video" ? item.msgId : 0)
            viewing = item.msgId
        } else if (k === "round") {
            roundId = roundId === item.msgId ? 0 : item.msgId
        } else if (k === "voice" || k === "audio" || (k === "file" && mime.startsWith("audio/"))) {
            play(item.msgId, item.path)
        } else if (k === "file" && mime.startsWith("image/")) {
            viewer.show(item.face, fileAspect[item.msgId] || 1, "file://" + item.path)
            viewing = item.msgId
        } else if (k === "file") {
            save(item.msgId)
        }
    }
    property var fileMime: ({})         // a document's mime type, by message
    property var fileAspect: ({})       // and a picture's height / width (its thumbnail's)
    property var viewing: 0             // the message full screen (its ↓ saves it)

    // into ~/Downloads (td.save), brought down first when it is not here
    function save(id) {
        const f = mains[id]
        if (!f)
            return
        const name = fileNames[id] || f.local.path.split("/").pop()
        store.fetch(f, 32, (path) => {
            const to = td.save(path, name)
            if (page)
                page.toast(to ? "Saqlandi: Downloads/" + to.split("/").pop() : "Saqlab bo'lmadi")
        })
    }
    property var fileNames: ({})

    // the one sound the page plays: a voice note or a song; the next voice note under it follows
    property var soundId: 0
    function play(id, path) {
        if (soundId === id) {
            if (sound.playbackState === MediaPlayer.PlayingState)
                sound.pause()
            else
                sound.play()
            return
        }
        roundId = 0
        soundId = id
        sound.source = "file://" + path
        sound.play()
    }
    function next() {
        const i = indexOf(soundId)
        const was = soundId
        soundId = 0
        if (i > 0) {
            const r = messages.get(i - 1)
            if (r.rowKind === "voice" && was) {
                if (r.path)
                    play(r.msgId, r.path)
                else
                    download(r.msgId, true)
            }
        }
    }
    MediaPlayer {
        id: sound
        audioOutput: AudioOutput {}
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) page.next()
    }
    property var roundId: 0             // the round video playing in its bubble, with its sound
    onRoundIdChanged: if (roundId) sound.pause()

    function toast(text) {
        toastText.text = text
        toastBox.opacity = 1
        toastAway.restart()
    }

    function loadPic(id) {
        const f = files[id]
        if (f)
            store.fetch(f, 1, (path) => {
                if (!page)
                    return
                const i = page.indexOf(id)
                if (i >= 0)
                    messages.setProperty(i, "pic", path)
            })
    }

    function row(m) {
        const s = shown(m.content, m.id)
        const p = media(m.content)
        if (p.file)
            files[m.id] = p.file
        if (p.big)
            bigFiles[m.id] = p.big
        if (p.main) {
            own(m.id, p.main)
            if (p.fileName)
                fileNames[m.id] = p.fileName
            const doc = m.content.document
            if (doc) {
                fileMime[m.id] = doc.mime_type || ""
                if (doc.thumbnail && doc.thumbnail.width)
                    fileAspect[m.id] = doc.thumbnail.height / doc.thumbnail.width
            }
        }
        const words = store.plain(m.content)
        // in a post's comments the post itself goes plain and an answer to it has no quote (as Telegram has them)
        const root = thread && m.id === thread
        const r = m.reply_to && m.reply_to["@type"] === "messageReplyToMessage" &&
                  !(thread && m.reply_to.message_id === thread) ? m.reply_to : null
        let quote = null
        if (r && r.chat_id === chatId) {
            quote = quotes[r.message_id]
            if (!quote)
                want(r.message_id)
        } else if (r && r.content) {        // a reply to a message in another chat comes with it
            quote = { name: "", text: store.preview(r.content) }
        }
        return {
            msgId: m.id, out: m.is_outgoing, date: m.date, text: s.text, rich: s.rich, kind: s.kind, said: store.service(m, chat) || "",
            sender: page.group && !m.is_outgoing && !root ? store.senderName(m.sender_id, false) : "",
            senderKey: JSON.stringify(m.sender_id), sending: !!m.sending_state,
            tint: store.tints[Math.abs(m.sender_id.user_id || m.sender_id.chat_id || 0) % store.tints.length],
            time: Qt.formatTime(new Date(m.date * 1000), "HH:mm"),
            views: m.interaction_info ? m.interaction_info.view_count : 0,
            // a channel post with a discussion group: its comments (-1: none can be left)
            comments: m.is_channel_post && page.channel && m.interaction_info && m.interaction_info.reply_info
                      ? m.interaction_info.reply_info.reply_count : -1,
            // a group's message: how many answered it (Telegram-iOS's ↩ 9 by the time)
            replies: !m.is_channel_post && m.interaction_info && m.interaction_info.reply_info
                     ? m.interaction_info.reply_info.reply_count : 0,
            edited: m.edit_date > 0,
            replyId: r ? r.message_id : 0,
            quoteName: quote ? quote.name : "", quoteText: quote ? quote.text : (r ? "..." : ""),
            picKind: p.picKind, picW: p.picW, picH: p.picH, mini: p.mini, dur: p.dur, edge: 0,
            pic: p.file && p.file.local.is_downloading_completed ? p.file.local.path : "",
            rowKind: p.rowKind, fileName: p.fileName, fileSize: p.main ? (p.main.size || p.main.expected_size) : 0,
            wave: p.wave, title: p.title, sub: p.sub, anim: p.anim, auto: p.auto,
            got: p.main ? store.progress(p.main) : -1,
            path: p.main && p.main.local.is_downloading_completed ? p.main.local.path : "",
            jumbo: words !== null && !r && !m.forward_info ? store.emojiCount(words.trim()) : 0,
            fwd: root ? "" : store.origin(m.forward_info),
            reacts: JSON.stringify(store.reactions(m.interaction_info)),
            isPinned: !!m.is_pinned
        }
    }

    // a replied message not loaded here: ask for it, then fill the replies to it
    function want(id) {
        if (asked[id])
            return
        asked[id] = true
        store.send({ "@type": "getMessage", chat_id: chatId, message_id: id }, (m) => {
            if (!page)
                return
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

    // what is on the screen is read: the newest message in sight and all before it (as Telegram counts)
    function seen() {
        if (!ready || !messages.count)
            return
        let i = list.indexAt(list.width / 2, list.contentY + list.height - page.foot - 4)
        if (i < 0)
            i = list.atYBeginning ? 0 : -1
        away = gap || i > 2
        if (i < 0 || messages.get(i).msgId <= readTo)
            return
        const ids = []
        const newest = messages.get(i).msgId
        for (let k = i; k < messages.count && ids.length < 100; k++) {
            const r = messages.get(k)
            if (r.msgId <= readTo)
                break
            if (!r.out)
                ids.push(r.msgId)
        }
        readTo = newest
        if (ids.length)
            store.send({ "@type": "viewMessages", chat_id: chatId, message_ids: ids, force_read: true })
    }
    Timer { id: seenLater; interval: 250; onTriggered: page.seen() }
    Timer { id: unflash; interval: 1400; onTriggered: page.flashId = 0 }

    // newer messages while the bottom is 15 away, when it was opened at the unread ones
    function nearBottom() {
        if (!gap || newering || !messages.count)
            return
        const bottom = list.indexAt(list.width / 2, list.contentY + list.height - 4)
        if (bottom < 0 ? list.atYBeginning : bottom <= 15)
            newer()
    }

    function newer() {
        newering = true
        const from = messages.get(0).msgId
        store.send({ "@type": "getChatHistory", chat_id: chatId, from_message_id: from, offset: -40, limit: 41,
                     only_local: false }, (r) => {
            if (!page)
                return
            page.newering = false
            if (r["@type"] === "error") {
                console.warn("nullgram: getChatHistory (newer)", page.chatId, from, r.code, r.message)
                return
            }
            const got = (r.messages || []).filter((m) => m.id > from)      // newest first
            if (!got.length) {
                page.gap = false            // nothing newer: these are the newest
                return
            }
            for (const m of got)
                page.remember(m)
            for (let k = got.length - 1; k >= 0; k--)
                messages.insert(0, page.row(got[k]))
            const last = page.chat && page.chat.last_message
            if (last && got[0].id >= last.id)
                page.gap = false
            Qt.callLater(page.nearBottom)
            seenLater.restart()
        })
    }

    function older() {
        if (loading || !more || !messages.count)
            return
        loading = true
        store.history(chatId, messages.get(messages.count - 1).msgId, 40, (got, failed) => {
            if (!page)
                return
            page.add(page.withRoot(got, !failed && got.length < 40))
            page.more = failed || got.length > 0
            page.loading = false
            if (!failed)
                Qt.callLater(page.nearTop)      // still near the top (a short page, a fast flick): the next ones
        }, null, thread)
    }

    // older messages while the top of the list is still 15 messages away, not only once it is reached:
    // atYEnd alone does not change again when the list stays at the top after a load
    function nearTop() {
        if (loading || !more || !messages.count)
            return
        const top = list.indexAt(list.width / 2, list.contentY + 4)
        if (top < 0 ? list.atYEnd : top >= messages.count - 15)
            older()
    }

    // the replied message, if it is loaded
    function jump(id) {
        const i = indexOf(id)
        if (i >= 0)
            centre(i)
    }
    // a message in the middle of the screen; one taller than the room there from its top
    function centre(i) {
        list.positionViewAtIndex(i, ListView.Center)
        const it = list.itemAtIndex(i)
        if (it && it.height > list.height - bar.height - foot - 60) {
            list.positionViewAtIndex(i, ListView.End)      // (the end of a bottom-to-top list: its top)
            list.contentY = Math.max(list.originY, list.contentY - bar.height - 8)
        }
    }
    // a message in the middle, lit up a moment: loaded here, else the history around it in place of these
    function goTo(id) {
        if (indexOf(id) >= 0) {
            jump(id)
            flashId = id
            unflash.restart()
        } else {
            messages.clear()
            more = true
            openAt(id, false)
        }
    }

    // ---- searching in the chat (Telegram-iOS: the field in the header, ↑ ↓ and "1 of N" under) ----
    property bool searching: false
    property var hits: []               // the messages found, newest first
    property int hit: -1                // the one shown
    property bool searched: false       // TDLib has answered for what is in the field
    function find(q) {
        hits = []
        hit = -1
        searched = false
        if (!q.trim())
            return
        store.send({ "@type": "searchChatMessages", chat_id: chatId, topic_id: store.topic(thread), query: q,
                     sender_id: null, from_message_id: 0, offset: 0, limit: 100, filter: null }, (r) => {
            if (!page || !searching || q !== findField.text)
                return
            if (r["@type"] !== "foundChatMessages")
                console.warn("nullgram: search", JSON.stringify(r))
            page.hits = (r.messages || []).map((m) => m.id)
            page.searched = true
            if (page.hits.length)
                page.showHit(0)
        })
    }
    function showHit(k) {
        hit = k
        goTo(hits[k])
    }
    function focusFind() {
        searching = true
        findField.forceActiveFocus()
    }
    function stopSearch() {
        searching = false
        findField.text = ""
        findField.focus = false
        hits = []
        hit = -1
    }

    // ---- the menu ------------------------------------------------------------
    // testing (NULLGRAM_SAY with a channel): the newest post's comments open and these lines go there
    property string say: ""
    property string findNow: ""         // testing (NULLGRAM_FIND): search for this once the messages are in
    onReadyChanged: {
        if (ready && findNow) {
            searching = true
            findField.text = findNow
            findNow = ""
        }
        if (!ready || !say)
            return
        const t = say
        say = ""
        if (thread) {
            for (const line of t.split("\n"))
                if (line)
                    store.sendText(chatId, line, 0, thread)
        } else if (messages.count) {
            sayLater.text = t
            sayLater.start()            // (once this page is in: a push while one moves is dropped)
        }
    }
    Timer { id: sayLater; property string text; interval: 900; onTriggered: page.openComments(messages.get(0).msgId, text) }

    // a post's comments, in a page of their own over this one (the discussion group's thread)
    property Component commentsPage: null
    function openComments(id, say) {
        store.send({ "@type": "getMessageThread", chat_id: chatId, message_id: id }, (r) => {
            if (!page)
                return
            if (r["@type"] !== "messageThreadInfo") {
                console.warn("nullgram: getMessageThread", r.code, r.message)
                return
            }
            if (!page.commentsPage)
                page.commentsPage = Qt.createComponent("ChatPage.qml")
            page.nav.push(page.commentsPage, { chatId: r.chat_id, thread: r.message_thread_id, threadRoot: r.messages || [], say: say || "",
                                               threadOf: page.chat ? page.chat.title : "" })
        })
    }

    // a tap on a link in a message's words (Words' hrefs, Store.rich): a spoiler shows, @name, a
    // t.me link and a user open their chat (a message link at the message), #tag is looked for in
    // this chat, /command is sent; the rest goes to the browser
    function follow(url, id) {
        if (url === "spoiler") {
            bared[id] = true
            const i = indexOf(id)
            if (i >= 0 && spoilers[id] && originals[id] === undefined)
                messages.setProperty(i, "rich", store.rich(spoilers[id], true))
            return
        }
        const c = url.charAt(0)
        if (c === "#" || c === "$") {
            searching = true
            findField.text = url
            return
        }
        if (c === "/") {
            store.sendText(chatId, url, 0, thread)
            return
        }
        if (c === "@") {
            store.send({ "@type": "searchPublicChat", username: url.slice(1) }, (r) => openChat(r, 0))
            return
        }
        if (url.startsWith("user:")) {
            store.send({ "@type": "createPrivateChat", user_id: Number(url.slice(5)), force: false }, (r) => openChat(r, 0))
            return
        }
        if (url.startsWith("time:"))
            return
        if (!/^(https?:\/\/)?(t\.me|telegram\.me|telegram\.dog)\/|^tg:/i.test(url)) {
            Qt.openUrlExternally(url)
            return
        }
        store.send({ "@type": "getInternalLinkType", link: url }, (r) => {
            const t = r["@type"]
            if (t === "internalLinkTypePublicChat")
                store.send({ "@type": "searchPublicChat", username: r.chat_username }, (c) => openChat(c, 0))
            else if (t === "internalLinkTypeMessage")
                store.send({ "@type": "getMessageLinkInfo", url: url }, (info) => {
                    if (info["@type"] !== "messageLinkInfo" || !info.chat_id)
                        return toast("Xabar topilmadi")
                    openChat({ "@type": "chat", id: info.chat_id }, info.message ? info.message.id : 0)
                })
            else if (t === "internalLinkTypeChatInvite")
                store.send({ "@type": "checkChatInviteLink", invite_link: r.invite_link }, (info) => {
                    if (info.chat_id)
                        openChat({ "@type": "chat", id: info.chat_id }, 0)
                    else
                        toast(info.title ? "«" + info.title + "» — taklif havolasi" : "Havola ochilmadi")
                })
            else
                Qt.openUrlExternally(url)
        })
    }
    function openChat(r, target) {
        if (!page)
            return
        if (r["@type"] !== "chat")
            return toast("Topilmadi" + (r.message ? ": " + r.message : ""))
        if (r.id === chatId && !thread) {
            if (target)
                jump(target)
            return
        }
        if (!page.commentsPage)
            page.commentsPage = Qt.createComponent("ChatPage.qml")
        page.nav.push(page.commentsPage, target ? { chatId: r.id, target: target } : { chatId: r.id })
    }
    function unfold(id) {
        const u = Object.assign({}, unfolded)
        if (u[id])
            delete u[id]
        else
            u[id] = true
        unfolded = u
    }

    function openMenu(item) {
        if (page.kb > 0) {          // the keyboard down first, over the menu's actions it would stay
            field.focus = false
            osk.hide()
        }
        const m = { id: item.msgId, text: item.text, kind: item.kind, out: item.out,
                    name: item.out ? "Siz" : item.sender || (chat ? chat.title : "") }
        // its properties and the reactions it can get, both asked at once; the menu opens with both
        let props = null, reactions = null
        const both = () => { if (props && reactions) page.showMenu(item, m, props, reactions) }
        store.send({ "@type": "getMessageAvailableReactions", chat_id: chatId, message_id: m.id, row_size: 8 }, (r) => {
            const list = r["@type"] === "availableReactions" ? r.top_reactions.concat(r.popular_reactions || []) : []
            reactions = list.filter((a) => a.type["@type"] === "reactionTypeEmoji" && !a.needs_premium)
                            .map((a) => a.type.emoji).filter((e, i, all) => all.indexOf(e) === i).slice(0, 12)
            both()
        })
        store.send({ "@type": "getMessageProperties", chat_id: chatId, message_id: m.id }, (p) => {
            props = p
            both()
        })
    }

    function showMenu(item, m, p, reactions, waited) {
        const ok = p["@type"] === "messageProperties"
        const acts = []
        if (ok && p.can_be_replied && !page.channel)
            acts.push({ text: "Javob yozish", glyph: "↩", run: () => page.reply(m) })
        if (m.text)
            acts.push({ text: "Nusxalash", glyph: "⧉", run: () => page.copy(m.text) })
        if (ok && p.can_be_edited && !m.kind && !item.media && !item.rowKind)
            acts.push({ text: "Tahrirlash", glyph: "✎", run: () => page.edit(m) })
        if (m.text && !page.translating)        // this one alone in Uzbek, and back
            acts.push(page.originals[m.id] !== undefined
                      ? { text: "Asl nusxasi", glyph: "🌐", run: () => page.untranslateOne(m.id) }
                      : { text: "Tarjima qilish", glyph: "🌐", run: () => { page.ones[m.id] = true; page.translateId(m.id) } })
        if (ok && p.can_get_link)
            acts.push({ text: "Havolani nusxalash", glyph: "🔗", run: () => page.copyLink(m.id) })
        if (ok && p.can_be_forwarded)
            acts.push({ text: "Uzatish", glyph: "↪", run: () => { page.forwarding = [m.id]; page.copying = false; forwardSheet.show() } })
        if (ok && p.can_be_copied && page.channel)   // (Telegram-iOS's "forward without the author's name")
            acts.push({ text: "Imzosiz forward qilish", glyph: "↪", run: () => { page.forwarding = [m.id]; page.copying = true; forwardSheet.show() } })
        if (ok && p.can_be_pinned)
            acts.push({ text: item.isPinned ? "Qadashni olish" : "Qadash", glyph: "📌",
                        run: () => store.pin(page.chatId, m.id, !item.isPinned) })
        if (page.mains[m.id] && !item.sending)
            acts.push({ text: item.picKind === "photo" ? "Rasmni saqlash" : item.picKind === "video" || item.picKind === "round" ? "Videoni saqlash" : "Saqlash",
                        glyph: "↓", run: () => page.save(m.id) })
        if (ok && p.can_report_chat)
            acts.push({ text: "Shikoyat qilish", glyph: "ⓘ", run: () => page.report([m.id], "", "") })
        if (ok && p.can_be_deleted_only_for_self && p.can_be_deleted_for_all_users) {
            acts.push({ text: "Men uchun o'chirish", glyph: "✕", danger: true,
                        run: () => store.deleteMessages(page.chatId, [m.id], false) })
            acts.push({ text: "Hamma uchun o'chirish", glyph: "✕", danger: true,
                        run: () => store.deleteMessages(page.chatId, [m.id], true) })
        } else if (ok && (p.can_be_deleted_only_for_self || p.can_be_deleted_for_all_users)) {
            acts.push({ text: "O'chirish", glyph: "✕", danger: true,
                        run: () => store.deleteMessages(page.chatId, [m.id], p.can_be_deleted_for_all_users) })
        }
        if (!item.said && !item.sending)        // set apart at the end, as Telegram-iOS has it
            acts.push({ text: "Tanlash", glyph: "✓", gap: true, run: () => page.startPicking(m.id) })
        if (page.kb > 0 && !waited) {   // (opened once it is down: the bubble moves down with the list)
            menuWaits = () => page.showMenu(item, m, p, reactions, true)
            menuLate.restart()
            return
        }
        const i = page.indexOf(m.id)
        const it = i >= 0 ? list.itemAtIndex(i) : null
        page.reacting = m.id
        if (it && acts.length)
            menu.show(it.face, m.out, acts, reactions, it.reactList.filter((r) => r.mine).map((r) => r.e))
    }
    property var menuWaits: null        // the menu, while the keyboard goes down
    onKbChanged: if (kb === 0 && menuWaits) menuLate.triggered()
    Timer {
        id: menuLate
        interval: 800               // (should the keyboard not go)
        onTriggered: {
            const f = page.menuWaits
            page.menuWaits = null
            stop()
            if (f)
                f()
        }
    }
    property var forwarding: []         // the messages the forward sheet sends
    property bool copying: false        // and whether as our own (no "forwarded from")
    property var reacting: 0            // the message the menu's reactions go on

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
        // its formatting comes along (TDLib has the message at hand), unless already typed over
        store.send({ "@type": "getMessage", chat_id: chatId, message_id: m.id }, (r) => {
            const ft = r && r.content && store.formatted(r.content)
            if (!page || !editing || editing.id !== m.id || !ft || field.text !== ft.text)
                return
            marks = ft.entities.filter((e) => store.given.indexOf(e.type["@type"]) >= 0)
            ink.paint(field.textDocument, marks, Theme.accent)
        })
    }

    // whether the chosen words are all under a mark of this kind (the field's Format menu)
    function marked(kind) {
        const a = field.selectionStart, b = field.selectionEnd
        return b > a && marks.some((e) => e.type["@type"] === kind && e.offset <= a && e.offset + e.length >= b)
    }
    // the Format menu: the chosen words get this mark, or lose it when they have it (url: a link's)
    function toggleMark(kind, url) {
        const a = field.selectionStart, b = field.selectionEnd
        if (b <= a)
            return
        const off = marked(kind)
        const out = []
        let lo = a, hi = b
        for (const e of marks) {
            const x = e.offset, y = e.offset + e.length
            if (e.type["@type"] !== kind || y < a || x > b) {
                out.push(e)
                continue
            }
            if (off) {               // what is left of it on either side of the chosen words
                if (x < a)
                    out.push({ "@type": "textEntity", offset: x, length: a - x, type: e.type })
                if (y > b)
                    out.push({ "@type": "textEntity", offset: b, length: y - b, type: e.type })
            } else if (!url) {       // one with those it touches (a link keeps its own address)
                lo = Math.min(lo, x)
                hi = Math.max(hi, y)
            } else
                out.push(e)
        }
        if (!off) {
            const type = { "@type": kind }
            if (url)
                type.url = url
            out.push({ "@type": "textEntity", offset: lo, length: hi - lo, type: type })
        }
        marks = out.sort((p, q) => p.offset - q.offset)
        ink.paint(field.textDocument, marks, Theme.accent)
    }

    // the field's formatting as TDLib's textEntity's, moved along as its words change: what is
    // typed inside a mark grows it, at its edges stays out; a custom emoji typed over is dropped
    property var marks: []
    property string fieldWas: ""
    function reMark() {
        const was = fieldWas, now = field.text
        fieldWas = now
        if (!marks.length)
            return
        let p = 0
        while (p < was.length && p < now.length && was[p] === now[p])
            p++
        let q = 0
        while (q < was.length - p && q < now.length - p && was[was.length - 1 - q] === now[now.length - 1 - q])
            q++
        const end = was.length - q, d = now.length - was.length
        const out = []
        for (const e of marks) {
            const a = e.offset, b = e.offset + e.length
            if (e.type["@type"] === "textEntityTypeCustomEmoji" && a < end && b > p)
                continue
            const a2 = a < p ? a : a >= end ? a + d : p + Math.max(0, end - p + d)
            const b2 = b <= p ? b : b >= end ? b + d : p
            if (b2 > a2)
                out.push({ "@type": "textEntity", offset: a2, length: b2 - a2, type: e.type })
        }
        marks = out
        ink.paint(field.textDocument, marks, Theme.accent)
    }
    // the field's words to send, trimmed, with their marks moved to match
    function fieldWords() {
        const t = field.text, lead = t.length - t.replace(/^\s+/, "").length
        const text = t.trim()
        const out = []
        for (const e of marks) {
            const a = Math.max(0, e.offset - lead), b = Math.min(text.length, e.offset + e.length - lead)
            if (b > a)
                out.push({ "@type": "textEntity", offset: a, length: b - a, type: e.type })
        }
        return { text: text, marks: out }
    }

    // Shikoyat qilish (reportChat): Telegram asks step by step — why (its options, maybe nested),
    // some words when it wants them — until it is sent
    function report(ids, option, text) {
        store.send({ "@type": "reportChat", chat_id: chatId, option_id: option, message_ids: ids, text: text }, (r) => {
            if (!page)
                return
            const t = r["@type"]
            if (t === "reportChatResultOk")
                toast("Shikoyat yuborildi")
            else if (t === "reportChatResultOptionRequired")
                reportMenu.ask({ ids: ids, title: r.title, options: r.options })
            else if (t === "reportChatResultTextRequired")
                reportMenu.ask({ ids: ids, option: r.option_id, optional: r.is_optional })
            else
                toast(t === "error" ? "Shikoyat yuborilmadi" : "Avval xabarlarni tanlang")
        })
    }

    function copyLink(id) {
        store.send({ "@type": "getMessageLink", chat_id: chatId, message_id: id }, (r) => {
            if (!page)
                return
            if (r["@type"] === "messageLink") {
                page.copy(r.link)
                page.toast("Havola nusxalandi")
            } else {
                page.toast("Havolani olib bo'lmadi")
            }
        })
    }

    // «Tanlash» (Telegram-iOS: the menu's last, set apart): messages picked by a tap each — a circle on
    // each one's left, «N ta tanlandi» over them, under them deleting and forwarding them all at once
    property bool selecting: false
    property var picked: ({})           // id → its messageProperties (null until TDLib answers)
    readonly property var pickedIds: Object.keys(picked).map(Number).sort((a, b) => a - b)  // oldest first
    function startPicking(id) {
        if (page.kb > 0) {
            field.focus = false
            osk.hide()
        }
        cancelCompose()
        picked = ({})
        selecting = true
        pick(id)
    }
    function pick(id) {
        const p = Object.assign({}, picked)
        if (p[id] !== undefined) {
            delete p[id]
            picked = p
            return
        }
        p[id] = null
        picked = p
        store.send({ "@type": "getMessageProperties", chat_id: chatId, message_id: id }, (r) => {
            if (!page || picked[id] === undefined)
                return
            const q = Object.assign({}, picked)
            q[id] = r["@type"] === "messageProperties" ? r : {}
            picked = q
        })
    }
    function stopPicking() {
        selecting = false
        picked = ({})
        deleteMenu.visible = false
    }
    // whether every one picked can (each one's properties known)
    function pickedCan(what) {
        const ids = Object.keys(picked)
        return ids.length > 0 && ids.every((k) => picked[k] && picked[k][what])
    }
    readonly property bool pickedDeletable: pickedIds.length > 0 && Object.keys(picked).every((k) =>
        picked[k] && (picked[k].can_be_deleted_only_for_self || picked[k].can_be_deleted_for_all_users))
    function deletePicked(everyone) {
        store.deleteMessages(chatId, pickedIds, everyone)
        stopPicking()
    }
    // the picked ones' words, oldest first, a blank line between (those loaded; media without words left out)
    readonly property string pickedText: {
        const out = []
        for (const id of pickedIds) {
            const i = indexOf(id)
            const t = i >= 0 ? messages.get(i).text : ""
            if (t)
                out.push(t)
        }
        return out.join("\n\n")
    }
    function forwardPicked() {
        forwarding = pickedIds
        copying = false
        stopPicking()
        forwardSheet.show()
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
        if (sheet.open) {
            sheet.close()
            return true
        }
        if (forwardSheet.open) {
            forwardSheet.close()
            return true
        }
        if (viewer.open) {
            viewer.close()
            return true
        }
        if (menu.open) {
            menu.close()
            return true
        }
        if (deleteMenu.visible) {
            deleteMenu.visible = false
            return true
        }
        if (selecting) {
            stopPicking()
            return true
        }
        if (searching) {
            stopSearch()
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
            if (m.chat_id !== page.chatId || page.gap)      // (in a gap it comes with the newer ones)
                return
            if (page.thread && !(m.topic_id && m.topic_id.message_thread_id === page.thread))
                return
            for (let i = 0; i < Math.min(messages.count, 20); i++)
                if (messages.get(i).msgId === m.id)
                    return
            const from = m.is_outgoing && page.flying &&     // (one emoji alone comes back as messageAnimatedEmoji)
                         store.plain(m.content) === page.flying.text ? page.flying : null
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
            seenLater.restart()
        }
        function onChatChanged(chatId) {
            if (chatId === page.chatId) {
                page.unread = page.chat.unread_count
                page.muted = page.isMuted()
            }
        }
        function onMessageChanged(chatId, oldId, m) {
            if (chatId !== page.chatId)
                return
            for (let i = 0; i < Math.min(messages.count, 50); i++)
                if (messages.get(i).msgId === oldId) {
                    page.remember(m)
                    messages.set(i, page.row(m))
                    if (!messages.get(i).pic)       // (the delegate stays: it does not ask again by itself)
                        page.loadPic(m.id)
                    return
                }
        }
        function onMessageContent(chatId, id, content) {
            if (chatId !== page.chatId)
                return
            const i = page.indexOf(id)
            if (i >= 0) {
                const s = page.shown(content, id)
                delete page.translations[id]
                delete page.originals[id]
                page.put(i, s)
                if (page.translating || page.ones[id])
                    page.translateId(id)
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
        function onMessagePinned(chatId, id, on) {
            if (chatId !== page.chatId)
                return
            const i = page.indexOf(id)
            if (i >= 0)
                messages.setProperty(i, "isPinned", on)
            page.loadPinned()
        }
        function onMessageInteraction(chatId, id, info) {
            if (chatId !== page.chatId)
                return
            const i = page.indexOf(id)
            if (i < 0)
                return
            messages.setProperty(i, "reacts", JSON.stringify(store.reactions(info)))
            messages.setProperty(i, "views", info ? info.view_count : 0)
            if (page.channel && info && info.reply_info)
                messages.setProperty(i, "comments", info.reply_info.reply_count)
            else if (!page.channel)
                messages.setProperty(i, "replies", info && info.reply_info ? info.reply_info.reply_count : 0)
        }
        function onFileUpdated(f) {
            const ids = page.fileMsgs[f.id]
            if (!ids)
                return
            for (const id of ids) {
                page.mains[id] = f
                const i = page.indexOf(id)
                if (i < 0)
                    continue
                const done = f.local.is_downloading_completed
                messages.setProperty(i, "got", store.progress(f))
                if (done && messages.get(i).path !== f.local.path)
                    messages.setProperty(i, "path", f.local.path)
                if (done && page.wantOpen === id) {
                    page.wantOpen = 0
                    const it = list.itemAtIndex(i)
                    if (it)
                        page.openMedia(it)
                }
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
            if (page.selecting && ids.some((id) => page.picked[id] !== undefined)) {
                const p = Object.assign({}, page.picked)
                ids.forEach((id) => delete p[id])
                page.picked = p
            }
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
            transform: Translate { y: -page.kb }
            z: page.lift ? 2 : 0        // over the field while a sent bubble leaves it (the header stays over all)
            model: messages
            verticalLayoutDirection: ListView.BottomToTop
            cacheBuffer: 800
            maximumFlickVelocity: 6000
            flickDeceleration: 2200
            header: Item { width: 1; height: page.foot + 10 }
            footer: Item { width: 1; height: bar.height + pinBar.height + 8 + osk.h }   // (gone up: the oldest clear the header)
            onContentYChanged: {                             // (index 0 is the newest, at the bottom)
                page.nearTop()
                page.nearBottom()
                seenLater.restart()
            }
            // whether it stands at the newest: then it stays there when the field grows or shrinks
            property bool down: true
            onMovementEnded: down = atYBeginning

            delegate: Item {
                id: item
                required property int index
                required property var msgId
                required property bool out
                required property string text
                required property string rich
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
                required property int edge          // its older neighbour came: first and newDay again
                required property string rowKind    // voice | audio | file: a row in the bubble
                required property string fileName
                required property real fileSize
                required property string wave
                required property string title
                required property string sub
                required property bool anim         // a video sticker: it plays as a GIF does
                required property bool auto         // comes down by itself (GIFs, voice notes, round videos)
                required property real got          // the file coming down or going up: how far, else -1
                required property string path       // the file, here
                required property int jumbo         // one to three emoji alone: big, no bubble
                required property string fwd        // forwarded: who from
                required property string reacts     // its reactions, JSON: [{ e, n, mine }]
                required property bool isPinned
                required property int comments      // a channel post's comments (-1: none)
                required property int replies       // a group message's answers
                required property string said       // a service message: its words, in a pill in the middle
                readonly property Item face: bubble
                readonly property Item picFace: picture
                // a picture: photo, video or GIF in the bubble; sticker and round video without one
                readonly property bool media: picKind !== ""
                readonly property bool bare: picKind === "sticker" || picKind === "round" || jumbo > 0
                // nearly on the screen: a GIF's player is made ready; on it: only then it plays (one
                // playing just off the screen kept the whole window redrawn at the video's 30 fps)
                readonly property bool inSight: y + height > list.contentY - 200 && y < list.contentY + list.height + 200
                readonly property bool onScreen: y + height > list.contentY && y < list.contentY + list.height
                readonly property real aspect: picH / picW
                readonly property real pw: picKind === "round" ? 200 : picKind === "sticker" ? 160 * Math.min(1, 1 / aspect)
                                         : aspect * wide > 360 ? Math.max(150, 360 / aspect) : wide
                readonly property real ph: picKind === "round" ? 200 : picKind === "sticker" ? 160 * Math.min(1, aspect)
                                         : Math.max(110, Math.min(360, aspect * wide))
                readonly property real wide: Math.min(width * 0.72, 270) - moved
                readonly property bool overlaid: media && text === "" && !reacted     // the time over the picture
                readonly property var reactList: reacts ? JSON.parse(reacts) : []
                readonly property bool reacted: reactList.length > 0
                readonly property bool translated: page.translating
                onTranslatedChanged: if (translated) page.translateId(msgId)
                Component.onCompleted: {
                    if (page.translating || page.ones[msgId])
                        page.translateId(msgId)
                    if ((media || rowKind === "file") && !pic)
                        page.loadPic(msgId)
                    if (auto && !path && got < 0)
                        page.download(msgId, false)
                }
                // a run: one sender's messages within 10 minutes of each other. Its first (the
                // top) has the name and more space over it, its last (the bottom) the tail.
                readonly property bool first: edge, page.apart(messages.get(index + 1), senderKey, date)
                readonly property bool last: page.apart(messages.get(index - 1), senderKey, date)
                readonly property real most: width * 0.78 - moved
                // a group's incoming messages leave room on the left for their sender's picture,
                // which stands by the last of a run (Telegram-iOS)
                readonly property bool faced: sender !== "" && !said       // (sender: only a group's incoming)
                // the first message of a day has the day over it
                readonly property bool newDay: edge, page.otherDay(messages.get(index + 1), date)
                readonly property bool unreadBar: msgId === page.firstUnread
                // «Tanlash»: a circle on its left, the incoming ones moved over for it (iOS)
                readonly property bool pickable: page.selecting && !said && !sending
                readonly property bool isPicked: page.picked[msgId] !== undefined
                readonly property real moved: pickable && !out ? 40 : 0       // (and narrower by as much)
                readonly property real above: (newDay ? 38 : 0) + (unreadBar ? 36 : 0) + (first ? 8 : 2)
                width: list.width
                height: (said ? pill.height + 4 : bubble.height) + above

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
                Rectangle {          // the message found, lit up a moment (as Telegram-iOS does)
                    y: item.above - 2
                    width: parent.width; height: parent.height - y + 2
                    color: Theme.accent
                    opacity: item.msgId === page.flashId ? 0.18 : 0
                    Behavior on opacity { NumberAnimation { duration: 500 } }
                }
                Rectangle {          // Telegram-iOS's unread bar, over the first unread message
                    visible: item.unreadBar
                    y: (item.newDay ? 38 : 0) + 6
                    width: parent.width; height: 28
                    color: Theme.bar
                    Text {
                        anchors.centerIn: parent
                        text: "O'qilmagan xabarlar"
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 13
                    }
                }

                Rectangle {          // a service message (who did what): no bubble, a pill in the middle
                    id: pill
                    visible: item.said !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: item.above + 2
                    width: Math.min(saidText.implicitWidth, item.width - 80) + 20
                    height: saidText.height + 8; radius: Math.min(11, height / 2)
                    color: Theme.dayPill
                    Text {
                        id: saidText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, item.width - 80)
                        text: item.said
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.PlainText
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                }

                // a message just sent flies here from where its text was in the field: it starts
                // there (moved by mover's x, y) and comes to rest on Telegram-iOS's two curves
                // (ChatMessageTransitionNode.swift), on the render thread
                Item {
                    id: mover
                    visible: !item.said
                    width: item.width; height: item.height
                    transform: Translate {
                        x: item.moved
                        Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: menu.spring } }
                    }
                    Loader {
                        id: faceAt
                        active: item.faced && item.last
                        x: 8; y: bubble.y + bubble.height - 34
                        width: 34; height: 34
                        // (handed through: inside sourceComponent `item` is the Loader's)
                        readonly property string name: item.sender
                        readonly property string key: item.senderKey
                        readonly property string tint: item.tint
                        sourceComponent: Avatar {
                            id: face
                            letters: store.letters(faceAt.name)
                            tint: faceAt.tint
                            Component.onCompleted: {
                                const s = JSON.parse(faceAt.key)
                                if (s.user_id)
                                    store.userPhoto(store.users[s.user_id], (path) => face.source = path)
                                else if (store.chats[s.chat_id]) {
                                    store.watchPhoto(store.chats[s.chat_id])
                                    face.source = store.photoPath(store.chats[s.chat_id])
                                }
                            }
                        }
                    }
                    Item {
                        id: bubble
                        y: item.above
                        x: item.out ? item.width - width - 8 - 6 : 8 + 6 + (item.faced ? 40 : 0)
                        // the time goes in the last line's corner when it fits there, else under it
                        readonly property real stampRoom: stamp.implicitWidth + 8
                        readonly property real tail: item.comments >= 0 && !item.bare ? 42 : 0     // the comments row

                        readonly property bool stampUnder: !item.overlaid && body.last + stampRoom > (item.media ? width : item.most) - 24
                        width: item.jumbo ? Math.max(body.implicitWidth, stamp.implicitWidth + 12) + 8
                             : item.bare ? item.pw : item.media ? item.pw + 6
                             : Math.min(item.most, Math.max(body.implicitWidth, who.implicitWidth, quote.visible ? quote.wants : 0,
                                                            attach.visible ? attach.width : 0, fwdText.visible ? fwdText.implicitWidth : 0,
                                                            item.reacted ? reactRow.wants + stamp.implicitWidth + 6 : 0,
                                                            stampUnder ? stamp.implicitWidth : body.last + stampRoom, tail ? 196 : 0) + 24)
                        height: tail + (item.jumbo ? body.y + body.height + 26
                              : item.overlaid ? picture.y + item.ph + (item.bare ? 0 : 3)
                              : item.reacted ? reactRow.y + reactRow.height + 6
                              : body.y + body.height + (stampUnder ? 24 : 8))

                        Rectangle {     // while the stretched picture loads
                            anchors.fill: parent
                            visible: !item.bare && shape.status !== Image.Ready
                            radius: 17
                            color: item.out ? Theme.bubbleOut : Theme.bubbleIn
                        }
                        BorderImage {   // the bubble, stretched from a small picture (nullgram.py Bubble), drawn
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
                            onClicked: if (item.media || item.rowKind) page.tapMedia(item)
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
                        Text {          // forwarded: from whom (Telegram-iOS: two lines in the accent colour)
                            id: fwdText
                            visible: item.fwd !== "" && !item.bare
                            x: 12; y: who.visible ? who.y + who.height + 1 : 7
                            width: Math.min(implicitWidth, item.most - 24)
                            elide: Text.ElideRight
                            text: "Uzatilgan xabar\n" + item.fwd
                            color: item.out ? Theme.check : Theme.accent
                            lineHeight: 0.95
                            font.family: Theme.font; font.pixelSize: 14
                        }
                        // the lowest of the name and the forward line: what comes next goes under it
                        readonly property Item head: fwdText.visible ? fwdText : who
                        Rectangle {     // what it answers: a bar, the name, a line of the text; a tap goes there
                            id: quote
                            visible: item.replyId !== 0
                            readonly property color ink: item.out ? Theme.check : Theme.accent
                            readonly property real wants: Math.max(quoteWho.implicitWidth, Math.min(quoteWhat.implicitWidth, 220)) + 22
                            x: 8
                            y: bubble.head.visible ? bubble.head.y + bubble.head.height + 4 : 8
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
                            y: item.bare ? 0 : quote.visible ? quote.y + quote.height + 4 : bubble.head.visible ? bubble.head.y + bubble.head.height + 4 : 3
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
                            Loader {        // a GIF (or a video sticker) over and over; a round video tapped, once with sound
                                id: moving
                                anchors.fill: parent
                                readonly property bool round: item.picKind === "round"
                                active: item.path !== "" && page.visible && item.inSight &&
                                        ((Prefs.autoGif && (item.picKind === "gif" || item.anim)) || (round && page.roundId === item.msgId))
                                // (handed through here: inside sourceComponent `item` is not the delegate)
                                readonly property string file: item.path
                                // paused, not taken apart, under the gallery: made anew all at once as it
                                // closed they held up the frames of its flight back
                                readonly property bool playing: !viewer.open && (round || item.onScreen)
                                sourceComponent: InlineVideo {
                                    path: moving.file
                                    running: moving.playing
                                    radius: Number(picture.corner)
                                    sound: moving.round
                                    loop: !moving.round
                                    onEnded: if (moving.round) page.roundId = 0
                                }
                            }
                            Rectangle {     // a video: play over it (the ring while it comes); a GIF: the ring
                                visible: item.got >= 0 || (item.picKind === "video" || (item.picKind === "gif" && !item.path)
                                                            || (item.picKind === "round" && page.roundId !== item.msgId))
                                anchors.centerIn: parent
                                width: 48; height: 48; radius: 24
                                color: Qt.rgba(0, 0, 0, 0.45)
                                Icon {
                                    visible: item.got < 0
                                    anchors.centerIn: parent
                                    anchors.horizontalCenterOffset: name === "play" ? 1.5 : 0
                                    width: 24; height: 24
                                    name: item.path || item.picKind === "video" ? "play" : "down"
                                    color: "white"
                                }
                                Ring {
                                    visible: item.got >= 0
                                    anchors.fill: parent
                                    value: item.got
                                }
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
                                          + (item.picKind === "video" && !item.path && item.fileSize ? " · " + store.size(item.fileSize) : "")
                                    color: "white"
                                    font.family: Theme.font; font.pixelSize: 12
                                }
                            }
                        }
                        Item {          // a voice note, a song or a file
                            id: attach
                            visible: item.rowKind !== ""
                            x: 12
                            y: quote.visible ? quote.y + quote.height + 6 : bubble.head.visible ? bubble.head.y + bubble.head.height + 4 : 6
                            width: item.rowKind === "file" ? fileRow.width : 230
                            height: visible ? 50 : 0
                            AudioRow {
                                visible: item.rowKind === "voice" || item.rowKind === "audio"
                                kind: item.rowKind === "audio" ? "audio" : "voice"
                                out: item.out
                                wave: item.wave
                                dur: item.dur
                                title: item.title
                                sub: item.sub
                                got: item.got
                                here: item.path !== ""
                                current: page.soundId === item.msgId
                                playing: current && sound.playbackState === MediaPlayer.PlayingState
                                at: current ? sound.position : 0
                            }
                            FileRow {
                                id: fileRow
                                visible: item.rowKind === "file"
                                out: item.out
                                name: item.fileName
                                size: item.fileSize
                                got: item.got
                                here: item.path !== ""
                                thumb: item.pic
                            }
                        }
                        Words {
                            id: body
                            visible: !item.overlaid
                            x: item.jumbo ? 4 : 12
                            y: item.media ? picture.y + picture.height + 5 : attach.visible ? attach.y + attach.height + (text || parts ? 4 : 0)
                             : quote.visible ? quote.y + quote.height + 4 : bubble.head.visible ? bubble.head.y + bubble.head.height + 2 : item.jumbo ? 0 : 8
                            height: (attach.visible || item.media) && !text && !parts ? 0 : implicitHeight
                            width: item.media ? bubble.width - 24 : attach.visible ? Math.max(attach.width, Math.min(implicitWidth, item.most - 24))
                                 : Math.min(implicitWidth, item.most - 24)
                            text: (item.kind ? "[" + item.kind + "] " : "") + item.text
                            parts: item.kind ? "" : item.rich
                            ink: item.out ? Theme.outText : Theme.inText
                            tint: item.out ? Theme.check : Theme.accent
                            size: item.jumbo === 1 ? 56 : item.jumbo === 2 ? 46 : item.jumbo === 3 ? 38 : 16
                            open: !!page.unfolded[item.msgId]
                            onLink: (url) => page.follow(url, item.msgId)
                            onTouched: (down) => { if (down) { rise.stop(); sink.restart() } else { sink.stop(); rise.restart() } }
                            onHeld: page.openMenu(item)
                            onTapped: if (item.media || item.rowKind) page.tapMedia(item)
                            onFold: page.unfold(item.msgId)
                        }
                        Flow {          // the reactions: emoji and how many, ours lit; a tap puts ours on or off.
                            id: reactRow    // More than a line holds go on to the next, the time by the last (Telegram-iOS)
                            visible: item.reacted
                            x: item.bare ? 0 : 10
                            y: body.y + body.height + (body.height ? 6 : 4)
                            readonly property real wants: item.reactList.reduce((w, r, k) =>
                                w + chipMetrics.advanceWidth(r.e + " " + r.n) + 16 + (k ? 4 : 0), 0)
                            width: Math.min(wants + 1, bubble.width - x - 10)
                            // the time by the last line, or under it when that line has no room
                            property bool stampBelow: false
                            onPositioningComplete: {
                                const last = children.length > 1 ? children[children.length - 2] : null     // (the Repeater is last)
                                stampBelow = !!last && last.x + last.width + stamp.implicitWidth + 12 > bubble.width - x - 10
                            }
                            height: visible ? implicitHeight + (stampBelow ? 18 : 0) : 0
                            spacing: 4
                            Repeater {
                                model: item.reactList
                                Rectangle {
                                    required property var modelData
                                    width: chipText.implicitWidth + 16; height: 28; radius: 14
                                    readonly property color ink: item.out ? Theme.check : Theme.accent
                                    color: modelData.mine ? ink : Qt.rgba(ink.r, ink.g, ink.b, 0.15)
                                    Text {
                                        id: chipText
                                        anchors.centerIn: parent
                                        text: parent.modelData.e + " " + parent.modelData.n
                                        color: parent.modelData.mine ? (Theme.dark && item.out ? Theme.bubbleOut : "white") : parent.ink
                                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: store.react(page.chatId, item.msgId, parent.modelData.e, !parent.modelData.mine)
                                    }
                                }
                            }
                        }
                        Rectangle {     // under the time when it is over a picture
                            visible: item.overlaid || item.jumbo > 0
                            anchors.fill: stamp; anchors.margins: -3; anchors.leftMargin: -6; anchors.rightMargin: -6
                            radius: height / 2
                            color: Qt.rgba(0, 0, 0, 0.4)
                        }
                        Row {           // the time: 📌, 👁 views, ↩ answers, edited, when, ✓ (Telegram-iOS's order)
                            id: stamp
                            anchors.right: parent.right; anchors.rightMargin: item.overlaid || item.jumbo ? (item.bare ? 8 : 12) : 10
                            anchors.bottom: parent.bottom; anchors.bottomMargin: bubble.tail + (item.overlaid || item.jumbo ? (item.bare ? 6 : 10) : 6)
                            spacing: 2
                            readonly property color ink: item.overlaid || item.jumbo ? "white" : item.out ? Theme.outMeta : Theme.inMeta
                            Icon {
                                visible: item.views > 0
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14; height: 14
                                name: "eye"; color: stamp.ink
                            }
                            Text {
                                visible: item.views > 0
                                text: store.short(item.views) + " "
                                color: stamp.ink
                                font.family: Theme.font; font.pixelSize: 12
                            }
                            Icon {
                                visible: item.replies > 0
                                anchors.verticalCenter: parent.verticalCenter
                                width: 13; height: 13
                                name: "reply"; color: stamp.ink
                            }
                            Text {
                                visible: item.replies > 0
                                text: item.replies + " "
                                color: stamp.ink
                                font.family: Theme.font; font.pixelSize: 12
                            }
                            Text {
                                textFormat: Text.StyledText
                                text: (item.isPinned ? "📌 " : "") + (item.edited ? "tahrirlandi " : "") + item.time +
                                      (item.out ? (item.sending ? " ◷" : " <font color='" + (item.overlaid || item.jumbo ? "white" : Theme.check) + "'>✓</font>") : "")
                                color: stamp.ink
                                font.family: Theme.font; font.pixelSize: 12
                            }
                        }
                        Item {          // a channel post's comments: how many, a tap opens them
                            visible: bubble.tail > 0
                            anchors.bottom: parent.bottom
                            width: parent.width; height: bubble.tail
                            Rectangle { x: 12; width: parent.width - 24; height: 1; color: Theme.fieldBorder }
                            Icon {
                                x: 10; anchors.verticalCenter: parent.verticalCenter
                                name: "chats"; color: Theme.accent; scale: 0.8
                            }
                            Text {
                                x: 40; anchors.verticalCenter: parent.verticalCenter
                                text: item.comments > 0 ? item.comments + " ta izoh" : "Izoh qoldirish"
                                color: Theme.accent
                                font.family: Theme.font; font.pixelSize: 15
                            }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                                text: "›"
                                color: Theme.accent
                                font.family: Theme.font; font.pixelSize: 22
                            }
                            MouseArea { anchors.fill: parent; onClicked: page.openComments(item.msgId) }
                        }
                    }
                    Rectangle {         // beside a channel's post: send it on (as Telegram has it)
                        visible: page.channel && !item.out
                        x: bubble.x + bubble.width + 8
                        y: bubble.y + bubble.height - bubble.tail - height
                        width: 32; height: 32; radius: 16
                        color: Qt.rgba(0, 0, 0, 0.22)
                        Icon { anchors.centerIn: parent; name: "forward"; color: "white"; scale: 0.72 }
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -6
                            onClicked: { page.forwarding = [item.msgId]; forwardSheet.show() }
                        }
                    }
                }
                Rectangle {          // «Tanlash»: its circle, filled and ticked once picked
                    visible: opacity > 0
                    opacity: item.pickable ? 1 : 0
                    x: item.pickable ? 12 : -16
                    y: item.above + (bubble.height - height) / 2
                    width: 26; height: 26; radius: 13
                    color: item.isPicked ? Theme.accent : Qt.rgba(0, 0, 0, 0.12)
                    border.color: item.isPicked ? Theme.accent : "white"; border.width: 1.5
                    Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: menu.spring } }
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    Icon { visible: item.isPicked; anchors.centerIn: parent; width: 18; height: 18; name: "check"; color: "white" }
                }
                MouseArea {          // while picking a tap anywhere on its row picks it (or puts it back)
                    anchors.fill: parent
                    visible: item.pickable
                    onClicked: page.pick(item.msgId)
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

        Glass {              // ↓: to the newest (loaded afresh when it was opened at the unread ones)
            id: toNewest
            z: 2
            anchors.right: parent.right; anchors.rightMargin: 10
            y: parent.height - page.kb - page.foot - height - 8
            width: 40; height: 40
            visible: page.ready && page.away
            Text {
                anchors.centerIn: parent
                text: "⌄"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 26
                anchors.verticalCenterOffset: -5
            }
            Rectangle {      // how many are unread
                visible: page.unread > 0
                anchors.horizontalCenter: parent.horizontalCenter
                y: -9
                width: Math.max(20, unreadText.implicitWidth + 10); height: 20; radius: 10
                color: Theme.badge
                Text {
                    id: unreadText
                    anchors.centerIn: parent
                    text: store.count(page.unread)
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                }
            }
            MouseArea {
                anchors.fill: parent; anchors.margins: -6
                onClicked: {
                    if (page.gap) {
                        page.fresh()
                        return
                    }
                    list.down = true
                    list.positionViewAtBeginning()
                }
            }
        }

        Rectangle {          // a chat with nothing in it yet: a card in the middle, as Telegram-iOS's
            visible: page.ready && messages.count === 0
            anchors.centerIn: parent
            transform: Translate { y: -page.kb / 2 }
            width: Math.min(parent.width - 80, 240); height: emptyText.height + 32
            radius: 18
            color: Theme.dayPill
            Column {
                id: emptyText
                anchors.centerIn: parent
                width: parent.width - 32
                spacing: 6
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Hali xabar yo'q"
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: page.canPost ? "Birinchi xabarni yozing." : "Bu yerga hali hech narsa yuborilmagan."
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 14
                }
            }
        }

        Item {               // the header, Telegram-iOS 26's: three glass pieces over the chat — ‹ and the
            id: bar          // chats waiting unread, the name and what it is, the picture (owner's iPad 26204/26206)
            z: 3
            width: parent.width; height: 60
            Rectangle {      // iOS 26's edge: what scrolls up fades out under the glass
                width: parent.width; height: parent.height + pinBar.height + 16
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(Theme.glass.r, Theme.glass.g, Theme.glass.b, 0.7) }
                    GradientStop { position: 0.6; color: Qt.rgba(Theme.glass.r, Theme.glass.g, Theme.glass.b, 0.35) }
                    GradientStop { position: 1; color: Qt.rgba(Theme.glass.r, Theme.glass.g, Theme.glass.b, 0) }
                }
            }
            Glass {          // ‹ 24
                id: backCap
                visible: !page.selecting
                x: 10; y: 8
                width: backRow.width + 26; height: 44
                opacity: backHit.pressed ? 0.5 : 1
                Row {
                    id: backRow
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -2
                        text: "‹"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 34; font.weight: Font.Light
                    }
                    Rectangle {
                        visible: store.unreadChats > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(height, backCount.implicitWidth + 12); height: 20; radius: 10
                        color: Theme.text
                        Text {
                            id: backCount
                            anchors.centerIn: parent
                            text: store.unreadChats > 99 ? "99+" : store.unreadChats
                            color: Theme.bg
                            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                    }
                }
            }
            MouseArea {          // the back button: the bar's whole height and from the edge, as iOS takes it
                id: backHit
                enabled: !page.selecting
                width: backCap.x + backCap.width + 4; height: parent.height
                onClicked: page.nav.pop()
            }
            Glass {          // the name, and under it what it is
                id: titleCap
                readonly property real room: bar.width - 2 * (page.selecting ? bar.width - cancelCap.x
                                                                 : Math.max(backCap.x + backCap.width, bar.width - face.x)) - 16
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                width: Math.min(room, Math.max(titleText.implicitWidth, subText.visible ? subText.implicitWidth : 0) + 40)
                height: 44
                opacity: titleHit.pressed ? 0.6 : 1
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 28
                    Text {
                        id: titleText
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: page.selecting ? (page.pickedIds.length ? page.pickedIds.length + " ta tanlandi" : "Xabarlarni tanlang")
                            : page.thread ? "Izohlar" : store.title(page.chat)
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                    }
                    Text {
                        id: subText
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: page.thread ? page.threadOf : (store.seen, page.now, store.status(page.chat, page.now))     // (re-read when either changes)
                        visible: text !== "" && !page.selecting
                        color: text === "onlayn" || text.endsWith("...") ? Theme.accent : Theme.grey
                        font.family: Theme.font; font.pixelSize: 12
                    }
                }
            }
            MouseArea {          // the title, or the picture: the page about the chat (in comments: the search)
                id: titleHit
                enabled: !page.selecting
                anchors.left: backHit.right; anchors.right: parent.right
                height: parent.height
                onClicked: {
                    if (page.thread)
                        page.focusFind()
                    else
                        page.nav.push(infoPage, { chatId: page.chatId, chatPage: page })
                }
            }
            Avatar {
                id: face
                anchors.right: parent.right; anchors.rightMargin: 10
                y: 8
                width: 44; height: 44
                source: page.chat ? store.photoPath(page.chat) : ""
                letters: page.chat ? store.letters(page.chat.title) : ""
                tint: store.tints[Math.abs(page.chatId) % store.tints.length]
                saved: store.isSaved(page.chat)
                visible: !page.selecting
            }
            Glass {          // picking: «Bekor» where the picture was
                id: cancelCap
                visible: page.selecting
                anchors.right: parent.right; anchors.rightMargin: 10
                y: 8
                width: cancelPick.implicitWidth + 32; height: 44
                opacity: cancelPickHit.pressed ? 0.6 : 1
                Text {
                    id: cancelPick
                    anchors.centerIn: parent
                    text: "Bekor"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Medium
                }
                MouseArea { id: cancelPickHit; anchors.fill: parent; anchors.margins: -6; onClicked: page.stopPicking() }
            }
        }

        Rectangle {          // searching: the field over the header, "Bekor" to leave
            z: 4
            visible: page.searching
            width: parent.width; height: bar.height
            color: Qt.rgba(Theme.bar.r, Theme.bar.g, Theme.bar.b, 1)     // (the bar itself lets its title through)
            MouseArea { anchors.fill: parent }
            Rectangle {
                x: 12; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - cancelFind.width - 26; height: 36; radius: 18
                color: Theme.dark ? Qt.rgba(0.46, 0.46, 0.5, 0.24) : Qt.rgba(0.46, 0.46, 0.5, 0.12)
                Icon {
                    x: 11; anchors.verticalCenter: parent.verticalCenter
                    name: "search"; width: 18; height: 18; color: Theme.grey
                }
                TextInput {
                    id: findField
                    x: 36; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - 12
                    color: Theme.text
                    selectionColor: Theme.accent
                    font.family: Theme.font; font.pixelSize: 16
                    clip: true
                    inputMethodHints: Qt.ImhNoPredictiveText
                    onTextChanged: findLater.restart()
                    onAccepted: { findLater.stop(); page.find(text); focus = false }
                    Text {
                        visible: !findField.text
                        text: "Chatdan qidirish"
                        color: Theme.grey
                        font: findField.font
                    }
                }
                Timer { id: findLater; interval: 400; onTriggered: page.find(findField.text) }
            }
            Text {
                id: cancelFind
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "Bekor"
                color: Theme.accent
                font.family: Theme.font; font.pixelSize: 16
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: page.stopSearch() }
            }
        }

        Rectangle {          // searching: under the messages, which one of how many, ↑ older ↓ newer
            id: findBar
            z: 2
            visible: page.searching
            anchors.bottom: parent.bottom
            transform: Translate { y: -page.kb }
            width: parent.width; height: 52
            color: Theme.bar
            MouseArea { anchors.fill: parent }
            Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
            Row {
                x: 8; anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: [{ g: "⌃", d: 1 }, { g: "⌄", d: -1 }]
                    Text {
                        required property var modelData
                        readonly property int to: page.hit + modelData.d
                        readonly property bool can: to >= 0 && to < page.hits.length
                        width: 44; height: 44
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        text: modelData.g
                        color: can ? Theme.accent : Theme.grey
                        font.family: Theme.font; font.pixelSize: 26; font.weight: Font.DemiBold
                        MouseArea { anchors.fill: parent; enabled: parent.can; onClicked: page.showHit(parent.to) }
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                text: page.hits.length ? store.count(page.hits.length) + " tadan " + (page.hit + 1)
                    : page.searched ? "Hech narsa topilmadi" : ""
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 15
            }
        }

        Item {               // under the header, one glass panel as Telegram-iOS 26's (owner's iPad 26204/26206):
            id: pinBar       // who asks to join (admins), the pinned message (ChatPinnedMessageTitlePanelNode)
            z: 3
            y: bar.height
            width: parent.width
            height: panel.height > 0 ? panel.height + 8 : 0
            visible: height > 0
            Glass {
                id: panel
                x: 10; y: 2
                width: parent.width - 20
                height: (page.askingShown ? 48 : 0) + (page.pinned ? 48 : 0) + (page.translatable ? 48 : 0)
                radius: 20
                clip: true
                Item {          // "N ta qo'shilish so'rovi": the first one's picture, a tap lists them, × hides
                    id: askRow
                    width: parent.width; height: page.askingShown ? 48 : 0
                    visible: height > 0
                    opacity: askHit.pressed ? 0.6 : 1
                    property string photo: ""
                    readonly property var first: page.asking && page.asking.user_ids.length
                                                 ? (store.seen, store.users[page.asking.user_ids[0]]) : null
                    onFirstChanged: { photo = ""; if (first) store.userPhoto(first, (p) => askRow.photo = p) }
                    Avatar {
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        width: 34; height: 34
                        source: askRow.photo
                        letters: askRow.first ? store.letters(askRow.first.first_name + " " + askRow.first.last_name) : ""
                        tint: store.tints[Math.abs(askRow.first ? askRow.first.id : 0) % store.tints.length]
                    }
                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 120
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: page.asking ? store.count(page.asking.total_count) + " ta qo'shilish so'rovi" : ""
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 15
                    }
                    MouseArea {
                        id: askHit
                        anchors.fill: parent
                        onClicked: page.nav.push(joinPage, { chatId: page.chatId })
                    }
                    Icon {
                        anchors.right: parent.right; anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20; height: 20
                        name: "cross"
                        color: Theme.text
                        MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: page.askingHidden = page.asking.total_count }
                    }
                    Rectangle {
                        visible: !!page.pinned
                        x: 14; anchors.bottom: parent.bottom; width: parent.width - 28; height: 0.5; color: Theme.separator
                    }
                }
                Item {          // "O'zbek tiliga tarjima qilish" / back to the original; ⋯: not for this chat
                    id: transRow
                    y: askRow.height + pinRow.height
                    width: parent.width; height: page.translatable ? 48 : 0
                    visible: height > 0
                    Rectangle {
                        visible: askRow.visible || pinRow.visible
                        x: 14; width: parent.width - 28; height: 0.5; color: Theme.separator
                    }
                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        opacity: transHit.pressed ? 0.5 : 1
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22; height: 22
                            name: "translate"
                            color: Theme.text
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.translating ? "Asl nusxasini ko'rsatish" : "O'zbek tiliga tarjima qilish"
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 16
                        }
                    }
                    MouseArea {
                        id: transHit
                        anchors.fill: parent; anchors.rightMargin: 52
                        onClicked: page.setTranslating(!page.translating)
                    }
                    Rectangle {      // ⋯
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26; height: 26; radius: 13
                        color: "transparent"
                        border.color: Theme.text; border.width: 1.5
                        opacity: moreHit.pressed ? 0.5 : 1
                        Row {
                            anchors.centerIn: parent
                            spacing: 3
                            Repeater { model: 3; Rectangle { width: 3; height: 3; radius: 1.5; color: Theme.text } }
                        }
                        MouseArea { id: moreHit; anchors.fill: parent; anchors.margins: -10; onClicked: transMenu.show() }
                    }
                }
                Item {          // the pinned message: a tap goes to it
                    id: pinRow
                    y: askRow.height
                    width: parent.width; height: page.pinned ? 48 : 0
                    visible: height > 0
                    opacity: pinHit.pressed ? 0.6 : 1
                    Rectangle { x: 14; y: 9; width: 2.5; height: 30; radius: 1.25; color: Theme.accent }
                    Text {
                        x: 26; y: 6
                        text: "Qadalgan xabar"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    Text {
                        x: 26; y: 25
                        width: parent.width - x - 48
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        textFormat: Text.PlainText
                        text: page.pinned ? page.pinned.text.replace(/\s+/g, " ") : ""
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 14
                    }
                    Icon {
                        anchors.right: parent.right; anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20; height: 20
                        name: "pin"
                        color: Theme.text
                    }
                    MouseArea {
                        id: pinHit
                        anchors.fill: parent
                        onClicked: page.goTo(page.pinned.id)
                    }
                }
            }
        }

        Item {               // a channel we only read: its sound on or off instead of the field, a capsule
            id: chanBar      // and a round 🔍 of glass floating over the posts (Telegram-iOS 26, owner's IMG_0092)
            z: 1
            visible: !page.canPost && !page.searching && !page.selecting
            anchors.bottom: parent.bottom
            width: parent.width
            height: visible ? 60 : 0
            Glass {
                anchors.centerIn: parent
                width: muteText.implicitWidth + 44; height: 44
                opacity: muteHit.pressed ? 0.7 : 1
                Text {
                    id: muteText
                    anchors.centerIn: parent
                    text: page.outside ? "Qo'shilish" : page.muted ? "Sukutdan chiqarish" : "Sukut qilish"
                    color: page.outside ? Theme.accent : Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Medium
                }
                MouseArea {
                    id: muteHit
                    anchors.fill: parent
                    onClicked: {
                        if (page.outside)
                            return store.send({ "@type": "joinChat", chat_id: page.chatId }, store.check)
                        const n = Object.assign({}, page.chat.notification_settings)
                        n["@type"] = "chatNotificationSettings"
                        n.use_default_mute_for = false
                        n.mute_for = page.muted ? 0 : 2147483647
                        page.muted = !page.muted        // at once; TDLib's update says the same
                        store.send({ "@type": "setChatNotificationSettings", chat_id: page.chatId, notification_settings: n }, store.check)
                    }
                }
            }
            Glass {              // (as IMG_0297: the search on the bar's right)
                anchors.right: parent.right; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 44
                opacity: findHit.pressed ? 0.7 : 1
                Icon { anchors.centerIn: parent; name: "search"; color: Theme.text }
                MouseArea { id: findHit; anchors.fill: parent; onClicked: { page.searching = true; findField.forceActiveFocus() } }
            }
        }

        Item {               // picking: what goes for all of them — deleted (🗑, left), their words copied
            id: pickBar      // (the middle), forwarded (right); each a piece of glass as the field's
            z: 1
            visible: page.selecting
            anchors.bottom: parent.bottom
            width: parent.width
            height: visible ? 60 : 0
            Glass {
                x: 10; anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 44
                opacity: !page.pickedDeletable ? 0.4 : trashHit.pressed ? 0.7 : 1
                Icon { anchors.centerIn: parent; name: "trash"; color: Theme.danger }
                MouseArea { id: trashHit; anchors.fill: parent; enabled: page.pickedDeletable; onClicked: deleteMenu.show() }
            }
            Glass {
                anchors.centerIn: parent
                visible: page.pickedText !== ""
                width: copyPickText.implicitWidth + 44; height: 44
                opacity: copyPickHit.pressed ? 0.7 : 1
                Text {
                    id: copyPickText
                    anchors.centerIn: parent
                    text: "Nusxalash"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Medium
                }
                MouseArea {
                    id: copyPickHit
                    anchors.fill: parent
                    onClicked: {
                        page.copy(page.pickedText)
                        page.toast(page.pickedIds.length > 1 ? page.pickedIds.length + " ta xabar nusxalandi" : "Nusxalandi")
                        page.stopPicking()
                    }
                }
            }
            Glass {
                anchors.right: parent.right; anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 44
                readonly property bool can: page.pickedCan("can_be_forwarded")
                opacity: !can ? 0.4 : fwdPickHit.pressed ? 0.7 : 1
                Icon { anchors.centerIn: parent; name: "forward"; color: Theme.text }
                MouseArea { id: fwdPickHit; anchors.fill: parent; enabled: parent.can; onClicked: page.forwardPicked() }
            }
        }

        Item {               // the field, with what it answers or edits over it: Telegram-iOS 26's glass
            id: input        // floating over the chat — 📎, the field, the mic, each its own piece
            z: 1
            visible: page.canPost && !page.searching && !page.selecting
            anchors.bottom: parent.bottom
            transform: Translate { y: -page.kb }
            width: parent.width
            height: visible ? compose.height + Math.max(60, field.contentHeight + 38) : 0
            onHeightChanged: if (list.down && !scroll.running) Qt.callLater(list.positionViewAtBeginning)
            Glass {              // the field's menu (held): as iOS's edit menu, and Telegram's «Format»
                id: fieldMenu
                property bool shown: false
                property bool formats: false        // B I U S … in place of cut/copy/paste
                property bool linking: false        // the address of a link being written
                readonly property bool chosen: field.selectionEnd > field.selectionStart
                visible: shown && (field.activeFocus || link.activeFocus)
                onVisibleChanged: if (!visible) { formats = false; linking = false; shown = false }
                anchors.horizontalCenter: parent.horizontalCenter
                y: -height - 4
                height: 44
                width: Math.min(parent.width - 16, (linking ? linkRow.implicitWidth : acts.implicitWidth) + 12)
                radius: 22
                z: 3
                readonly property var plainActs: (chosen ? [
                    { t: "Kesish", run: () => field.cut() }, { t: "Nusxa", run: () => field.copy() } ] : [])
                    .concat(field.canPaste ? [{ t: "Joylash", run: () => field.paste() }] : [])
                    .concat(field.text && !(field.selectionStart === 0 && field.selectionEnd === field.length)
                            ? [{ t: "Hammasi", keep: true, run: () => field.selectAll() }] : [])
                    .concat(chosen ? [{ t: "Format ›", keep: true, run: () => fieldMenu.formats = true }] : [])
                readonly property var formatActs: [
                    { t: "B", w: Font.Bold, k: "textEntityTypeBold" }, { t: "I", i: true, k: "textEntityTypeItalic" },
                    { t: "U", u: true, k: "textEntityTypeUnderline" }, { t: "S", s: true, k: "textEntityTypeStrikethrough" },
                    { t: "Kod", mono: true, k: "textEntityTypeCode" }, { t: "Spoyler", k: "textEntityTypeSpoiler" },
                    { t: "Iqtibos", k: "textEntityTypeBlockQuote" }, { t: "Havola", k: "textEntityTypeTextUrl" }]
                onFormatsChanged: menuFlick.contentX = 0
                Flickable {
                    id: menuFlick
                    anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                    visible: !fieldMenu.linking
                    contentWidth: acts.implicitWidth
                    clip: true
                    Row {
                        id: acts
                        height: 44
                        Repeater {
                            model: fieldMenu.formats ? fieldMenu.formatActs : fieldMenu.plainActs
                            delegate: Item {
                                required property var modelData
                                required property int index
                                readonly property bool on: !!modelData.k && page.marked(modelData.k)
                                width: word.implicitWidth + 18; height: 44
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width - 6; height: 32; radius: 16
                                    color: parent.on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) : "transparent"
                                }
                                Text {
                                    id: word
                                    anchors.centerIn: parent
                                    text: modelData.t
                                    color: parent.on ? Theme.accent : Theme.text
                                    font.family: modelData.mono ? "monospace" : Theme.font; font.pixelSize: 15
                                    font.weight: modelData.w || Font.Normal; font.italic: !!modelData.i
                                    font.underline: !!modelData.u; font.strikeout: !!modelData.s
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        const a = modelData
                                        if (a.k === "textEntityTypeTextUrl" && !page.marked(a.k)) {
                                            fieldMenu.linking = true
                                            link.text = ""
                                            link.forceActiveFocus()
                                            return
                                        }
                                        if (a.k)
                                            return page.toggleMark(a.k)
                                        a.run()
                                        if (!a.keep)
                                            fieldMenu.shown = false
                                    }
                                }
                            }
                        }
                    }
                }
                Row {                // Havola: the address, ✓ to put it on the chosen words
                    id: linkRow
                    visible: fieldMenu.linking
                    x: 14; height: 44; spacing: 10
                    TextInput {
                        id: link
                        anchors.verticalCenter: parent.verticalCenter
                        width: 220
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 15
                        inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                        Text { visible: !link.text; text: "https://"; color: Theme.grey; font: link.font }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✓"; color: Theme.accent; font.pixelSize: 20; font.weight: Font.Bold
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -10
                            onClicked: {
                                const u = link.text.trim()
                                if (u)
                                    page.toggleMark("textEntityTypeTextUrl", /^[a-z][a-z0-9+.-]*:/i.test(u) ? u : "https://" + u)
                                fieldMenu.linking = false
                                field.forceActiveFocus()
                            }
                        }
                    }
                }
            }
            Glass {              // the clip: pictures and files from the phone
                x: 8
                anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                width: 44; height: 44
                visible: !page.editing
                opacity: clipHit.pressed ? 0.7 : 1
                Icon { anchors.centerIn: parent; width: 26; height: 26; name: "clip"; color: Theme.text }
                MouseArea {
                    id: clipHit
                    anchors.fill: parent
                    onClicked: {
                        Qt.inputMethod.hide()
                        sheet.show()
                    }
                }
            }
            Glass {
                id: fieldBox
                x: page.editing ? 8 : 58; y: 8
                width: parent.width - x - 58; height: parent.height - 16
                radius: 22
                Item {           // what it answers or edits, at the top of the field's glass
                    id: compose
                    width: parent.width
                    height: page.replying || page.editing ? 46 : 0
                    visible: height > 0
                    Rectangle { x: 14; y: 8; width: 2; height: 32; radius: 1; color: Theme.accent }
                    Text {
                        x: 24; y: 7
                        width: parent.width - 60
                        elide: Text.ElideRight
                        text: page.editing ? "Tahrirlash" : page.replying ? "Javob: " + page.replying.name : ""
                        color: Theme.accent
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    Text {
                        x: 24; y: 25
                        width: parent.width - 60
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        textFormat: Text.PlainText
                        text: page.replying ? page.replying.text.replace(/\s+/g, " ") : ""
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 14
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✕"
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 18
                        MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: page.cancelCompose() }
                    }
                }
                TextEdit {
                    id: field
                    x: 14; y: compose.height + 11
                    width: parent.width - 28 - (bell.visible ? 30 : 0) - (clock.visible ? 30 : 0)
                    wrapMode: TextEdit.Wrap
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16
                    onTextChanged: page.reMark()
                    persistentSelection: fieldMenu.linking      // the chosen words, while their link is written
                    onSelectedTextChanged: if (!selectedText && fieldMenu.shown && fieldMenu.formats) fieldMenu.shown = false
                    // held: the word under the finger chosen, and the field's menu. Chosen once let go:
                    // a touch's release puts the cursor and would undo it
                    TapHandler {
                        property int at: -1          // where it was held
                        onLongPressed: at = field.positionAt(point.position.x, point.position.y)
                        onPressedChanged: if (!pressed && at >= 0) Qt.callLater(() => {
                            if (field.text && !(at >= field.selectionStart && at < field.selectionEnd)) {
                                field.cursorPosition = at
                                field.selectWord()
                            }
                            at = -1
                            fieldMenu.formats = false
                            fieldMenu.shown = true
                        })
                        onTapped: fieldMenu.shown = false
                    }
                    Text {
                        visible: !field.text && !field.preeditText
                        text: page.channel ? "Xabar tarqatish" : "Xabar"
                        color: Theme.grey
                        font: field.font
                    }
                }
                Item {           // ⏱: how long messages stay (Telegram-iOS's auto-delete button), the time when set
                    id: clock
                    visible: page.canAutoDelete && !page.editing
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.bottom: parent.bottom; anchors.bottomMargin: (44 - height) / 2
                    width: 22; height: 22
                    Icon {
                        visible: !page.autoDelete
                        anchors.fill: parent
                        name: "timer"
                        color: Theme.grey
                    }
                    Rectangle {
                        visible: page.autoDelete > 0
                        anchors.centerIn: parent
                        width: Math.max(22, clockText.implicitWidth + 8); height: 22; radius: 11
                        color: "transparent"
                        border.color: Theme.accent; border.width: 1.5
                        Text {
                            id: clockText
                            anchors.centerIn: parent
                            text: store.lastingShort(page.autoDelete)
                            color: Theme.accent
                            font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                        }
                    }
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: timerMenu.show() }
                }
                Icon {           // a channel's 🔔: the post with or without a sound (Telegram-iOS's silent posting)
                    id: bell
                    visible: page.channel && !page.editing
                    anchors.right: clock.visible ? clock.left : parent.right; anchors.rightMargin: clock.visible ? 8 : 12
                    anchors.bottom: parent.bottom; anchors.bottomMargin: (44 - height) / 2
                    width: 22; height: 22
                    name: "bell"
                    color: Theme.grey
                    Rectangle {     // the stroke through it when silent
                        visible: page.silent
                        anchors.centerIn: parent
                        width: 2; height: 26; radius: 1
                        rotation: -45
                        color: Theme.grey
                        border.color: Theme.glass; border.width: 0.5
                    }
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: page.setSilent(!page.silent) }
                }
            }
            Rectangle {          // recording: the time, and how to let it go (over the clip and the field)
                id: recBar
                visible: page.recording
                x: 8; y: fieldBox.y + compose.height
                width: parent.width - 66; height: fieldBox.height - compose.height
                radius: 22
                color: Theme.glass
                Rectangle {
                    id: dot
                    x: 18; anchors.verticalCenter: parent.verticalCenter
                    width: 10; height: 10; radius: 5
                    color: Theme.danger
                    SequentialAnimation on opacity {
                        running: page.recording; loops: Animation.Infinite
                        OpacityAnimator { from: 1; to: 0.2; duration: 500 }
                        OpacityAnimator { from: 0.2; to: 1; duration: 500 }
                    }
                }
                Text {
                    x: 36; anchors.verticalCenter: parent.verticalCenter
                    readonly property int tenths: Math.floor(page.recordMs / 100)
                    text: Math.floor(tenths / 600) + ":" + String(Math.floor(tenths / 10) % 60).padStart(2, "0") + "," + tenths % 10
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.features: { "tnum": 1 }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: parent.width - implicitWidth - 12 + Math.min(0, page.recordSlide)
                    opacity: 1 - Math.min(0.8, -page.recordSlide / 150)
                    text: page.recordSlide < -110 ? "Qo'yib yuboring — bekor bo'ladi" : "‹ bekor qilish uchun suring"
                    color: page.recordSlide < -110 ? Theme.danger : Theme.grey
                    font.family: Theme.font; font.pixelSize: 14
                }
            }
            Rectangle {          // send (✓ for an edit); with the field empty, the mic: held, it records
                id: sendButton
                readonly property bool mic: !field.text.trim() && !page.editing
                anchors.right: parent.right; anchors.rightMargin: 8
                anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                width: 44; height: 44; radius: 22
                color: mic ? (page.recording ? Theme.danger : "transparent") : field.text.trim() ? Theme.accent : Theme.mutedBadge
                scale: page.recording ? 1.6 : 1
                Behavior on scale { ScaleAnimator { duration: 200; easing.type: Easing.OutBack } }
                Glass {          // the mic's own round glass (the send button is the accent's colour)
                    z: -1
                    anchors.fill: parent
                    visible: sendButton.mic && !page.recording
                }
                Icon {
                    visible: sendButton.mic
                    anchors.centerIn: parent
                    width: 26; height: 26
                    name: "mic"
                    color: page.recording ? "white" : Theme.text
                }
                Text { visible: !sendButton.mic; anchors.centerIn: parent; text: page.editing ? "✓" : "↑"; color: "white"; font.pixelSize: 20; font.weight: Font.Bold }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -6
                    property real startX: 0
                    onPressed: (m) => {
                        if (!sendButton.mic)
                            return
                        startX = m.x
                        page.startVoice()
                    }
                    onPositionChanged: (m) => { if (page.recording) page.recordSlide = m.x - startX }
                    onReleased: if (page.recording) page.stopVoice(page.recordSlide < -110)
                    onCanceled: if (page.recording) page.stopVoice(true)
                    onClicked: {
                        if (sendButton.mic)
                            return
                        const w = page.fieldWords(), t = w.text
                        if (!t)
                            return
                        if (page.editing) {
                            store.editText(page.chatId, page.editing.id, t, w.marks)
                            page.editing = null
                            field.text = ""
                            return
                        }
                        if (page.gap)           // what is sent goes under the newest: go there first
                            page.fresh()
                        const at = field.mapToItem(page, 0, 0)
                        page.flying = { text: t, x: at.x, y: at.y }
                        store.sendText(page.chatId, t, page.replying ? page.replying.id : 0, page.thread, page.silent, w.marks)
                        page.replying = null
                        field.text = ""
                        list.positionViewAtBeginning()
                    }
                }
            }
        }
    }

    Component { id: infoPage; ChatInfoPage {} }
    Component { id: joinPage; JoinRequestsPage {} }
    PhotoViewer {
        id: viewer
        store: page.store
        chatId: page.chatId
        thread: page.thread
        locate: (id) => {           // a paged-to message's picture, when its bubble is on the page
            const i = page.indexOf(id)
            const it = i >= 0 ? list.itemAtIndex(i) : null
            return it && it.media ? it.picFace : null
        }
        onSave: {
            const s = viewer.current
            if (s && s.file)
                store.saveFile(s.file, s.name, (text) => { if (page) page.toast(text) })
            else if (page.viewing)
                page.save(page.viewing)
        }
    }

    ForwardSheet {
        id: forwardSheet
        store: page.store
        onPicked: (to, title) => store.forward(to, page.chatId, page.forwarding, page.copying, (ok) => {
            if (page && ok)
                page.toast("Uzatildi: " + title)
        })
    }

    AttachSheet {
        id: sheet
        onSend: (picked, asFiles) => {
            if (page.gap)
                page.fresh()
            store.sendFiles(page.chatId, picked, field.text.trim(), page.replying ? page.replying.id : 0, asFiles, page.thread, page.silent)
            field.text = ""
            page.replying = null
            list.down = true
            list.positionViewAtBeginning()
        }
    }

    Rectangle {          // a word that comes and goes (saved, no mic)
        id: toastBox
        z: 25
        anchors.horizontalCenter: parent.horizontalCenter
        y: bar.height + pinBar.height + 12
        width: Math.min(parent.width - 40, toastText.implicitWidth + 28); height: toastText.implicitHeight + 16
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.75)
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }      // (an Animator would set it only at the end)
        Text {
            id: toastText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.parent.width - 68)
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            color: "white"
            font.family: Theme.font; font.pixelSize: 14
        }
    }
    Timer { id: toastAway; interval: 2200; onTriggered: toastBox.opacity = 0 }

    // ---- a voice note ----------------------------------------------------------
    // held: it records (Ogg Opus, what Telegram's voice notes are); let go: it is sent, its
    // waveform worked out from the file (td.voice); slid left: thrown away
    property bool recording: false
    property real recordMs: 0
    property real recordSlide: 0
    property bool recordCancel: false
    property real recordFrom: 0
    MediaDevices { id: devices }
    Timer {
        interval: 100; repeat: true; running: page.recording
        onTriggered: page.recordMs = Date.now() - page.recordFrom
    }
    Timer {             // Telegram shows "ovozli xabar yozmoqda" while it lasts: say it again now and then
        interval: 4000; repeat: true; running: page.recording
        onTriggered: page.acting("chatActionRecordingVoiceNote")
    }
    function acting(what) {
        store.send({ "@type": "sendChatAction", chat_id: chatId, action: what ? { "@type": what } : null })
    }
    function startVoice() {
        if (devices.audioInputs.length === 0) {
            toast("Mikrofon topilmadi — telefonning mikrofoni hali ulanmagan")
            return
        }
        sound.pause()
        roundId = 0
        recordCancel = false
        recordSlide = 0
        recordMs = 0
        recordFrom = Date.now()
        mic.device = devices.defaultAudioInput     // (the one there now: it was made with what there was then)
        recorder.outputLocation = "file://" + td.voicePath()
        recording = true
        recorder.record()
        acting("chatActionRecordingVoiceNote")
    }
    function stopVoice(cancel) {
        recordCancel = cancel || Date.now() - recordFrom < 700     // a tap is not a voice note
        if (recordCancel && Date.now() - recordFrom < 700)
            toast("Ovozli xabar uchun tugmani bosib turing")
        recording = false
        recorder.stop()
        acting("")
    }
    function recorded() {
        const at = String(recorder.actualLocation).replace(/^file:\/\//, "")
        if (recordCancel || !at)
            return
        const v = td.voice(at)
        if (page.gap)
            page.fresh()
        store.sendVoice(chatId, at, v.duration, v.waveform, replying ? replying.id : 0, thread, silent)
        replying = null
        list.down = true
        list.positionViewAtBeginning()
    }
    CaptureSession {
        audioInput: AudioInput { id: mic }
        recorder: MediaRecorder {
            id: recorder
            mediaFormat {
                fileFormat: MediaFormat.Ogg
                audioCodec: MediaFormat.AudioCodec.Opus
            }
            audioChannelCount: 1
            audioSampleRate: 48000
            audioBitRate: 32000
            encodingMode: MediaRecorder.ConstantBitRateEncoding
            onRecorderStateChanged: if (recorderState === MediaRecorder.StoppedState) page.recorded()
            onErrorOccurred: (error, text) => {
                page.recording = false
                page.toast("Yozib bo'lmadi: " + text)
            }
        }
    }

    Item {               // ⏱'s choices, over the field as Telegram-iOS's context menu
        id: timerMenu
        z: 30
        anchors.fill: parent
        visible: false
        function show() {
            Qt.inputMethod.hide()
            visible = true
            card.scale = 0.01
            grow.start()
        }
        MouseArea { anchors.fill: parent; onClicked: timerMenu.visible = false }
        Rectangle {
            id: card
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.bottom: parent.bottom; anchors.bottomMargin: page.foot + 8
            width: 230; height: choices.height
            radius: 16
            color: Theme.menu
            transformOrigin: Item.BottomRight
            layer.enabled: true
            ScaleAnimator { id: grow; target: card; from: 0.01; to: 1; duration: 420
                            easing.type: Easing.BezierSpline; easing.bezierCurve: menu.spring }
            Column {
                id: choices
                width: parent.width
                Text {
                    x: 16; width: parent.width - 32
                    topPadding: 10; bottomPadding: 6
                    wrapMode: Text.Wrap
                    text: "Yangi xabarlar shuncha vaqtdan keyin o'chadi"
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 13
                }
                Repeater {
                    model: [0, 86400, 604800, 2678400]
                    Rectangle {
                        required property int modelData
                        width: choices.width; height: 44
                        color: choiceHit.pressed ? Theme.highlight : "transparent"
                        Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                        Text {
                            x: 16; anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData ? store.lasting(parent.modelData) : "O'chirilgan"
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 16
                        }
                        Text {
                            visible: page.autoDelete === parent.modelData
                            anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                            text: "✓"
                            color: Theme.accent
                            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                        }
                        MouseArea {
                            id: choiceHit
                            anchors.fill: parent
                            onClicked: {
                                timerMenu.visible = false
                                if (parent.modelData !== page.autoDelete)
                                    page.setAutoDelete(parent.modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    Item {               // the picked ones deleted: for us, or for everyone too (as the ⏱'s choices)
        id: deleteMenu
        z: 30
        anchors.fill: parent
        visible: false
        // what TDLib lets with all of them: both, or only one of the two
        readonly property var choices: {
            const all = page.pickedCan("can_be_deleted_for_all_users"), self = page.pickedCan("can_be_deleted_only_for_self")
            return all && self ? [{ t: "Hamma uchun o'chirish", everyone: true }, { t: "Men uchun o'chirish", everyone: false }]
                 : all ? [{ t: "O'chirish", everyone: true }] : [{ t: "Men uchun o'chirish", everyone: false }]
        }
        function show() {
            visible = true
            delCard.scale = 0.01
            delGrow.start()
        }
        MouseArea { anchors.fill: parent; onClicked: deleteMenu.visible = false }
        Rectangle {
            id: delCard
            x: 10
            anchors.bottom: parent.bottom; anchors.bottomMargin: page.foot + 8
            width: 250; height: delChoices.height
            radius: 16
            color: Theme.menu
            transformOrigin: Item.BottomLeft
            layer.enabled: true
            ScaleAnimator { id: delGrow; target: delCard; from: 0.01; to: 1; duration: 420
                            easing.type: Easing.BezierSpline; easing.bezierCurve: menu.spring }
            Column {
                id: delChoices
                width: parent.width
                Text {
                    x: 16; width: parent.width - 32
                    topPadding: 10; bottomPadding: 6
                    wrapMode: Text.Wrap
                    text: page.pickedIds.length > 1 ? page.pickedIds.length + " ta xabar o'chirilsinmi?" : "Xabar o'chirilsinmi?"
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 13
                }
                Repeater {
                    model: deleteMenu.choices
                    Rectangle {
                        required property var modelData
                        width: delChoices.width; height: 44
                        color: delHit.pressed ? Theme.highlight : "transparent"
                        Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                        Text {
                            x: 16; anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.t
                            color: Theme.danger
                            font.family: Theme.font; font.pixelSize: 16
                        }
                        MouseArea {
                            id: delHit
                            anchors.fill: parent
                            onClicked: {
                                deleteMenu.visible = false
                                page.deletePicked(parent.modelData.everyone)
                            }
                        }
                    }
                }
            }
        }
    }

    Item {               // Shikoyat qilish: why (Telegram's options), or a few words, a step at a time
        id: reportMenu
        z: 30
        anchors.fill: parent
        visible: false
        property var step: null         // { ids, title, options } or { ids, option, optional }
        function ask(st) {
            step = st
            why.text = ""
            visible = true
            reportCard.scale = 0.01
            reportGrow.start()
            if (!st.options)
                why.forceActiveFocus()
        }
        function close() {
            visible = false
            why.focus = false
        }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.25) }
        MouseArea { anchors.fill: parent; onClicked: reportMenu.close() }
        Rectangle {
            id: reportCard
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(60, (parent.height - page.kb - height) / 2)
            width: Math.min(parent.width - 48, 300); height: Math.min(steps.height, parent.height - page.kb - 120)
            radius: 16
            clip: true
            color: Theme.menu
            layer.enabled: true
            ScaleAnimator { id: reportGrow; target: reportCard; from: 0.01; to: 1; duration: 420
                            easing.type: Easing.BezierSpline; easing.bezierCurve: menu.spring }
            MouseArea { anchors.fill: parent }      // (not through to the shade, which closes it)
            Flickable {
                anchors.fill: parent
                contentHeight: steps.height
                Column {
                    id: steps
                    width: reportCard.width
                    readonly property var st: reportMenu.step || {}
                    Text {
                        x: 16; width: parent.width - 32
                        topPadding: 14; bottomPadding: 8
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                        text: steps.st.options ? (steps.st.title || "Shikoyat sababi") : "Batafsil yozing" + (steps.st.optional ? " (ixtiyoriy)" : "")
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                    Repeater {
                        model: steps.st.options || []
                        Rectangle {
                            required property var modelData
                            width: steps.width; height: Math.max(44, optText.implicitHeight + 20)
                            color: optHit.pressed ? Theme.highlight : "transparent"
                            Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                            Text {
                                id: optText
                                x: 16; width: parent.width - 48
                                anchors.verticalCenter: parent.verticalCenter
                                wrapMode: Text.Wrap
                                text: parent.modelData.text
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: 16
                            }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                                text: "›"; color: Theme.grey; font.pixelSize: 20
                            }
                            MouseArea {
                                id: optHit
                                anchors.fill: parent
                                onClicked: {
                                    const ids = steps.st.ids
                                    reportMenu.close()
                                    page.report(ids, parent.modelData.id, "")
                                }
                            }
                        }
                    }
                    Rectangle {          // the words, when Telegram asks for them
                        visible: !steps.st.options
                        x: 16; width: parent.width - 32
                        height: visible ? Math.max(44, why.contentHeight + 20) : 0
                        radius: 10
                        color: Theme.field
                        TextEdit {
                            id: why
                            x: 10; y: 10; width: parent.width - 20
                            wrapMode: TextEdit.Wrap
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 16
                        }
                    }
                    Rectangle {
                        visible: !steps.st.options
                        width: steps.width; height: visible ? 52 : 0
                        color: "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "Yuborish"
                            color: steps.st.optional || why.text.trim() ? Theme.accent : Theme.grey
                            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (!steps.st.optional && !why.text.trim())
                                    return
                                const st = steps.st
                                reportMenu.close()
                                page.report(st.ids, st.option, why.text.trim())
                            }
                        }
                    }
                    Rectangle {
                        width: steps.width; height: 48
                        color: cancelHit.pressed ? Theme.highlight : "transparent"
                        Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                        Text {
                            anchors.centerIn: parent
                            text: "Bekor qilish"
                            color: Theme.accent
                            font.family: Theme.font; font.pixelSize: 17
                        }
                        MouseArea { id: cancelHit; anchors.fill: parent; onClicked: reportMenu.close() }
                    }
                }
            }
        }
    }

    Item {               // ⋯ of the translation row: hide it for this chat (Telegram-iOS: "Tarjima qilmaslik")
        id: transMenu
        z: 30
        anchors.fill: parent
        visible: false
        function show() {
            visible = true
            transCard.scale = 0.01
            transGrow.start()
        }
        MouseArea { anchors.fill: parent; onClicked: transMenu.visible = false }
        Rectangle {
            id: transCard
            anchors.right: parent.right; anchors.rightMargin: 16
            y: pinBar.y + pinBar.height
            width: 250; height: 44
            radius: 16
            color: Theme.menu
            transformOrigin: Item.TopRight
            layer.enabled: true
            ScaleAnimator { id: transGrow; target: transCard; from: 0.01; to: 1; duration: 420
                            easing.type: Easing.BezierSpline; easing.bezierCurve: menu.spring }
            Rectangle {
                anchors.fill: parent; radius: parent.radius
                color: hideHit.pressed ? Theme.highlight : "transparent"
            }
            Text {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                text: "Bu chatni tarjima qilmaslik"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16
            }
            MouseArea {
                id: hideHit
                anchors.fill: parent
                onClicked: {
                    transMenu.visible = false
                    page.setTranslating(false)
                    store.send({ "@type": "toggleChatIsTranslatable", chat_id: page.chatId, is_translatable: false })
                }
            }
        }
    }

    FontMetrics {        // a reaction's chip, measured before it is made (the bubble's width)
        id: chipMetrics
        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
    }

    MessageMenu {
        id: menu
        behind: content
        ceiling: bar.height
        floor: page.height
        onReacted: (emoji) => {
            store.react(page.chatId, page.reacting, emoji, menu.chosen.indexOf(emoji) < 0)
        }
    }
}
