import QtQuick
import QtQuick.Controls.Basic

MenuSeparator {
    id: ms
    required property var ui
    leftPadding: ui.pad
    rightPadding: ui.pad
    topPadding: ui.px * 2
    bottomPadding: ui.px * 2
    height: visible ? implicitHeight : 0
    contentItem: Rectangle {
        implicitWidth: Math.round(160 * ms.ui.fs)
        implicitHeight: Math.max(1, ms.ui.px - 1)
        color: skinTheme.palette.mintDim
    }
}
