// Those who asked to join a group or channel by a link that needs an admin's yes (Telegram-iOS's
// "Qo'shilish so'rovlari"): who, what they say about themselves, when, and Qabul qilish / Rad etish.
import QtQuick

SubPage {
    id: page
    property var chatId: 0
    readonly property var chat: store.chats[chatId]
    readonly property bool channel: chat && chat.type["@type"] === "chatTypeSupergroup" && chat.type.is_channel
    title: "Qo'shilish so'rovlari"

    property var asked: []              // chatJoinRequest: user_id, date, bio
    property bool loaded: false
    Component.onCompleted: load()
    function load() {
        store.send({ "@type": "getChatJoinRequests", chat_id: chatId, invite_link: "", query: "",
                     offset_request: null, limit: 100 }, (r) => {
            page.loaded = true
            if (r["@type"] === "chatJoinRequests")
                page.asked = r.requests
        })
    }
    function answer(userId, yes) {
        store.send({ "@type": "processChatJoinRequest", chat_id: chatId, user_id: userId, approve: yes }, (r) => {
            if (r["@type"] === "error")
                return
            page.asked = page.asked.filter((q) => q.user_id !== userId)
        })
    }

    Text {
        visible: page.loaded && page.asked.length === 0
        x: 32; width: parent.width - 64
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: "Hozircha so'rov yo'q."
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 15
    }

    SettingsGroup {
        visible: page.asked.length > 0
        title: store.count(page.asked.length) + " ta so'rov"
        Repeater {
            id: rows
            model: page.asked
            Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property var u: (store.seen, store.users[modelData.user_id])
                readonly property string name: u ? (u.first_name + " " + u.last_name).trim() || "O'chirilgan hisob" : ""
                width: parent.width; height: about.y + about.height + 58
                color: "transparent"
                property string photo: ""
                Component.onCompleted: {
                    if (u)
                        store.userPhoto(u, (p) => row.photo = p)
                }
                Avatar {
                    x: 14; y: 10
                    width: 40; height: 40
                    source: row.photo
                    letters: store.letters(row.name)
                    tint: store.tints[Math.abs(row.modelData.user_id) % store.tints.length]
                }
                Text {
                    x: 66; y: 10
                    width: parent.width - x - when.width - 24
                    elide: Text.ElideRight
                    text: row.name
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                Text {
                    id: when
                    anchors.right: parent.right; anchors.rightMargin: 14; y: 12
                    text: Qt.formatDate(new Date(row.modelData.date * 1000), "dd.MM.yy")
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 13
                }
                Text {
                    id: about
                    x: 66; y: 32
                    width: parent.width - x - 14
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    text: row.modelData.bio || (row.u && row.u.usernames ? "@" + row.u.usernames.active_usernames[0] : "")
                    visible: text !== "" && text !== "@undefined"
                    height: visible ? implicitHeight : 0
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 14
                }
                Row {
                    x: 66; y: about.y + about.height + 10
                    spacing: 10
                    Rectangle {
                        width: yesText.implicitWidth + 32; height: 34; radius: 17
                        color: yesHit.pressed ? Qt.darker(Theme.accent, 1.2) : Theme.accent
                        Text {
                            id: yesText
                            anchors.centerIn: parent
                            text: page.channel ? "Kanalga qo'shish" : "Guruhga qo'shish"
                            color: "white"
                            font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                        }
                        MouseArea { id: yesHit; anchors.fill: parent; onClicked: page.answer(row.modelData.user_id, true) }
                    }
                    Rectangle {
                        width: noText.implicitWidth + 32; height: 34; radius: 17
                        color: noHit.pressed ? Theme.highlight : "transparent"
                        Text {
                            id: noText
                            anchors.centerIn: parent
                            text: "Rad etish"
                            color: Theme.accent
                            font.family: Theme.font; font.pixelSize: 15
                        }
                        MouseArea { id: noHit; anchors.fill: parent; onClicked: page.answer(row.modelData.user_id, false) }
                    }
                }
                Rectangle {
                    visible: row.index < rows.count - 1
                    x: 66; anchors.bottom: parent.bottom; width: parent.width - 66; height: 0.5; color: Theme.separator
                }
            }
        }
    }
}
