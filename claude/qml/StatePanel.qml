import QtQuick
import "theme.js" as T

// Finished empty / loading / error / login states: a bitmap word, one line of
// what is happening, one line of what to do, and the action that fixes it.
Item {
    id: sp
    required property var ui
    property string glyph: ""
    property string heading: ""
    property string detail: ""
    property bool alarm: false
    property string action: ""
    property string action2: ""
    signal acted()
    signal acted2()

    Column {
        id: col
        width: Math.max(0, Math.min(sp.width - sp.ui.pad * 4, Math.round(400 * sp.ui.fs)))
        x: Math.round((sp.width - width) / 2)
        y: Math.round(Math.max(sp.ui.pad, (sp.height - height) * 0.42))
        spacing: sp.ui.pad
        PixelText {
            visible: sp.glyph !== ""
            text: sp.glyph
            px: sp.ui.px * 2
            color: sp.alarm ? skinTheme.palette.alert : skinTheme.palette.mint
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: sp.heading
            color: skinTheme.palette.ink
            font.pixelSize: sp.ui.fBody + 1
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: sp.detail
            color: sp.alarm ? skinTheme.palette.alert : skinTheme.palette.inkDim
            font.pixelSize: sp.ui.fSmall
            wrapMode: Text.Wrap
            lineHeight: 1.25
            textFormat: Text.PlainText
        }
        Row {
            visible: sp.action !== "" || sp.action2 !== ""
            spacing: sp.ui.px * 3
            PixelButton {
                ui: sp.ui
                visible: sp.action !== ""
                tone: "primary"
                label: sp.action
                size: Math.round(32 * sp.ui.fs)
                onClicked: sp.acted()
            }
            PixelButton {
                ui: sp.ui
                visible: sp.action2 !== ""
                tone: "line"
                label: sp.action2
                size: Math.round(32 * sp.ui.fs)
                onClicked: sp.acted2()
            }
        }
    }
}
