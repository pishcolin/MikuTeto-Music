import QtQuick
import "theme.js" as T

// Persistent strip at the top of AUDIO for faults that stop everyday use: the
// playback service is gone, or the account could not be read. It stays until the
// fault clears and always carries the action that recovers from it.
Rectangle {
    id: sb
    required property var app
    required property var ui
    readonly property bool reconnecting: app.serviceReconnecting === true
    readonly property bool serviceDown: !app.connected && (reconnecting || app.serviceError !== "")
    readonly property bool accountFailed: app.connected && app.accountState === "error"
    readonly property bool canLogin: { var a = ui.acts; return !!a && a.providerSync(app.provider).canLogin === true }

    visible: serviceDown || accountFailed
    implicitHeight: Math.max(label.implicitHeight, actions.implicitHeight) + ui.px * 4
    color: reconnecting ? skinTheme.palette.select : skinTheme.palette.alertBar

    Badge {
        id: mark
        x: sb.ui.px * 3
        anchors.verticalCenter: parent.verticalCenter
        ui: sb.ui
        text: sb.serviceDown ? "OFFLINE" : "ACCOUNT"
        tint: skinTheme.palette.paper
    }
    Text {
        id: label
        anchors.left: mark.right
        anchors.leftMargin: sb.ui.px * 3
        anchors.right: actions.left
        anchors.rightMargin: sb.ui.px * 3
        anchors.verticalCenter: parent.verticalCenter
        text: sb.reconnecting ? "正在重新连接播放服务…"
            : sb.serviceDown ? sb.app.serviceError
            : "没有读到" + sb.app.providerName + "账号" + (sb.app.accountError ? "：" + sb.app.accountError : "")
        color: skinTheme.palette.paper
        font.pixelSize: sb.ui.fSmall
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }
    Row {
        id: actions
        anchors.right: parent.right
        anchors.rightMargin: sb.ui.px * 3
        anchors.verticalCenter: parent.verticalCenter
        spacing: sb.ui.px * 2
        PixelButton {
            visible: sb.serviceDown
            ui: sb.ui
            tone: "line"
            accent: skinTheme.palette.paper
            size: sb.ui.px * 12
            label: "重新连接"
            enabled: !sb.reconnecting
            onClicked: sb.app.reconnectService()
        }
        PixelButton {
            visible: sb.accountFailed
            ui: sb.ui
            tone: "line"
            accent: skinTheme.palette.paper
            size: sb.ui.px * 12
            label: "重新读取"
            onClicked: sb.app.refreshAccount()
        }
        PixelButton {
            visible: sb.accountFailed && sb.canLogin
            ui: sb.ui
            tone: "line"
            accent: skinTheme.palette.paper
            size: sb.ui.px * 12
            label: "重新登录"
            onClicked: sb.app.openProviderLogin(sb.app.provider)
        }
    }
}
