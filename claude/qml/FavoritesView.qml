import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

// Favorites: one list for both platforms, kept on this computer. Liked songs of
// both signed-in accounts merge in automatically and a heart click also updates
// the song's own platform. QQ and NetEase songs sit side by side, each tagged with
// its source colour. It works signed out too: those changes stay here, marked as
// waiting. The header states each account's sync; browsing skin changes nothing.
Item {
    id: fv
    required property var app
    required property var ui
    readonly property var acts: ui.acts
    property string filter: ""
    property int gen: 0
    property bool busy: false
    property string error: ""
    property bool more: false
    property int offset: 0
    property int total: 0
    property bool loaded: false
    property bool dirty: false
    // Songs un-hearted from this view stay in place (outline heart) until the tab
    // is left, so a slip of the mouse can be undone with one more click.
    property var held: ({})
    readonly property bool supported: typeof app.queryLocalFavorites === "function"
    readonly property bool ready: app.localFavoritesReady === true
    readonly property string storeError: app.localFavoritesError ? String(app.localFavoritesError) : ""
    readonly property int count: T.num(app.localFavoritesCount)
    readonly property bool syncing: app.favoritesSyncBusy === true
    readonly property int firstSong: {
        var a = list.all
        for (var i = 0; i < a.length; i++) if (app.isSong(a[i])) return i
        return -1
    }
    readonly property string phase: !supported ? "unsupported"
        : (!ready ? (storeError !== "" ? "broken" : "busy")
        : (busy && list.count === 0 ? "busy"
        : (error !== "" ? "error"
        : (loaded && list.count === 0 ? (filter !== "" ? "nomatch" : (syncing ? "syncing" : "empty")) : ""))))
    signal browseRequested()

    // ---------------------------------------------------------------- loading
    function load() {
        if (!supported || !ready) return
        held = ({})
        gen++
        var g = gen
        busy = true
        error = ""
        more = false
        offset = 0
        list.setItems([])
        app.queryLocalFavorites(filter, 0, function (v, err) { if (g === fv.gen) fv._accept(v, err, true, 0) })
    }
    function next() {
        if (!more || busy) return
        var g = gen, off = offset
        busy = true
        app.queryLocalFavorites(filter, off, function (v, err) { if (g === fv.gen) fv._accept(v, err, false, off) })
    }
    function _accept(v, err, fresh, off) {
        busy = false
        loaded = true
        if (err) {
            if (fresh) error = String(err)
            else app.notify("收藏没有读出来：" + err, true)
            return
        }
        var items = v && T.isList(v.items) ? v.items : []
        if (fresh) list.setItems(items)
        else list.addItems(items)
        total = T.num(v && v.total) || list.count
        more = !!(v && v.more) && items.length > 0
        offset = off + (T.num(v && v.rawCount) || items.length)
    }
    // After a change: re-read as many rows as were on screen, then swap them in
    // place so the scroll position holds (local reads, no network).
    function refresh() {
        if (!supported || !ready) return
        if (!loaded || error !== "") { load(); return }
        gen++
        var g = gen, want = Math.max(list.count, 1), acc = []
        busy = true
        var step = function (off) {
            fv.app.queryLocalFavorites(fv.filter, off, function (v, err) {
                if (g !== fv.gen) return
                if (err) { fv.busy = false; fv.app.notify("收藏没有刷新：" + err, true); return }
                var items = v && T.isList(v.items) ? v.items : []
                acc = acc.concat(items)
                var nextOff = off + (T.num(v && v.rawCount) || items.length)
                var hasMore = !!(v && v.more) && items.length > 0
                if (hasMore && acc.length < want) { step(nextOff); return }
                fv.busy = false
                list.setItems(fv._withHeld(acc), true)
                fv.total = T.num(v && v.total) || acc.length
                fv.more = hasMore
                fv.offset = nextOff
            })
        }
        step(0)
    }
    function _withHeld(items) {
        var keys = {}, out = items.slice(), add = []
        for (var i = 0; i < items.length; i++) keys[T.keyOf(items[i])] = true
        for (var k in held) if (!keys[k]) add.push(held[k])
        add.sort(function (a, b) { return a.index - b.index })
        for (var j = 0; j < add.length; j++) out.splice(Math.min(add[j].index, out.length), 0, add[j].item)
        return out
    }
    Connections {
        target: fv.acts
        function onConfirmed(key, what) {
            if (!fv.visible) return
            var h = Object.assign({}, fv.held)
            if (what === "unfav") {
                for (var i = 0; i < list.all.length; i++)
                    if (T.keyOf(list.all[i]) === key) { h[key] = { item: list.all[i], index: i }; break }
            } else if (what === "fav") {
                delete h[key]
            }
            fv.held = h
        }
    }
    function changed() {
        if (visible) refreshTimer.restart()
        else dirty = true
    }
    Timer { id: refreshTimer; interval: 60; onTriggered: fv.refresh() }
    Timer { id: filterTimer; interval: 220; onTriggered: { fv.filter = field.text.trim(); fv.load() } }
    onVisibleChanged: {
        if (!visible) {
            if (Object.keys(held).length > 0) { held = ({}); dirty = true }
            return
        }
        if (!loaded) load()
        else if (dirty) { dirty = false; refresh() }
    }
    Connections {
        target: fv.app
        ignoreUnknownSignals: true
        function onLocalFavoritesRevisionChanged() { fv.changed() }
        function onLocalFavoritesReadyChanged() { if (fv.ready) fv.changed() }
    }
    Component.onCompleted: if (visible) load()

    // Double-click starts the whole Favorites queue at that song when the list
    // is unfiltered; a filtered view plays just what it shows.
    function playFrom(i, item) { app.playLocalFavoritesFrom(item, filter) }
    function playAll() { app.playLocalFavorites(filter) }

    // ---------------------------------------------------------------- header
    Rectangle {
        id: head
        width: parent.width
        height: titleRow.height + legend.height + field.height + fv.ui.pad * 2 + fv.ui.px * 6
        color: skinTheme.palette.raised

        Item {
            id: titleRow
            x: fv.ui.pad
            y: fv.ui.pad
            width: parent.width - 2 * fv.ui.pad
            height: Math.max(nameRow.height, playButton.height)
            Row {
                id: nameRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: fv.ui.px * 4
                PixelText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "{heart}"
                    px: fv.ui.px * 2
                    color: skinTheme.palette.mint
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "我的收藏"
                    color: skinTheme.palette.ink
                    font.pixelSize: fv.ui.fBody + 3
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: fv.ready
                    text: fv.filter !== "" ? (fv.loaded && !fv.busy ? "找到 " + fv.total + " 首" : "") : fv.count + " 首"
                    color: skinTheme.palette.inkDim
                    font.pixelSize: fv.ui.fSmall
                }
            }
            PixelButton {
                id: playButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                ui: fv.ui
                tone: "primary"
                size: Math.round(28 * fv.ui.fs)
                glyph: "{play}"
                label: fv.filter !== "" ? "播放这些" : "播放全部"
                tip: fv.filter !== "" ? "播放查找结果" : "按收藏顺序播放全部，QQ 音乐和网易云混排"
                enabled: fv.ready && (fv.filter !== "" ? fv.firstSong >= 0 : fv.count > 0)
                onClicked: fv.playAll()
            }
        }

        // The two tags double as the sync status of each account. Below them, what
        // this list does; a sync failure takes that line until it is resolved.
        Item {
            id: legend
            x: fv.ui.pad
            anchors.top: titleRow.bottom
            anchors.topMargin: fv.ui.px * 3
            width: parent.width - 2 * fv.ui.pad
            readonly property int statusH: Math.max(syncRow.height, pendingButton.visible ? pendingButton.height : 0)
            height: statusH + fv.ui.px * 2 + note.implicitHeight
            Flow {
                id: syncRow
                width: parent.width - (pendingButton.visible ? pendingButton.width + fv.ui.px * 3 : 0)
                spacing: fv.ui.px * 5
                Repeater {
                    model: ["qq", "netease"]
                    Row {
                        id: syncItem
                        required property string modelData
                        readonly property var sync: fv.acts ? fv.acts.providerSync(modelData) : ({})
                        spacing: fv.ui.px * 2
                        SourceTag {
                            anchors.verticalCenter: parent.verticalCenter
                            ui: fv.ui
                            provider: syncItem.modelData
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: fv.acts ? fv.acts.syncLabel(syncItem.modelData) : ""
                            color: fv.acts ? fv.acts.syncColor(syncItem.modelData) : skinTheme.palette.inkDim
                            font.pixelSize: fv.ui.fSmall
                            textFormat: Text.PlainText
                        }
                        PixelButton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: syncItem.sync.canLogin === true
                            ui: fv.ui
                            tone: "line"
                            size: Math.round(24 * fv.ui.fs)
                            label: "登录"
                            tip: "登录" + T.sourceLabel(syncItem.modelData)
                            onClicked: fv.acts.loginProvider(syncItem.modelData)
                        }
                        PixelButton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: syncItem.sync.canRetry === true
                            ui: fv.ui
                            tone: "line"
                            size: Math.round(24 * fv.ui.fs)
                            label: syncItem.sync.state === "ready" ? "刷新" : "重试"
                            tip: "重新同步" + T.sourceLabel(syncItem.modelData)
                            onClicked: fv.acts.retryProvider(syncItem.modelData)
                        }
                    }
                }
            }
            PixelButton {
                id: pendingButton
                anchors.right: parent.right
                visible: !!fv.acts && fv.acts.pendingTotal > 0
                ui: fv.ui
                tone: "line"
                size: Math.round(24 * fv.ui.fs)
                label: "待同步 " + (fv.acts ? fv.acts.pendingTotal : 0)
                tip: "查看还没有写到平台的改动"
                onClicked: fv.acts.openPendingSync()
            }
            Text {
                id: note
                y: legend.statusH + fv.ui.px * 2
                width: parent.width
                readonly property string problem: fv.acts ? fv.acts.syncProblem : ""
                text: problem !== "" ? problem : "两个账号喜欢的歌自动合并到这里。点心形也会更新歌曲所属的平台；未登录或离线时先存在这台电脑上，之后再同步。"
                color: problem !== "" ? skinTheme.palette.alert : skinTheme.palette.inkDim
                font.pixelSize: fv.ui.fSmall
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }

        TextField {
            id: field
            x: fv.ui.pad
            anchors.top: legend.bottom
            anchors.topMargin: fv.ui.px * 3
            width: parent.width - 2 * fv.ui.pad
            height: Math.round(30 * fv.ui.fs)
            enabled: fv.ready
            maximumLength: 60
            placeholderText: "在我的收藏里找歌名、歌手或专辑"
            placeholderTextColor: skinTheme.palette.inkFaint
            color: skinTheme.palette.ink
            selectionColor: skinTheme.palette.mint
            selectedTextColor: skinTheme.palette.pane
            font.pixelSize: fv.ui.fSmall + 1
            leftPadding: fv.ui.px * 12
            rightPadding: clearButton.visible ? clearButton.width + fv.ui.px * 4 : fv.ui.px * 4
            verticalAlignment: TextInput.AlignVCenter
            background: Rectangle {
                color: skinTheme.palette.pane
                border.width: field.activeFocus ? fv.ui.border : 1
                border.color: field.activeFocus ? skinTheme.palette.mint : skinTheme.palette.mintDim
                PixelText {
                    x: fv.ui.px * 3
                    anchors.verticalCenter: parent.verticalCenter
                    text: "{find}"
                    px: fv.ui.px
                    color: field.activeFocus ? skinTheme.palette.mint : skinTheme.palette.inkFaint
                }
            }
            onTextEdited: filterTimer.restart()
            onAccepted: { filterTimer.stop(); fv.filter = text.trim(); fv.load() }
            Keys.onEscapePressed: {
                if (text !== "") { text = ""; filterTimer.restart() }
                else fv.ui.release()
            }
            Keys.onDownPressed: {
                if (list.count > 0) {
                    list.currentIndex = Math.max(0, list.currentIndex)
                    list.forceActiveFocus()
                }
            }
            PixelButton {
                id: clearButton
                anchors.right: parent.right
                anchors.rightMargin: fv.ui.px
                anchors.verticalCenter: parent.verticalCenter
                visible: field.text !== ""
                ui: fv.ui
                tone: "tab"
                glyph: "{x}"
                tip: "清除查找"
                onClicked: { field.text = ""; filterTimer.stop(); fv.filter = ""; fv.load() }
            }
        }
    }

    ItemList {
        id: list
        anchors.top: head.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        app: fv.app
        ui: fv.ui
        numbered: true
        showSource: true
        playHandler: fv.playFrom
        more: fv.more
        busy: fv.busy && list.count > 0
        onLoadMore: fv.next()
    }

    StatePanel {
        anchors.fill: list
        ui: fv.ui
        visible: fv.phase !== ""
        alarm: fv.phase === "error" || fv.phase === "broken"
        glyph: ({ unsupported: "FAV", busy: "LOADING", syncing: "SYNC", broken: "ERROR", error: "ERROR", empty: "{hearto}", nomatch: "NO MATCH" })[fv.phase] || ""
        heading: fv.phase === "unsupported" ? "这个版本还没有收藏"
            : fv.phase === "busy" ? "正在读取收藏"
            : fv.phase === "syncing" ? "正在合并账号里喜欢的歌"
            : fv.phase === "broken" ? "收藏没有读出来"
            : fv.phase === "error" ? "收藏没有读出来"
            : fv.phase === "empty" ? "还没有收藏"
            : fv.phase === "nomatch" ? "我的收藏里没有“" + fv.filter + "”" : ""
        detail: fv.phase === "broken" ? fv.storeError
            : fv.phase === "error" ? fv.error
            : fv.phase === "empty" ? "点任意歌曲旁的心形加入收藏。登录 QQ 音乐或网易云后，账号里喜欢的歌也会自动合并到这里。"
            : fv.phase === "nomatch" ? "换个关键词，或清除查找看全部收藏。" : ""
        action: fv.phase === "empty" ? "去发现"
            : fv.phase === "error" ? "重新读取"
            : (fv.phase === "broken" && typeof fv.app.reloadLocalFavorites === "function") ? "重新读取" : ""
        action2: fv.phase === "nomatch" ? "清除查找" : ""
        onActed: {
            if (fv.phase === "empty") fv.browseRequested()
            else if (fv.phase === "broken") fv.app.reloadLocalFavorites()
            else fv.load()
        }
        onActed2: { field.text = ""; fv.filter = ""; fv.load() }
    }
}
