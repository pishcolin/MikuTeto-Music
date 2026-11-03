import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

// Playback queue in the wallpaper NOTEPAD manner: ragged-right titles.
// Rows follow the backend queue by prefix/suffix diff so scroll is kept.
Item {
    id: qv
    required property var app
    required property var ui
    property bool showHistory: false
    property bool inlineTools: false      // compact layout: no title bar has room for the tools
    property var _keys: []
    property int menuIndex: -1
    property string _movingKey: ""
    readonly property int playingIndex: typeof app.queueIndex === "number" ? app.queueIndex : app.index
    signal historyPicked(bool history)

    function openMenu(ctx, i, item) {
        menuIndex = i
        rowMenu.context = ctx
        rowMenu.show(item, null)
    }
    // The queue may have shifted while the menu was open; follow the song.
    function _menuRow() {
        var k = T.keyOf(rowMenu.song)
        if (menuIndex >= 0 && app.queueKeys[menuIndex] === k) return menuIndex
        return app.queueKeys.indexOf(k)
    }
    SongMenu {
        id: rowMenu
        app: qv.app
        ui: qv.ui
        onPlayRequested: {
            if (rowMenu.context === "queue") { var i = qv._menuRow(); if (i >= 0) qv.app.playQueueAt(i) }
            else qv.app.playSingle(rowMenu.song)
        }
        onRemoveFromQueueRequested: { var i = qv._menuRow(); if (i >= 0) qv.app.removeAt(i) }
    }

    function _sync() {
        var next = app.queueKeys || [], prev = _keys
        var n = prev.length, m = next.length, p = 0, q = 0
        while (p < n && p < m && prev[p] === next[p]) p++
        while (q < n - p && q < m - p && prev[n - 1 - q] === next[m - 1 - q]) q++
        if (n - p - q > 0) rows.remove(p, n - p - q)
        var batch = []
        for (var i = 0; i < m - p - q; i++) batch.push({n: 0})
        if (batch.length) rows.insert(p, batch)
        _keys = next.slice()
        if (_movingKey !== "") {
            var at = next.indexOf(_movingKey)
            _movingKey = ""
            moveGuard.stop()
            if (at >= 0) {
                qlist.currentIndex = at
                qlist.positionViewAtIndex(at, ListView.Contain)
            }
        }
    }
    function locateCurrent() {
        var i = playingIndex
        if (i < 0 || i >= rows.count) { app.notify("正在播放的歌曲不在当前队列里", false); return }
        qlist.currentIndex = i
        qlist.positionViewAtIndex(i, ListView.Center)
        qlist.forceActiveFocus()
    }
    // One move at a time: the next waits for the queue that comes back, so a quick
    // second click cannot act on stale positions. Selection follows the moved song.
    function moveRow(from, to) {
        if (_movingKey !== "" || from < 0 || to < 0 || from >= rows.count || to >= rows.count) return
        _movingKey = app.queueKeys[from] || ""
        if (_movingKey === "") return
        moveGuard.restart()
        app.moveQueue(from, to)
    }
    Timer { id: moveGuard; interval: 2000; onTriggered: qv._movingKey = "" }
    ListModel { id: rows }
    Connections {
        target: qv.app
        function onQueueKeysChanged() { qv._sync() }
        function onIndexChanged() { if (qv.visible && !qv.showHistory) Qt.callLater(qv.locateCurrent) }
    }
    Component.onCompleted: _sync()
    onVisibleChanged: if (visible && !showHistory && playingIndex >= 0) Qt.callLater(locateCurrent)

    Rectangle {
        id: toolStrip
        width: parent.width
        height: visible ? qv.ui.titleH : 0
        visible: qv.inlineTools
        color: skinTheme.palette.raised
        QueueTools {
            x: qv.ui.pad
            app: qv.app
            ui: qv.ui
            view: qv
            history: qv.showHistory
            onPicked: (h) => qv.historyPicked(h)
        }
    }

    ListView {
        id: qlist
        anchors.top: toolStrip.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: moveBar.top
        visible: !qv.showHistory && rows.count > 0
        model: rows
        clip: true
        activeFocusOnTab: true
        keyNavigationEnabled: true
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: -1
        ScrollBar.vertical: PixelScrollBar { ui: qv.ui }
        Keys.onReturnPressed: qv.app.playQueueAt(currentIndex)
        Keys.onEnterPressed: qv.app.playQueueAt(currentIndex)
        Keys.onDeletePressed: if (currentIndex >= 0) qv.app.removeAt(currentIndex)
        Keys.onPressed: (event) => {
            if (!(event.modifiers & Qt.AltModifier)) return
            if (event.key === Qt.Key_Up) { qv.moveRow(currentIndex, currentIndex - 1); event.accepted = true }
            else if (event.key === Qt.Key_Down) { qv.moveRow(currentIndex, currentIndex + 1); event.accepted = true }
        }
        delegate: Rectangle {
            id: qrow
            required property int index
            readonly property var item: qv.app.queue[index] || null
            readonly property bool now: index === qv.playingIndex
            readonly property bool focusRow: ListView.isCurrentItem && qlist.activeFocus
            readonly property bool showActs: qhover.hovered || focusRow
            width: qlist.width
            height: Math.round(qv.ui.rowH * 0.8)
            color: focusRow ? skinTheme.palette.select : (qhover.hovered ? skinTheme.palette.hover : "transparent")
            HoverHandler { id: qhover }
            TapHandler {
                onTapped: {
                    qlist.currentIndex = qrow.index
                    qlist.forceActiveFocus()
                }
                onDoubleTapped: qv.app.playQueueAt(qrow.index)
            }
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: {
                    qlist.currentIndex = qrow.index
                    qlist.forceActiveFocus()
                    qv.openMenu("queue", qrow.index, qrow.item)
                }
            }
            // Left slot: the song's source tag, swapped for the remove button on
            // hover/focus. Down the queue the tags show the QQ / 163 hand-offs.
            Item {
                id: lslot
                x: qv.ui.px * 3
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(rm.implicitWidth, qtag.implicitWidth)
                height: Math.max(rm.implicitHeight, qtag.implicitHeight)
                SourceTag {
                    id: qtag
                    anchors.verticalCenter: parent.verticalCenter
                    ui: qv.ui
                    provider: T.providerOf(qrow.item)
                    tip: ""
                    opacity: qrow.showActs ? 0 : 1
                }
                PixelButton {
                    id: rm
                    anchors.verticalCenter: parent.verticalCenter
                    ui: qv.ui
                    tone: "line"
                    glyph: "{x}"
                    tip: "从播放队列移除  Delete"
                    opacity: qrow.showActs ? 1 : 0
                    enabled: qrow.showActs
                    onClicked: qv.app.removeAt(qrow.index)
                }
            }
            Item {
                id: mark
                anchors.right: parent.right
                anchors.rightMargin: qv.ui.pad
                anchors.verticalCenter: parent.verticalCenter
                width: qv.ui.px * 17
                height: qv.ui.px * 7
                PixelText {
                    anchors.right: parent.right
                    text: qrow.now ? (qv.app.playing ? "{play}" : "{pause}") : String(qrow.index + 1)
                    px: qv.ui.px
                    color: qrow.now ? skinTheme.palette.mint : skinTheme.palette.inkFaint
                }
            }
            Text {
                id: qtitle
                anchors.right: mark.left
                anchors.rightMargin: qv.ui.px * 4
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, (qrow.width - lslot.width - mark.width) * 0.62)
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: qrow.item ? String(qrow.item.title || "") : ""
                color: qrow.now ? skinTheme.palette.mint : skinTheme.palette.ink
                font.pixelSize: qv.ui.fBody
                textFormat: Text.PlainText
            }
            Text {
                anchors.right: qtitle.left
                anchors.rightMargin: qv.ui.px * 4
                anchors.left: lslot.right
                anchors.leftMargin: qv.ui.px * 3
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: T.artists(qrow.item)
                color: skinTheme.palette.inkFaint
                font.pixelSize: qv.ui.fSmall
                textFormat: Text.PlainText
            }
        }
    }

    // Fixed under the list, so repeated clicks keep moving the same song while
    // the rows shift underneath the pointer.
    Rectangle {
        id: moveBar
        readonly property int row: qlist.currentIndex
        readonly property var song: row >= 0 ? qv.app.queue[row] || null : null
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: visible ? qv.ui.titleH : 0
        visible: !qv.showHistory && rows.count > 1 && song !== null
        color: skinTheme.palette.raised
        Text {
            anchors.left: parent.left
            anchors.leftMargin: qv.ui.pad
            anchors.right: moveActs.left
            anchors.rightMargin: qv.ui.px * 3
            anchors.verticalCenter: parent.verticalCenter
            text: (moveBar.row + 1) + "  " + (moveBar.song ? String(moveBar.song.title || "") : "")
            color: skinTheme.palette.inkDim
            font.pixelSize: qv.ui.fSmall
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
        Row {
            id: moveActs
            anchors.right: parent.right
            anchors.rightMargin: qv.ui.px * 3
            anchors.verticalCenter: parent.verticalCenter
            spacing: qv.ui.px * 2
            PixelButton {
                ui: qv.ui
                tone: "line"
                glyph: "{up}"
                tip: "上移  Alt+↑"
                enabled: moveBar.row > 0 && qv._movingKey === ""
                onClicked: qv.moveRow(moveBar.row, moveBar.row - 1)
            }
            PixelButton {
                ui: qv.ui
                tone: "line"
                glyph: "{down}"
                tip: "下移  Alt+↓"
                enabled: moveBar.row < rows.count - 1 && qv._movingKey === ""
                onClicked: qv.moveRow(moveBar.row, moveBar.row + 1)
            }
        }
    }

    ListView {
        id: hlist
        anchors.top: toolStrip.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: qv.showHistory && qv.app.history.length > 0
        model: qv.app.history
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: PixelScrollBar { ui: qv.ui }
        delegate: Rectangle {
            id: hrow
            required property var modelData
            width: hlist.width
            height: Math.round(qv.ui.rowH * 0.8)
            color: hhover.hovered ? skinTheme.palette.hover : "transparent"
            HoverHandler { id: hhover }
            TapHandler { onDoubleTapped: qv.app.playSingle(hrow.modelData) }
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: qv.openMenu("history", -1, hrow.modelData)
            }
            Item {
                id: hslot
                x: qv.ui.px * 3
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(hacts.implicitWidth, htag.implicitWidth)
                height: Math.max(hacts.implicitHeight, htag.implicitHeight)
                SourceTag {
                    id: htag
                    anchors.verticalCenter: parent.verticalCenter
                    ui: qv.ui
                    provider: T.providerOf(hrow.modelData)
                    tip: ""
                    opacity: hhover.hovered ? 0 : 1
                }
                Row {
                    id: hacts
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: qv.ui.px * 2
                    opacity: hhover.hovered ? 1 : 0
                    PixelButton { ui: qv.ui; tone: "line"; glyph: "{play}"; tip: "播放"; enabled: hhover.hovered; opacity: 1; onClicked: qv.app.playSingle(hrow.modelData) }
                    PixelButton { ui: qv.ui; tone: "line"; glyph: "+"; tip: "加入播放队列"; enabled: hhover.hovered; opacity: 1; onClicked: qv.app.enqueue(hrow.modelData, false) }
                }
            }
            Text {
                id: htitle
                anchors.right: parent.right
                anchors.rightMargin: qv.ui.pad
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, (hrow.width - hslot.width) * 0.62)
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: hrow.modelData ? String(hrow.modelData.title || "") : ""
                color: skinTheme.palette.ink
                font.pixelSize: qv.ui.fBody
                textFormat: Text.PlainText
            }
            Text {
                anchors.right: htitle.left
                anchors.rightMargin: qv.ui.px * 4
                anchors.left: hslot.right
                anchors.leftMargin: qv.ui.px * 3
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: T.artists(hrow.modelData)
                color: skinTheme.palette.inkFaint
                font.pixelSize: qv.ui.fSmall
                textFormat: Text.PlainText
            }
        }
    }

    StatePanel {
        anchors.top: toolStrip.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        ui: qv.ui
        visible: qv.showHistory ? !hlist.visible : !qlist.visible
        glyph: qv.showHistory ? "HISTORY" : "EMPTY"
        heading: qv.showHistory ? "还没有播放记录" : "播放队列是空的"
        detail: qv.showHistory ? "播放过的歌曲会按后台记录出现在这里。" : "在曲库里双击歌曲播放，或点 + 把歌曲加入队列。选中歌曲后可以调整顺序，按 Delete 移除。"
    }
}
