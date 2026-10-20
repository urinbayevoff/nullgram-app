// The signed-in user as others see them (Telegram-iOS's My Profile): the picture, the name,
// online, then the number, the username, the bio and the birthday from getUserFullInfo.
import QtQuick

SubPage {
    id: page
    title: ""
    property string photo: ""
    property var full: null
    readonly property var me: store.me
    Component.onCompleted: {
        if (me) {
            store.userPhoto(me, (path) => page.photo = path)
            store.send({ "@type": "getUserFullInfo", user_id: me.id }, (r) => {
                if (r["@type"] === "userFullInfo")
                    page.full = r
            })
        }
    }
    readonly property var months: ["yanvar", "fevral", "mart", "aprel", "may", "iyun", "iyul", "avgust",
                                   "sentabr", "oktabr", "noyabr", "dekabr"]

    Item {
        width: parent.width; height: 190
        Avatar {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 110; height: 110
            source: page.photo
            letters: page.me ? store.letters(page.me.first_name + " " + page.me.last_name) : ""
            tint: page.me ? store.tints[Math.abs(page.me.id) % store.tints.length] : Theme.accent
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 122
            text: page.me ? (page.me.first_name + " " + page.me.last_name).trim() : ""
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 24; font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 156
            text: "onlayn"
            color: Theme.accent
            font.family: Theme.font; font.pixelSize: 15
        }
    }
    SettingsGroup {
        Repeater {
            model: {
                const out = []
                const me = page.me
                if (me)
                    out.push({ k: "telefon", v: "+" + me.phone_number })
                if (me && me.usernames && me.usernames.active_usernames.length)
                    out.push({ k: "foydalanuvchi nomi", v: "@" + me.usernames.active_usernames.join(", @") })
                const f = page.full
                if (f && f.birthdate)
                    out.push({ k: "tug'ilgan kun", v: f.birthdate.day + "-" + page.months[f.birthdate.month - 1] +
                                                      (f.birthdate.year ? " " + f.birthdate.year : "") })
                if (f && f.bio && f.bio.text)
                    out.push({ k: "bio", v: f.bio.text })
                return out
            }
            Item {
                required property var modelData
                required property int index
                width: parent.width; height: value.y + value.height + 10
                Text {
                    x: 16; y: 9
                    text: parent.modelData.k
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 14
                }
                Text {
                    id: value
                    x: 16; y: 29
                    width: parent.width - 32
                    wrapMode: Text.Wrap
                    text: parent.modelData.v
                    color: Theme.accent
                    font.family: Theme.font; font.pixelSize: 16
                }
                Rectangle { x: 16; anchors.bottom: parent.bottom; width: parent.width - 16; height: 0.5; color: Theme.separator }
            }
        }
    }
}
