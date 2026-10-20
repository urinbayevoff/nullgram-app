// An iOS switch: green when on, the knob sliding over.
import QtQuick

Rectangle {
    id: sw
    property bool on: false
    signal toggled()
    width: 51; height: 31; radius: 15.5
    color: on ? "#34c759" : Theme.dark ? "#39393d" : "#e9e9ea"
    Behavior on color { ColorAnimation { duration: 200 } }
    Rectangle {
        y: 2; width: 27; height: 27; radius: 13.5
        x: sw.on ? sw.width - width - 2 : 2
        color: "white"
        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }
}
