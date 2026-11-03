import QtQuick
import "theme.js" as T

// A song's platform as a small pixel tag: QQ in MIKU teal, 163 in TETO red.
// The colours do not follow the skin, so a source reads the same while
// either skin is browsing. framed adds a pane-coloured rim for title bars.
Rectangle {
    id: tag
    required property var ui
    property string provider: ""
    property bool framed: false
    property string tip: T.sourceLabel(provider) !== "" ? "来自" + T.sourceLabel(provider) : ""
    readonly property bool known: T.sourceShort[provider] !== undefined
    visible: known
    implicitWidth: ui.px * 21
    implicitHeight: ui.px * 9
    width: implicitWidth
    height: implicitHeight
    color: known ? T.sourceTint[provider] : "transparent"
    border.width: framed ? Math.max(1, ui.px - 1) : 0
    border.color: skinTheme.palette.pane
    Accessible.name: T.sourceLabel(provider)

    PixelText {
        anchors.centerIn: parent
        text: T.sourceShort[tag.provider] || ""
        px: tag.ui.px
        color: skinTheme.palette.pane
    }
    HoverHandler {
        enabled: tag.tip !== ""
        onHoveredChanged: {
            if (hovered && tag.ui.showTip) tag.ui.showTip(tag, tag.tip)
            else if (tag.ui.hideTip) tag.ui.hideTip(tag)
        }
    }
}
