import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

Item {
    id: dv
    required property var app
    required property var ui
    property string tab: "charts"
    property var category: "全部"
    property var cache: ({})
    property int gen: 0
    property bool busy: false
    property string error: ""
    property bool more: false
    property int offset: 0
    property bool primed: false
    property bool dirty: true
    property var contexts: ({})
    property var cacheOrder: []
    property var accountOwners: ({})
    readonly property bool radioHere: tab === "guess" && app.radioActive && app.radio.provider === app.provider
    readonly property var tabs: app.provider === "netease" ? [
        { id: "charts", label: "排行榜" }, { id: "playlists", label: "推荐歌单" },
        { id: "albums", label: "新碟" }, { id: "daily", label: "每日推荐" }, { id: "guess", label: "私人 FM" }
    ] : [
        { id: "charts", label: "排行榜" }, { id: "playlists", label: "推荐歌单" },
        { id: "new-songs", label: "新歌" }, { id: "albums", label: "新碟" },
        { id: "daily", label: "每日推荐" }, { id: "guess", label: "猜你喜欢" }
    ]
    readonly property bool locked: (tab === "daily" || tab === "guess") && app.accountChecked && !app.loggedIn && app.accountState !== "error"
    readonly property var chips: {
        var out = [{ id: "全部", name: "全部" }]
        var c = app.categories || []
        for (var i = 0; i < c.length; i++)
            if (c[i] && c[i].id !== undefined && c[i].id !== null && String(c[i].id) !== "全部" && c[i].name !== "全部") out.push(c[i])
        return out
    }
    readonly property string phase: radioHere ? "" : !app.connected ? "offline"
        : (locked ? "login"
        : (busy && list.count === 0 ? "busy"
        : (error !== "" ? (app.needsLogin(error) ? "login" : "error")
        : (!primed ? "busy"
        : (list.count === 0 ? "empty" : "")))))

    // Category IDs come from categories(); "全部" is the service's default.
    function requestTab() { return tab === "playlists" && String(category) !== "全部" ? "categories" : tab }
    function requestCategory() { return tab === "playlists" ? category : "全部" }
    function cacheKey() { return app.provider + "|" + requestTab() + "|" + String(requestCategory()) }
    function remember(key) {
        cache[key] = {items: list.all, offset: offset, more: more}
        var keys = cacheOrder.filter(function (k) { return k !== key }); keys.push(key)
        while (keys.length > 6) delete cache[keys.shift()]
        cacheOrder = keys
    }
    function saveContext() {
        contexts[app.provider] = {tab: tab, category: category, items: list.all, offset: offset,
            more: more, error: error, primed: primed, dirty: dirty || busy, y: list.contentY, selected: list.currentIndex}
    }
    function restoreContext() {
        gen++; busy = false
        var s = contexts[app.provider]
        tab = s ? s.tab : "charts"; category = s ? s.category : "全部"
        offset = s ? s.offset : 0; more = s ? s.more : false; error = s ? s.error : ""
        primed = s ? s.primed : false; dirty = !s || s.dirty
        list.setItems(s ? s.items : [])
        if (s) Qt.callLater(function () { list.currentIndex = s.selected; list.contentY = s.y })
        if (radioHere) syncRadio()
        else if (visible && dirty) load(false)
    }
    onVisibleChanged: if (visible && dirty && app.connected) load(false)
    function select(t, c) {
        tab = t
        if (c !== undefined) category = c
        load(false)
    }
    function load(force) {
        if (radioHere) { syncRadio(); return }
        if (!visible) { dirty = true; return }
        gen++
        var g = gen
        error = ""
        if (!app.connected) return
        dirty = false; primed = true
        if (locked) { busy = false; more = false; list.setItems([]); return }
        var key = cacheKey()
        var hit = cache[key]
        if (hit && !force) {
            busy = false
            list.setItems(hit.items)
            offset = hit.offset
            more = hit.more
            return
        }
        busy = true
        more = false
        offset = 0
        list.setItems([])
        app.query("discover", [requestTab(), 0, requestCategory()], function (v, err) {
            if (g !== dv.gen) return
            dv.busy = false
            if (err) { dv.error = err; return }
            var items = v && T.isList(v.items) ? v.items : []
            list.setItems(items)
            dv.offset = T.num(v && v.rawCount) || items.length
            dv.more = !!(v && v.more) && items.length > 0
            dv.remember(key)
        })
    }
    function syncRadio() {
        if (!radioHere) return
        gen++; busy = false; error = ""; more = false; primed = true; dirty = false
        list.setItems(app.queue.slice(Math.max(0, app.index)), true)
    }
    onRadioHereChanged: {
        if (radioHere) syncRadio()
        else if (tab === "guess" && visible) load(false)
    }
    function next() {
        if (!more || busy) return
        var g = gen, key = cacheKey(), off = offset
        busy = true
        app.query("discover", [requestTab(), off, requestCategory()], function (v, err) {
            if (g !== dv.gen) return
            dv.busy = false
            if (err) { dv.app.notify(err, true); return }
            var items = v && T.isList(v.items) ? v.items : []
            list.addItems(items)
            dv.offset = off + (T.num(v && v.rawCount) || items.length)
            dv.more = !!(v && v.more) && items.length > 0
            dv.remember(key)
        })
    }
    Connections {
        target: dv.app
        function onQueueChanged() { if (dv.radioHere) dv.syncRadio() }
        function onIndexChanged() { if (dv.radioHere) dv.syncRadio() }
        function onPlatformReset() { dv.saveContext(); dv.gen++; dv.busy = false }
        function onPlatformReady() { dv.restoreContext() }
        function onAccountReloaded() {
            if (dv.app.accountState === "error") return
            var source = dv.app.provider, owner = dv.app.loggedIn ? String(dv.app.userId) : ""
            if (dv.accountOwners[source] !== owner) {
                dv.accountOwners[source] = owner
                delete dv.cache[source + "|daily|全部"]; delete dv.cache[source + "|guess|全部"]
                if (dv.tab === "daily" || dv.tab === "guess") {
                    dv.gen++; dv.busy = false; dv.dirty = true; dv.primed = false; list.setItems([])
                }
            }
            if (dv.dirty && dv.visible) dv.load(false)
        }
    }

    Rectangle {
        id: head
        width: parent.width
        height: tabFlow.height + (chipBar.visible ? chipBar.height + dv.ui.px * 3 : 0) + dv.ui.pad * 2
        color: skinTheme.palette.raised
        Flow {
            id: tabFlow
            x: dv.ui.pad
            y: dv.ui.pad
            width: parent.width - 2 * dv.ui.pad
            spacing: dv.ui.px * 2
            Repeater {
                model: dv.tabs
                PixelButton {
                    required property var modelData
                    ui: dv.ui
                    tone: "tab"
                    size: Math.round(26 * dv.ui.fs)
                    label: modelData.label
                    active: dv.tab === modelData.id
                    onClicked: dv.select(modelData.id)
                }
            }
        }
        ListView {
            id: chipBar
            visible: dv.tab === "playlists" && dv.chips.length > 1
            anchors.top: tabFlow.bottom
            anchors.topMargin: dv.ui.px * 3
            x: dv.ui.pad
            width: parent.width - 2 * dv.ui.pad
            height: Math.round(24 * dv.ui.fs)
            orientation: ListView.Horizontal
            spacing: dv.ui.px * 2
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: dv.chips
            delegate: PixelButton {
                required property var modelData
                ui: dv.ui
                tone: "line"
                size: chipBar.height
                label: String(modelData.name)
                active: String(dv.category) === String(modelData.id)
                onClicked: dv.select("playlists", modelData.id)
            }
        }
    }

    RadioPanel {
        id: receiver
        objectName: "radioPanel"
        anchors.top: head.bottom
        anchors.topMargin: visible ? dv.ui.px * 3 : 0
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: dv.ui.pad; anchors.rightMargin: dv.ui.pad
        height: visible ? implicitHeight : 0
        visible: dv.tab === "guess"
        app: dv.app; ui: dv.ui
        onRefreshRequested: dv.load(true)
    }

    ItemList {
        id: list
        anchors.top: receiver.bottom
        anchors.topMargin: receiver.visible ? dv.ui.px * 3 : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        app: dv.app
        ui: dv.ui
        numbered: dv.tab !== "playlists" && dv.tab !== "albums"
        playHandler: dv.tab === "guess" ? function (index, item) {
            if (dv.radioHere) {
                for (var at = Math.max(0, dv.app.index); at < dv.app.queue.length; at++)
                    if (T.keyOf(dv.app.queue[at]) === T.keyOf(item)) { dv.app.playQueueAt(at); break }
            } else dv.app.startRadio(item)
        } : null
        more: dv.more
        busy: dv.busy && list.count > 0
        onLoadMore: dv.next()
    }

    StatePanel {
        anchors.fill: list
        ui: dv.ui
        visible: dv.phase !== ""
        alarm: dv.phase === "error"
        glyph: ({ offline: "OFFLINE", login: "LOGIN", busy: "LOADING", error: "ERROR", empty: "EMPTY" })[dv.phase] || ""
        heading: dv.phase === "offline" ? "播放服务还没有就绪"
            : dv.phase === "login" ? "这一栏按你的账号推荐，需要先登录"
            : dv.phase === "busy" ? "正在读取" + ((dv.tabs.filter(function (t) { return t.id === dv.tab })[0] || {}).label || "")
            : dv.phase === "error" ? "这一栏没有读出来"
            : dv.phase === "empty" ? "这一栏暂时没有内容" : ""
        detail: dv.phase === "offline" ? dv.app.serviceError
            : dv.phase === "login" ? (dv.error !== "" ? dv.error + "。" : "") + "排行榜、新歌和歌单无需登录即可浏览。"
            : dv.phase === "error" ? dv.error : ""
        action: dv.phase === "login" ? "扫码登录" : (dv.phase === "error" || dv.phase === "empty" ? "重新读取" : "")
        onActed: {
            if (dv.phase === "login") dv.app.openLogin()
            else dv.load(true)
        }
    }
}
