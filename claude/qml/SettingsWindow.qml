import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

// Settings cover the whole deck pane, so the library and lyrics stay in view
// while something is adjusted. Every choice
// shows the value the service reports; a click only marks it pending until
// that value actually moves.
RetroPane {
    id: sw
    objectName: "settingsWindow"
    required property var app
    readonly property var acts: ui.acts
    readonly property string section: acts ? acts.settingsSection : "quality"
    readonly property var sections: [
        { id: "quality", label: "音质" }, { id: "playback", label: "播放" },
        { id: "lyrics", label: "歌词" }, { id: "account", label: "账号" }
    ]
    readonly property var prefs: app.preferences ? app.preferences : ({})
    readonly property bool prefsReady: app.preferencesReady === true
    property var prefPending: ({})
    property var prefErrors: ({})
    property string qualityWant: ""
    property string qualityError: ""
    property bool globalWant: false
    readonly property bool blink: acts ? acts.blink : true

    readonly property var qualityList: T.isList(app.qualityOptions) ? app.qualityOptions : []
    readonly property var qualityCodes: ({ best: "AUTO", standard: "STD", exhigh: "HQ", lossless: "SQ FLAC", ape: "SQ APE" })
    function qualityLabel(v) {
        for (var i = 0; i < qualityList.length; i++) if (qualityList[i].value === v) return String(qualityList[i].label)
        return String(v || "")
    }
    readonly property string playingQuality: app.actualQuality !== "" ? app.actualQuality : app.quality
    readonly property string playingCode: !app.hasTrack || playingQuality === "" ? "--"
        : (qualityCodes[playingQuality] || String(playingQuality).toUpperCase())

    readonly property bool lyricUsable: app.connected && app.hasTrack && app.lyricSynced
    readonly property var lyricNow: app.lyricIndex >= 0 && app.lyricIndex < app.lyricLines.length ? app.lyricLines[app.lyricIndex] : null
    readonly property var lyricNext: app.lyricIndex + 1 >= 0 && app.lyricIndex + 1 < app.lyricLines.length ? app.lyricLines[app.lyricIndex + 1] : null
    function ms(v) { var n = Math.round(T.num(v)); return (n > 0 ? "+" : "") + n + "MS" }

    readonly property var prefGroups: [
        { key: "close-behavior", title: "点 × 关闭窗口时", options: [
            { value: "quit", label: "退出播放器", hint: "停止播放并退出程序。" },
            { value: "tray", label: "缩到系统托盘", hint: "窗口隐藏，音乐继续播放；点托盘图标可以重新打开。" }
        ] },
        { key: "single-play-mode", title: "双击一首歌时", options: [
            { value: "replace", label: "替换播放队列", hint: "用这首歌所在的列表替换当前队列，从这首开始播放。" },
            { value: "append", label: "加入当前队列", hint: "把这首歌加进现在的队列并开始播放，原来的队列保留。" }
        ] },
        { key: "motion", title: "动画", options: [
            { value: "full", label: "完整", hint: "切歌时专辑封面带过渡动画，歌词平滑滚动。" },
            { value: "reduced", label: "减弱", hint: "封面直接切换，歌词直接跳到当前行，等待中的提示不闪烁。" }
        ] }
    ]

    framed: true
    title: "SETTINGS"
    tools: [
        PixelButton {
            anchors.verticalCenter: parent.verticalCenter
            ui: sw.ui
            tone: "solid"
            glyph: "{x}"
            tip: "关闭设置  Esc"
            onClicked: sw.app.closeSettings()
        }
    ]

    function _with(obj, key, val) {
        var o = Object.assign({}, obj)
        if (val === undefined) delete o[key]
        else o[key] = val
        return o
    }
    function setPref(key, value) {
        if (!app.connected || !prefsReady || typeof app.setPreference !== "function") return
        if (String(prefs[key]) === value || prefPending[key] !== undefined) return
        prefPending = _with(prefPending, key, value)
        prefErrors = _with(prefErrors, key, undefined)
        app.setPreference(key, value, function (v, err) {
            sw.prefPending = sw._with(sw.prefPending, key, undefined)
            if (err) sw.prefErrors = sw._with(sw.prefErrors, key, String(err))
        })
    }
    function setQuality(value) {
        if (!app.connected || typeof app.setQuality !== "function") return
        if (value === app.quality || qualityWant !== "") return
        qualityWant = value
        qualityError = ""
        qualityTimer.restart()
        app.setQuality(value, function (v, err) {
            if (err && sw.qualityWant === value) {
                sw.qualityWant = ""
                qualityTimer.stop()
                sw.qualityError = String(err)
            }
        })
    }
    function applyGlobal() {
        if (!lyricUsable || globalWant || typeof app.useLyricOffsetGlobally !== "function") return
        globalWant = true
        globalTimer.restart()
        app.useLyricOffsetGlobally()
    }
    Timer {
        id: qualityTimer
        interval: 6000
        onTriggered: {
            if (sw.qualityWant === "") return
            sw.qualityError = "播放器还没有确认切换到「" + sw.qualityLabel(sw.qualityWant) + "」，当前仍是「"
                + (sw.app.quality !== "" ? sw.qualityLabel(sw.app.quality) : "未知") + "」。"
            sw.qualityWant = ""
        }
    }
    Timer { id: globalTimer; interval: 5000; onTriggered: sw.globalWant = false }
    onVisibleChanged: {
        if (visible && app.connected && !prefsReady && !app.preferencesBusy && typeof app.refreshPreferences === "function")
            app.refreshPreferences()
    }
    Connections {
        target: sw.app
        ignoreUnknownSignals: true
        function onQualityChanged() {
            if (sw.qualityWant !== "" && sw.app.quality === sw.qualityWant) { sw.qualityWant = ""; qualityTimer.stop() }
        }
        function onLyricGlobalOffsetChanged() { sw.globalWant = false; globalTimer.stop() }
    }

    component GroupTitle: Text {
        property var ui
        width: parent ? parent.width : 0
        color: skinTheme.palette.ink
        font.pixelSize: ui ? ui.fBody + 1 : 15
        font.weight: Font.DemiBold
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }
    component Note: Text {
        property var ui
        property bool alarm: false
        width: parent ? parent.width : 0
        visible: text !== ""
        color: alarm ? skinTheme.palette.alert : skinTheme.palette.inkDim
        font.pixelSize: ui ? ui.fSmall : 12
        wrapMode: Text.Wrap
        lineHeight: 1.2
        textFormat: Text.PlainText
    }
    component Rule: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: skinTheme.palette.mintDim
    }

    Rectangle {
        id: head
        width: parent.width
        height: tabRow.height + sw.ui.pad * 2
        color: skinTheme.palette.raised
        Row {
            id: tabRow
            x: sw.ui.pad
            y: sw.ui.pad
            spacing: sw.ui.px * 2
            Repeater {
                model: sw.sections
                PixelButton {
                    required property var modelData
                    ui: sw.ui
                    tone: "tab"
                    size: Math.round(26 * sw.ui.fs)
                    label: modelData.label
                    active: sw.section === modelData.id
                    onClicked: {
                        sw.acts.settingsSection = modelData.id
                        flick.contentY = 0
                    }
                }
            }
        }
    }

    Flickable {
        id: flick
        anchors.top: head.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: sw.app.connected
        clip: true
        contentWidth: width
        contentHeight: (page.item ? page.item.implicitHeight : 0) + 2 * sw.ui.pad
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: PixelScrollBar { ui: sw.ui }
        Loader {
            id: page
            x: Math.round(sw.ui.pad * 1.5)
            y: sw.ui.pad
            width: flick.width - 2 * x
            sourceComponent: ({ quality: qualityPage, playback: playbackPage, lyrics: lyricsPage, account: accountPage })[sw.section] || qualityPage
        }
    }

    StatePanel {
        anchors.fill: flick
        ui: sw.ui
        visible: !sw.app.connected
        alarm: sw.app.serviceError !== ""
        glyph: "OFFLINE"
        heading: "播放服务还没有就绪"
        detail: sw.app.serviceError !== "" ? sw.app.serviceError : "服务启动后这里的设置才能读写。"
    }

    // ---------------------------------------------------------------- quality
    Component {
        id: qualityPage
        Column {
            spacing: sw.ui.pad
            Rectangle {
                width: parent.width
                height: meterCol.implicitHeight + sw.ui.px * 10
                color: "transparent"
                border.width: 1
                border.color: skinTheme.palette.mintDim
                Column {
                    id: meterCol
                    x: sw.ui.px * 5
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - meter.width - sw.ui.px * 15
                    spacing: sw.ui.px
                    Row {
                        spacing: sw.ui.px * 3
                        SourceTag {
                            anchors.verticalCenter: parent.verticalCenter
                            ui: sw.ui
                            provider: sw.app.hasTrack ? (sw.app.playingProvider ? String(sw.app.playingProvider) : T.providerOf(sw.app.current)) : ""
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: sw.app.hasTrack ? "正在播放的音质" : "现在没有在播放"
                            color: skinTheme.palette.inkDim
                            font.pixelSize: sw.ui.fSmall
                            textFormat: Text.PlainText
                        }
                    }
                    Text {
                        width: parent.width
                        visible: sw.app.hasTrack && sw.playingQuality !== ""
                        text: sw.qualityLabel(sw.playingQuality)
                        color: skinTheme.palette.ink
                        font.pixelSize: sw.ui.fBody
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                }
                PixelText {
                    id: meter
                    anchors.right: parent.right
                    anchors.rightMargin: sw.ui.px * 5
                    anchors.verticalCenter: parent.verticalCenter
                    text: sw.playingCode
                    px: sw.ui.px * (parent.width < Math.round(350 * sw.ui.fs) ? 1 : 2)
                    color: sw.app.hasTrack ? skinTheme.palette.mint : skinTheme.palette.mintDim
                }
            }

            GroupTitle { ui: sw.ui; text: sw.app.providerName + "想要的音质" }
            Note { ui: sw.ui; text: "这里设置的是" + sw.app.providerName + "的歌；另一个平台的音质切到 " + (sw.app.provider === "netease" ? "MIKU" : "TETO") + " 后设置。实际拿到的音质取决于账号权益和这首歌的版权，可能比这里选的低。" }
            Column {
                width: parent.width
                spacing: sw.ui.px
                Repeater {
                    model: sw.qualityList
                    RadioRow {
                        required property var modelData
                        width: parent.width
                        ui: sw.ui
                        label: String(modelData.label)
                        hint: modelData.value === "best" ? "按账号和这首歌能拿到的最高音质播放。" : ""
                        selected: sw.app.quality === modelData.value
                        pending: sw.qualityWant === modelData.value
                        blink: sw.blink
                        enabled: sw.app.connected && (sw.qualityWant === "" || pending)
                        onClicked: sw.setQuality(modelData.value)
                    }
                }
            }
            Note { ui: sw.ui; text: sw.qualityList.length === 0 ? "音质选项还没有读到。" : "" }
            Note { ui: sw.ui; alarm: true; text: sw.qualityError }
        }
    }

    // ---------------------------------------------------------------- playback
    Component {
        id: playbackPage
        Column {
            spacing: sw.ui.pad
            Note {
                ui: sw.ui
                text: !sw.prefsReady && sw.app.preferencesError === "" ? "正在读取播放设置…" : ""
            }
            Note {
                ui: sw.ui
                alarm: true
                text: sw.app.preferencesError ? (sw.prefsReady ? "上次修改没有保存：" : "播放设置没有读出来：") + sw.app.preferencesError : ""
            }
            PixelButton {
                visible: !sw.prefsReady && !!sw.app.preferencesError
                ui: sw.ui
                tone: "line"
                label: "重新读取"
                size: Math.round(28 * sw.ui.fs)
                enabled: !sw.app.preferencesBusy
                onClicked: if (typeof sw.app.refreshPreferences === "function") sw.app.refreshPreferences()
            }
            Repeater {
                model: sw.prefsReady ? sw.prefGroups : []
                Column {
                    id: group
                    required property var modelData
                    required property int index
                    width: parent.width
                    spacing: sw.ui.px * 2
                    readonly property string current: sw.prefs[modelData.key] !== undefined ? String(sw.prefs[modelData.key]) : ""
                    Rule { visible: group.index > 0 }
                    Item { width: 1; height: sw.ui.px * 2; visible: group.index > 0 }
                    GroupTitle { ui: sw.ui; text: group.modelData.title }
                    Repeater {
                        model: group.modelData.options
                        RadioRow {
                            required property var modelData
                            width: group.width
                            ui: sw.ui
                            label: modelData.label
                            hint: modelData.hint
                            selected: group.current === modelData.value
                            pending: sw.prefPending[group.modelData.key] === modelData.value
                            blink: sw.blink
                            enabled: sw.app.connected && sw.prefPending[group.modelData.key] === undefined || pending
                            onClicked: sw.setPref(group.modelData.key, modelData.value)
                        }
                    }
                    Note { ui: sw.ui; text: group.current === "" ? "当前值没有读到。" : "" }
                    Note { ui: sw.ui; alarm: true; text: sw.prefErrors[group.modelData.key] ? "没有保存：" + sw.prefErrors[group.modelData.key] : "" }
                }
            }
        }
    }

    // ---------------------------------------------------------------- lyrics
    Component {
        id: lyricsPage
        Column {
            spacing: sw.ui.pad
            GroupTitle { ui: sw.ui; text: "这首歌的歌词时间" }
            Note {
                ui: sw.ui
                text: !sw.app.hasTrack ? "播放一首有同步歌词的歌，就能在这里边听边校准。"
                    : (!sw.app.lyricSynced ? "《" + String(sw.app.current.title || "") + "》没有逐行同步的歌词，不需要校准。"
                    : "《" + String(sw.app.current.title || "") + "》  " + T.artists(sw.app.current))
            }

            // Live preview: the line on screen now and the one after it.
            Rectangle {
                width: parent.width
                height: previewCol.implicitHeight + sw.ui.px * 10
                color: skinTheme.palette.raised
                opacity: sw.lyricUsable ? 1 : 0.5
                Rectangle {
                    width: sw.ui.px * 2
                    height: parent.height - sw.ui.px * 8
                    anchors.verticalCenter: parent.verticalCenter
                    x: sw.ui.px * 4
                    color: skinTheme.palette.mint
                }
                Column {
                    id: previewCol
                    x: sw.ui.px * 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - sw.ui.px * 5
                    spacing: sw.ui.px * 2
                    Text {
                        width: parent.width
                        text: sw.lyricUsable ? (sw.lyricNow && sw.lyricNow.text !== "" ? sw.lyricNow.text : "♪") : "LYRICS"
                        color: skinTheme.palette.paper
                        font.pixelSize: sw.ui.fLyric
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                    Text {
                        width: parent.width
                        visible: sw.lyricUsable
                        text: sw.lyricNext ? sw.lyricNext.text : ""
                        color: skinTheme.palette.inkDim
                        font.pixelSize: sw.ui.fSmall + 1
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                }
            }

            Item {
                width: parent.width
                height: Math.max(offsetLabel.implicitHeight, bigOffset.height)
                Text {
                    id: offsetLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: "这首歌的校准"
                    color: skinTheme.palette.inkDim
                    font.pixelSize: sw.ui.fSmall
                }
                PixelText {
                    id: bigOffset
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: sw.ms(sw.app.lyricOffset)
                    px: sw.ui.px * 2
                    color: sw.lyricUsable ? skinTheme.palette.mint : skinTheme.palette.mintDim
                }
            }
            Flow {
                width: parent.width
                spacing: sw.ui.px * 3
                Repeater {
                    model: [
                        { glyph: "-0.5S", delta: -500, tip: "歌词推迟 0.5 秒" },
                        { glyph: "-0.1S", delta: -100, tip: "歌词推迟 0.1 秒" },
                        { glyph: "+0.1S", delta: 100, tip: "歌词提前 0.1 秒" },
                        { glyph: "+0.5S", delta: 500, tip: "歌词提前 0.5 秒" }
                    ]
                    PixelButton {
                        required property var modelData
                        ui: sw.ui
                        tone: "line"
                        size: Math.round(30 * sw.ui.fs)
                        glyph: modelData.glyph
                        tip: modelData.tip
                        enabled: sw.lyricUsable
                        onClicked: sw.app.setLyricOffset(sw.app.lyricOffset + modelData.delta)
                    }
                }
                PixelButton {
                    ui: sw.ui
                    tone: "line"
                    size: Math.round(30 * sw.ui.fs)
                    label: "归零"
                    tip: "恢复这首歌的歌词时间"
                    enabled: sw.lyricUsable && sw.app.lyricOffset !== 0
                    onClicked: sw.app.resetLyricOffset()
                }
            }
            Note { ui: sw.ui; text: "数值越大，歌词出现得越早。歌词比歌声慢，就往 + 调；点歌词面板里的任意一行可以跳过去对照。" }

            Rule {}
            GroupTitle { ui: sw.ui; text: "所有歌曲" }
            Item {
                width: parent.width
                height: Math.max(globalLabel.implicitHeight, globalValue.height)
                Text {
                    id: globalLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: "全局校准"
                    color: skinTheme.palette.inkDim
                    font.pixelSize: sw.ui.fSmall
                }
                PixelText {
                    id: globalValue
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: sw.app.lyricGlobalOffset !== undefined ? sw.ms(sw.app.lyricGlobalOffset) : "--"
                    px: sw.ui.px * 2
                    color: skinTheme.palette.mint
                }
            }
            Note { ui: sw.ui; text: "把这首歌现在的校准值设为所有歌曲的默认校准。适合整台电脑的声音输出都有固定延迟的时候。" }
            PixelButton {
                ui: sw.ui
                tone: "primary"
                size: Math.round(30 * sw.ui.fs)
                label: sw.globalWant ? "正在应用…" : "应用到所有歌曲"
                enabled: sw.lyricUsable && !sw.globalWant && typeof sw.app.useLyricOffsetGlobally === "function"
                onClicked: sw.applyGlobal()
            }
        }
    }

    // ---------------------------------------------------------------- account
    Component {
        id: accountPage
        Column {
            spacing: sw.ui.pad
            Note { ui: sw.ui; text: !sw.app.accountChecked || sw.app.accountState === "loading" ? "正在读取账号…" : "" }

            Column {
                width: parent.width
                spacing: sw.ui.pad
                visible: sw.app.accountState === "error"
                PixelText { text: "ERROR"; px: sw.ui.px * 2; color: skinTheme.palette.alert }
                GroupTitle { ui: sw.ui; text: "没有读到" + sw.app.providerName + "账号" }
                Note { ui: sw.ui; alarm: true; text: sw.app.accountError ? String(sw.app.accountError) : "" }
                Row {
                    spacing: sw.ui.px * 3
                    PixelButton {
                        ui: sw.ui
                        tone: "primary"
                        size: Math.round(32 * sw.ui.fs)
                        label: "重新读取"
                        onClicked: sw.app.refreshAccount()
                    }
                    PixelButton {
                        ui: sw.ui
                        tone: "line"
                        size: Math.round(32 * sw.ui.fs)
                        label: "重新登录"
                        onClicked: sw.app.openProviderLogin(sw.app.provider)
                    }
                }
            }

            Column {
                width: parent.width
                spacing: sw.ui.pad
                visible: sw.app.accountChecked && !sw.app.loggedIn && sw.app.accountState !== "error"
                PixelText { text: "GUEST"; px: sw.ui.px * 2; color: skinTheme.palette.mintDim }
                GroupTitle { ui: sw.ui; text: "还没有登录" + sw.app.providerName }
                Note { ui: sw.ui; text: "登录后可以搜索和播放，收藏歌曲、专辑和歌单，并管理你自己创建的歌单。账号里喜欢的歌会自动合并到我的收藏。" }
                PixelButton {
                    ui: sw.ui
                    tone: "primary"
                    size: Math.round(32 * sw.ui.fs)
                    label: "扫码登录"
                    onClicked: sw.app.openLogin()
                }
            }

            Column {
                width: parent.width
                spacing: sw.ui.pad
                visible: sw.app.loggedIn
                Row {
                    spacing: sw.ui.px * 4
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: sw.app.nickname !== "" ? sw.app.nickname : sw.app.providerName + "账号"
                        color: skinTheme.palette.ink
                        font.pixelSize: sw.ui.fTitle
                        font.weight: Font.DemiBold
                        textFormat: Text.PlainText
                    }
                    Badge {
                        anchors.verticalCenter: parent.verticalCenter
                        ui: sw.ui
                        visible: sw.app.vip
                        text: "VIP"
                        tint: skinTheme.palette.trial
                        filled: true
                    }
                }
                Note {
                    ui: sw.ui
                    text: sw.app.userId !== null && sw.app.userId !== undefined ? "账号 ID  " + String(sw.app.userId) : ""
                }
                Note { ui: sw.ui; text: "登录信息由后台播放服务加密保存。" }
                Rule {}
                GroupTitle { ui: sw.ui; text: "退出登录" }
                Note { ui: sw.ui; text: "播放会停止，播放器保存的登录信息和播放记录会被清除。我的收藏留在这台电脑上，之后这个平台的改动要等重新登录才会同步。退出前会再确认一次。" }
                PixelButton {
                    ui: sw.ui
                    tone: "line"
                    accent: skinTheme.palette.alert
                    size: Math.round(30 * sw.ui.fs)
                    label: "退出登录…"
                    enabled: sw.app.connected
                    onClicked: sw.acts.logout()
                }
            }

            // Favorites spans both accounts, whichever platform is being browsed.
            Rule {}
            Row {
                spacing: sw.ui.px * 3
                PixelText { anchors.verticalCenter: parent.verticalCenter; text: "{heart}"; px: sw.ui.px; color: skinTheme.palette.mint }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "我的收藏"
                    color: skinTheme.palette.ink
                    font.pixelSize: sw.ui.fBody + 1
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: sw.app.localFavoritesReady === true ? T.num(sw.app.localFavoritesCount) + " 首" : ""
                    color: skinTheme.palette.inkDim
                    font.pixelSize: sw.ui.fSmall
                }
            }
            Repeater {
                model: ["qq", "netease"]
                Row {
                    id: syncItem
                    required property string modelData
                    readonly property var sync: sw.acts ? sw.acts.providerSync(modelData) : ({})
                    spacing: sw.ui.px * 3
                    SourceTag {
                        anchors.verticalCenter: parent.verticalCenter
                        ui: sw.ui
                        provider: syncItem.modelData
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: sw.acts ? sw.acts.syncLabel(syncItem.modelData) : ""
                        color: sw.acts ? sw.acts.syncColor(syncItem.modelData) : skinTheme.palette.inkDim
                        font.pixelSize: sw.ui.fSmall
                        textFormat: Text.PlainText
                    }
                    PixelButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: syncItem.sync.canLogin === true
                        ui: sw.ui
                        tone: "line"
                        size: Math.round(24 * sw.ui.fs)
                        label: "登录"
                        tip: "登录" + T.sourceLabel(syncItem.modelData)
                        onClicked: sw.acts.loginProvider(syncItem.modelData)
                    }
                    PixelButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: syncItem.sync.canRetry === true
                        ui: sw.ui
                        tone: "line"
                        size: Math.round(24 * sw.ui.fs)
                        label: syncItem.sync.state === "ready" ? "刷新" : "重试"
                        tip: "重新同步" + T.sourceLabel(syncItem.modelData)
                        onClicked: sw.acts.retryProvider(syncItem.modelData)
                    }
                }
            }
            Note { ui: sw.ui; alarm: true; text: sw.acts ? sw.acts.syncProblem : "" }
            PixelButton {
                visible: !!sw.acts && sw.acts.pendingTotal > 0
                ui: sw.ui
                tone: "line"
                size: Math.round(30 * sw.ui.fs)
                label: "查看待同步 " + (sw.acts ? sw.acts.pendingTotal : 0)
                onClicked: sw.acts.openPendingSync()
            }
            Note { ui: sw.ui; text: "保存在这台电脑上，QQ 音乐和网易云音乐共用。已登录账号喜欢的歌会自动合并进来，点心形也会更新这首歌所属的平台。未登录或离线时的改动先留在这台电脑上，之后再同步。" }
            Note { ui: sw.ui; alarm: true; text: sw.app.localFavoritesError ? "收藏没有读出来：" + sw.app.localFavoritesError : "" }
        }
    }
}
