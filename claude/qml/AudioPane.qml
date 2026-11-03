import QtQuick
import QtQuick.Layouts
import "theme.js" as T

// Now playing, bound to the real snapshot. Trial/preview, loading, buffering
// and failures are stated as they are; controls are disabled when unusable.
// The song's artists and album are links, led by its source tag; the heart is
// local Favorites; the {more} menu adds album/artist/platform actions. When the
// playing song comes from the platform not being browsed, one line says which
// account plays it, so the account shown in the title bar is not mistaken for it.
RetroPane {
    id: audio
    required property var app
    property bool compact: false
    property real lastVolume: 0.6
    property bool blink: true
    title: "AUDIO"
    implicitHeight: ui.titleH + ui.border + col.implicitHeight + 2 * ui.pad

    readonly property string qualityText: (app.actualQuality !== "" ? app.actualQuality : app.quality).toUpperCase()
    readonly property string modeLabel: app.mode === "one" ? "单曲循环" : (app.mode === "shuffle" ? "随机播放" : "列表循环")
    readonly property string modeGlyph: app.mode === "one" ? "{loop}1" : (app.mode === "shuffle" ? "RND" : "{loop}")
    readonly property string errorText: app.playError !== "" ? app.playError : (app.failed ? (app.status !== "" ? app.status : "这首歌没能播放") : "")
    readonly property var lyricNow: app.lyricIndex >= 0 && app.lyricIndex < app.lyricLines.length ? app.lyricLines[app.lyricIndex] : null
    readonly property string previewText: {
        var p = app.preview
        if (!p || typeof p !== "object") return ""
        var a = T.num(p.startMs !== undefined ? p.startMs : p.start)
        var b = T.num(p.endMs !== undefined ? p.endMs : p.end)
        return b > a ? "试听片段 " + T.time(a) + "–" + T.time(b) : ""
    }

    readonly property string playingSource: !app.hasTrack ? ""
        : (app.playingProvider ? String(app.playingProvider) : T.providerOf(app.current))
    readonly property bool foreign: playingSource !== "" && app.provider !== "" && playingSource !== app.provider
    SongMenu { id: nowMenu; app: audio.app; ui: audio.ui; context: "now" }

    Timer {
        interval: 480
        repeat: true
        running: audio.app.loading
        onTriggered: audio.blink = !audio.blink
        onRunningChanged: if (!running) audio.blink = true
    }

    tools: [
        PixelText {
            anchors.verticalCenter: parent.verticalCenter
            visible: audio.app.hasTrack && audio.qualityText !== ""
            text: audio.qualityText
            px: audio.ui.px
            color: skinTheme.palette.barTextDim
        },
        PixelButton {
            anchors.verticalCenter: parent.verticalCenter
            ui: audio.ui
            visible: audio.app.connected && audio.app.accountChecked && !audio.app.loggedIn && audio.app.accountState !== "error"
            tone: "solid"
            glyph: "LOGIN"
            tip: "扫码登录" + audio.app.providerName
            onClicked: audio.app.openLogin()
        },
        PixelButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: audio.app.loggedIn
            ui: audio.ui
            tone: "bar"
            readonly property string nick: audio.app.nickname !== "" ? audio.app.nickname : "已登录"
            label: nick.length > 12 ? nick.substring(0, 11) + "…" : nick
            tip: audio.app.providerName + "账号与设置"
            onClicked: audio.ui.acts.openSettings("account")
        },
        Badge {
            anchors.verticalCenter: parent.verticalCenter
            ui: audio.ui
            visible: audio.app.loggedIn && audio.app.vip
            text: "VIP"
            tint: skinTheme.palette.trial
            filled: true
        }
    ]

    ColumnLayout {
        id: col
        x: audio.ui.pad
        y: audio.ui.pad
        width: parent.width - 2 * audio.ui.pad
        spacing: audio.ui.px * 3

        ServiceBanner {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            app: audio.app
            ui: audio.ui
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: audio.ui.px * 2
            Text {
                Layout.fillWidth: true
                text: audio.app.hasTrack ? String(audio.app.current.title || "未知歌曲")
                    : (audio.app.connected ? "没有正在播放的歌曲"
                    : (audio.app.serviceError !== "" ? "播放服务没有启动" : "正在启动播放服务"))
                color: audio.app.hasTrack ? skinTheme.palette.ink : skinTheme.palette.inkDim
                font.pixelSize: audio.ui.fTitle
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
                textFormat: Text.PlainText
            }
            HeartButton {
                Layout.alignment: Qt.AlignVCenter
                ui: audio.ui
                visible: audio.app.hasTrack
                item: audio.app.hasTrack ? audio.app.current : null
                size: Math.round(30 * audio.ui.fs)
            }
            PixelButton {
                id: moreButton
                Layout.alignment: Qt.AlignVCenter
                ui: audio.ui
                visible: audio.app.hasTrack
                tone: "tab"
                size: Math.round(30 * audio.ui.fs)
                glyph: "{more}"
                tip: "专辑、歌手、加入歌单"
                onClicked: nowMenu.show(audio.app.current, moreButton)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: audio.app.hasTrack
            spacing: audio.ui.px * 3
            SourceTag {
                Layout.alignment: Qt.AlignVCenter
                ui: audio.ui
                provider: audio.playingSource
            }
            TrackLinks {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                app: audio.app
                ui: audio.ui
                track: audio.app.hasTrack ? audio.app.current : null
            }
        }
        Text {
            Layout.fillWidth: true
            visible: audio.foreign
            text: T.sourceLabel(audio.playingSource) + "的歌，按" + T.sourceLabel(audio.playingSource)
                + "的账号和权益播放；现在浏览的是" + audio.app.providerName + "。"
            color: skinTheme.palette.inkFaint
            font.pixelSize: audio.ui.fSmall
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
        Text {
            Layout.fillWidth: true
            text: audio.app.hasTrack ? ""
                : (!audio.app.connected ? ""
                : "在曲库中双击歌曲开始播放。" + (audio.app.accountChecked && !audio.app.loggedIn ? (audio.app.provider === "qq" ? "搜索和播放请先登录 QQ 音乐。" : "登录网易云音乐后可读取你的歌单与每日推荐。") : ""))
            visible: text !== ""
            color: audio.app.connected ? skinTheme.palette.inkFaint : skinTheme.palette.alert
            font.pixelSize: audio.ui.fSmall + 1
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }

        Flow {
            Layout.fillWidth: true
            spacing: audio.ui.px * 3
            visible: audio.app.hasTrack && (audio.app.trial || audio.app.loading || audio.app.buffering || audio.errorText !== "" || audio.app.status !== "")
            Badge { visible: audio.app.trial; ui: audio.ui; text: "TRIAL"; tint: skinTheme.palette.trial }
            Text {
                visible: audio.app.trial
                height: audio.ui.px * 11
                verticalAlignment: Text.AlignVCenter
                text: audio.previewText !== "" ? audio.previewText : "试听版本，不是完整音频"
                color: skinTheme.palette.trial
                font.pixelSize: audio.ui.fSmall
            }
            Badge {
                visible: audio.app.loading
                ui: audio.ui
                text: "LOADING"
                opacity: audio.blink ? 1 : 0.3
            }
            Badge { visible: audio.app.buffering && !audio.app.loading; ui: audio.ui; text: "BUFFER" }
            Badge { visible: audio.errorText !== ""; ui: audio.ui; text: "ERROR"; tint: skinTheme.palette.alert }
            Text {
                visible: audio.errorText !== ""
                height: audio.ui.px * 11
                verticalAlignment: Text.AlignVCenter
                text: audio.errorText
                color: skinTheme.palette.alert
                font.pixelSize: audio.ui.fSmall
                textFormat: Text.PlainText
            }
            PixelButton {
                visible: audio.errorText !== "" && audio.app.recoverable
                ui: audio.ui
                tone: "line"
                accent: skinTheme.palette.alert
                label: "重试"
                size: audio.ui.px * 11
                onClicked: audio.app.retry()
            }
            PixelButton {
                readonly property var sync: audio.ui.acts ? audio.ui.acts.providerSync(audio.playingSource) : ({})
                visible: audio.errorText !== "" && audio.foreign && sync.canLogin === true
                ui: audio.ui
                tone: "line"
                accent: skinTheme.palette.alert
                label: "登录" + T.sourceLabel(audio.playingSource)
                size: audio.ui.px * 11
                onClicked: audio.app.openProviderLogin(audio.playingSource)
            }
            Text {
                visible: audio.app.status !== "" && audio.app.status !== audio.errorText
                height: audio.ui.px * 11
                verticalAlignment: Text.AlignVCenter
                text: audio.app.status
                color: skinTheme.palette.inkDim
                font.pixelSize: audio.ui.fSmall
                textFormat: Text.PlainText
            }
        }

        Text {
            Layout.fillWidth: true
            visible: audio.compact && audio.app.hasTrack && audio.lyricNow !== null && audio.lyricNow.text !== ""
            text: audio.lyricNow ? audio.lyricNow.text : ""
            color: skinTheme.palette.mint
            font.pixelSize: audio.ui.fLyric
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: audio.ui.px * 4
            PixelText {
                Layout.alignment: Qt.AlignBottom
                text: audio.app.hasTrack ? T.clock(seek.pressed ? seek.value * audio.app.durationMs : audio.app.displayMs) : "--:--"
                px: audio.compact ? Math.round(audio.ui.px * 1.5) : audio.ui.px * 2
                color: audio.app.hasTrack ? skinTheme.palette.mint : skinTheme.palette.mintDim
            }
            Item { Layout.fillWidth: true; implicitHeight: 1 }
            PixelText {
                Layout.alignment: Qt.AlignBottom
                text: audio.app.durationMs > 0 ? T.clock(audio.app.durationMs) : "--:--"
                px: audio.ui.px
                color: skinTheme.palette.inkDim
            }
        }

        SegSlider {
            id: seek
            Layout.fillWidth: true
            ui: audio.ui
            enabled: audio.app.hasTrack && audio.app.seekable && audio.app.durationMs > 0
            external: audio.app.fraction
            stepSize: audio.app.durationMs > 0 ? Math.min(1, 5000 / audio.app.durationMs) : 0.05
            Accessible.name: "播放进度"
            onCommitted: (v) => audio.app.seekMs(v * audio.app.durationMs)
        }

        RowLayout {
            id: controls
            Layout.fillWidth: true
            spacing: audio.ui.px * 3
            readonly property int h: Math.round(34 * audio.ui.fs)
            PixelButton {
                ui: audio.ui
                size: controls.h
                tone: "line"
                glyph: "{prev}"
                tip: "上一首  Ctrl+←"
                enabled: audio.app.canControl
                onClicked: audio.app.step(-1)
            }
            PixelButton {
                ui: audio.ui
                size: controls.h
                Layout.preferredWidth: Math.round(controls.h * 1.6)
                tone: "primary"
                glyph: audio.app.playing ? "{pause}" : "{play}"
                tip: audio.app.playing ? "暂停  空格" : "播放  空格"
                enabled: audio.app.canControl
                onClicked: audio.app.toggle()
            }
            PixelButton {
                ui: audio.ui
                size: controls.h
                tone: "line"
                glyph: "{next}"
                tip: "下一首  Ctrl+→"
                enabled: audio.app.canControl
                onClicked: audio.app.step(1)
            }
            PixelButton {
                ui: audio.ui
                size: controls.h
                tone: "line"
                glyph: audio.modeGlyph
                label: audio.compact ? "" : audio.modeLabel
                tip: "播放顺序：" + audio.modeLabel + "，点按切换"
                enabled: audio.app.connected
                onClicked: audio.app.cycleMode()
            }
            Item { Layout.fillWidth: true; implicitHeight: 1 }
            PixelButton {
                ui: audio.ui
                size: controls.h
                tone: "bar"
                glyph: audio.app.volume <= 0.001 ? "{mute}" : "{vol}"
                tip: audio.app.volume <= 0.001 ? "恢复音量" : "静音"
                enabled: audio.app.connected
                onClicked: {
                    if (audio.app.volume > 0.001) {
                        audio.lastVolume = audio.app.volume
                        audio.app.setVolume(0)
                    } else {
                        audio.app.setVolume(audio.lastVolume > 0.01 ? audio.lastVolume : 0.6)
                    }
                }
            }
            SegSlider {
                ui: audio.ui
                Layout.preferredWidth: Math.round((audio.compact ? 84 : 124) * audio.ui.fs)
                enabled: audio.app.connected
                external: audio.app.volume
                stepSize: 0.05
                Accessible.name: "音量"
                onDragged: (v) => audio.app.setVolume(v)
                onCommitted: (v) => audio.app.setVolume(v)
            }
            PixelText {
                Layout.preferredWidth: audio.ui.px * 23
                text: Math.round(audio.app.volume * 100) + "%"
                px: audio.ui.px
                color: skinTheme.palette.inkDim
            }
        }
    }
}
