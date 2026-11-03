import QtQuick
import "theme.js" as T

// Queue pane tools: queue / history, jump to the playing song, save as a playlist.
Row {
    id: qt
    required property var app
    required property var ui
    property bool history: false
    property var view: null               // the QueueView these tools drive
    signal picked(bool history)
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    spacing: ui.px * 2
    PixelButton {
        anchors.verticalCenter: parent.verticalCenter
        ui: qt.ui
        glyph: "QUEUE " + qt.app.queue.length
        tip: "播放队列"
        active: !qt.history
        onClicked: qt.picked(false)
    }
    PixelButton {
        anchors.verticalCenter: parent.verticalCenter
        ui: qt.ui
        glyph: "HIST"
        tip: "最近播放"
        active: qt.history
        onClicked: qt.picked(true)
    }
    PixelButton {
        anchors.verticalCenter: parent.verticalCenter
        ui: qt.ui
        glyph: "{locate}"
        tip: "定位到正在播放的歌曲"
        enabled: qt.app.hasTrack && qt.view !== null
        onClicked: {
            qt.picked(false)
            Qt.callLater(qt.view.locateCurrent)
        }
    }
    PixelButton {
        anchors.verticalCenter: parent.verticalCenter
        ui: qt.ui
        glyph: "{save}"
        tip: qt.app.queue.length > 0 ? "把当前队列存成本地歌单" : "播放队列是空的"
        enabled: qt.app.queue.length > 0
        onClicked: qt.ui.acts.saveQueue()
    }
}
