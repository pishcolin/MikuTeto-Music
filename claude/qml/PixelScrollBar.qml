import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

ScrollBar {
    id: sb
    required property var ui
    policy: ScrollBar.AsNeeded
    minimumSize: 0.08
    padding: 0
    contentItem: Rectangle {
        implicitWidth: sb.ui.px * 3
        implicitHeight: sb.ui.px * 3
        color: sb.pressed ? skinTheme.palette.paper : skinTheme.palette.mint
        opacity: sb.active ? 1 : 0.4
    }
    background: Item {}
}
