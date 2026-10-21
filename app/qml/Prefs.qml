// What the user chose in the settings, beyond the night theme (Theme.dark); kept by Main.qml's
// Settings in ~/.config/OmonullOS/Nullgram.conf.
pragma Singleton
import QtQuick

QtObject {
    property bool autoGif: true         // GIFs come down and play by themselves
    property bool autoVoice: true       // voice notes and round videos come down by themselves
    property string silent: ""          // the channels whose posts go without a sound (their 🔔 off): ids, comma between
}
