import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

Item {
    id: mv
    objectName: "mineView"
    required property var app
    required property var ui
    property string tab: "liked"
    property int gen: 0
    property bool busy: false
    property string error: ""
    property bool more: false
    property int offset: 0
    property bool incomplete: false
    property int total: 0
    property bool loaded: false
    property bool dirty: true
    property string loadedAccount: ""
    property var contexts: ({})
    function saveContext() {
        contexts[app.provider] = {tab: tab, items: list.all, offset: offset, more: more, total: total,
            incomplete: incomplete, loaded: loaded, owner: loadedAccount, error: error,
            dirty: dirty || busy, y: list.contentY, selected: list.currentIndex}
    }
    function restoreContext() {
        gen++; busy = false
        var s = contexts[app.provider]
        tab = s ? s.tab : "liked"; loaded = s ? s.loaded : false; loadedAccount = s ? s.owner : ""
        more = s ? s.more : false; offset = s ? s.offset : 0; total = s ? s.total : 0
        incomplete = s ? s.incomplete : false; error = s ? s.error : ""; dirty = !s || s.dirty
        list.setItems(s ? s.items : [])
        if (s) Qt.callLater(function () { list.currentIndex = s.selected; list.contentY = s.y })
        if (visible && dirty && app.accountState === "ready") { if (loaded) refresh(); else load() }
    }
    onVisibleChanged: if (visible && dirty && app.connected && app.loggedIn) { if (loaded) refresh(); else load() }
    readonly property var tabs: [
        { id: "liked", label: "喜欢的歌曲" }, { id: "playlists", label: "歌单" }, { id: "albums", label: "收藏的专辑" }
    ]
    readonly property string phase: !app.connected ? "offline"
        : (!app.accountChecked ? "busy"
        : (app.accountState === "error" ? "account" : !app.loggedIn ? "login"
        : (busy && list.count === 0 ? "busy"
        : (error !== "" ? (app.needsLogin(error) ? "login" : "error")
        : (loaded && list.count === 0 ? "empty" : "")))))

    function select(t) { tab = t; load() }
    function load() {
        if (!visible) { dirty = true; return }
        gen++
        var g = gen
        busy = false
        error = ""
        more = false
        offset = 0
        incomplete = false
        total = 0
        loaded = false
        list.setItems([])
        if (!app.connected || !app.loggedIn) return
        dirty = false; loadedAccount = String(app.userId)
        busy = true
        var done = function (v, err) { if (g === mv.gen) mv._accept(v, err, true, 0) }
        if (tab === "playlists") app.query("userPlaylists", [app.userId], done)
        else app.query(tab === "liked" ? "likedSongs" : "likedAlbums", [0], done)
    }
    // After a write (like, save, playlist edit) refresh the open tab in place.
    function refresh() {
        dirty = true
        if (!visible || !app.connected || !app.loggedIn || busy || !loaded) return
        gen++
        var g = gen
        busy = true; dirty = false
        var target = Math.max(offset, 1), collected = []
        function page(off) {
            var done = function (v, err) {
                if (g !== mv.gen) return
                if (err) { mv._accept(v, err, true, 0, true); return }
                var items = v && T.isList(v.items) ? v.items : []
                collected = collected.concat(items)
                var nextOff = off + (T.num(v && v.rawCount) || items.length)
                if (mv.tab !== "playlists" && v.more && nextOff > off && nextOff < target) { page(nextOff); return }
                mv._accept(Object.assign({}, v, {items: collected, rawCount: nextOff}), "", true, 0, true)
            }
            if (mv.tab === "playlists") mv.app.query("userPlaylists", [mv.app.userId], done)
            else mv.app.query(mv.tab === "liked" ? "likedSongs" : "likedAlbums", [off], done)
        }
        page(0)
    }
    function next() {
        if (!more || busy || tab === "playlists") return
        var g = gen, off = offset
        busy = true
        app.query(tab === "liked" ? "likedSongs" : "likedAlbums", [off], function (v, err) { if (g === mv.gen) mv._accept(v, err, false, off) })
    }
    function _accept(v, err, fresh, off, keep) {
        busy = false
        loaded = true
        if (err) {
            if (fresh && !keep) error = err
            else app.notify(err, true)
            return
        }
        var items = v && T.isList(v.items) ? v.items : []
        if (tab === "liked" || tab === "albums") app.rememberSubscribed(items)
        if (fresh) list.setItems(items, !!keep)
        else list.addItems(items)
        total = T.num(v && v.total) || list.count
        incomplete = !!(v && v.incomplete)
        more = tab !== "playlists" && !!(v && v.more) && items.length > 0
        offset = off + (T.num(v && v.rawCount) || items.length)
        if (dirty && visible) Qt.callLater(refresh)
    }
    Connections {
        target: mv.app
        function onPlatformReset() { mv.saveContext(); mv.gen++; mv.busy = false }
        function onPlatformReady() { mv.restoreContext() }
        function onAccountReloaded() {
            if (mv.app.accountState === "error") return
            var owner = mv.app.loggedIn ? String(mv.app.userId) : ""
            if (mv.loadedAccount !== owner) {
                mv.gen++; mv.busy = false; mv.loaded = false; mv.loadedAccount = owner
                mv.dirty = true; list.setItems([])
            }
            if (mv.visible && mv.dirty) { if (mv.loaded) mv.refresh(); else mv.load() }
        }
    }
    Connections {
        target: mv.app
        ignoreUnknownSignals: true
        function onLibraryChanged() { mv.refresh() }
        function onProviderLibraryChanged(source) {
            if (mv.contexts[source]) mv.contexts[source].dirty = true
        }
    }

    Rectangle {
        id: head
        visible: mv.app.loggedIn
        width: parent.width
        height: visible ? who.height + tabRow.height + mv.ui.pad * 2 + mv.ui.px * 3
            + (likedNote.visible ? likedNote.height + mv.ui.px * 3 : 0) : 0
        color: skinTheme.palette.raised
        Row {
            id: who
            x: mv.ui.pad
            y: mv.ui.pad
            spacing: mv.ui.px * 4
            SourceTag {
                anchors.verticalCenter: parent.verticalCenter
                ui: mv.ui
                provider: mv.app.provider
                tip: mv.app.providerName + "账号"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: mv.app.nickname !== "" ? mv.app.nickname : mv.app.providerName + "账号"
                color: skinTheme.palette.ink
                font.pixelSize: mv.ui.fBody + 2
                font.weight: Font.DemiBold
                textFormat: Text.PlainText
            }
            Badge {
                anchors.verticalCenter: parent.verticalCenter
                ui: mv.ui
                visible: mv.app.vip
                text: "VIP"
                tint: skinTheme.palette.trial
                filled: true
            }
        }
        Row {
            id: tabRow
            x: mv.ui.pad
            anchors.top: who.bottom
            anchors.topMargin: mv.ui.px * 3
            spacing: mv.ui.px * 2
            Repeater {
                model: mv.tabs
                PixelButton {
                    required property var modelData
                    ui: mv.ui
                    tone: "tab"
                    size: Math.round(26 * mv.ui.fs)
                    label: modelData.label
                    active: mv.tab === modelData.id
                    onClicked: mv.select(modelData.id)
                }
            }
        }
        // Say how this platform list relates to Favorites, where both appear.
        Text {
            id: likedNote
            x: mv.ui.pad
            anchors.top: tabRow.bottom
            anchors.topMargin: mv.ui.px * 3
            width: parent.width - 2 * mv.ui.pad
            visible: mv.tab === "liked"
            text: "这是" + mv.app.providerName + "账号里的「我喜欢」。自动合并进度可在「我的收藏」查看。"
            color: skinTheme.palette.inkFaint
            font.pixelSize: mv.ui.fSmall
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
        PixelButton {
            id: newList
            anchors.right: parent.right
            anchors.rightMargin: mv.ui.pad
            anchors.verticalCenter: tabRow.verticalCenter
            visible: mv.tab === "playlists"
            ui: mv.ui
            tone: "line"
            size: Math.round(26 * mv.ui.fs)
            glyph: "+"
            label: mv.ui.acts && mv.ui.acts.gate("createPlaylist") === "unsupported" ? "不支持新建" : "新建歌单"
            enabled: !!mv.ui.acts && mv.ui.acts.gate("createPlaylist") !== "unsupported"
            onClicked: mv.ui.acts.createPlaylist(null)
        }
        Text {
            anchors.right: newList.visible ? newList.left : parent.right
            anchors.rightMargin: mv.ui.pad
            anchors.verticalCenter: tabRow.verticalCenter
            visible: mv.loaded && mv.error === "" && mv.total > 0
            text: "共 " + mv.total + (mv.tab === "liked" ? " 首" : " 个") + (mv.incomplete ? "，部分歌单没有读到" : "")
            color: mv.incomplete ? skinTheme.palette.trial : skinTheme.palette.inkDim
            font.pixelSize: mv.ui.fSmall
        }
    }

    ItemList {
        id: list
        anchors.top: head.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        app: mv.app
        ui: mv.ui
        numbered: mv.tab === "liked"
        more: mv.more
        busy: mv.busy && list.count > 0
        onLoadMore: mv.next()
    }

    StatePanel {
        anchors.fill: list
        ui: mv.ui
        visible: mv.phase !== ""
        alarm: mv.phase === "error" || mv.phase === "account"
        glyph: ({ offline: "OFFLINE", busy: "LOADING", login: "MINE", account: "ACCOUNT", error: "ERROR", empty: "EMPTY" })[mv.phase] || ""
        heading: mv.phase === "offline" ? "播放服务还没有就绪"
            : mv.phase === "busy" ? "正在读取你的音乐库"
            : mv.phase === "login" ? "登录后查看你的音乐库"
            : mv.phase === "account" ? "没有读到" + mv.app.providerName + "账号"
            : mv.phase === "error" ? "音乐库没有读出来"
            : mv.phase === "empty" ? (mv.tab === "liked" ? "还没有喜欢的歌曲" : (mv.tab === "playlists" ? "还没有歌单" : "还没有收藏的专辑")) : ""
        detail: mv.phase === "offline" ? mv.app.serviceError
            : mv.phase === "login" ? "喜欢的歌曲、创建和收藏的歌单、收藏的专辑会出现在这里。"
            : mv.phase === "account" ? String(mv.app.accountError || "")
            : mv.phase === "error" ? mv.error : ""
        action: mv.phase === "login" ? "扫码登录" : (mv.phase === "error" || mv.phase === "account" ? "重新读取" : "")
        action2: mv.phase === "empty" && mv.tab === "playlists" && !!mv.ui.acts && mv.ui.acts.gate("createPlaylist") === "" ? "新建歌单" : ""
        onActed: {
            if (mv.phase === "login") mv.app.openLogin()
            else if (mv.phase === "account") mv.app.refreshAccount()
            else mv.load()
        }
        onActed2: mv.ui.acts.createPlaylist(null)
    }
}
