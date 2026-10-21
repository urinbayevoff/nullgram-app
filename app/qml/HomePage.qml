// Home: the three tabs (Kontaktlar, Chatlar, Sozlamalar) under one floating capsule, as
// Telegram-iOS 26 has them (IMG_0296): a tap swaps the page at once, only the lens moves.
// The shell's back goes to the chats first, then out of the search.
import QtQuick

Page {
    id: home
    property int tab: 1

    ContactsPage { id: contacts; store: home.store; nav: home.nav; visible: home.tab === 0 }
    ChatListPage { id: chats; store: home.store; nav: home.nav; visible: home.tab === 1 }
    SettingsPage { id: settings; store: home.store; nav: home.nav; visible: home.tab === 2 }

    TabBar {
        x: 16; width: parent.width - 32
        y: parent.height - height - 10
        visible: !(home.tab === 1 && chats.searching)
        current: home.tab
        badges: [0, chats.unreadChats, 0]
        onPicked: (i) => {
            if (i === home.tab && i === 1)
                chats.toTop()
            home.tab = i
        }
    }

    // NULLGRAM_OPEN=<chat id>, its name, "me", "channel", "private", "group", "barred" or "russian" (testing from the PC): that chat at once,
    // unless it has unread messages (opening it would read them)
    Timer {
        running: td.devOpen !== ""
        interval: 1500
        onTriggered: {
            const me = home.store.me
            if (td.devOpen === "me" && me)
                home.store.chatWith(me.id, (id) => home.devPush(id))
            else if (td.devOpen === "russian") {     // a read chat whose last words are Russian (ы, щ: not Uzbek)
                const c = Object.values(home.store.chats).find((c) => c.unread_count === 0 && c.last_message &&
                    /[ыщ]/.test(home.store.plain(c.last_message.content) || ""))
                if (c)
                    home.devPush(c.id)
                else
                    console.warn("nullgram: NULLGRAM_OPEN russian: none read")
            } else if (td.devOpen === "channel") {     // a channel with comments, all read
                const c = Object.values(home.store.chats).find((c) => {
                    const g = c.type["@type"] === "chatTypeSupergroup" && c.type.is_channel ? home.store.groups["s" + c.type.supergroup_id] : null
                    return g && g.has_linked_chat && c.unread_count === 0
                })
                if (c)
                    home.devPush(c.id)
                else
                    console.warn("nullgram: NULLGRAM_OPEN channel: none read with comments")
            }
            else if (td.devOpen === "private") {     // a person's chat, all read (not a bot, not ourselves)
                const c = home.store.chatList.count && Array.from({ length: home.store.chatList.count },
                    (_, i) => home.store.chats[home.store.chatList.get(i).chatId]).find((c) => {
                    const u = c && c.type["@type"] === "chatTypePrivate" ? home.store.users[c.type.user_id] : null
                    return u && u.type["@type"] === "userTypeRegular" && c.unread_count === 0 && !home.store.isSaved(c)
                })
                if (c)
                    home.devPush(c.id)
                else
                    console.warn("nullgram: NULLGRAM_OPEN private: none read")
            }
            else if (td.devOpen === "barred") {      // a read group where only its admins write (the bar, not the field)
                const all = Object.values(home.store.chats).filter((c) => c.permissions && c.unread_count === 0
                    && (c.type["@type"] === "chatTypeBasicGroup" || (c.type["@type"] === "chatTypeSupergroup" && !c.type.is_channel)))
                const c = all.find((c) => c.permissions.can_send_basic_messages === false || c.permissions.can_send_messages === false)
                console.warn("nullgram: NULLGRAM_OPEN barred:", all.length, "groups read,", all.filter((c) =>
                    c.permissions.can_send_basic_messages === false || c.permissions.can_send_messages === false).map((c) => c.title).join(" | "))
                if (c)
                    home.devPush(c.id)
            }
            else if (td.devOpen === "group") {       // the biggest group, all read (its members, for the page about it)
                const size = (c) => {
                    const g = home.store.groups[c.type["@type"] === "chatTypeBasicGroup" ? "b" + c.type.basic_group_id : "s" + c.type.supergroup_id]
                    return g ? g.member_count : 0
                }
                const c = Array.from({ length: home.store.chatList.count }, (_, i) => home.store.chats[home.store.chatList.get(i).chatId])
                    .filter((c) => c && c.unread_count === 0
                        && (c.type["@type"] === "chatTypeBasicGroup" || (c.type["@type"] === "chatTypeSupergroup" && !c.type.is_channel)))
                    .sort((a, b) => size(b) - size(a))[0]
                if (c)
                    home.devPush(c.id)
                else
                    console.warn("nullgram: NULLGRAM_OPEN group: none read")
            }
            else if (td.devOpen !== "me") {      // an id, or a chat's name ("!" first: even unread -- our own test chats)
                const force = td.devOpen.startsWith("!"), key = force ? td.devOpen.slice(1) : td.devOpen
                const c = home.store.chats[key] ||
                          Object.values(home.store.chats).find((c) => c.title === key) ||
                          Object.values(home.store.chats).find((c) => c.title.startsWith(key))     // (an emoji at the end comes through ssh changed)
                if (c && (c.unread_count === 0 || force))
                    home.devPush(c.id)
                else
                    console.warn("nullgram: NULLGRAM_OPEN", td.devOpen, c ? "has unread messages: not opened" : "not found")
            }
            else
                restart()
        }
    }
    Component { id: devChat; ChatPage {} }
    function devPush(id) {
        const c = store.chats[id]
        if (c && c.type.is_channel) {           // a channel: what to say goes to its newest post's comments
            nav.push(devChat, { chatId: id, say: td.devSay, findNow: td.devFind })
            return
        }
        nav.push(devChat, { chatId: id, findNow: td.devFind })
        for (const line of td.devSay.split("\n"))
            if (line)
                store.sendText(id, line, 0)
    }

    function dismiss() {
        if (tab === 1 && chats.dismiss())
            return true
        if (tab !== 1) {
            tab = 1
            return true
        }
        return false
    }
}
