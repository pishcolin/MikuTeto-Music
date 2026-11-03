import QtQuick
import QtQuick.Controls.Basic

// One choice in a settings group: square pixel marker, label, optional hint.
// `selected` is the value the service reports; `pending` marks a request that
// has been sent and not yet confirmed (marker blinks in the trial colour).
AbstractButton {
    id: rr
    required property var ui
    property string label: ""
    property string hint: ""
    property bool selected: false
    property bool pending: false
    property bool blink: true

    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    padding: 0
    implicitWidth: Math.round(300 * ui.fs)
    implicitHeight: texts.implicitHeight + ui.px * 6
    opacity: enabled ? 1 : 0.4
    Accessible.role: Accessible.RadioButton
    Accessible.name: label
    Accessible.checked: selected

    background: Rectangle {
        color: rr.hovered && !rr.selected ? skinTheme.palette.hover : "transparent"
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            color: "transparent"
            border.width: 2
            border.color: skinTheme.palette.paper
            visible: rr.visualFocus
        }
    }
    contentItem: Item {
        Rectangle {
            id: box
            x: rr.ui.px * 3
            y: texts.y + Math.max(0, Math.round((labelText.height - height) / 2))
            width: rr.ui.px * 7
            height: width
            color: "transparent"
            border.width: rr.ui.px
            border.color: rr.selected || rr.pending ? skinTheme.palette.mint
                : (rr.hovered ? skinTheme.palette.inkDim : skinTheme.palette.inkFaint)
            Rectangle {
                anchors.centerIn: parent
                width: rr.ui.px * 3
                height: width
                visible: rr.selected || (rr.pending && rr.blink)
                color: rr.pending && !rr.selected ? skinTheme.palette.trial : skinTheme.palette.mint
            }
        }
        Column {
            id: texts
            x: box.x + box.width + rr.ui.px * 5
            y: rr.ui.px * 3
            width: Math.max(0, parent.width - x - rr.ui.px * 3)
            spacing: rr.ui.px
            Text {
                id: labelText
                width: parent.width
                text: rr.label + (rr.pending && !rr.selected ? "  …" : "")
                color: rr.selected ? skinTheme.palette.mint : skinTheme.palette.ink
                font.pixelSize: rr.ui.fBody
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Text {
                width: parent.width
                visible: text !== ""
                text: rr.hint
                color: skinTheme.palette.inkDim
                font.pixelSize: rr.ui.fSmall
                wrapMode: Text.Wrap
                lineHeight: 1.15
                textFormat: Text.PlainText
            }
        }
    }
}
