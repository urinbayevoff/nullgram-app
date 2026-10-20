// Colours, from Telegram-iOS's own themes (TelegramPresentationData/Sources/
// DefaultDayPresentationTheme.swift, DefaultDarkPresentationTheme.swift). Day is
// what the owner's iPhone shows: white lists, the green freeform wallpaper,
// light green bubbles of ours.
pragma Singleton
import QtQuick

QtObject {
    property bool dark: false

    readonly property color bg: dark ? "#000000" : "#ffffff"
    readonly property color bar: dark ? Qt.rgba(0.11, 0.11, 0.11, 0.92) : Qt.rgba(0.97, 0.97, 0.97, 0.92)
    readonly property color field: dark ? "#1c1c1d" : "#ffffff"
    readonly property color fieldBorder: dark ? "#3a3a3c" : "#d9d9de"
    readonly property color text: dark ? "#ffffff" : "#000000"
    readonly property color grey: "#8e8e93"
    readonly property color separator: dark ? "#38383a" : "#c8c7cc"
    readonly property color accent: dark ? "#3e88f7" : "#0088ff"
    readonly property color badge: accent
    readonly property color mutedBadge: dark ? "#666666" : "#b6b6bb"
    readonly property color highlight: dark ? "#2c2c2e" : "#e5e5ea"
    readonly property color menu: dark ? Qt.rgba(0.14, 0.14, 0.15, 0.96) : Qt.rgba(1, 1, 1, 0.96)
    readonly property color danger: dark ? "#ff453a" : "#ff3b30"
    readonly property color bubbleIn: dark ? "#1d1d1d" : "#ffffff"
    readonly property color bubbleOut: dark ? "#3e88f7" : "#e1ffc7"
    readonly property color inText: text
    readonly property color outText: dark ? "#ffffff" : "#000000"
    readonly property color inMeta: dark ? Qt.rgba(1, 1, 1, 0.5) : "#8e8e93"
    readonly property color outMeta: dark ? Qt.rgba(1, 1, 1, 0.65) : Qt.rgba(0, 0.549, 0.035, 0.8)
    readonly property color check: dark ? "#ffffff" : "#19c700"
    // the chat's wallpaper: Telegram's default four colours (dark: a night version of them)
    readonly property string wall: dark ? "1b2b23,16241c,2b3423,1f3022" : "dbddbb,6ba587,d5d88d,88b884"
    readonly property string font: "Adwaita Sans"
}
