// Settings, as far as there are any yet: who is signed in, the night theme, what this is.
// (Signing out waits: TDLib's client closes on it, and a new one has to be made.)
import QtQuick

Page {
    id: page
    property string photo: ""
    property string tdVersion: ""
    onVisibleChanged: if (visible) {
        if (!photo && store.me)
            store.userPhoto(store.me, (path) => page.photo = path)
        if (!tdVersion)
            store.send({ "@type": "getOption", name: "version" }, (r) => {
                if (r.value)
                    page.tdVersion = r.value
            })
    }
    readonly property var me: store.me

    Flickable {
        anchors.fill: parent
        contentHeight: column.height + 120
        Column {
            id: column
            width: parent.width
            Item {
                width: parent.width; height: 56
                Text {
                    anchors.centerIn: parent
                    text: "Sozlamalar"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                }
            }
            Item {           // who is signed in
                width: parent.width; height: 196
                Avatar {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 8
                    width: 96; height: 96
                    source: page.photo
                    letters: page.me ? store.letters(page.me.first_name + " " + page.me.last_name) : ""
                    tint: page.me ? store.tints[Math.abs(page.me.id) % store.tints.length] : Theme.accent
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 116
                    text: page.me ? (page.me.first_name + " " + page.me.last_name).trim() : ""
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 24; font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 150
                    text: !page.me ? "" : ("+" + page.me.phone_number) +
                          (page.me.usernames && page.me.usernames.active_usernames.length
                           ? "  ·  @" + page.me.usernames.active_usernames[0] : "")
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 15
                }
            }

            Rectangle {      // a group of rows, rounded, as iOS lists settings
                x: 16; width: parent.width - 32
                height: rows.height
                radius: 12
                color: Theme.dark ? "#1c1c1d" : "#f2f2f7"
                Column {
                    id: rows
                    width: parent.width
                    Item {
                        width: parent.width; height: 50
                        Text {
                            x: 16; anchors.verticalCenter: parent.verticalCenter
                            text: "Tungi rejim"
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 16
                        }
                        Rectangle {          // a switch, iOS-like
                            id: sw
                            anchors.right: parent.right; anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 51; height: 31; radius: 15.5
                            color: Theme.dark ? "#34c759" : "#e9e9ea"
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Rectangle {
                                y: 2; width: 27; height: 27; radius: 13.5
                                x: Theme.dark ? parent.width - width - 2 : 2
                                color: "white"
                                Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: Theme.dark = !Theme.dark }
                    }
                    Rectangle { x: 16; width: parent.width - 16; height: 0.5; color: Theme.separator }
                    Item {
                        width: parent.width; height: 50
                        Text {
                            x: 16; anchors.verticalCenter: parent.verticalCenter
                            text: "Ilova haqida"
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 16
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Nullgram 0.8" + (page.tdVersion ? " · TDLib " + page.tdVersion : "")
                            color: Theme.grey
                            font.family: Theme.font; font.pixelSize: 15
                        }
                    }
                }
            }
        }
    }
}
