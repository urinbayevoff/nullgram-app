// The sessions signed in to this account (getActiveSessions): this one first, then the others
// by when they were last active, with their app, device and place.
import QtQuick

SubPage {
    id: page
    title: "Qurilmalar"
    property var sessions: []
    Component.onCompleted: store.send({ "@type": "getActiveSessions" }, (r) => {
        if (r.sessions)
            page.sessions = r.sessions.slice().sort((a, b) => (b.is_current - a.is_current) || (b.last_active_date - a.last_active_date))
    })

    function when(unix, current) {
        if (current)
            return "onlayn"
        return store.stamp(unix)
    }

    Repeater {
        model: [{ title: "Bu qurilma", list: page.sessions.filter((s) => s.is_current) },
                { title: "Faol seanslar", list: page.sessions.filter((s) => !s.is_current) }]
        SettingsGroup {
            id: group
            required property var modelData
            visible: modelData.list.length > 0
            title: modelData.title
            Repeater {
                model: group.modelData.list
                Item {
                    required property var modelData
                    required property int index
                    width: parent.width; height: 70
                    Rectangle {
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        width: 32; height: 32; radius: 8
                        color: ["#007aff", "#34c759", "#ff9500", "#af52de", "#ff3b30"][parent.index % 5]
                        Icon { anchors.centerIn: parent; width: 20; height: 20; name: "laptop"; color: "white" }
                    }
                    Text {
                        x: 60; y: 9
                        width: parent.width - x - 80
                        elide: Text.ElideRight
                        text: parent.modelData.device_model || parent.modelData.application_name
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 14; y: 11
                        text: page.when(parent.modelData.last_active_date, parent.modelData.is_current)
                        color: parent.modelData.is_current ? Theme.accent : Theme.grey
                        font.family: Theme.font; font.pixelSize: 14
                    }
                    Text {
                        x: 60; y: 30
                        width: parent.width - x - 14
                        elide: Text.ElideRight
                        text: parent.modelData.application_name + " " + parent.modelData.application_version
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 14
                    }
                    Text {
                        x: 60; y: 48
                        width: parent.width - x - 14
                        elide: Text.ElideRight
                        text: [parent.modelData.platform, parent.modelData.system_version, parent.modelData.location]
                              .filter((s) => s).join(" · ")
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 13
                    }
                    Rectangle { x: 60; anchors.bottom: parent.bottom; width: parent.width - 60; height: 0.5; color: Theme.separator }
                }
            }
        }
    }
}
