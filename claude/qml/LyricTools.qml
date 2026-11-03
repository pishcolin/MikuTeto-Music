import QtQuick
import "theme.js" as T

// Per-track lyric offset. Active line = position + document.offsetMs + lyrics.offsetMs,
// so a larger offset shows lines earlier.
Row {
    id: lt
    required property var app
    required property var ui
    readonly property bool usable: app.connected && app.hasTrack && app.lyricSynced
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    spacing: ui.px * 2
    PixelButton {
        anchors.verticalCenter: parent.verticalCenter
        ui: lt.ui
        glyph: "-"
        tip: "歌词推迟 0.2 秒"
        enabled: lt.usable
        onClicked: lt.app.setLyricOffset(lt.app.lyricOffset - 200)
    }
    PixelText {
        anchors.verticalCenter: parent.verticalCenter
        text: (lt.app.lyricOffset > 0 ? "+" : "") + Math.round(lt.app.lyricOffset) + "MS"
        px: lt.ui.px
        color: lt.usable ? skinTheme.palette.paper : skinTheme.palette.inkFaint
    }
    PixelButton {
        anchors.verticalCenter: parent.verticalCenter
        ui: lt.ui
        glyph: "+"
        tip: "歌词提前 0.2 秒"
        enabled: lt.usable
        onClicked: lt.app.setLyricOffset(lt.app.lyricOffset + 200)
    }
    PixelButton {
        anchors.verticalCenter: parent.verticalCenter
        ui: lt.ui
        glyph: "0"
        tip: "恢复这首歌的歌词时间"
        enabled: lt.usable && lt.app.lyricOffset !== 0
        onClicked: lt.app.resetLyricOffset()
    }
}
