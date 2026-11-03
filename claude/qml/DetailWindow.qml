import QtQuick
import "theme.js" as T

// Album / playlist / artist detail as an overlapping window. Windows cascade
// over the library; back closes this one, the close box closes all.
// Albums and other people's playlists can be saved; the user's own ordinary
// playlists can be renamed, edited and deleted (delete is confirmed separately).
RetroPane {
    id: dw
    objectName: "detailWindow"
    required property var app
    required property int index
    required property string payload
    readonly property var acts: ui.acts
    readonly property var item: {
        try { return JSON.parse(payload) } catch (e) { return ({}) }
    }
    readonly property string kind: item && item.kind ? String(item.kind) : ""
    property var info: item
    property bool dirty: false
    onVisibleChanged: if (visible && dirty && !busy) load(true)
    // The catalog item with the fresher fields from detail(); keeps the list key.
    readonly property var target: {
        var out = {}, a = item || {}, b = info || {}
        for (var k in a) out[k] = a[k]
        for (var j in b) if (b[j] !== undefined && b[j] !== null && b[j] !== "") out[j] = b[j]
        if (a.key) out.key = a.key
        if (!out.kind && kind !== "") out.kind = kind
        return out
    }
    readonly property bool own: kind === "playlist" && !!target.owned
    readonly property bool collectible: (kind === "album" || kind === "playlist") && !own
    readonly property bool editable: { var u = app.userId, l = app.loggedIn; return kind === "playlist" && !!acts && acts.canEdit(target) }
    readonly property string subState: { var s = acts ? acts.states : null; return collectible && acts ? acts.stateOf(target) : "unknown" }
    readonly property bool subBusy: { var p = acts ? acts.pending : null; return collectible && !!acts && acts.isPending(target) }
    readonly property string subGate: { var c = app.connected, l = app.loggedIn; return collectible && acts ? acts.gate(acts.subAction(target)) : "" }
    readonly property string editGate: { var c = app.connected, l = app.loggedIn; return editable && acts ? acts.gate("renamePlaylist") : "" }
    readonly property string deleteGate: { var c = app.connected, l = app.loggedIn; return editable && acts ? acts.gate("deletePlaylist") : "" }
    property var allIds: []
    property int idCursor: 0
    property int gen: 0
    property bool busy: true
    property string error: ""
    property bool moreBusy: false
    property string section: "songs"
    property int albumOffset: 0
    property bool albumMore: false
    property bool albumBusy: false
    property bool albumLoaded: false
    property string albumError: ""
    readonly property bool hasMoreSongs: idCursor < allIds.length
    readonly property int firstSong: {
        var a = songs.all
        for (var i = 0; i < a.length; i++) if (app.isSong(a[i])) return i
        return -1
    }
    readonly property string subtitle: {
        var i = info || {}
        if (kind === "album") return T.artists(i)
        if (kind === "playlist") return String(i.description || i.artist || "").replace(/\s+/g, " ")
        if (kind === "artist") return String(i.description || "").replace(/\s+/g, " ")
        return ""
    }
    readonly property string countText: {
        if (kind === "artist") return ""
        var n = T.num((info || {}).trackCount) || allIds.length || songs.count
        return n > 0 ? n + " 首" : ""
    }
    readonly property string phase: section === "songs"
        ? (busy ? "busy" : (error !== "" ? "error" : (songs.count === 0 ? "empty" : "")))
        : (albumBusy && albums.count === 0 ? "busy" : (albumError !== "" ? "error" : (albumLoaded && albums.count === 0 ? "empty" : "")))

    framed: true
    title: T.kindPixel[kind] || "DETAIL"
    readonly property string itemSource: T.providerOf(target)
    readonly property string platform: T.sourceLabel(itemSource) !== "" ? T.sourceLabel(itemSource) : app.providerName
    readonly property bool sameSource: itemSource === "" || itemSource === app.provider
    tools: [
        SourceTag {
            anchors.verticalCenter: parent.verticalCenter
            ui: dw.ui
            framed: true
            provider: dw.itemSource
        },
        PixelButton {
            anchors.verticalCenter: parent.verticalCenter
            ui: dw.ui
            tone: "bar"
            glyph: "{back}"
            tip: "返回上一层  Alt+←"
            onClicked: dw.app.closeDetailsFrom(dw.index)
        },
        PixelButton {
            anchors.verticalCenter: parent.verticalCenter
            ui: dw.ui
            tone: "solid"
            glyph: "{x}"
            tip: "关闭全部详情"
            onClicked: dw.app.clearDetails()
        }
    ]

    // soft: refresh after a library write; keeps the rows and scroll on screen.
    function load(soft) {
        dirty = false
        gen++
        moreBusy = false
        albumBusy = false
        var g = gen
        if (!soft) {
            busy = true
            error = ""
        }
        app.queryFor(item.provider, "detail", [item], function (v, err) {
            if (!dw || g !== dw.gen) return
            dw.busy = false
            if (err || !T.isList(v)) {
                if (soft) dw.app.notify("歌单没有刷新：" + (err || "没有读到详情"), true)
                else dw.error = err || "没有读到详情"
                return
            }
            if (v[0] && typeof v[0] === "object") dw.info = v[0]
            var tracks = T.isList(v[1]) ? v[1] : []
            songs.setItems(tracks, !!soft)
            dw.allIds = T.isList(v[2]) ? v[2] : []
            dw.idCursor = Math.min(tracks.length, dw.allIds.length)
            if (dw.collectible && dw.acts) dw.acts.peek(dw.target)
        })
        if (!soft && collectible && acts) acts.peek(target)
    }
    function moreSongs() {
        if (moreBusy || !hasMoreSongs) return
        var ids = allIds.slice(idCursor, idCursor + 50)
        var g = gen
        moreBusy = true
        app.queryFor(item.provider, "songs", [ids], function (v, err) {
            if (!dw || g !== dw.gen) return
            dw.moreBusy = false
            if (err) { dw.app.notify(err, true); return }
            dw.idCursor += ids.length
            songs.addItems(T.isList(v) ? v : [])
        })
    }
    function loadAlbums(fresh) {
        if (albumBusy || (!fresh && !albumMore)) return
        var off = fresh ? 0 : albumOffset
        var g = gen
        albumBusy = true
        albumError = ""
        if (fresh) albums.setItems([])
        app.queryFor(item.provider, "artistAlbums", [item.id, off], function (v, err) {
            if (!dw || g !== dw.gen) return
            dw.albumBusy = false
            dw.albumLoaded = true
            if (err) {
                if (fresh) dw.albumError = err
                else dw.app.notify(err, true)
                return
            }
            var items = v && T.isList(v.items) ? v.items : []
            if (fresh) albums.setItems(items)
            else albums.addItems(items)
            dw.albumOffset = off + (T.num(v && v.rawCount) || items.length)
            dw.albumMore = !!(v && v.more) && items.length > 0
        })
    }
    function showSection(s) {
        section = s
        if (s === "albums" && !albumLoaded) loadAlbums(true)
    }
    Component.onCompleted: load(false)

    // A write to the user's own playlist (add/remove/rename) refreshes it in place.
    Connections {
        target: dw.app
        ignoreUnknownSignals: true
        function onLibraryChanged() {
            if (!dw.own || dw.itemSource !== dw.app.provider) return
            if (dw.visible && !dw.busy) dw.load(true)
            else dw.dirty = true
        }
    }

    Item {
        id: head
        x: dw.ui.pad
        y: dw.ui.pad
        width: parent.width - 2 * dw.ui.pad
        height: Math.max(coverBox.height, infoCol.implicitHeight)
        Rectangle {
            id: coverBox
            width: Math.round(88 * dw.ui.fs)
            height: width
            color: skinTheme.palette.raised
            PixelText {
                anchors.centerIn: parent
                visible: art.status !== Image.Ready
                text: dw.title.charAt(0)
                px: dw.ui.px * 2
                color: skinTheme.palette.inkFaint
            }
            Image {
                id: art
                anchors.fill: parent
                visible: status === Image.Ready
                source: dw.info && dw.info.cover ? String(dw.info.cover) : ""
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 256
                sourceSize.height: 256
            }
        }
        Column {
            id: infoCol
            anchors.left: coverBox.right
            anchors.leftMargin: dw.ui.pad
            anchors.right: parent.right
            spacing: dw.ui.px * 2
            Text {
                width: parent.width
                text: dw.info ? String(dw.info.title || dw.info.name || "") : ""
                color: skinTheme.palette.ink
                font.pixelSize: Math.round(dw.ui.fTitle * 0.9)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Text {
                width: parent.width
                visible: text !== ""
                text: dw.subtitle
                color: skinTheme.palette.inkDim
                font.pixelSize: dw.ui.fSmall
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Row {
                spacing: dw.ui.px * 3
                visible: dw.countText !== "" || dw.own
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                    text: dw.countText
                    color: skinTheme.palette.inkDim
                    font.pixelSize: dw.ui.fSmall
                }
                Badge {
                    anchors.verticalCenter: parent.verticalCenter
                    ui: dw.ui
                    visible: dw.own
                    text: "MINE"
                }
            }
            Flow {
                width: parent.width
                spacing: dw.ui.px * 3
                PixelButton {
                    ui: dw.ui
                    tone: "primary"
                    glyph: "{play}"
                    label: "播放全部"
                    size: Math.round(30 * dw.ui.fs)
                    enabled: dw.firstSong >= 0
                    onClicked: dw.app.playCollection(songs.all, dw.allIds)
                }
                PixelButton {
                    ui: dw.ui
                    visible: dw.kind === "artist"
                    tone: "tab"
                    label: "热门歌曲"
                    size: Math.round(30 * dw.ui.fs)
                    active: dw.section === "songs"
                    onClicked: dw.showSection("songs")
                }
                PixelButton {
                    ui: dw.ui
                    visible: dw.kind === "artist"
                    tone: "tab"
                    label: "专辑"
                    size: Math.round(30 * dw.ui.fs)
                    active: dw.section === "albums"
                    onClicked: dw.showSection("albums")
                }
                // Platform save (bookmark, not the local heart): filled only when the
                // platform says saved; an unknown state is read first.
                PixelButton {
                    id: saveButton
                    ui: dw.ui
                    visible: dw.collectible
                    tone: "line"
                    size: Math.round(30 * dw.ui.fs)
                    width: Math.max(implicitWidth, Math.round(150 * dw.ui.fs))
                    readonly property bool saved: dw.subState === "subscribed"
                    active: saved && !dw.subBusy
                    glyph: saved ? "{save}" : "{saveo}"
                    label: !dw.sameSource ? "切到 " + (T.sourceSkin[dw.itemSource] || "") + " 后可收藏"
                        : dw.subBusy ? "正在同步"
                        : dw.subGate === "unsupported" ? "不支持收藏"
                        : saved ? (hovered ? "取消收藏" : "已在" + dw.platform + "收藏") : "收藏到" + dw.platform
                    tip: dw.subGate === "login" ? "登录" + dw.platform + "后才能收藏"
                        : (dw.subState === "unknown" && dw.subGate === "" ? "会先确认是否已经收藏" : "专辑和歌单收藏在" + dw.platform + "账号里，不进入我的收藏")
                    enabled: dw.sameSource && dw.subGate !== "unsupported" && dw.subGate !== "offline"
                    opacity: !enabled ? 0.35 : (dw.subBusy && !dw.acts.blink ? 0.5 : 1)
                    onClicked: if (!dw.subBusy) dw.acts.subscribe(dw.target)
                }
                PixelButton {
                    ui: dw.ui
                    visible: dw.editable
                    tone: "line"
                    size: Math.round(30 * dw.ui.fs)
                    label: dw.editGate === "unsupported" ? "不支持改名" : "重命名"
                    enabled: dw.editGate !== "unsupported" && dw.editGate !== "offline"
                    onClicked: dw.acts.renamePlaylist(dw.target)
                }
                PixelButton {
                    ui: dw.ui
                    visible: dw.editable
                    tone: "line"
                    accent: skinTheme.palette.alert
                    size: Math.round(30 * dw.ui.fs)
                    label: dw.deleteGate === "unsupported" ? "不支持删除" : "删除歌单…"
                    enabled: dw.deleteGate !== "unsupported" && dw.deleteGate !== "offline"
                    onClicked: dw.acts.deletePlaylist(dw.target)
                }
            }
            Text {
                width: parent.width
                visible: dw.own && !dw.editable
                text: "这个歌单由" + dw.app.providerName + "维护，不能在这里改名、删除或增减歌曲。"
                color: skinTheme.palette.inkFaint
                font.pixelSize: dw.ui.fSmall
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }
        }
    }

    ItemList {
        id: songs
        anchors.top: head.bottom
        anchors.topMargin: dw.ui.pad
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        app: dw.app
        ui: dw.ui
        visible: dw.section === "songs"
        numbered: true
        allTrackIds: dw.allIds
        playlist: dw.editable ? dw.target : null
        more: dw.hasMoreSongs
        busy: dw.moreBusy
        onLoadMore: dw.moreSongs()
    }
    ItemList {
        id: albums
        anchors.fill: songs
        app: dw.app
        ui: dw.ui
        visible: dw.section === "albums"
        more: dw.albumMore
        busy: dw.albumBusy && albums.count > 0
        onLoadMore: dw.loadAlbums(false)
    }
    StatePanel {
        anchors.fill: songs
        ui: dw.ui
        visible: dw.phase !== ""
        alarm: dw.phase === "error"
        glyph: ({ busy: "LOADING", error: "ERROR", empty: "EMPTY" })[dw.phase] || ""
        heading: dw.phase === "busy" ? "正在读取" : (dw.phase === "error" ? "没有读到这里的内容" : (dw.phase === "empty" ? (dw.section === "songs" ? (dw.editable ? "这个歌单还是空的" : "这里没有可播放的歌曲") : "没有找到专辑") : ""))
        detail: dw.phase === "error" ? (dw.section === "songs" ? dw.error : dw.albumError)
            : (dw.phase === "empty" && dw.editable ? "在任意歌曲的右键菜单或 … 按钮里选「加入" + dw.platform + "歌单…」，把歌放进来。" : "")
        action: dw.phase === "error" ? "重试" : ""
        action2: dw.phase === "error" && dw.app.needsLogin(dw.section === "songs" ? dw.error : dw.albumError) ? "扫码登录" : ""
        onActed: {
            if (dw.section === "songs") dw.load(false)
            else dw.loadAlbums(true)
        }
        onActed2: dw.app.openLogin()
    }
}
