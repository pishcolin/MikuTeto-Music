import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

Item {
    id: sv
    required property var app
    required property var ui
    property string kind: "song"
    property string term: ""
    property int gen: 0
    property int offset: 0
    property bool more: false
    property bool busy: false
    property string error: ""
    property bool searched: false
    property int total: 0
    property var contexts: ({})
    property bool resumeSearch: false
    function saveContext() {
        contexts[app.provider] = {kind: kind, term: term, field: field.text, offset: offset, more: more,
            error: error, searched: searched, total: total, items: results.all,
            y: results.contentY, selected: results.currentIndex, inFlight: busy}
    }
    function restoreContext() {
        gen++; busy = false
        var saved = contexts[app.provider]
        kind = saved ? saved.kind : "song"; term = saved ? saved.term : ""
        field.text = saved ? saved.field : ""
        offset = saved ? saved.offset : 0; more = saved ? saved.more : false
        error = saved ? saved.error : ""; searched = saved ? saved.searched : false
        total = saved ? saved.total : 0
        results.setItems(saved ? saved.items : [])
        if (saved) Qt.callLater(function () { results.currentIndex = saved.selected; results.contentY = saved.y })
        // A cancelled first page has no result to restore. Resume only on demand.
        resumeSearch = !!(saved && saved.inFlight && !results.count && !error && term)
        if (visible && resumeSearch) run(term, kind)
    }
    onVisibleChanged: if (visible && resumeSearch && app.connected) run(term, kind)
    readonly property bool loginBlocked: error !== "" && app.needsLogin(error)
    readonly property var kinds: [
        { id: "song", label: "歌曲" }, { id: "album", label: "专辑" },
        { id: "artist", label: "歌手" }, { id: "playlist", label: "歌单" }
    ]
    readonly property string phase: !app.connected ? "offline"
        : (busy && results.count === 0 ? "busy"
        : (loginBlocked ? "login"
        : (error !== "" ? "error"
        : (searched && results.count === 0 ? "empty"
        : (!searched && app.provider === "qq" && app.accountChecked && !app.loggedIn && app.accountState !== "error" ? "login"
        : (!searched ? "idle" : ""))))))

    function focusField() { field.forceActiveFocus(); field.selectAll() }
    function run(text, k) {
        var t = String(text || "").trim()
        if (t.length > 60) t = t.substring(0, 60)
        if (k) kind = k
        if (t === "" || !app.connected) return
        term = t
        resumeSearch = false
        field.text = t
        gen++
        var g = gen
        offset = 0
        more = false
        busy = true
        error = ""
        searched = true
        total = 0
        results.setItems([])
        app.query("search", [t, kind, 0], function (v, err) { if (g === sv.gen) sv._accept(v, err, true, 0) })
    }
    function next() {
        if (!more || busy || term === "") return
        var g = gen, off = offset
        busy = true
        app.query("search", [term, kind, off], function (v, err) { if (g === sv.gen) sv._accept(v, err, false, off) })
    }
    function _accept(v, err, fresh, off) {
        busy = false
        if (err) {
            if (fresh) error = err
            else app.notify(err, true)
            return
        }
        var items = v && T.isList(v.items) ? v.items : []
        if (fresh) results.setItems(items)
        else results.addItems(items)
        total = T.num(v && v.total)
        more = !!(v && v.more) && items.length > 0
        offset = off + (T.num(v && v.rawCount) || items.length)
    }
    Connections {
        target: sv.app
        function onPlatformReset() { sv.saveContext(); sv.gen++; sv.busy = false }
        function onPlatformReady() { sv.restoreContext() }
        function onAccountReloaded() { if (sv.visible && sv.app.accountState === "ready" && sv.app.loggedIn && sv.loginBlocked && sv.term !== "") sv.run(sv.term, sv.kind) }
    }

    Rectangle {
        id: head
        width: parent.width
        height: fieldRow.height + kindRow.height + sv.ui.pad * 2 + sv.ui.px * 3
        color: skinTheme.palette.raised
        Item {
            id: fieldRow
            x: sv.ui.pad
            y: sv.ui.pad
            width: parent.width - 2 * sv.ui.pad
            height: Math.round(34 * sv.ui.fs)
            TextField {
                id: field
                anchors.left: parent.left
                anchors.right: go.left
                anchors.rightMargin: sv.ui.px * 3
                height: parent.height
                enabled: sv.app.connected
                maximumLength: 60
                placeholderText: "搜索歌曲、专辑、歌手或歌单"
                placeholderTextColor: skinTheme.palette.inkFaint
                color: skinTheme.palette.ink
                selectionColor: skinTheme.palette.mint
                selectedTextColor: skinTheme.palette.pane
                font.pixelSize: sv.ui.fBody
                leftPadding: sv.ui.px * 12
                rightPadding: sv.ui.px * 4
                verticalAlignment: TextInput.AlignVCenter
                background: Rectangle {
                    color: skinTheme.palette.pane
                    border.width: field.activeFocus ? sv.ui.border : 1
                    border.color: field.activeFocus ? skinTheme.palette.mint : skinTheme.palette.mintDim
                    PixelText {
                        x: sv.ui.px * 3
                        anchors.verticalCenter: parent.verticalCenter
                        text: "{find}"
                        px: sv.ui.px
                        color: field.activeFocus ? skinTheme.palette.mint : skinTheme.palette.inkFaint
                    }
                }
                onAccepted: sv.run(text, sv.kind)
                Keys.onEscapePressed: {
                    if (text !== "") text = ""
                    else sv.ui.release()
                }
                Keys.onDownPressed: {
                    if (results.count > 0) {
                        results.currentIndex = Math.max(0, results.currentIndex)
                        results.forceActiveFocus()
                    }
                }
            }
            PixelButton {
                id: go
                anchors.right: parent.right
                height: parent.height
                ui: sv.ui
                size: parent.height
                tone: "primary"
                glyph: "{find}"
                label: "搜索"
                enabled: sv.app.connected && field.text.trim() !== ""
                onClicked: sv.run(field.text, sv.kind)
            }
        }
        Row {
            id: kindRow
            x: sv.ui.pad
            anchors.top: fieldRow.bottom
            anchors.topMargin: sv.ui.px * 3
            height: Math.round(26 * sv.ui.fs)
            spacing: sv.ui.px * 2
            Repeater {
                model: sv.kinds
                PixelButton {
                    required property var modelData
                    ui: sv.ui
                    tone: "tab"
                    size: kindRow.height
                    label: modelData.label
                    active: sv.kind === modelData.id
                    onClicked: {
                        if (sv.kind === modelData.id) return
                        if (sv.term !== "") sv.run(sv.term, modelData.id)
                        else sv.kind = modelData.id
                    }
                }
            }
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: sv.ui.pad
            anchors.verticalCenter: kindRow.verticalCenter
            visible: sv.searched && !sv.busy && sv.error === "" && sv.total > 0
            text: "共 " + sv.total + " 个结果"
            color: skinTheme.palette.inkDim
            font.pixelSize: sv.ui.fSmall
        }
    }

    ItemList {
        id: results
        anchors.top: head.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        app: sv.app
        ui: sv.ui
        numbered: sv.kind === "song"
        more: sv.more
        busy: sv.busy && results.count > 0
        onLoadMore: sv.next()
    }

    StatePanel {
        anchors.fill: results
        ui: sv.ui
        visible: sv.phase !== ""
        alarm: sv.phase === "error" || (sv.phase === "offline" && sv.app.serviceError !== "")
        glyph: ({ offline: "OFFLINE", busy: "SEARCHING", login: "LOGIN", error: "ERROR", empty: "NO MATCH", idle: "SEARCH" })[sv.phase] || ""
        heading: sv.phase === "offline" ? "播放服务还没有就绪"
            : sv.phase === "busy" ? "正在搜索“" + sv.term + "”"
            : sv.phase === "login" ? sv.app.providerName + "要求登录后才能搜索"
            : sv.phase === "error" ? "搜索没有完成"
            : sv.phase === "empty" ? "没有找到与“" + sv.term + "”相关的" + (T.kindLabel[sv.kind] || "内容")
            : sv.phase === "idle" ? "输入关键词，按 Enter 搜索" : ""
        detail: sv.phase === "offline" ? (sv.app.serviceError !== "" ? sv.app.serviceError : "正在启动后台播放组件。")
            : sv.phase === "login" ? (sv.error !== "" ? sv.error + "。" : "") + sv.app.loginHint + "，账号由后台服务加密保存。"
            : sv.phase === "error" ? sv.error
            : sv.phase === "empty" ? "换个关键词，或切换到专辑、歌手、歌单再试。"
            : sv.phase === "idle" ? "Ctrl+F 随时回到搜索框。↑↓ 选择结果，Enter 播放，右键查看更多操作。" : ""
        action: sv.phase === "login" ? "扫码登录" : (sv.phase === "error" ? "重试" : "")
        onActed: {
            if (sv.phase === "login") sv.app.openLogin()
            else sv.run(sv.term, sv.kind)
        }
    }
}
