// A video playing in its bubble: a GIF over and over without sound, a round video once with
// it, cut to the bubble's corners (or a circle) by a mask on the GPU.
import QtQuick
import QtQuick.Effects
import QtMultimedia

Item {
    id: v
    property string path: ""
    property real radius: 14            // -1: a circle
    property bool sound: false
    property bool loop: true
    property bool running: true
    readonly property real position: player.position
    readonly property real duration: player.duration
    readonly property bool showing: player.playbackState !== MediaPlayer.StoppedState && player.hasVideo
    signal ended()

    MediaPlayer {
        id: player
        source: v.path ? "file://" + v.path : ""
        videoOutput: out
        audioOutput: v.sound ? audio : null
        loops: v.loop ? MediaPlayer.Infinite : 1
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) v.ended()
    }
    AudioOutput { id: audio }
    onRunningChanged: running ? player.play() : player.pause()
    // (the path may come after it is made: play then)
    onPathChanged: if (running && path) player.play()
    Component.onCompleted: if (running && path) player.play()

    VideoOutput {
        id: out
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        visible: false
        layer.enabled: true
    }
    Rectangle {
        id: mask
        anchors.fill: parent
        radius: v.radius < 0 ? width / 2 : v.radius
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        anchors.fill: parent
        source: out
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
}
