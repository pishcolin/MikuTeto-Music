import QtQuick
import QtQuick.Layouts
import "theme.js" as T

// A small receiver in the wallpaper's pixel-window language. The signal strip
// shows actual request activity, not pretend audio levels.
Rectangle {
    id: radioPane
    required property var app
    required property var ui
    signal refreshRequested()
    readonly property bool here: app.radioActive && app.radio.provider === app.provider
    readonly property bool blocked: here && !!app.radio.error
    readonly property bool hasError: app.radio.provider === app.provider && !!app.radio.error
    readonly property bool loginNeeded: !app.loggedIn || (hasError && app.needsLogin(app.radio.error))
    readonly property bool paused: here && !!app.radio.paused
    readonly property bool fetching: here && !!app.radio.busy
    readonly property string station: app.provider === "netease" ? "私人 FM" : "猜你喜欢电台"
    readonly property string phase: !app.connected ? "OFFLINE" : !here ? "READY"
        : blocked ? "RETRY" : paused ? "PAUSED" : fetching ? "TUNING" : app.radio.waiting ? "WAIT" : "ON AIR"
    readonly property string detail: !app.connected ? "连接播放服务后，即可收听"
        : hasError ? app.radio.error
        : here ? (paused ? "电台已暂停，准备好再继续" : app.radio.waiting ? "正在等下一批推荐，不会循环旧歌" : fetching ? "正在寻找下一段旋律…" : "按你的口味，接着听下去")
        : app.radioActive ? "另一平台的电台正在播放，点开始可切换"
        : "从这一首开始，让下一首自己来"
    implicitHeight: Math.round(118 * ui.fs)
    color: skinTheme.palette.raised
    border.width: ui.border
    border.color: skinTheme.palette.rule

    Rectangle {
        id: receiverTop
        x: radioPane.ui.border; y: radioPane.ui.border
        width: parent.width - x * 2
        height: radioPane.ui.titleH
        color: skinTheme.palette.bar
        Row {
            x: radioPane.ui.px * 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: radioPane.ui.px * 4
            PixelText { text: "FM"; px: radioPane.ui.px; color: skinTheme.palette.paper }
            PixelText { text: radioPane.app.provider === "netease" ? "TETO / 02" : "MIKU / 01"; px: radioPane.ui.px; color: skinTheme.palette.barTextDim }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: radioPane.ui.px * 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: radioPane.ui.px * 3
            PixelText { text: radioPane.phase; px: radioPane.ui.px; color: skinTheme.palette.paper }
        }
    }

    RowLayout {
        id: receiverBody
        x: radioPane.ui.pad
        y: receiverTop.y + receiverTop.height + radioPane.ui.px * 5
        width: parent.width - 2 * x
        spacing: radioPane.ui.pad
        ColumnLayout {
            Layout.fillWidth: true
            spacing: radioPane.ui.px * 2
            Text {
                text: radioPane.station
                color: skinTheme.palette.ink
                font.pixelSize: radioPane.ui.fBody + 2
                font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                text: radioPane.detail
                color: radioPane.hasError ? skinTheme.palette.trial : skinTheme.palette.inkDim
                font.pixelSize: radioPane.ui.fSmall
                elide: Text.ElideRight
                textFormat: Text.PlainText
                HoverHandler { onHoveredChanged: if (hovered) radioPane.ui.showTip(parent, parent.text); else radioPane.ui.hideTip(parent) }
            }
        }
        PixelButton {
            objectName: "radioPrimary"
            Layout.alignment: Qt.AlignVCenter
            ui: radioPane.ui; tone: "primary"; size: Math.round(30 * radioPane.ui.fs)
            glyph: radioPane.here && !radioPane.blocked && !radioPane.paused ? "{pause}" : "{play}"
            label: radioPane.loginNeeded ? "登录" : radioPane.blocked ? "重试" : radioPane.here ? (radioPane.paused ? "继续" : "暂停") : "开始"
            tip: radioPane.loginNeeded ? "登录" + radioPane.app.providerName + "后收听" : !radioPane.here ? "开启" + radioPane.station + "，自动补入新推荐" : radioPane.blocked ? radioPane.app.radio.error : label + "电台"
            enabled: radioPane.app.connected && (radioPane.loginNeeded || !(radioPane.blocked && (radioPane.fetching || radioPane.app.radio.retryAfterMs > 0)))
            onClicked: {
                if (radioPane.loginNeeded) radioPane.app.openLogin()
                else if (radioPane.blocked) radioPane.app.retryRadio()
                else if (radioPane.here) radioPane.app.control("player.pause", {paused: !radioPane.paused}, radioPane.app.reportError)
                else radioPane.app.startRadio(null)
            }
        }
    }

    RowLayout {
        x: radioPane.ui.pad
        anchors.bottom: parent.bottom; anchors.bottomMargin: radioPane.ui.px * 4
        width: parent.width - x * 2
        spacing: radioPane.ui.px * 4
        Row {
            spacing: radioPane.ui.px
            property int pulse: 0
            Repeater {
                model: 8
                Rectangle {
                    required property int index
                    width: radioPane.ui.px * 3; height: radioPane.ui.px * 3
                    color: radioPane.here && (radioPane.fetching ? index === parent.pulse : index < Math.min(8, radioPane.app.radio.upcoming))
                        ? skinTheme.palette.mint : skinTheme.palette.rule
                }
            }
            Timer {
                interval: 180; repeat: true
                running: radioPane.visible && radioPane.fetching && !radioPane.ui.reducedMotion
                onTriggered: parent.pulse = (parent.pulse + 1) % 8
            }
        }
        Text {
            Layout.fillWidth: true
            text: radioPane.here ? "待播 " + radioPane.app.radio.upcoming + " 首 · 自动续播" : "个性化推荐 · 自动续播"
            color: skinTheme.palette.inkFaint
            font.pixelSize: radioPane.ui.fSmall
            elide: Text.ElideRight
        }
        PixelButton {
            objectName: "radioSecondary"
            ui: radioPane.ui; tone: "tab"; size: Math.round(22 * radioPane.ui.fs)
            label: radioPane.here ? "停止续播" : "换一批"
            tip: radioPane.here ? "停止自动补歌，保留当前歌曲和队列" : "重新读取当前平台的推荐"
            enabled: radioPane.app.connected
            onClicked: radioPane.here ? radioPane.app.stopRadio() : radioPane.refreshRequested()
        }
    }
}
