// The chats, as Telegram-iOS lists them (ChatListItem.swift): a round picture, the
// name and time on one line, two lines of the last message under it, the unread
// count in a pill. A tap lights the row at once; the chat comes in when it is ready.
import QtQuick

Page {
    id: page

    ListView {
        id: list
        anchors.fill: parent
        model: store.chatList
        cacheBuffer: 600
        boundsBehavior: Flickable.DragOverBounds
        maximumFlickVelocity: 6000
        flickDeceleration: 2200
        header: Item {
            width: list.width; height: 104
            Text {
                x: 16; y: 52
                text: "Chatlar"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 32; font.weight: Font.Bold
            }
            Text {
                x: 16; y: 32
                text: store.connection
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13
            }
        }

        delegate: Rectangle {
            id: row
            required property int index
            required property var chatId
            required property string title
            required property string who
            required property string preview
            required property string time
            required property int unread
            required property bool muted
            required property bool pinned
            required property string photo
            required property string letters
            required property string tint
            required property bool outgoing
            required property bool read

            width: list.width; height: 76
            color: tap.pressed || lit ? Theme.highlight : Theme.bg
            property bool lit: false

            Avatar {
                x: 10; y: 8
                width: 60; height: 60
                source: row.photo; letters: row.letters; tint: row.tint
            }
            Text {
                id: name
                x: 80; y: 9
                width: parent.width - x - stamp.width - 20
                text: row.title
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            Text {
                id: stamp
                anchors.right: parent.right; anchors.rightMargin: 14
                y: 11
                text: (row.outgoing ? (row.read ? "✓✓ " : "✓ ") : "") + row.time
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13
            }
            Text {
                x: 80; y: 31
                width: parent.width - x - (pill.visible ? pill.width + 22 : 14)
                height: 40
                maximumLineCount: 2
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                textFormat: Text.PlainText
                readonly property string busy: store.acting, store.activity(store.chats[row.chatId])
                text: busy || (row.who ? row.who + ": " : "") + row.preview
                color: busy ? Theme.accent : Theme.grey
                font.family: Theme.font; font.pixelSize: 15
                lineHeight: 0.95
            }
            Rectangle {
                id: pill
                visible: row.unread > 0 || row.pinned
                anchors.right: parent.right; anchors.rightMargin: 14
                y: 40
                height: 22; radius: 11
                width: row.unread > 0 ? Math.max(22, count.implicitWidth + 14) : 22
                color: row.unread > 0 ? (row.muted ? Theme.mutedBadge : Theme.badge) : "transparent"
                Text {
                    id: count
                    anchors.centerIn: parent
                    text: row.unread > 0 ? (row.unread > 9999 ? Math.floor(row.unread / 1000) + "K" : row.unread) : "📌"
                    color: row.unread > 0 ? "white" : Theme.grey
                    font.family: Theme.font; font.pixelSize: row.unread > 0 ? 13 : 11; font.weight: Font.DemiBold
                }
            }
            Rectangle {
                x: 80; y: parent.height - 0.5
                width: parent.width - x; height: 0.5
                color: Theme.separator
            }
            MouseArea {
                id: tap
                anchors.fill: parent
                onClicked: {
                    row.lit = true
                    unlight.restart()
                    page.nav.push(chatPage, { chatId: row.chatId })
                }
            }
            Timer { id: unlight; interval: 600; onTriggered: row.lit = false }
        }
    }

    Component { id: chatPage; ChatPage {} }
}
