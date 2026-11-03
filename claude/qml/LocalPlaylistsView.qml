import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

// Named local playlists: saved copies of the queue, kept on this computer and
// free to mix QQ Music and NetEase songs. The first level lists them; opening one
// shows its songs in the same pane, so nothing here depends on the browsing theme.
Item {
    id: lv
    objectName: "localPlaylistsView"
    required property var app
    required property var ui
    readonly property var acts: ui.acts
    readonly property var lists: T.isList(app.localPlaylists) ? app.localPlaylists : []
    readonly property bool ready: app.localPlaylistsReady === true
    readonly property string listError: app.localPlaylistsError ? String(app.localPlaylistsError) : ""
    property string openId: ""
    property string openName: ""
    property int gen: 0
    property bool itemsBusy: false
    property string itemsError: ""
    readonly property bool opened: openId !== ""
    readonly property var openRecord: {
        for (var i = 0; i < lists.length; i++) if (String(lists[i].id) === openId) return lists[i]
        return null
    }
    readonly property string shownName: openRecord ? String(openRecord.name || "") : openName
    readonly property string phase: opened
        ? (itemsBusy ? "loading" : (itemsError !== "" ? "itemsError" : (songs.count === 0 ? "itemsEmpty" : "")))
        : (listError !== "" && lists.length === 0 ? "error"
        : (!ready ? "busy" : (lists.length === 0 ? "empty" : "")))

    function reloadList() { if (typeof app.refreshLocalPlaylists === "function") app.refreshLocalPlaylists() }
    function open(p) {
        openId = String(p.id)
        openName = String(p.name || "")
        loadOpen()
    }
    function closeList() {
        gen++
        openId = ""
        itemsBusy = false
        itemsError = ""
        songs.setItems([])
    }
    function loadOpen() {
        gen++
        var g = gen
        itemsBusy = true
        itemsError = ""
        songs.setItems([])
        app.loadLocalPlaylist(openId, function (err, result) {
            if (g !== lv.gen) return
            lv.itemsBusy = false
            if (err) { lv.itemsError = String(err); return }
            songs.setItems(result && T.isList(result.items) ? result.items : [])
        })
    }
    function dateOf(v) {
        var n = Number(v), d = null
        if (isFinite(n) && n > 0) {
            if (n > 1e17) n = n / 1e6          // nanoseconds
            else if (n < 1e11) n = n * 1000    // seconds
            d = new Date(n)
        } else if (v) {
            d = new Date(String(v))
        }
        return d && !isNaN(d.getTime()) ? Qt.formatDate(d, "yyyy-MM-dd") : ""
    }
    onVisibleChanged: if (visible && !ready && listError === "") reloadList()
    Component.onCompleted: if (visible && !ready) reloadList()

    Rectangle {
        id: head
        width: parent.width
        height: lv.opened ? openBar.height + lv.ui.pad * 2 : listBar.height + listNote.implicitHeight + lv.ui.pad * 2 + lv.ui.px * 3
        color: skinTheme.palette.raised

        // First level: what this is, and how to add to it.
        Item {
            id: listBar
            x: lv.ui.pad
            y: lv.ui.pad
            width: parent.width - 2 * lv.ui.pad
            height: saveButton.height
            visible: !lv.opened
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: lv.ui.px * 4
                PixelText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "{list}"
                    px: lv.ui.px * 2
                    color: skinTheme.palette.mint
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "本地歌单"
                    color: skinTheme.palette.ink
                    font.pixelSize: lv.ui.fBody + 3
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: lv.ready
                    text: lv.lists.length + " 个"
                    color: skinTheme.palette.inkDim
                    font.pixelSize: lv.ui.fSmall
                }
            }
            PixelButton {
                id: saveButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                ui: lv.ui
                tone: "primary"
                size: Math.round(28 * lv.ui.fs)
                glyph: "{save}"
                label: "保存当前队列"
                tip: lv.app.queue.length > 0 ? "把现在的 " + lv.app.queue.length + " 首存成新歌单" : "播放队列是空的"
                enabled: lv.app.queue.length > 0
                onClicked: lv.acts.saveQueue()
            }
        }
        Text {
            id: listNote
            x: lv.ui.pad
            anchors.top: listBar.bottom
            anchors.topMargin: lv.ui.px * 3
            width: parent.width - 2 * lv.ui.pad
            visible: !lv.opened
            text: lv.listError !== "" ? "歌单没有更新：" + lv.listError : "保存在这台电脑上，QQ 音乐和网易云的歌可以放在同一个歌单。"
            color: lv.listError !== "" ? skinTheme.palette.alert : skinTheme.palette.inkDim
            font.pixelSize: lv.ui.fSmall
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }

        // Second level: one playlist.
        Item {
            id: openBar
            x: lv.ui.pad
            y: lv.ui.pad
            width: parent.width - 2 * lv.ui.pad
            height: Math.round(28 * lv.ui.fs)
            visible: lv.opened
            PixelButton {
                id: backButton
                anchors.verticalCenter: parent.verticalCenter
                ui: lv.ui
                tone: "tab"
                size: parent.height
                glyph: "{back}"
                tip: "返回本地歌单"
                onClicked: lv.closeList()
            }
            Text {
                anchors.left: backButton.right
                anchors.leftMargin: lv.ui.px * 3
                anchors.right: openActs.left
                anchors.rightMargin: lv.ui.px * 3
                anchors.verticalCenter: parent.verticalCenter
                text: lv.shownName + (songs.count > 0 ? "  " + songs.count + " 首" : "")
                color: skinTheme.palette.ink
                font.pixelSize: lv.ui.fBody + 2
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Row {
                id: openActs
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: lv.ui.px * 2
                PixelButton {
                    ui: lv.ui
                    tone: "primary"
                    size: openBar.height
                    glyph: "{play}"
                    label: "播放全部"
                    enabled: songs.count > 0
                    onClicked: lv.app.playLocalPlaylist(lv.openId)
                }
                PixelButton {
                    ui: lv.ui
                    tone: "line"
                    size: openBar.height
                    label: "改名"
                    onClicked: lv.acts.renameLocalPlaylist({ id: lv.openId, name: lv.shownName })
                }
            }
        }
    }

    ListView {
        id: plist
        anchors.top: head.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: !lv.opened && lv.lists.length > 0
        model: lv.lists
        clip: true
        activeFocusOnTab: true
        keyNavigationEnabled: true
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: -1
        ScrollBar.vertical: PixelScrollBar { ui: lv.ui }
        Keys.onReturnPressed: if (currentIndex >= 0) lv.open(lv.lists[currentIndex])
        Keys.onEnterPressed: if (currentIndex >= 0) lv.open(lv.lists[currentIndex])
        delegate: Rectangle {
            id: prow
            required property var modelData
            required property int index
            readonly property bool focusRow: ListView.isCurrentItem && plist.activeFocus
            readonly property bool showActs: phover.hovered || focusRow
            readonly property string updated: lv.dateOf(modelData.updatedAt)
            width: plist.width
            height: lv.ui.rowH
            color: focusRow ? skinTheme.palette.select : (phover.hovered ? skinTheme.palette.hover : "transparent")
            HoverHandler { id: phover }
            MouseArea {
                anchors.fill: parent
                onClicked: lv.open(prow.modelData)
            }
            Rectangle {
                id: mark
                x: lv.ui.pad
                anchors.verticalCenter: parent.verticalCenter
                width: prow.height - lv.ui.px * 4
                height: width
                color: skinTheme.palette.raised
                PixelText {
                    anchors.centerIn: parent
                    text: "{list}"
                    px: lv.ui.px
                    color: skinTheme.palette.inkFaint
                }
            }
            Column {
                anchors.left: mark.right
                anchors.leftMargin: lv.ui.pad
                anchors.right: prow.showActs ? pacts.left : parent.right
                anchors.rightMargin: lv.ui.pad
                anchors.verticalCenter: parent.verticalCenter
                spacing: lv.ui.px
                Text {
                    width: parent.width
                    text: String(prow.modelData.name || "")
                    color: skinTheme.palette.ink
                    font.pixelSize: lv.ui.fBody
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                Text {
                    width: parent.width
                    text: T.num(prow.modelData.count) + " 首" + (prow.updated !== "" ? "，更新于 " + prow.updated : "")
                    color: skinTheme.palette.inkDim
                    font.pixelSize: lv.ui.fSmall
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }
            Row {
                id: pacts
                anchors.right: parent.right
                anchors.rightMargin: lv.ui.pad
                anchors.verticalCenter: parent.verticalCenter
                spacing: lv.ui.px * 2
                visible: prow.showActs
                PixelButton {
                    ui: lv.ui
                    tone: "line"
                    glyph: "{play}"
                    tip: "播放这个歌单"
                    enabled: T.num(prow.modelData.count) > 0
                    onClicked: lv.app.playLocalPlaylist(String(prow.modelData.id))
                }
                PixelButton {
                    ui: lv.ui
                    tone: "line"
                    label: "改名"
                    onClicked: lv.acts.renameLocalPlaylist(prow.modelData)
                }
            }
        }
    }

    ItemList {
        id: songs
        anchors.top: head.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: lv.opened && lv.phase === ""
        app: lv.app
        ui: lv.ui
        numbered: true
        showSource: true
    }

    StatePanel {
        anchors.top: head.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        ui: lv.ui
        visible: lv.phase !== ""
        alarm: lv.phase === "error" || lv.phase === "itemsError"
        glyph: ({ busy: "LOADING", loading: "LOADING", error: "ERROR", itemsError: "ERROR", empty: "{list}", itemsEmpty: "EMPTY" })[lv.phase] || ""
        heading: lv.phase === "busy" ? "正在读取本地歌单"
            : lv.phase === "loading" ? "正在读取《" + lv.shownName + "》"
            : lv.phase === "error" ? "本地歌单没有读出来"
            : lv.phase === "itemsError" ? "这个歌单没有读出来"
            : lv.phase === "empty" ? "还没有本地歌单"
            : lv.phase === "itemsEmpty" ? "这个歌单里没有歌曲" : ""
        detail: lv.phase === "error" ? lv.listError
            : lv.phase === "itemsError" ? lv.itemsError
            : lv.phase === "empty" ? "先播放几首歌，再把当前队列存成歌单。QQ 音乐和网易云的歌可以放在一起。" : ""
        action: lv.phase === "error" || lv.phase === "itemsError" ? "重新读取"
            : (lv.phase === "empty" && lv.app.queue.length > 0 ? "保存当前队列" : "")
        onActed: {
            if (lv.phase === "error") lv.reloadList()
            else if (lv.phase === "itemsError") lv.loadOpen()
            else lv.acts.saveQueue()
        }
    }
}
