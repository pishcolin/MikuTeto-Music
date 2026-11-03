import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

// Synchronized lyrics. The active line comes from the backend index; a click
// seeks to startMs - document.offsetMs - lyrics.offsetMs.
Item {
    id: lv
    required property var app
    required property var ui
    readonly property bool hasPlain: !app.lyricSynced && (app.lyricPlain !== "" || app.lyricLines.length > 0)

    function follow() { lines.currentIndex = lv.app.lyricIndex }
    Connections {
        target: lv.app
        function onLyricIndexChanged() { lv.follow() }
        function onLyricLinesChanged() { Qt.callLater(lv.follow) }
    }

    ListView {
        id: lines
        anchors.fill: parent
        anchors.leftMargin: lv.ui.pad
        anchors.rightMargin: lv.ui.pad
        visible: lv.app.hasTrack && lv.app.lyricSynced
        model: lv.app.lyricLines
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: Math.round(height * 0.34)
        preferredHighlightEnd: Math.round(height * 0.34) + lv.ui.rowH
        highlightMoveDuration: lv.ui.reducedMotion ? 0 : 280
        highlight: Item {}
        currentIndex: -1
        header: Item { width: 1; height: Math.round(lines.height * 0.34) }
        footer: Item { width: 1; height: Math.round(lines.height * 0.55) }
        ScrollBar.vertical: PixelScrollBar { ui: lv.ui }
        delegate: Item {
            id: line
            required property int index
            required property var modelData
            readonly property bool now: index === lv.app.lyricIndex
            readonly property bool past: lv.app.lyricIndex >= 0 && index < lv.app.lyricIndex
            width: lines.width
            height: textCol.implicitHeight + lv.ui.px * 5
            Rectangle {
                anchors.fill: parent
                color: skinTheme.palette.hover
                visible: lineHover.hovered && lv.app.seekable
            }
            Rectangle {
                visible: line.now
                width: lv.ui.px * 2
                height: textCol.implicitHeight
                anchors.verticalCenter: parent.verticalCenter
                color: skinTheme.palette.mint
            }
            Column {
                id: textCol
                x: lv.ui.px * 6
                width: parent.width - x
                anchors.verticalCenter: parent.verticalCenter
                spacing: lv.ui.px
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: line.modelData.text
                    wrapMode: Text.Wrap
                    color: line.now ? skinTheme.palette.paper : (line.past ? skinTheme.palette.inkFaint : skinTheme.palette.inkDim)
                    font.pixelSize: lv.ui.fLyric
                    font.weight: line.now ? Font.DemiBold : Font.Normal
                    textFormat: Text.PlainText
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: line.modelData.tr
                    wrapMode: Text.Wrap
                    color: line.now ? skinTheme.palette.mint : skinTheme.palette.inkFaint
                    font.pixelSize: lv.ui.fSmall
                    textFormat: Text.PlainText
                }
                Item {
                    width: 1
                    height: lv.ui.px * 3
                    visible: line.modelData.text === "" && line.modelData.tr === ""
                }
            }
            HoverHandler {
                id: lineHover
                cursorShape: lv.app.seekable ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
            TapHandler {
                enabled: lv.app.seekable
                onTapped: lv.app.seekLyric(line.index)
            }
        }
    }

    Flickable {
        id: plain
        anchors.fill: parent
        anchors.margins: lv.ui.pad
        visible: lv.app.hasTrack && lv.hasPlain
        contentHeight: plainCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: PixelScrollBar { ui: lv.ui }
        Column {
            id: plainCol
            width: plain.width
            spacing: lv.ui.pad
            Badge { ui: lv.ui; text: "UNSYNCED"; tint: skinTheme.palette.inkDim }
            Text {
                width: parent.width
                text: lv.app.lyricPlain !== "" ? lv.app.lyricPlain : lv.app.lyricLines.map(function (l) { return l.text }).join("\n")
                color: skinTheme.palette.inkDim
                font.pixelSize: lv.ui.fLyric
                wrapMode: Text.Wrap
                lineHeight: 1.5
                textFormat: Text.PlainText
            }
        }
    }

    StatePanel {
        anchors.fill: parent
        ui: lv.ui
        visible: !lines.visible && !plain.visible
        glyph: !lv.app.hasTrack ? "LYRICS" : (lv.app.lyricStatus === "loading" ? "LOADING" : "NO LYRICS")
        heading: !lv.app.hasTrack ? "播放歌曲后，歌词会跟着进度滚动"
            : (lv.app.lyricStatus === "loading" ? "正在读取歌词"
            : (lv.app.lyricMessage !== "" ? lv.app.lyricMessage : "这首歌没有可用的歌词"))
        detail: !lv.app.hasTrack ? "点任意一行跳到那里；标题栏的 + 和 - 调整歌词快慢。" : ""
    }
}
