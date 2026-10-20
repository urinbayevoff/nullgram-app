// The contacts, by name (loaded the first time the tab is shown): a picture, the name and
// when they were last here. A tap opens the chat with them.
import QtQuick

Page {
    id: page
    property bool loaded: false
    property int now: Date.now() / 1000
    onVisibleChanged: if (visible) {
        now = Date.now() / 1000
        if (!loaded) {
            loaded = true
            store.contacts((list) => {
                people.clear()
                for (const u of list)
                    people.append({ userId: u.id, name: (u.first_name + " " + u.last_name).trim(),
                                    letters: store.letters(u.first_name + " " + u.last_name),
                                    tint: store.tints[Math.abs(u.id) % store.tints.length] })
            })
        }
    }

    ListModel { id: people }

    ListView {
        id: list
        anchors.fill: parent
        model: people
        cacheBuffer: 600
        maximumFlickVelocity: 6000
        flickDeceleration: 2200
        header: Item {
            width: list.width; height: 56
            Text {
                anchors.centerIn: parent
                text: "Kontaktlar"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
        }
        footer: Item { width: 1; height: 96 }       // room over the tab bar

        delegate: Rectangle {
            id: row
            required property var userId
            required property string name
            required property string letters
            required property string tint
            width: list.width; height: 62
            color: tap.pressed ? Theme.highlight : Theme.bg
            property string photo: ""
            Component.onCompleted: store.userPhoto(store.users[userId], (path) => row.photo = path)
            Avatar {
                x: 14; y: 8
                width: 46; height: 46
                source: row.photo; letters: row.letters; tint: row.tint
            }
            Text {
                x: 72; y: 11
                width: parent.width - x - 14
                text: row.name
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            Text {
                x: 72; y: 33
                width: parent.width - x - 14
                readonly property string s: store.seen, store.userStatus(store.users[row.userId], page.now)
                text: s
                elide: Text.ElideRight
                color: s === "onlayn" ? Theme.accent : Theme.grey
                font.family: Theme.font; font.pixelSize: 14
            }
            Rectangle {
                x: 72; y: parent.height - 0.5
                width: parent.width - x; height: 0.5
                color: Theme.separator
            }
            MouseArea {
                id: tap
                anchors.fill: parent
                onClicked: store.chatWith(row.userId, (id) => page.nav.push(chatPage, { chatId: id }))
            }
        }
    }

    Text {
        visible: page.loaded && people.count === 0
        anchors.centerIn: parent
        text: "Kontaktlar yo'q"
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 15
    }

    Component { id: chatPage; ChatPage {} }
}
