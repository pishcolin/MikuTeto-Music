import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

MenuItem {
    id: mi
    required property var ui
    implicitHeight: Math.round(30 * ui.fs)
    height: visible ? implicitHeight : 0      // hidden context items leave no gap
    implicitWidth: Math.round(200 * ui.fs)
    leftPadding: ui.pad
    rightPadding: ui.pad
    contentItem: Text {
        text: mi.text
        color: mi.highlighted ? skinTheme.palette.pane : skinTheme.palette.ink
        font.pixelSize: mi.ui.fSmall
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle { color: mi.highlighted ? skinTheme.palette.mint : "transparent" }
    opacity: enabled ? 1 : 0.4
}
