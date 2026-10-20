// The chats, as Telegram-iOS lists them (ChatListItem.swift): a round picture, the
// name and time on one line, two lines of the last message under it, the unread
// count in a pill. A tap lights the row at once; the chat comes in when it is ready.
// Over the list, as on iOS 26: the title in the middle and the search box under it; a tap
// on the box turns the page into the search (SearchView). Under it the chat folders (IMG_0295): a
// capsule of chips, the one shown on grey with its unread count; a sideways swipe on the list
// goes to the next or the one before.
import QtQuick

Page {
    id: page
    property bool searching: false
    // chats with something unread (not muted): the tab bar's badge
    readonly property int unreadChats: store.unreadChats

    function toTop() {
        list.positionViewAtBeginning()
    }

    // the folders as the chips show them: all chats first
    readonly property var tabs: [{ id: 0, name: "Hammasi" }].concat(store.folders)
    readonly property int tabIndex: Math.max(0, tabs.findIndex((t) => t.id === store.folder))
    function go(i) {
        if (i < 0 || i >= tabs.length || tabs[i].id === store.folder)
            return
        store.showFolder(tabs[i].id)
        fadeIn.restart()
    }
    OpacityAnimator { id: fadeIn; target: list; from: 0.3; to: 1; duration: 180; easing.type: Easing.OutQuad }

    // TDLib counts a folder's unread chats once the folder is loaded: load each a little
    property bool countsAsked: false
    Connections {
        target: store
        function onFoldersChanged() {
            if (page.countsAsked || !store.folders.length)
                return
            page.countsAsked = true
            for (const f of store.folders)
                store.send({ "@type": "loadChats", chat_list: { "@type": "chatListFolder", chat_folder_id: f.id }, limit: 20 })
        }
    }
    function dismiss() {
        if (searching) {
            search.close()
            return true
        }
        return false
    }

    ListView {
        id: list
        anchors.fill: parent
        model: store.chatList
        cacheBuffer: 600
        boundsBehavior: Flickable.DragOverBounds
        maximumFlickVelocity: 6000
        flickDeceleration: 2200
        header: Item {
            width: list.width; height: 104 + (store.folders.length ? 52 : 0)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 16
                text: store.connection || "Chatlar"
                color: store.connection ? Theme.grey : Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            Rectangle {          // the search box: a tap opens the search
                x: 14; y: 52
                width: parent.width - 28; height: 38; radius: 19
                color: Theme.dark ? Qt.rgba(0.46, 0.46, 0.5, 0.24) : Qt.rgba(0.46, 0.46, 0.5, 0.12)
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { name: "search"; width: 18; height: 18; color: Theme.grey; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Qidiruv"
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 16
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: search.show() }
            }
            Rectangle {          // the folders
                visible: store.folders.length > 0
                x: 12; y: 100
                width: parent.width - 24; height: 44; radius: 22
                color: Theme.bg
                border.color: Theme.fieldBorder; border.width: 0.5
                ListView {
                    id: chips
                    anchors.fill: parent; anchors.margins: 4
                    orientation: ListView.Horizontal
                    clip: true
                    spacing: 2
                    model: page.tabs
                    currentIndex: page.tabIndex
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: 250
                    highlightResizeDuration: 250
                    highlight: Rectangle { radius: 18; color: Theme.highlight }
                    delegate: Item {
                        id: chip
                        required property var modelData
                        required property int index
                        readonly property int unread: modelData.id ? (store.folderUnread[modelData.id] || 0) : store.unreadChats
                        width: label.implicitWidth + (badge.visible ? badge.width + 6 : 0) + 28; height: 36
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                id: label
                                anchors.verticalCenter: parent.verticalCenter
                                text: chip.modelData.name
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: 15; font.weight: chip.index === page.tabIndex ? Font.DemiBold : Font.Normal
                            }
                            Rectangle {
                                id: badge
                                visible: chip.unread > 0
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(20, n.implicitWidth + 10); height: 20; radius: 10
                                color: Theme.mutedBadge
                                Text {
                                    id: n
                                    anchors.centerIn: parent
                                    text: store.count(chip.unread)
                                    color: "white"
                                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                                }
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: page.go(chip.index) }
                    }
                }
            }
        }
        footer: Item { width: 1; height: 90 }      // room over the tab bar

        delegate: Rectangle {
            id: row
            required property int index
            required property var chatId
            required property string title
            required property bool saved
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
                source: row.photo; letters: row.letters; tint: row.tint; saved: row.saved
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

    // sideways over the rows: the next folder, or the one before. Over the list, not in it: a row's
    // MouseArea takes the press, and a handler under it would never see it. It begins under the
    // folder chips (they scroll sideways themselves).
    Item {
        y: Math.max(0, list.headerItem ? list.headerItem.height - (list.contentY - list.originY) : 0)
        width: parent.width; height: parent.height - y
        enabled: store.folders.length > 0 && !page.searching
        DragHandler {
            target: null
            xAxis.enabled: true
            yAxis.enabled: false
            // (the translation is back at 0 by the time it lets go: kept while it moves)
            property real dx: 0
            onActiveTranslationChanged: if (active) dx = activeTranslation.x
            onActiveChanged: {
                if (active)
                    dx = 0
                else if (Math.abs(dx) > 70)
                    page.go(page.tabIndex + (dx < 0 ? 1 : -1))
            }
        }
    }

    Component { id: chatPage; ChatPage {} }

    SearchView {
        id: search
        anchors.fill: parent
        store: page.store
        onOpenChanged: page.searching = open
        onPicked: (chatId, messageId) => page.nav.push(chatPage, messageId ? { chatId: chatId, target: messageId }
                                                                            : { chatId: chatId })
    }
}
