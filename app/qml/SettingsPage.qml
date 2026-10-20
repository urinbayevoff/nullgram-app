// Settings, laid out as Telegram-iOS's (IMG_0298): who is signed in at the top, then rounded
// groups of rows with coloured icons. What works opens a page of its own (ProfilePage,
// DevicesPage, FoldersPage, StoragePage, AppearancePage); the rest waits for later.
// (Signing out waits: TDLib's client closes on it, and a new one has to be made.)
import QtQuick

Page {
    id: page
    color: Theme.grouped
    property string photo: ""
    property string tdVersion: ""
    property int devices: 0
    onVisibleChanged: if (visible) {
        if (!photo && store.me)
            store.userPhoto(store.me, (path) => page.photo = path)
        if (!tdVersion)
            store.send({ "@type": "getOption", name: "version" }, (r) => {
                if (r.value)
                    page.tdVersion = r.value
            })
        store.send({ "@type": "getActiveSessions" }, (r) => {
            if (r.sessions)
                page.devices = r.sessions.length
        })
    }
    readonly property var me: store.me

    function open(component) {
        nav.push(component, {})
    }

    Flickable {
        anchors.fill: parent
        contentHeight: column.height + 120
        Column {
            id: column
            width: parent.width
            spacing: 22
            Item {           // who is signed in
                width: parent.width; height: 196
                Avatar {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 18
                    width: 96; height: 96
                    source: page.photo
                    letters: page.me ? store.letters(page.me.first_name + " " + page.me.last_name) : ""
                    tint: page.me ? store.tints[Math.abs(page.me.id) % store.tints.length] : Theme.accent
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 124
                    text: page.me ? (page.me.first_name + " " + page.me.last_name).trim() : ""
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 24; font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 158
                    text: !page.me ? "" : ("+" + page.me.phone_number) +
                          (page.me.usernames && page.me.usernames.active_usernames.length
                           ? "  ·  @" + page.me.usernames.active_usernames[0] : "")
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 15
                }
            }

            SettingsGroup {
                SettingsRow { icon: "person"; tint: "#ff3b30"; text: "Mening profilim"; last: true; onClicked: page.open(profilePage) }
            }
            SettingsGroup {
                SettingsRow {
                    icon: "bookmark"; tint: "#007aff"; text: "Saqlangan xabarlar"
                    onClicked: if (page.me) store.chatWith(page.me.id, (id) => page.nav.push(chatPage, { chatId: id }))
                }
                SettingsRow { icon: "laptop"; tint: "#ff9500"; text: "Qurilmalar"; value: page.devices ? page.devices : ""; onClicked: page.open(devicesPage) }
                SettingsRow { icon: "folder"; tint: "#32ade6"; text: "Chat papkalari"; value: store.folders.length ? store.folders.length : ""; last: true; onClicked: page.open(foldersPage) }
            }
            SettingsGroup {
                SettingsRow { icon: "data"; tint: "#34c759"; text: "Ma'lumotlar va xotira"; onClicked: page.open(storagePage) }
                SettingsRow { icon: "halfmoon"; tint: "#5ac8fa"; text: "Ko'rinish"; value: Theme.dark ? "Tungi" : "Kunduzgi"; onClicked: page.open(appearancePage) }
                SettingsRow { icon: "globe"; tint: "#af52de"; text: "Til"; value: "O'zbekcha"; chevron: false; last: true }
            }
            SettingsGroup {
                note: "Nullgram — OmonullOS uchun Telegram (Qt Quick + TDLib)."
                SettingsRow {
                    icon: "info"; tint: "#8e8e93"; text: "Ilova haqida"; chevron: false; last: true
                    value: "0.9" + (page.tdVersion ? " · TDLib " + page.tdVersion : "")
                }
            }
        }
    }

    Component { id: chatPage; ChatPage {} }
    Component { id: profilePage; ProfilePage {} }
    Component { id: devicesPage; DevicesPage {} }
    Component { id: foldersPage; FoldersPage {} }
    Component { id: storagePage; StoragePage {} }
    Component { id: appearancePage; AppearancePage {} }
}
