// The chat folders, in their order, with how many of their chats have unread messages. They are
// changed in another Telegram app for now; here a tap shows that folder in the chats.
import QtQuick

SubPage {
    id: page
    title: "Chat papkalari"

    SettingsGroup {
        note: store.folders.length ? "Papkani bosing — chatlar ro'yxatida o'sha papka ochiladi. Papkalarni hozircha boshqa Telegram ilovasida o'zgartiring."
                                   : "Papkalar yo'q. Ularni boshqa Telegram ilovasida yarating — bu yerda o'zi chiqadi."
        SettingsRow {
            icon: "chats"; tint: "#007aff"; text: "Hammasi"
            value: store.unreadChats ? store.unreadChats : ""
            last: store.folders.length === 0
            onClicked: { store.showFolder(0); page.nav.pop() }
        }
        Repeater {
            model: store.folders
            SettingsRow {
                required property var modelData
                required property int index
                icon: "folder"; tint: "#32ade6"
                text: modelData.name
                value: store.folderUnread[modelData.id] ? store.folderUnread[modelData.id] : ""
                last: index === store.folders.length - 1
                onClicked: { store.showFolder(modelData.id); page.nav.pop() }
            }
        }
    }
}
