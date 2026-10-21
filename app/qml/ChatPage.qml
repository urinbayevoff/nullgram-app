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
        if (!channel)
            return true
        const g = (store.seen, store.groups["s" + chat.type.supergroup_id])
        const st = g ? g.status : null
        return !!st && (st["@type"] === "chatMemberStatusCreator" ||
                        (st["@type"] === "chatMemberStatusAdministrator" && st.rights.can_post_messages))
    }
    // a post's comments: chatId is then the channel's discussion group and this its thread there
    property var thread: 0
    readonly property real foot: input.visible ? input.height : chanBar.height    // what is under the messages
    function isMuted() {
        const n = chat ? chat.notification_settings : null
        return !!n && n.mute_for > 0
    }
    property bool muted: isMuted()
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
                    list.positionViewAtIndex(t, ListView.Center)
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

    function shown(content) {
        const t = content["@type"]
        const words = store.plain(content)
        return {
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
        viewer.show(item.picFace, item.aspect, src)
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
            viewer.show(item.media ? item.picFace : item.face, item.media ? item.aspect : 9 / 16, src, item.path)
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
        const s = shown(m.content)
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
            msgId: m.id, out: m.is_outgoing, date: m.date, text: s.text, kind: s.kind,
            sender: page.group && !m.is_outgoing && !root ? store.senderName(m.sender_id, false) : "",
            senderKey: JSON.stringify(m.sender_id), sending: !!m.sending_state,
            tint: store.tints[Math.abs(m.sender_id.user_id || m.sender_id.chat_id || 0) % store.tints.length],
            time: Qt.formatTime(new Date(m.date * 1000), "HH:mm"),
            views: m.interaction_info ? m.interaction_info.view_count : 0,
            // a channel post with a discussion group: its comments (-1: none can be left)
            comments: m.is_channel_post && page.channel && m.interaction_info && m.interaction_info.reply_info
                      ? m.interaction_info.reply_info.reply_count : -1,
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
            list.positionViewAtIndex(i, ListView.Center)
    }

    // ---- the menu ------------------------------------------------------------
    // testing (NULLGRAM_SAY with a channel): the newest post's comments open and these lines go there
    property string say: ""
    onReadyChanged: {
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

    function openMenu(item) {
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

    function showMenu(item, m, p, reactions) {
        const ok = p["@type"] === "messageProperties"
        const acts = []
        if (ok && p.can_be_replied && !page.channel)
            acts.push({ text: "Javob berish", glyph: "↩", run: () => page.reply(m) })
        if (m.text)
            acts.push({ text: "Nusxa olish", glyph: "⧉", run: () => page.copy(m.text) })
        if (ok && p.can_be_edited && !m.kind && !item.media && !item.rowKind)
            acts.push({ text: "Tahrirlash", glyph: "✎", run: () => page.edit(m) })
        if (ok && p.can_be_forwarded)
            acts.push({ text: "Uzatish", glyph: "↪", run: () => { page.forwarding = [m.id]; forwardSheet.show() } })
        if (ok && p.can_be_pinned)
            acts.push({ text: item.isPinned ? "Qadashni olish" : "Qadash", glyph: "📌",
                        run: () => store.pin(page.chatId, m.id, !item.isPinned) })
        if (page.mains[m.id] && !item.sending)
            acts.push({ text: "Saqlash", glyph: "↓", run: () => page.save(m.id) })
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
        page.reacting = m.id
        if (it && acts.length)
            menu.show(it.face, m.out, acts, reactions, it.reactList.filter((r) => r.mine).map((r) => r.e))
    }
    property var forwarding: []         // the messages the forward sheet sends
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
                readonly property Item face: bubble
                readonly property Item picFace: picture
                // a picture: photo, video or GIF in the bubble; sticker and round video without one
                readonly property bool media: picKind !== ""
                readonly property bool bare: picKind === "sticker" || picKind === "round" || jumbo > 0
                // on the screen (or nearly): only then a GIF plays
                readonly property bool inSight: y + height > list.contentY - 200 && y < list.contentY + list.height + 200
                readonly property real aspect: picH / picW
                readonly property real pw: picKind === "round" ? 200 : picKind === "sticker" ? 160 * Math.min(1, 1 / aspect)
                                         : aspect * wide > 360 ? Math.max(150, 360 / aspect) : wide
                readonly property real ph: picKind === "round" ? 200 : picKind === "sticker" ? 160 * Math.min(1, aspect)
                                         : Math.max(110, Math.min(360, aspect * wide))
                readonly property real wide: Math.min(width * 0.72, 270)
                readonly property bool overlaid: media && text === "" && !reacted     // the time over the picture
                readonly property var reactList: reacts ? JSON.parse(reacts) : []
                readonly property bool reacted: reactList.length > 0
                Component.onCompleted: {
                    if ((media || rowKind === "file") && !pic)
                        page.loadPic(msgId)
                    if (auto && !path && got < 0)
                        page.download(msgId, false)
                }
                // a run: one sender's messages within 10 minutes of each other. Its first (the
                // top) has the name and more space over it, its last (the bottom) the tail.
                readonly property bool first: edge, page.apart(messages.get(index + 1), senderKey, date)
                readonly property bool last: page.apart(messages.get(index - 1), senderKey, date)
                readonly property real most: width * 0.78
                // the first message of a day has the day over it
                readonly property bool newDay: edge, page.otherDay(messages.get(index + 1), date)
                readonly property bool unreadBar: msgId === page.firstUnread
                readonly property real above: (newDay ? 38 : 0) + (unreadBar ? 36 : 0) + (first ? 8 : 2)
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
                        readonly property real tail: item.comments >= 0 && !item.bare ? 42 : 0     // the comments row

                        readonly property bool stampUnder: !item.overlaid && body.last + stampRoom > (item.media ? width : item.most) - 24
                        width: item.jumbo ? Math.max(body.implicitWidth, stamp.implicitWidth + 12) + 8
                             : item.bare ? item.pw : item.media ? item.pw + 6
                             : Math.min(item.most, Math.max(body.implicitWidth, who.implicitWidth, quote.visible ? quote.wants : 0,
                                                            attach.visible ? attach.width : 0, fwdText.visible ? fwdText.implicitWidth : 0,
                                                            item.reacted ? reactRow.implicitWidth + stamp.implicitWidth + 6 : 0,
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
                                active: item.path !== "" && page.visible && !viewer.open && item.inSight &&
                                        ((Prefs.autoGif && (item.picKind === "gif" || item.anim)) || (round && page.roundId === item.msgId))
                                // (handed through here: inside sourceComponent `item` is not the delegate)
                                readonly property string file: item.path
                                sourceComponent: InlineVideo {
                                    path: moving.file
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
                        Text {
                            id: body
                            visible: !item.overlaid
                            x: item.jumbo ? 4 : 12
                            y: item.media ? picture.y + picture.height + 5 : attach.visible ? attach.y + attach.height + (text ? 4 : 0)
                             : quote.visible ? quote.y + quote.height + 4 : bubble.head.visible ? bubble.head.y + bubble.head.height + 2 : item.jumbo ? 0 : 8
                            height: (attach.visible || item.media) && !text ? 0 : implicitHeight
                            width: item.media ? bubble.width - 24 : attach.visible ? Math.max(attach.width, Math.min(implicitWidth, item.most - 24))
                                 : Math.min(implicitWidth, item.most - 24)
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            property real last: 0       // the last line's width
                            onLineLaidOut: (line) => { if (line.isLast) last = line.implicitWidth }
                            text: (item.kind ? "[" + item.kind + "] " : "") + item.text
                            color: item.out ? Theme.outText : Theme.inText
                            font.family: Theme.font; font.pixelSize: item.jumbo === 1 ? 56 : item.jumbo === 2 ? 46 : item.jumbo === 3 ? 38 : 16
                        }
                        Row {           // the reactions: emoji and how many, ours lit; a tap puts ours on or off
                            id: reactRow
                            visible: item.reacted
                            x: item.bare ? 0 : 10
                            y: body.y + body.height + (body.height ? 6 : 4)
                            height: visible ? 28 : 0
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
                        Text {
                            id: stamp
                            anchors.right: parent.right; anchors.rightMargin: item.overlaid || item.jumbo ? (item.bare ? 8 : 12) : 10
                            anchors.bottom: parent.bottom; anchors.bottomMargin: bubble.tail + (item.overlaid || item.jumbo ? (item.bare ? 6 : 10) : 6)
                            textFormat: Text.StyledText
                            text: (item.isPinned ? "📌 " : "") + (item.views ? item.views + " · " : "") + (item.edited ? "tahrirlandi " : "") + item.time +
                                  (item.out ? (item.sending ? " ◷" : " <font color='" + (item.overlaid || item.jumbo ? "white" : Theme.check) + "'>✓</font>") : "")
                            color: item.overlaid || item.jumbo ? "white" : item.out ? Theme.outMeta : Theme.inMeta
                            font.family: Theme.font; font.pixelSize: 12
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

        Rectangle {          // ↓: to the newest (loaded afresh when it was opened at the unread ones)
            id: toNewest
            z: 2
            anchors.right: parent.right; anchors.rightMargin: 10
            y: parent.height - page.kb - page.foot - height - 12
            width: 40; height: 40; radius: 20
            color: Theme.menu
            border.color: Theme.fieldBorder; border.width: 1
            visible: page.ready && page.away
            Text {
                anchors.centerIn: parent
                text: "⌄"
                color: Theme.grey
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

        Rectangle {          // the header: back, the name and what it is
            id: bar
            z: 3
            width: parent.width; height: 56
            color: Theme.bar
            Text {
                x: 8; anchors.verticalCenter: parent.verticalCenter
                text: "‹"
                color: Theme.accent
                opacity: backHit.pressed ? 0.4 : 1
                font.family: Theme.font; font.pixelSize: 34
            }
            MouseArea {          // the back button: the bar's whole height and 72 pt in, as iOS takes it
                id: backHit
                width: 72; height: parent.height
                onClicked: page.nav.pop()
            }
            Column {
                anchors.centerIn: parent
                width: parent.width - 120
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: page.thread ? "Izohlar" : store.title(page.chat)
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: page.thread ? page.threadOf : (store.seen, page.now, store.status(page.chat, page.now))     // (re-read when either changes)
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
                saved: store.isSaved(page.chat)
            }
        }

        Rectangle {          // the pinned message under the header (Telegram-iOS's ChatPinnedMessageTitlePanelNode)
            id: pinBar
            z: 3
            y: bar.height
            width: parent.width
            height: page.pinned ? 48 : 0
            visible: height > 0
            color: Theme.bar
            Rectangle { x: 14; y: 9; width: 2.5; height: 30; radius: 1.25; color: Theme.accent }
            Text {
                x: 26; y: 6
                text: "Qadalgan xabar"
                color: Theme.accent
                font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            }
            Text {
                x: 26; y: 25
                width: parent.width - x - 48
                elide: Text.ElideRight
                maximumLineCount: 1
                textFormat: Text.PlainText
                text: page.pinned ? page.pinned.text.replace(/\s+/g, " ") : ""
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 14
            }
            Icon {
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20
                name: "pin"
                color: Theme.grey
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.5; color: Theme.separator }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    const id = page.pinned.id
                    if (page.indexOf(id) >= 0) {
                        page.jump(id)
                        page.flashId = id
                        unflash.restart()
                    } else {
                        page.openAt(id, false)
                    }
                }
            }
        }

        Rectangle {          // a channel we only read: its sound on or off instead of the field
            id: chanBar
            z: 1
            visible: !page.canPost
            anchors.bottom: parent.bottom
            width: parent.width
            height: visible ? 60 : 0
            color: Theme.bar
            Rectangle {
                anchors.centerIn: parent
                width: muteText.implicitWidth + 64; height: 40; radius: 20
                color: Theme.field
                border.color: Theme.fieldBorder; border.width: 1
                Icon { x: 18; anchors.verticalCenter: parent.verticalCenter; name: "bell"; color: Theme.accent; scale: 0.8 }
                Text {
                    id: muteText
                    x: 46; anchors.verticalCenter: parent.verticalCenter
                    text: page.muted ? "Ovozni yoqish" : "Ovozni o'chirish"
                    color: Theme.accent
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        const n = Object.assign({}, page.chat.notification_settings)
                        n["@type"] = "chatNotificationSettings"
                        n.use_default_mute_for = false
                        n.mute_for = page.muted ? 0 : 2147483647
                        page.muted = !page.muted        // at once; TDLib's update says the same
                        store.send({ "@type": "setChatNotificationSettings", chat_id: page.chatId, notification_settings: n }, store.check)
                    }
                }
            }
        }

        Rectangle {          // the field, with what it answers or edits over it
            id: input
            z: 1
            visible: page.canPost
            anchors.bottom: parent.bottom
            transform: Translate { y: -page.kb }
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
            Icon {               // the clip: pictures and files from the phone
                x: 12
                anchors.bottom: parent.bottom; anchors.bottomMargin: 16
                width: 26; height: 26
                name: "clip"
                color: Theme.grey
                visible: !page.editing
                MouseArea {
                    anchors.fill: parent; anchors.margins: -10
                    onClicked: {
                        Qt.inputMethod.hide()
                        sheet.show()
                    }
                }
            }
            Rectangle {
                x: page.editing ? 10 : 48; y: compose.height + 8
                width: parent.width - x - 56; height: parent.height - compose.height - 16
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
            Rectangle {          // recording: the time, and how to let it go (over the field)
                id: recBar
                visible: page.recording
                x: 0; y: compose.height
                width: parent.width - 56; height: parent.height - compose.height
                color: Theme.bar
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
                anchors.right: parent.right; anchors.rightMargin: 10
                anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                width: 36; height: 36; radius: 18
                color: mic ? (page.recording ? Theme.danger : "transparent") : field.text.trim() ? Theme.accent : Theme.mutedBadge
                scale: page.recording ? 1.6 : 1
                Behavior on scale { ScaleAnimator { duration: 200; easing.type: Easing.OutBack } }
                Icon {
                    visible: sendButton.mic
                    anchors.centerIn: parent
                    width: 26; height: 26
                    name: "mic"
                    color: page.recording ? "white" : Theme.grey
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
                        const t = field.text.trim()
                        if (!t)
                            return
                        if (page.editing) {
                            store.editText(page.chatId, page.editing.id, t)
                            page.editing = null
                            field.text = ""
                            return
                        }
                        if (page.gap)           // what is sent goes under the newest: go there first
                            page.fresh()
                        const at = field.mapToItem(page, 0, 0)
                        page.flying = { text: t, x: at.x, y: at.y }
                        store.sendText(page.chatId, t, page.replying ? page.replying.id : 0, page.thread)
                        page.replying = null
                        field.text = ""
                        list.positionViewAtBeginning()
                    }
                }
            }
        }
    }

    PhotoViewer {
        id: viewer
        onSave: if (page.viewing) page.save(page.viewing)
    }

    ForwardSheet {
        id: forwardSheet
        store: page.store
        onPicked: (to, title) => store.forward(to, page.chatId, page.forwarding, (ok) => {
            if (page && ok)
                page.toast("Uzatildi: " + title)
        })
    }

    AttachSheet {
        id: sheet
        onSend: (picked, asFiles) => {
            if (page.gap)
                page.fresh()
            store.sendFiles(page.chatId, picked, field.text.trim(), page.replying ? page.replying.id : 0, asFiles, page.thread)
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
        y: bar.height + 12
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
        store.sendVoice(chatId, at, v.duration, v.waveform, replying ? replying.id : 0, thread)
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
