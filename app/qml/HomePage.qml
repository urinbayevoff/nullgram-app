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

    // NULLGRAM_OPEN=<chat id>, its name, "me" or "channel" (testing from the PC): that chat at once,
    // unless it has unread messages (opening it would read them)
    Timer {
        running: td.devOpen !== ""
        interval: 1500
        onTriggered: {
            const me = home.store.me
            if (td.devOpen === "me" && me)
                home.store.chatWith(me.id, (id) => home.devPush(id))
            else if (td.devOpen === "channel") {     // a channel with comments, all read
                const c = Object.values(home.store.chats).find((c) => {
                    const g = c.type["@type"] === "chatTypeSupergroup" && c.type.is_channel ? home.store.groups["s" + c.type.supergroup_id] : null
                    return g && g.has_linked_chat && c.unread_count === 0
                })
                if (c)
                    home.devPush(c.id)
                else
                    console.warn("nullgram: NULLGRAM_OPEN channel: none read with comments")
            }
            else if (td.devOpen !== "me") {      // an id, or a chat's name ("!" first: even unread -- our own test chats)
                const force = td.devOpen.startsWith("!"), key = force ? td.devOpen.slice(1) : td.devOpen
                const c = home.store.chats[key] ||
                          Object.values(home.store.chats).find((c) => c.title === key)
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
            nav.push(devChat, { chatId: id, say: td.devSay })
            return
        }
        nav.push(devChat, { chatId: id })
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
