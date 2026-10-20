// What every page has: the store, the navigation, and whether it is ready to move in.
import QtQuick

Rectangle {
    width: parent ? parent.width : 360
    height: parent ? parent.height : 760
    color: Theme.bg
    property var store
    property var nav
    property bool ready: true
    property bool started: false
}
