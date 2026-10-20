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

    // NULLGRAM_OPEN=<chat id> or "me" (testing from the PC): that chat at once
    Timer {
        running: td.devOpen !== ""
        interval: 1500
        onTriggered: {
            const me = home.store.me
            if (td.devOpen === "me" && me)
                home.store.chatWith(me.id, (id) => home.nav.push(devChat, { chatId: id }))
            else if (td.devOpen !== "me")
                home.store.send({ "@type": "getChat", chat_id: Number(td.devOpen) }, (c) => {
                    if (c["@type"] === "chat")
                        home.nav.push(devChat, { chatId: c.id })
                })
            else
                restart()
        }
    }
    Component { id: devChat; ChatPage {} }

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
