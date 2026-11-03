import QtQuick
import QtQuick.Controls.Basic

// Context menu frame shared by song and collection menus.
Menu {
    id: rm
    required property var ui
    padding: ui.px
    background: Rectangle {
        implicitWidth: Math.round(252 * rm.ui.fs)      // fits platform-labelled items
        color: skinTheme.palette.raised
        border.color: skinTheme.palette.mint
        border.width: rm.ui.border
    }
}
