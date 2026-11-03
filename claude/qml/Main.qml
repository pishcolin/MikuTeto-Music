import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import "theme.js" as T

// Miku Music: tiled retro windows on a mint desk. The right pane is the two-bay
// MIKU / TETO deck (PixelDeckStage), which follows the song actually playing.
ApplicationWindow {
    id: win
    width: 1280
    height: 800
    minimumWidth: 900
    minimumHeight: 600
    visible: true
    flags: Qt.Window | Qt.FramelessWindowHint
    onClosing: (event) => { event.accepted = desktop.closeWindow() }
    color: skinTheme.palette.mint
    title: store.hasTrack && store.current.title ? store.current.title + " - Miku Teto Music" : "Miku Teto Music"

    property string deckTab: "discover"
    property bool showHistory: false
    property string favSection: "favorites"   // favorites | playlists, both inside the FAV tab

    function toggleWindowSize() {
        if (visibility === Window.Maximized) showNormal()
        else showMaximized()
    }

    Store { id: store; objectName: "playerStore" }

    QtObject {
        id: metrics
        readonly property real s: T.clamp(Math.min(win.width / 1280, win.height / 800), 0.8, 2.2)
        readonly property real fs: T.clamp(1 + (s - 1) * 0.65, 0.9, 1.7)
        readonly property int px: s >= 1.75 ? 3 : 2
        readonly property int border: px
        readonly property int gap: px * 3
        readonly property int titleH: px * 13
        readonly property int pad: Math.round(12 * fs)
        readonly property int fBody: Math.round(14 * fs)
        readonly property int fSmall: Math.round(12 * fs)
        readonly property int fTitle: Math.round(22 * fs)
        readonly property int fLyric: Math.round(16 * fs)
        readonly property int rowH: Math.round(46 * fs)
        // Shared write flows and dialogs (FeatureActions); every component reaches them as ui.acts.
        readonly property var acts: featureActions
        readonly property bool reducedMotion: !!store.preferences && store.preferences["motion"] === "reduced"
        property Item desk: null
        property Item tipTarget: null
        property string tipText: ""
        property bool tipShown: false
        function release() { if (desk) desk.forceActiveFocus() }
        function showTip(target, text) {
            tipShown = false
            tipTarget = target
            tipText = text
            tipDelay.restart()
        }
        function hideTip(target) {
            if (target !== null && tipTarget !== target) return
            tipDelay.stop()
            tipShown = false
            tipTarget = null
        }
    }

    readonly property int margin: metrics.px + 1
    readonly property int fullBodyH: height - 2 * margin - metrics.titleH - metrics.border
    readonly property int artW: Math.round(Math.min(fullBodyH * 716 / 1200, width * 0.42))
    readonly property int restW: width - 2 * margin - artW - metrics.gap
    readonly property bool compact: restW < Math.round(740 * metrics.fs)
    readonly property int sideW: compact ? 0 : Math.round(T.clamp(restW * 0.36, 300 * metrics.fs, 480 * metrics.fs))
    readonly property int mainW: compact ? restW : restW - sideW - metrics.gap
    // FAV is the player's own Favorites (QQ + NetEase), so it stays put when the skin switches.
    readonly property var deckTabs: compact
        ? [{ id: "search", glyph: "SEARCH", tip: "搜索  Ctrl+F" }, { id: "discover", glyph: "DISCOVER", tip: "发现" }, { id: "mine", glyph: "MINE", tip: "我的音乐（当前平台账号）" },
           { id: "favorites", glyph: "FAV", tip: "我的收藏和本地歌单" },
           { id: "queue", glyph: "QUEUE", tip: "播放队列" }, { id: "lyrics", glyph: "LYRICS", tip: "歌词" }]
        : [{ id: "search", glyph: "SEARCH", tip: "搜索  Ctrl+F" }, { id: "discover", glyph: "DISCOVER", tip: "发现" }, { id: "mine", glyph: "MINE", tip: "我的音乐（当前平台账号）" },
           { id: "favorites", glyph: "FAV", tip: "我的收藏和本地歌单" }]

    onCompactChanged: if (!compact && (deckTab === "queue" || deckTab === "lyrics")) deckTab = "discover"

    function openTab(id) {
        if (store.settingsOpen === true) store.closeSettings()
        store.clearDetails()
        deckTab = id
        if (id === "search") Qt.callLater(function () { searchView.focusField() })
    }
    function showFavSection(s) {
        store.clearDetails()
        favSection = s
    }
    function deskKey(event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
        if (event.key === Qt.Key_Space) { store.toggle(); event.accepted = true }
        else if (event.key === Qt.Key_Left) { store.seekBy(-5000); event.accepted = true }
        else if (event.key === Qt.Key_Right) { store.seekBy(5000); event.accepted = true }
        else if (event.key === Qt.Key_Escape && store.settingsOpen === true) { store.closeSettings(); event.accepted = true }
        else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Escape) { if (store.popDetail()) event.accepted = true }
    }

    Shortcut { sequences: [StandardKey.Find]; onActivated: win.openTab("search") }
    Shortcut { sequence: "Ctrl+Left"; onActivated: store.step(-1) }
    Shortcut { sequence: "Ctrl+Right"; onActivated: store.step(1) }
    Shortcut { sequence: "Ctrl+Up"; onActivated: store.setVolume(store.volume + 0.05) }
    Shortcut { sequence: "Ctrl+Down"; onActivated: store.setVolume(store.volume - 0.05) }
    Shortcut { sequence: "Alt+Left"; onActivated: store.popDetail() }
    Shortcut { sequence: "Ctrl+,"; onActivated: featureActions.toggleSettings() }
    Shortcut { sequence: "F1"; onActivated: desktop.showLicenses() }

    Connections {
        target: store
        function onActivateRequested() {
            if (win.visibility === Window.Minimized) win.showNormal()
            win.show()
            win.raise()
            win.requestActivate()
        }
    }

    FocusScope {
        id: desk
        anchors.fill: parent
        focus: true
        Component.onCompleted: metrics.desk = desk
        Keys.onPressed: (event) => win.deskKey(event)

        MouseArea {
            anchors.fill: parent
            z: -1
            onPressed: (mouse) => {
                metrics.hideTip(null)
                desk.forceActiveFocus()
                mouse.accepted = false
            }
        }

        AudioPane {
            id: audioPane
            chromeWindow: win
            ui: metrics
            app: store
            compact: win.compact
            x: win.margin
            y: win.margin
            width: win.mainW
            height: implicitHeight
        }

        RetroPane {
            id: deck
            ui: metrics
            x: win.margin
            y: audioPane.y + audioPane.height + metrics.gap
            width: win.mainW
            height: win.height - y - win.margin
            leading: [
                Repeater {
                    model: win.deckTabs
                    PixelButton {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        ui: metrics
                        glyph: modelData.glyph
                        tip: modelData.tip
                        active: win.deckTab === modelData.id
                        onClicked: win.openTab(modelData.id)
                    }
                }
            ]
            tools: [
                LyricTools { app: store; ui: metrics; visible: win.compact && win.deckTab === "lyrics" },
                PixelButton {
                    anchors.verticalCenter: parent.verticalCenter
                    ui: metrics
                    visible: win.deckTab === "favorites"
                    glyph: "{heart}"
                    label: win.compact ? "" : "收藏"
                    tip: "我的收藏"
                    active: win.favSection === "favorites"
                    onClicked: win.showFavSection("favorites")
                },
                PixelButton {
                    anchors.verticalCenter: parent.verticalCenter
                    ui: metrics
                    visible: win.deckTab === "favorites"
                    glyph: "{list}"
                    label: win.compact ? "" : "本地歌单"
                    tip: "本地歌单"
                    active: win.favSection === "playlists"
                    onClicked: win.showFavSection("playlists")
                }
            ]

            SearchView { id: searchView; anchors.fill: parent; app: store; ui: metrics; visible: win.deckTab === "search" }
            DiscoverView { id: discoverView; anchors.fill: parent; app: store; ui: metrics; visible: win.deckTab === "discover" }
            MineView { id: mineView; anchors.fill: parent; app: store; ui: metrics; visible: win.deckTab === "mine" }
            FavoritesView {
                id: favoritesView
                anchors.fill: parent
                app: store
                ui: metrics
                visible: win.deckTab === "favorites" && win.favSection === "favorites"
                onBrowseRequested: win.openTab("discover")
            }
            LocalPlaylistsView {
                anchors.fill: parent
                app: store
                ui: metrics
                visible: win.deckTab === "favorites" && win.favSection === "playlists"
            }
            Item { id: deckQueueSlot; anchors.fill: parent; visible: win.deckTab === "queue" }
            Item { id: deckLyricSlot; anchors.fill: parent; visible: win.deckTab === "lyrics" }

            Item {
                id: cascade
                anchors.fill: parent
                visible: store.detailCount > 0
                readonly property int step: Math.round(14 * metrics.fs)
                Repeater {
                    model: store.details
                    DetailWindow {
                        required property string scope
                        visible: scope === store.provider
                        app: store
                        ui: metrics
                        x: (store.detailRank(index) + 1) * cascade.step
                        y: (store.detailRank(index) + 1) * cascade.step
                        width: cascade.width - store.detailCount * cascade.step
                        height: cascade.height - store.detailCount * cascade.step
                        z: index
                    }
                }
            }

        }

        RetroPane {
            id: lyricPane
            chromeWindow: win
            ui: metrics
            visible: !win.compact
            title: "LYRICS"
            x: win.margin + win.mainW + metrics.gap
            y: win.margin
            width: win.sideW
            height: Math.round((win.height - 2 * win.margin - metrics.gap) * 0.58)
            tools: [ LyricTools { app: store; ui: metrics } ]
        }

        RetroPane {
            id: queuePane
            ui: metrics
            visible: !win.compact
            x: lyricPane.x
            y: lyricPane.y + lyricPane.height + metrics.gap
            width: win.sideW
            height: win.height - y - win.margin
            leading: [
                QueueTools {
                    app: store
                    ui: metrics
                    view: queueView
                    history: win.showHistory
                    onPicked: (h) => win.showHistory = h
                }
            ]
        }

        RetroPane {
            id: artPane
            chromeWindow: win
            ui: metrics
            leading: [
                PixelButton {
                    objectName: "mikuSkinButton"
                    anchors.verticalCenter: parent.verticalCenter
                    ui: metrics
                    glyph: "MIKU"
                    tip: "MIKU · QQ 音乐"
                    active: skinTheme.choice === "miku"
                    enabled: backend.connected && !backend.writeBusy
                    onClicked: backend.selectPlatform("qq")
                },
                PixelButton {
                    objectName: "tetoSkinButton"
                    anchors.verticalCenter: parent.verticalCenter
                    ui: metrics
                    glyph: "TETO"
                    tip: "TETO · 网易云音乐"
                    active: skinTheme.choice === "teto"
                    enabled: backend.connected && !backend.writeBusy
                    onClicked: backend.selectPlatform("netease")
                }
            ]
            x: win.width - win.margin - win.artW
            y: win.margin
            width: win.artW
            height: win.height - 2 * win.margin
            tools: [
                PixelButton {
                    objectName: "settingsButton"
                    anchors.verticalCenter: parent.verticalCenter
                    ui: metrics
                    glyph: "{gear}"
                    tip: "设置  Ctrl+,"
                    active: store.settingsOpen === true
                    onClicked: featureActions.toggleSettings()
                },
                PixelButton {
                    anchors.verticalCenter: parent.verticalCenter
                    ui: metrics
                    glyph: "{minimize}"
                    tip: "最小化"
                    onClicked: win.showMinimized()
                },
                PixelButton {
                    anchors.verticalCenter: parent.verticalCenter
                    ui: metrics
                    glyph: win.visibility === Window.Maximized ? "{restore}" : "{maximize}"
                    tip: win.visibility === Window.Maximized ? "还原窗口" : "最大化"
                    onClicked: win.toggleWindowSize()
                },
                PixelButton {
                    anchors.verticalCenter: parent.verticalCenter
                    ui: metrics
                    tone: "solid"
                    glyph: "{x}"
                    tip: "关闭播放器"
                    onClicked: win.close()
                }
            ]
            PixelDeckStage {
                id: stage
                objectName: "pixelDeckStage"
                anchors.fill: parent
                app: store
                ui: metrics
                mikuSource: mikuSpriteSource
                tetoSource: tetoSpriteSource
                hostVisible: win.visible && win.visibility !== Window.Minimized && win.visibility !== Window.Hidden
                visible: store.settingsOpen !== true
            }

            // Settings cover the whole deck and keep doing so as the pane resizes.
            SettingsWindow {
                id: settingsWindow
                app: store
                ui: metrics
                visible: store.settingsOpen === true
                z: 40
                anchors.fill: parent
            }
        }

        QueueView {
            id: queueView
            app: store
            ui: metrics
            showHistory: win.showHistory
            inlineTools: win.compact
            onHistoryPicked: (h) => win.showHistory = h
            parent: win.compact ? deckQueueSlot : queuePane.bodyItem
            anchors.fill: parent
        }
        LyricsView {
            id: lyricsView
            app: store
            ui: metrics
            parent: win.compact ? deckLyricSlot : lyricPane.bodyItem
            anchors.fill: parent
        }

        RetroPane {
            id: notice
            ui: metrics
            framed: true
            property bool shown: false
            z: 50
            visible: shown
            title: store.noticeError ? "ERROR" : "NOTICE"
            barColor: store.noticeError ? skinTheme.palette.alertBar : skinTheme.palette.bar
            width: Math.min(Math.round(360 * metrics.fs), deck.width - 4 * metrics.pad)
            height: metrics.titleH + metrics.border * 3 + noticeLabel.implicitHeight + 2 * metrics.pad
            x: deck.x + metrics.pad * 2
            y: win.height - height - metrics.pad * 2
            tools: [
                PixelButton {
                    anchors.verticalCenter: parent.verticalCenter
                    ui: metrics
                    tone: "solid"
                    glyph: "{x}"
                    tip: "关闭"
                    onClicked: notice.shown = false
                }
            ]
            Text {
                id: noticeLabel
                x: metrics.pad
                y: metrics.pad
                width: parent.width - 2 * metrics.pad
                text: store.noticeText
                color: store.noticeError ? skinTheme.palette.alert : skinTheme.palette.ink
                font.pixelSize: metrics.fSmall + 1
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }
            Timer {
                id: noticeTimer
                interval: store.noticeError ? 6500 : 3200
                onTriggered: notice.shown = false
            }
            Connections {
                target: store
                function onNoticeSerialChanged() {
                    notice.shown = true
                    noticeTimer.restart()
                }
            }
        }

        Rectangle {
            id: tipBox
            z: 100
            property point at: Qt.point(0, 0)
            visible: metrics.tipShown && metrics.tipTarget !== null && metrics.tipText !== ""
            x: T.clamp(at.x, 4, win.width - width - 4)
            y: at.y
            width: tipLabel.implicitWidth + metrics.pad
            height: tipLabel.implicitHeight + metrics.px * 4
            color: skinTheme.palette.pane
            border.color: skinTheme.palette.mint
            border.width: metrics.border
            Text {
                id: tipLabel
                anchors.centerIn: parent
                text: metrics.tipText
                color: skinTheme.palette.ink
                font.pixelSize: metrics.fSmall
            }
        }
        Timer {
            id: tipDelay
            interval: 550
            onTriggered: {
                var t = metrics.tipTarget
                if (!t || !t.visible) return
                var p = t.mapToItem(desk, 0, t.height + metrics.px * 2)
                if (p.y + tipBox.height > win.height - 4) p = t.mapToItem(desk, 0, -tipBox.height - metrics.px * 2)
                tipBox.at = Qt.point(p.x, p.y)
                metrics.tipShown = true
            }
        }
    }

    LoginWindow { app: store; ui: metrics }
    FeatureActions { id: featureActions; app: store; ui: metrics }
    WindowEdges { anchors.fill: parent; hostWindow: win; z: 200 }
}
