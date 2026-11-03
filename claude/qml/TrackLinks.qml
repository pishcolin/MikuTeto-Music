import QtQuick
import "theme.js" as T

// A song's artists and album as links into their detail windows. Every name
// keeps its own hit area (several artists → several links); long names are
// elided one by one so each stays clickable.
Item {
    id: tl
    required property var app
    required property var ui
    property var track: null
    property color tint: skinTheme.palette.inkDim
    property int fontSize: ui.fSmall + 1
    readonly property var acts: ui.acts
    readonly property var artistList: acts && track ? acts.artistsOf(track) : []
    readonly property var album: track && typeof app.albumItem === "function" ? app.albumItem(track) : null
    readonly property string albumName: album ? String(album.title || album.name || (track && track.album) || "")
        : (track && track.album ? String(track.album) : "")
    readonly property var parts: {
        var out = []
        var names = tl.artistList
        if (names.length > 0) {
            for (var i = 0; i < names.length; i++) {
                if (i > 0) out.push({ text: " / ", link: null, tip: "" })
                var n = String(names[i].title || names[i].name || "")
                out.push({ text: n, link: names[i], tip: "打开歌手：" + n })
            }
        } else {
            var plain = T.artists(tl.track)
            if (plain !== "") out.push({ text: plain, link: null, tip: "" })
        }
        if (tl.albumName !== "") {
            if (out.length > 0) out.push({ text: "  ", link: null, tip: "" })
            out.push({ text: "《" + tl.albumName + "》", link: tl.album, tip: "打开专辑" })
        }
        return out
    }
    readonly property int linkCount: {
        var n = 0
        for (var i = 0; i < parts.length; i++) if (parts[i].link) n++
        return n
    }

    implicitHeight: probe.implicitHeight
    clip: true
    Text { id: probe; visible: false; text: "Ag《》"; font.pixelSize: tl.fontSize }

    Row {
        height: parent.height
        Repeater {
            model: tl.parts
            Text {
                id: part
                required property var modelData
                readonly property bool isLink: !!modelData.link
                width: isLink ? Math.min(implicitWidth, Math.max(tl.ui.px * 24, Math.floor(tl.width * 0.94 / Math.max(1, tl.linkCount))))
                    : implicitWidth
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.text
                color: isLink && hov.hovered ? skinTheme.palette.mint : tl.tint
                font.pixelSize: tl.fontSize
                font.underline: isLink && hov.hovered
                elide: Text.ElideRight
                textFormat: Text.PlainText
                HoverHandler {
                    id: hov
                    enabled: part.isLink
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: {
                        if (hovered && tl.ui.showTip) tl.ui.showTip(part, part.modelData.tip)
                        else if (tl.ui.hideTip) tl.ui.hideTip(part)
                    }
                }
                TapHandler {
                    enabled: part.isLink
                    onTapped: tl.acts.openItem(part.modelData.link)
                }
            }
        }
    }
}
