// Signing in: the QR code to scan from a phone already signed in (Settings → Devices →
// Link Desktop Device), or the number, its code and the cloud password.
import QtQuick

Page {
    id: page
    readonly property string step: store.auth === "WaitCode" ? "code"
                                  : store.auth === "WaitPassword" ? "password"
                                  : byPhone ? "phone" : "qr"
    property bool byPhone: td.testDc

    Column {
        x: 24; y: 90
        width: parent.width - 48
        spacing: 18

        Text {
            text: "Nullgram"
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 30; font.weight: Font.Bold
        }
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 15
            text: page.step === "qr" ? "Boshqa telefoningizda Telegram → Sozlamalar → Qurilmalar → «Qurilma ulash», va shu kodni skanerlang."
                : page.step === "phone" ? "Telefon raqamingiz (+998...)"
                : page.step === "code" ? "Telegram yuborgan kod"
                : "Bulutli parol" + (store.passwordHint ? " (eslatma: " + store.passwordHint + ")" : "")
        }

        Rectangle {          // the QR code: black modules on white
            visible: page.step === "qr"
            width: 236; height: 236
            color: "white"
            radius: 12
            property var rows: store.qrLink ? td.qr(store.qrLink) : []
            Grid {
                id: modules
                anchors.centerIn: parent
                property real cell: parent.rows.length ? Math.floor(212 / parent.rows.length * 4) / 4 : 0
                columns: parent.rows.length
                Repeater {
                    model: parent.parent.rows.length * parent.parent.rows.length
                    Rectangle {
                        required property int index
                        readonly property var rows: modules.parent.rows
                        width: modules.cell; height: modules.cell
                        color: rows[Math.floor(index / rows.length)].charAt(index % rows.length) === "1" ? "black" : "white"
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: !store.qrLink
                text: "kod tayyorlanmoqda..."
                color: "#666666"
                font.family: Theme.font; font.pixelSize: 14
            }
        }

        Rectangle {          // the field for a number, a code or the password
            visible: page.step !== "qr"
            width: parent.width; height: 48
            radius: 12
            color: Theme.field
            border.color: Theme.fieldBorder; border.width: 1
            TextInput {
                id: field
                anchors.fill: parent
                anchors.leftMargin: 14; anchors.rightMargin: 14
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 18
                echoMode: page.step === "password" ? TextInput.Password : TextInput.Normal
                inputMethodHints: page.step === "password" ? Qt.ImhNone : Qt.ImhDialableCharactersOnly
                onAccepted: page.next()
            }
        }

        Rectangle {
            visible: page.step !== "qr"
            width: parent.width; height: 48
            radius: 12
            color: Theme.accent
            Text { anchors.centerIn: parent; text: "Davom etish"; color: "white"; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold }
            MouseArea { anchors.fill: parent; onClicked: page.next() }
        }

        Text {
            text: page.step === "qr" ? "Raqam bilan kirish" : page.step === "phone" ? "QR kod bilan kirish" : ""
            color: Theme.accent
            font.family: Theme.font; font.pixelSize: 16
            MouseArea {
                anchors.fill: parent; anchors.margins: -10
                onClicked: {
                    page.byPhone = !page.byPhone
                    if (!page.byPhone)
                        store.send({ "@type": "requestQrCodeAuthentication" }, store.check)
                }
            }
        }

        Text {
            width: parent.width
            wrapMode: Text.Wrap
            visible: store.error !== ""
            text: store.error
            color: "#ff453a"
            font.family: Theme.font; font.pixelSize: 14
        }
    }

    function next() {
        const v = field.text.trim()
        if (!v)
            return
        if (step === "phone")
            store.send({ "@type": "setAuthenticationPhoneNumber", phone_number: v }, store.check)
        else if (step === "code")
            store.send({ "@type": "checkAuthenticationCode", code: v }, store.check)
        else if (step === "password")
            store.send({ "@type": "checkAuthenticationPassword", password: v }, store.check)
        field.text = ""
    }
}
