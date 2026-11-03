import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

// Square-cornered button: bitmap glyph and/or Chinese label.
// tone: bar (title bar), solid (mint square, like the wallpaper close box),
//       line (outlined), primary (filled), tab (body tab).
AbstractButton {
    id: b
    required property var ui
    property string glyph: ""
    property string label: ""
    property string tip: ""
    property string tone: "bar"
    property bool active: false
    property color accent: skinTheme.palette.mint
    // Optional glyph colour for state icons (heart); transparent = follow tone.
    property color glyphColor: "transparent"
    property int size: ui.titleH - ui.px * 2
    property real glyphPx: ui.px

    readonly property bool lit: active || down || hovered
    readonly property color fg: {
        if (tone === "solid") return lit ? accent : skinTheme.palette.paper
        if (tone === "primary") return skinTheme.palette.pane
        if (tone === "line") return lit ? skinTheme.palette.pane : accent
        if (tone === "tab") return active ? skinTheme.palette.pane : (hovered ? skinTheme.palette.ink : skinTheme.palette.inkDim)
        return active ? skinTheme.palette.pane : skinTheme.palette.paper
    }
    readonly property color bg: {
        if (tone === "solid") return lit ? skinTheme.palette.paper : accent
        if (tone === "primary") return down ? skinTheme.palette.paper : (hovered ? skinTheme.palette.primaryHover : accent)
        if (tone === "line") return lit ? accent : "transparent"
        if (tone === "tab") return active ? accent : (hovered ? skinTheme.palette.hover : "transparent")
        return active ? accent : (hovered ? skinTheme.palette.barHover : "transparent")
    }

    focusPolicy: Qt.TabFocus
    hoverEnabled: true
    padding: 0
    implicitHeight: size
    implicitWidth: Math.max(size, row.implicitWidth + (label !== "" ? ui.px * 10 : ui.px * 6))
    opacity: enabled ? 1 : 0.35
    Accessible.name: tip !== "" ? tip : (label !== "" ? label : glyph)

    background: Rectangle {
        color: b.bg
        border.width: b.tone === "line" ? Math.max(1, b.ui.px - 1) : 0
        border.color: b.accent
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            color: "transparent"
            border.width: 2
            border.color: skinTheme.palette.paper
            visible: b.visualFocus
        }
    }
    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight
        Row {
            id: row
            anchors.centerIn: parent
            spacing: b.ui.px * 3
            PixelText {
                visible: b.glyph !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: b.glyph
                px: b.glyphPx
                color: b.glyphColor.a > 0 ? b.glyphColor : b.fg
            }
            Text {
                visible: b.label !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: b.label
                color: b.fg
                font.pixelSize: b.ui.fSmall
                textFormat: Text.PlainText
            }
        }
    }
    Keys.onReturnPressed: b.clicked()
    Keys.onEnterPressed: b.clicked()
    onHoveredChanged: {
        if (hovered && tip !== "" && ui.showTip) ui.showTip(b, tip)
        else if (ui.hideTip) ui.hideTip(b)
    }
}
