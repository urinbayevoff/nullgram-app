// The chats, as Telegram-iOS lists them (ChatListItem.swift): a round picture, the
// name and time on one line, two lines of the last message under it, the unread
// count in a pill. A tap lights the row at once; the chat comes in when it is ready.
// Over the list, as on iOS 26: the title in the middle and the search box under it; a tap
// on the box turns the page into the search (SearchView). Under it the chat folders (IMG_0295): a
// capsule of chips, the one shown on grey with its unread count; the folders' lists side by side
// under them, a sideways swipe slides to the next or the one before.
import QtQuick

Page {
    id: page
    property bool searching: false
    // chats with something unread (not muted): the tab bar's badge
    readonly property int unreadChats: store.unreadChats

    function toTop() {
        if (list)
            list.positionViewAtBeginning()
    }

    // the folders as the chips show them: all chats first
    readonly property var tabs: [{ id: 0, name: "Hammasi" }].concat(store.folders)
    readonly property int tabIndex: Math.max(0, tabs.findIndex((t) => t.id === store.folder))
    function go(i) {
        if (i < 0 || i >= tabs.length || tabs[i].id === store.folder)
            return
        store.showFolder(tabs[i].id)
    }

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

    // the folders side by side (Telegram-iOS: the list slides with the finger to the next folder, the
    // chips follow), each its own list, kept as it was: going back shows it at once with its pictures
    // (one list filled afresh at each folder lit up white and put initials over every picture, IMG_0085)
    readonly property real headHeight: 104 + (store.folders.length ? 52 : 0)
    readonly property ListView list: pager.currentItem ? pager.currentItem.rows : null
    ListView {
        id: pager
        anchors.fill: parent
        orientation: ListView.Horizontal
        model: page.tabs
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        boundsBehavior: Flickable.StopAtBounds
        interactive: store.folders.length > 0 && !page.searching
        flickDeceleration: 4000
        highlightMoveDuration: 400
        cacheBuffer: width * Math.max(1, page.tabs.length)      // all of them made, none dropped
        currentIndex: page.tabIndex
        onCurrentIndexChanged: if (currentIndex !== page.tabIndex && page.tabs[currentIndex]) {
            page.align()
            store.showFolder(page.tabs[currentIndex].id)
        }
        delegate: Item {
            id: folderPage
            required property var modelData
            readonly property ListView rows: rows
            width: pager.width; height: pager.height
            ListView {
                id: rows
                anchors.fill: parent
                Component.onCompleted: model = store.modelOf(folderPage.modelData.id)
                cacheBuffer: 600
                boundsBehavior: Flickable.DragOverBounds
                maximumFlickVelocity: 6000
                flickDeceleration: 2200
                header: Item { width: 1; height: page.headHeight }     // the title, search and chips are over it
                footer: Item { width: 1; height: 90 }      // room over the tab bar
                delegate: rowDelegate
            }
        }
    }
    // a folder comes in with the title where the one before had it (when both are near their tops)
    function align() {
        const l = list
        const off = l ? l.contentY - l.originY : 0
        Qt.callLater(() => {
            const n = page.list
            if (!n || off >= page.headHeight || n.contentY - n.originY >= page.headHeight)
                return
            n.contentY = n.originY + off
        })
    }

    // over the lists: the title, the search box, the folder chips. It goes up with the list shown,
    // as if in it
    Item {
        id: head
        width: parent.width; height: page.headHeight
        y: page.list ? Math.max(-height, -(page.list.contentY - page.list.originY)) : 0
        Rectangle { anchors.fill: parent; color: Theme.bg }
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
                // the grey capsule goes along with the lists as they slide, between the two chips
                highlightFollowsCurrentItem: false
                highlight: Rectangle {
                    readonly property real at: pager.width > 0 ? Math.max(0, Math.min(page.tabs.length - 1, (pager.contentX - pager.originX) / pager.width)) : 0
                    readonly property Item from: chips.itemAtIndex(Math.floor(at))
                    readonly property Item to: chips.itemAtIndex(Math.ceil(at)) || from
                    readonly property real t: at - Math.floor(at)
                    x: from ? from.x + (to.x - from.x) * t : 0
                    width: from ? from.width + (to.width - from.width) * t : 0
                    height: 36
                    radius: 18; color: Theme.highlight
                }
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

    Component {
        id: rowDelegate
        Rectangle {
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

            width: ListView.view.width; height: 76
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
