import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

// QR login as an overlapping window. All key/poll/stale-reply logic is in Store.
Popup {
    id: dlg
    required property var app
    required property var ui
    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    modal: true
    focus: true
    padding: 0
    closePolicy: Popup.CloseOnEscape
    background: Item {}
    Overlay.modal: Rectangle { color: skinTheme.palette.modalVeil }
    onClosed: if (dlg.app.qrOpen) dlg.app.closeLogin()

    Connections {
        target: dlg.app
        function onQrOpenChanged() {
            if (dlg.app.qrOpen) dlg.open()
            else dlg.close()
        }
    }

    readonly property string statusText: {
        var p = app.qrPhase
        if (p === "loading") return "正在生成二维码"
        if (p === "waiting" && app.provider === "netease") return "用网易云音乐手机端扫描二维码登录"
        if (p === "waiting") return app.qrChannel === "wechat" ? "用微信扫描二维码登录 QQ 音乐" : "用手机 QQ 扫描二维码登录"
        if (p === "scanned") return "已扫描，请在手机上确认登录"
        if (p === "expired") return app.qrMessage !== "" ? app.qrMessage : "二维码已过期，请刷新"
        return app.qrMessage
    }

    contentItem: RetroPane {
        id: frame
        ui: dlg.ui
        framed: true
        title: "LOGIN"
        implicitWidth: Math.round(380 * dlg.ui.fs)
        implicitHeight: dlg.ui.titleH + dlg.ui.border * 3 + body.implicitHeight + 2 * dlg.ui.pad
        tools: [
            PixelButton {
                anchors.verticalCenter: parent.verticalCenter
                ui: dlg.ui
                tone: "solid"
                glyph: "{x}"
                tip: "关闭"
                onClicked: dlg.app.closeLogin()
            }
        ]
        Column {
            id: body
            x: dlg.ui.pad
            y: dlg.ui.pad
            width: parent.width - 2 * dlg.ui.pad
            spacing: dlg.ui.pad

            Row {
                spacing: dlg.ui.px * 2
                PixelButton {
                    ui: dlg.ui
                    tone: "tab"
                    size: Math.round(28 * dlg.ui.fs)
                    label: dlg.app.provider === "netease" ? "网易云扫码" : "QQ 扫码"
                    active: dlg.app.qrChannel === (dlg.app.provider === "netease" ? "netease" : "qq")
                    enabled: dlg.app.qrChannels.indexOf(dlg.app.provider === "netease" ? "netease" : "qq") >= 0
                    onClicked: if (!active || dlg.app.qrPhase === "expired" || dlg.app.qrPhase === "error") dlg.app.qrStart(dlg.app.provider === "netease" ? "netease" : "qq")
                }
                PixelButton {
                    ui: dlg.ui
                    tone: "tab"
                    size: Math.round(28 * dlg.ui.fs)
                    visible: dlg.app.provider === "qq"
                    label: "微信扫码"
                    active: dlg.app.qrChannel === "wechat"
                    enabled: dlg.app.qrChannels.indexOf("wechat") >= 0
                    onClicked: if (!active || dlg.app.qrPhase === "expired" || dlg.app.qrPhase === "error") dlg.app.qrStart("wechat")
                }
            }

            Rectangle {
                id: qrBox
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.round(208 * dlg.ui.fs)
                height: width
                color: skinTheme.palette.paper
                Image {
                    anchors.fill: parent
                    anchors.margins: dlg.ui.px * 3
                    source: dlg.app.qrImage
                    visible: dlg.app.qrImage !== ""
                    fillMode: Image.PreserveAspectFit
                    smooth: false
                    cache: false
                    opacity: dlg.app.qrPhase === "waiting" || dlg.app.qrPhase === "scanned" ? 1 : 0.15
                }
                Rectangle {
                    anchors.fill: parent
                    visible: dlg.app.qrPhase !== "waiting"
                    color: dlg.app.qrPhase === "scanned" ? skinTheme.palette.qrScanVeil : "transparent"
                }
                PixelText {
                    anchors.centerIn: parent
                    visible: dlg.app.qrPhase !== "waiting"
                    text: ({ loading: "LOADING", scanned: "SCANNED", expired: "EXPIRED", success: "OK", error: "ERROR" })[dlg.app.qrPhase] || ""
                    px: dlg.ui.px * 2
                    color: dlg.app.qrPhase === "error" ? skinTheme.palette.alert : (dlg.app.qrPhase === "scanned" ? skinTheme.palette.mint : skinTheme.palette.bar)
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: dlg.statusText
                visible: text !== ""
                color: dlg.app.qrPhase === "error" ? skinTheme.palette.alert : skinTheme.palette.ink
                font.pixelSize: dlg.ui.fBody
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: dlg.ui.px * 3
                PixelButton {
                    ui: dlg.ui
                    tone: "primary"
                    glyph: "{loop}"
                    label: "刷新二维码"
                    size: Math.round(32 * dlg.ui.fs)
                    enabled: dlg.app.qrPhase !== "loading" && dlg.app.qrPhase !== "success"
                    onClicked: dlg.app.qrStart(dlg.app.qrChannel)
                }
                PixelButton {
                    ui: dlg.ui
                    tone: "line"
                    label: "取消"
                    size: Math.round(32 * dlg.ui.fs)
                    onClicked: dlg.app.closeLogin()
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "登录信息由后台播放服务加密保存，这个窗口不读取、不记录账号凭据。"
                color: skinTheme.palette.inkFaint
                font.pixelSize: dlg.ui.fSmall
                wrapMode: Text.Wrap
            }
        }
    }
}
