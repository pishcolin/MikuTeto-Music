import QtQuick
import "theme.js" as T

Rectangle {
    id: badge
    required property var ui
    property string text: ""
    property color tint: skinTheme.palette.mint
    property bool filled: false
    implicitWidth: label.width + ui.px * 6
    implicitHeight: ui.px * 11
    color: filled ? tint : "transparent"
    border.width: Math.max(1, ui.px - 1)
    border.color: tint
    PixelText {
        id: label
        anchors.centerIn: parent
        text: badge.text
        px: badge.ui.px
        color: badge.filled ? skinTheme.palette.pane : badge.tint
    }
}
