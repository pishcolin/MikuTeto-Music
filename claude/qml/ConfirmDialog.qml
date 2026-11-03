import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

// A separate confirmation window for writes that cannot be taken back.
// It names the exact thing affected and lists what will happen. Focus starts
// on the safe button; the write runs only from the confirm button, once per
// click, and a failure stays in the window instead of closing it.
Popup {
    id: cd
    objectName: "confirmDialog"
    required property var app
    required property var ui
    property var opts: ({})
    property bool busy: false
    property string error: ""
    readonly property var lines: T.isList(opts.body) ? opts.body : []

    function ask(o) {
        opts = o || {}
        busy = false
        error = ""
        open()
        Qt.callLater(function () { keep.forceActiveFocus() })
    }
    function go() {
        if (busy || typeof opts.run !== "function") return
        busy = true
        error = ""
        opts.run(function (v, err) {
            cd.busy = false
            if (err) cd.error = String(err)
            else cd.close()
        })
    }

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    modal: true
    focus: true
    padding: 0
    closePolicy: busy ? Popup.NoAutoClose : Popup.CloseOnEscape
    background: Item {}
    Overlay.modal: Rectangle { color: skinTheme.palette.modalVeil }

    contentItem: RetroPane {
        id: frame
        ui: cd.ui
        framed: true
        title: cd.opts.title || "CONFIRM"
        barColor: cd.opts.alarm ? skinTheme.palette.alertBar : skinTheme.palette.bar
        implicitWidth: Math.min(Math.round(420 * cd.ui.fs), cd.parent ? cd.parent.width - 4 * cd.ui.pad : 420)
        implicitHeight: cd.ui.titleH + cd.ui.border * 3 + body.implicitHeight + 2 * cd.ui.pad
        tools: [
            PixelButton {
                anchors.verticalCenter: parent.verticalCenter
                ui: cd.ui
                tone: "solid"
                glyph: "{x}"
                tip: "关闭"
                enabled: !cd.busy
                onClicked: cd.close()
            }
        ]

        Column {
            id: body
            x: cd.ui.pad
            y: cd.ui.pad
            width: parent.width - 2 * cd.ui.pad
            spacing: cd.ui.pad

            Text {
                width: parent.width
                text: cd.opts.heading || ""
                color: skinTheme.palette.ink
                font.pixelSize: cd.ui.fBody + 2
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }

            // The exact thing that will be affected, framed so it cannot be missed.
            Rectangle {
                width: parent.width
                height: nameCol.implicitHeight + cd.ui.px * 8
                color: skinTheme.palette.raised
                border.width: cd.ui.border
                border.color: cd.opts.alarm ? skinTheme.palette.alert : skinTheme.palette.mintDim
                Column {
                    id: nameCol
                    x: cd.ui.px * 5
                    y: cd.ui.px * 4
                    width: parent.width - 2 * x
                    spacing: cd.ui.px * 2
                    Text {
                        width: parent.width
                        text: cd.opts.name ? "《" + cd.opts.name + "》" : ""
                        visible: text !== ""
                        color: skinTheme.palette.ink
                        font.pixelSize: Math.round(cd.ui.fTitle * 0.85)
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                    Text {
                        width: parent.width
                        text: cd.opts.meta || ""
                        visible: text !== ""
                        color: skinTheme.palette.inkDim
                        font.pixelSize: cd.ui.fSmall
                        textFormat: Text.PlainText
                    }
                }
            }

            Column {
                width: parent.width
                spacing: cd.ui.px * 3
                Repeater {
                    model: cd.lines
                    Item {
                        required property var modelData
                        width: parent.width
                        height: line.implicitHeight
                        Rectangle {
                            y: Math.round(line.font.pixelSize * 0.55)
                            width: cd.ui.px * 2
                            height: width
                            color: cd.opts.alarm ? skinTheme.palette.alert : skinTheme.palette.mint
                        }
                        Text {
                            id: line
                            x: cd.ui.px * 6
                            width: parent.width - x
                            text: String(modelData)
                            color: skinTheme.palette.inkDim
                            font.pixelSize: cd.ui.fSmall + 1
                            wrapMode: Text.Wrap
                            lineHeight: 1.2
                            textFormat: Text.PlainText
                        }
                    }
                }
            }

            Text {
                width: parent.width
                visible: cd.error !== ""
                text: "没有完成：" + cd.error
                color: skinTheme.palette.alert
                font.pixelSize: cd.ui.fSmall
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }

            Row {
                spacing: cd.ui.px * 3
                PixelButton {
                    id: keep
                    ui: cd.ui
                    tone: "primary"
                    label: cd.opts.cancel || "取消"
                    size: Math.round(32 * cd.ui.fs)
                    enabled: !cd.busy
                    onClicked: cd.close()
                }
                PixelButton {
                    ui: cd.ui
                    tone: "line"
                    accent: skinTheme.palette.alert
                    label: cd.busy ? (cd.opts.working || "正在处理…") : (cd.opts.confirm || "确定")
                    size: Math.round(32 * cd.ui.fs)
                    enabled: !cd.busy
                    onClicked: cd.go()
                }
            }
        }
    }
}
