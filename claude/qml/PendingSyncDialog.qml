import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

// Every Favorites change its platform has not confirmed yet, with what is holding
// it up and the action that clears it: login to the song's own platform, reconnect
// or retry. Abandoning, after a confirmation, only stops further retries: an earlier
// request may already have reached the server. Account IDs are never shown.
Popup {
    id: pd
    objectName: "pendingSyncDialog"
    required property var app
    required property var ui
    required property var acts
    readonly property var items: acts.pendingItems
    readonly property int staleCount: {
        var n = 0
        for (var i = 0; i < items.length; i++) if (items[i].reason === "account" && items[i].canDiscard === true) n++
        return n
    }
    readonly property bool anyRetry: {
        for (var i = 0; i < items.length; i++) if (items[i].canRetry === true) return true
        return false
    }
    readonly property bool anyOffline: {
        for (var i = 0; i < items.length; i++) if (items[i].reason === "offline") return true
        return false
    }
    readonly property bool reconnecting: app.serviceReconnecting === true

    function login(provider) {
        close()
        app.openProviderLogin(provider)
    }

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    modal: true
    focus: true
    padding: 0
    closePolicy: Popup.CloseOnEscape
    background: Item {}
    Overlay.modal: Rectangle { color: skinTheme.palette.modalVeil }

    contentItem: RetroPane {
        ui: pd.ui
        framed: true
        title: "PENDING " + pd.items.length
        implicitWidth: Math.min(Math.round(500 * pd.ui.fs), pd.parent ? pd.parent.width - 4 * pd.ui.pad : 500)
        implicitHeight: Math.min(Math.round(440 * pd.ui.fs), pd.parent ? pd.parent.height - 4 * pd.ui.pad : 440)
        tools: [
            PixelButton {
                anchors.verticalCenter: parent.verticalCenter
                ui: pd.ui
                tone: "solid"
                glyph: "{x}"
                tip: "关闭"
                onClicked: pd.close()
            }
        ]

        Text {
            id: intro
            x: pd.ui.pad
            y: pd.ui.px * 4
            width: parent.width - 2 * pd.ui.pad
            text: pd.items.length > 0 ? "平台尚未确认这些改动。当前收藏状态已保存在本机。放弃只会停止重试，之前的请求可能已到达平台。" : ""
            color: skinTheme.palette.inkDim
            font.pixelSize: pd.ui.fSmall
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
        ListView {
            id: plist
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: intro.bottom
            anchors.topMargin: pd.ui.px * 3
            anchors.bottom: foot.top
            model: pd.items
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: PixelScrollBar { ui: pd.ui }
            delegate: Rectangle {
                id: prow
                required property var modelData
                readonly property bool writing: modelData.state === "syncing"
                readonly property string reason: String(modelData.reason || "")
                readonly property bool needsLogin: !writing && (reason === "login" || reason === "account")
                width: plist.width
                height: Math.round(pd.ui.rowH * 1.05)
                color: phover.hovered ? skinTheme.palette.hover : "transparent"
                HoverHandler { id: phover }
                SourceTag {
                    id: ptag
                    x: pd.ui.pad
                    anchors.verticalCenter: parent.verticalCenter
                    ui: pd.ui
                    provider: prow.modelData.provider
                    tip: ""
                }
                Column {
                    anchors.left: ptag.right
                    anchors.leftMargin: pd.ui.px * 4
                    anchors.right: pacts.left
                    anchors.rightMargin: pd.ui.px * 3
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: pd.ui.px
                    Text {
                        width: parent.width
                        text: (prow.modelData.desired === true ? "加入：" : "移出：") + pd.acts.title(prow.modelData.song)
                        color: skinTheme.palette.ink
                        font.pixelSize: pd.ui.fBody
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                    Text {
                        width: parent.width
                        text: pd.acts.pendingStatus(prow.modelData)
                        color: pd.acts.pendingColor(prow.modelData)
                        font.pixelSize: pd.ui.fSmall
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                }
                Row {
                    id: pacts
                    anchors.right: parent.right
                    anchors.rightMargin: pd.ui.pad
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: pd.ui.px * 2
                    PixelButton {
                        visible: prow.needsLogin
                        ui: pd.ui
                        tone: "line"
                        size: pd.ui.px * 12
                        label: prow.reason === "account" ? "切换账号" : "登录"
                        tip: (prow.reason === "account" ? "切回之前的" : "登录") + T.sourceLabel(prow.modelData.provider) + (prow.reason === "account" ? "账号" : "")
                        enabled: pd.app.connected
                        onClicked: pd.login(prow.modelData.provider)
                    }
                    PixelButton {
                        visible: prow.modelData.canRetry === true
                        ui: pd.ui
                        tone: "line"
                        size: pd.ui.px * 12
                        label: "重试"
                        onClicked: pd.acts.retryPending(prow.modelData)
                    }
                    PixelButton {
                        ui: pd.ui
                        tone: "line"
                        accent: skinTheme.palette.alert
                        size: pd.ui.px * 12
                        label: "放弃…"
                        tip: prow.writing ? "正在写入，完成后才能放弃" : "不再重试这项同步，平台可能已收到之前的请求"
                        enabled: prow.modelData.canDiscard === true
                        onClicked: pd.acts.abandonPending(prow.modelData)
                    }
                }
            }
        }
        StatePanel {
            anchors.fill: plist
            ui: pd.ui
            visible: pd.items.length === 0
            glyph: "{heart}"
            heading: "没有待同步的改动"
            detail: "收藏的改动都处理完了。"
        }
        Rectangle {
            id: foot
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: visible ? pd.ui.titleH + pd.ui.px * 2 : 0
            visible: pd.anyRetry || pd.anyOffline || pd.staleCount > 0
            color: skinTheme.palette.raised
            Row {
                x: pd.ui.pad
                anchors.verticalCenter: parent.verticalCenter
                spacing: pd.ui.px * 3
                PixelButton {
                    visible: pd.anyRetry
                    ui: pd.ui
                    tone: "line"
                    size: pd.ui.px * 12
                    label: "全部重试"
                    enabled: pd.acts.canRetrySync
                    onClicked: pd.acts.retrySync()
                }
                PixelButton {
                    visible: pd.anyOffline
                    ui: pd.ui
                    tone: "line"
                    size: pd.ui.px * 12
                    label: pd.reconnecting ? "正在连接…" : "重新连接"
                    tip: "重新连接播放服务"
                    enabled: !pd.reconnecting
                    onClicked: pd.app.reconnectService()
                }
                PixelButton {
                    visible: pd.staleCount > 0
                    ui: pd.ui
                    tone: "line"
                    accent: skinTheme.palette.alert
                    size: pd.ui.px * 12
                    label: "放弃之前账号的 " + pd.staleCount + " 项…"
                    tip: "不再重试这些同步，平台可能已收到之前的请求"
                    onClicked: pd.acts.abandonOldAccount()
                }
            }
        }
    }
}
