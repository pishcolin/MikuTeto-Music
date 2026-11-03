import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

// Song / album / artist / playlist rows. Items are kept whole in `all` and
// passed untouched to play/detail. Rows are appended, so paging keeps scroll.
// Songs keep a heart column for Favorites (either platform, in any theme); the
// play / next / queue / more buttons float over the row end on hover or focus.
// Mixed lists (showSource) tag every song with its platform; any list tags a
// song that comes from the platform not being browsed.
ListView {
    id: list
    required property var app
    required property var ui
    property var all: []
    property var allTrackIds: []
    property bool showSource: false      // mixed-source list: tag every song
    property var playHandler: null       // optional function(index, item) replacing playAt for songs
    property bool more: false
    property bool busy: false
    property bool numbered: false
    property var playlist: null          // set when these are tracks of the user's own ordinary playlist
    property var _seen: ({})
    property int menuAt: -1
    readonly property bool wide: width > Math.round(560 * ui.fs)
    readonly property var acts: ui.acts
    signal loadMore()

    // keepScroll: replace the rows after a library write without jumping to the top.
    function setItems(items, keepScroll) {
        var y = contentY
        var selected = currentIndex >= 0 ? T.keyOf(all[currentIndex]) : ""
        var merged = [], seen = {}, at = -1
        items = T.isList(items) ? items : []
        for (var i = 0; i < items.length; i++) {
            var k = T.keyOf(items[i])
            if (!k || seen[k]) continue
            seen[k] = true
            if (k === selected) at = merged.length
            merged.push(items[i])
        }
        // Delegates read all[index]; keep the row objects and keyboard focus.
        if (rows.count > merged.length) rows.remove(merged.length, rows.count - merged.length)
        var batch = []
        for (var n = rows.count; n < merged.length; n++) batch.push({n: n})
        all = merged; _seen = seen
        if (batch.length) rows.append(batch)
        currentIndex = keepScroll ? at : -1
        if (keepScroll) {
            Qt.callLater(function () {
                var top = list.originY
                var bottom = list.originY + Math.max(0, list.contentHeight - list.height)
                list.contentY = Math.max(top, Math.min(y, bottom))
            })
        } else {
            positionViewAtBeginning()
        }
    }
    function addItems(items) {
        if (!T.isList(items) || items.length === 0) return
        var merged = all.slice()
        var batch = []
        for (var i = 0; i < items.length; i++) {
            var it = items[i]
            if (!it || typeof it !== "object") continue
            var k = T.keyOf(it)
            if (_seen[k]) continue
            _seen[k] = true
            batch.push({ n: merged.length })
            merged.push(it)
        }
        all = merged
        if (batch.length) rows.append(batch)
    }
    function activate(i) {
        var it = all[i]
        if (!it) return
        if (app.isSong(it)) {
            if (typeof playHandler === "function") playHandler(i, it)
            else app.playAt(all, i, allTrackIds)
        }
        else if (acts) acts.openItem(it)
        else app.openDetail(it)
    }
    function subtitle(it) {
        if (!it) return ""
        if (app.isSong(it)) return wide || !it.album ? T.artists(it) : T.artists(it) + "  《" + it.album + "》"
        if (it.kind === "album") return T.artists(it)
        if (it.kind === "artist") return "歌手"
        var parts = []
        if (T.num(it.trackCount) > 0) parts.push(it.trackCount + " 首")
        var d = it.description ? String(it.description).replace(/\s+/g, " ") : (it.artist ? String(it.artist) : "")
        if (d !== "") parts.push(d)
        return parts.join("    ")
    }
    function popupMenu(i, anchorItem) {
        var it = all[i]
        if (!it) return
        menuAt = i
        if (app.isSong(it)) songMenu.show(it, anchorItem)
        else collectionMenu.show(it, anchorItem)
    }

    model: ListModel { id: rows }
    clip: true
    activeFocusOnTab: true
    keyNavigationEnabled: true
    boundsBehavior: Flickable.StopAtBounds
    currentIndex: -1
    ScrollBar.vertical: PixelScrollBar { ui: list.ui }

    Keys.onReturnPressed: activate(currentIndex)
    Keys.onEnterPressed: activate(currentIndex)
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            if (currentItem) { list.popupMenu(currentIndex, currentItem); event.accepted = true }
        }
    }
    onAtYEndChanged: if (atYEnd && more && !busy && count > 0 && contentHeight > height) loadMore()

    delegate: Rectangle {
        id: row
        required property int index
        readonly property var item: list.all[index] || null
        readonly property bool song: list.app.isSong(item)
        readonly property bool hasMenu: song || (!!item && (item.kind === "album" || item.kind === "playlist"))
        readonly property bool now: song && list.app.currentKey !== "" && T.keyOf(item) === list.app.currentKey
        readonly property bool focusRow: ListView.isCurrentItem && list.activeFocus
        readonly property bool showActs: hover.hovered || focusRow
        readonly property string source: T.providerOf(item)
        readonly property bool tagged: song && source !== "" && (list.showSource || source !== list.app.provider)
        width: list.width
        height: list.ui.rowH
        color: focusRow ? skinTheme.palette.select : (hover.hovered ? skinTheme.palette.hover : "transparent")

        // Taps that land on a row button must not also open or play the row.
        function hitsControl(p) {
            var boxes = [actsBox, heartSlot]
            for (var i = 0; i < boxes.length; i++) {
                var b = boxes[i]
                if (!b.visible) continue
                var q = b.mapFromItem(row, p.x, p.y)
                if (q.x >= 0 && q.y >= 0 && q.x < b.width && q.y < b.height) return true
            }
            return false
        }

        HoverHandler { id: hover }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: (eventPoint, button) => {
                if (row.hitsControl(eventPoint.position)) return
                list.currentIndex = row.index
                list.forceActiveFocus()
                if (!row.song) list.activate(row.index)
            }
            onDoubleTapped: (eventPoint, button) => {
                if (row.song && !row.hitsControl(eventPoint.position)) list.activate(row.index)
            }
        }
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: {
                list.currentIndex = row.index
                list.forceActiveFocus()
                list.popupMenu(row.index, null)
            }
        }

        Rectangle { visible: row.now; width: list.ui.px * 2; height: parent.height; color: skinTheme.palette.mint }

        Item {
            id: lead
            x: list.ui.pad
            anchors.verticalCenter: parent.verticalCenter
            width: row.song ? (list.numbered ? Math.round(28 * list.ui.fs) : 0) : row.height - list.ui.px * 4
            height: row.song ? row.height : width
            Text {
                visible: row.song && list.numbered
                anchors.verticalCenter: parent.verticalCenter
                text: row.index + 1
                color: row.now ? skinTheme.palette.mint : skinTheme.palette.inkFaint
                font.pixelSize: list.ui.fSmall
            }
            Rectangle {
                visible: !row.song
                anchors.fill: parent
                color: skinTheme.palette.raised
                PixelText {
                    anchors.centerIn: parent
                    visible: thumb.status !== Image.Ready
                    text: (T.kindPixel[row.item ? row.item.kind : ""] || "?").charAt(0)
                    px: list.ui.px
                    color: skinTheme.palette.inkFaint
                }
                Image {
                    id: thumb
                    anchors.fill: parent
                    visible: status === Image.Ready
                    source: !row.song && row.item && row.item.cover ? String(row.item.cover) : ""
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 128
                    sourceSize.height: 128
                }
            }
        }

        Row {
            id: tail
            anchors.right: parent.right
            anchors.rightMargin: list.ui.pad
            anchors.verticalCenter: parent.verticalCenter
            spacing: list.ui.px * 4
            Text {
                visible: row.song && list.wide
                width: Math.round(list.width * 0.22)
                anchors.verticalCenter: parent.verticalCenter
                text: row.item && row.item.album ? String(row.item.album) : ""
                color: skinTheme.palette.inkDim
                font.pixelSize: list.ui.fSmall
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Item {
                id: heartSlot
                visible: row.song
                anchors.verticalCenter: parent.verticalCenter
                width: list.ui.titleH - list.ui.px * 2
                height: width
                HeartButton {
                    anchors.centerIn: parent
                    ui: list.ui
                    item: row.song ? row.item : null
                    reveal: row.showActs
                }
            }
            Text {
                visible: row.song
                width: Math.round(42 * list.ui.fs)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: T.time(row.item ? row.item.duration : 0)
                color: skinTheme.palette.inkDim
                font.pixelSize: list.ui.fSmall
            }
            PixelText {
                visible: !row.song
                anchors.verticalCenter: parent.verticalCenter
                text: (list.wide ? (T.kindPixel[row.item ? row.item.kind : ""] || "") + " " : "") + ">"
                px: list.ui.px
                color: hover.hovered ? skinTheme.palette.mint : skinTheme.palette.inkFaint
            }
        }

        Column {
            anchors.left: lead.right
            anchors.leftMargin: lead.width > 0 ? list.ui.pad : 0
            anchors.right: tail.left
            anchors.rightMargin: list.ui.pad
            anchors.verticalCenter: parent.verticalCenter
            spacing: list.ui.px
            Text {
                width: parent.width
                text: row.item ? String(row.item.title || row.item.name || "") : ""
                color: row.now ? skinTheme.palette.mint : skinTheme.palette.ink
                font.pixelSize: list.ui.fBody
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Item {
                width: parent.width
                height: Math.max(subText.implicitHeight, row.tagged ? srcTag.height : 0)
                visible: subText.text !== "" || row.tagged
                SourceTag {
                    id: srcTag
                    anchors.verticalCenter: parent.verticalCenter
                    ui: list.ui
                    provider: row.tagged ? row.source : ""
                }
                Text {
                    id: subText
                    anchors.left: row.tagged ? srcTag.right : parent.left
                    anchors.leftMargin: row.tagged ? list.ui.px * 3 : 0
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: list.subtitle(row.item)
                    color: skinTheme.palette.inkDim
                    font.pixelSize: list.ui.fSmall
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }
        }

        // Hover / focus action strip. It sits over the end of the text (and the
        // album column on wide lists) so titles keep their full width otherwise.
        Rectangle {
            id: actsBox
            visible: row.showActs && row.hasMenu
            color: row.color
            height: row.height
            width: actRow.implicitWidth + list.ui.pad
            x: row.song ? tail.x + heartSlot.x - width - list.ui.px * 2 : tail.x - width - list.ui.px * 2
            Row {
                id: actRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: list.ui.px * 2
                PixelButton {
                    visible: row.song
                    ui: list.ui; tone: "line"; glyph: "{play}"; tip: "播放"
                    onClicked: list.activate(row.index)
                }
                PixelButton {
                    visible: row.song
                    ui: list.ui; tone: "line"; glyph: "{later}"; tip: "下一首播放"
                    onClicked: list.app.enqueue(row.item, true)
                }
                PixelButton {
                    visible: row.song
                    ui: list.ui; tone: "line"; glyph: "+"; tip: "加入播放队列"
                    onClicked: list.app.enqueue(row.item, false)
                }
                PixelButton {
                    id: moreBtn
                    ui: list.ui; tone: "line"; glyph: "{more}"
                    tip: row.song ? "更多：喜欢、加入歌单、专辑、歌手" : "更多操作"
                    onClicked: {
                        list.currentIndex = row.index
                        list.popupMenu(row.index, moreBtn)
                    }
                }
            }
        }
    }

    footer: Item {
        width: list.width
        height: list.more || list.busy ? list.ui.rowH : list.ui.pad
        PixelButton {
            anchors.centerIn: parent
            visible: list.more && !list.busy
            ui: list.ui
            tone: "line"
            label: "加载更多"
            size: Math.round(28 * list.ui.fs)
            onClicked: list.loadMore()
        }
        PixelText {
            anchors.centerIn: parent
            visible: list.busy
            text: "LOADING"
            px: list.ui.px
            color: skinTheme.palette.inkDim
        }
    }

    SongMenu {
        id: songMenu
        app: list.app
        ui: list.ui
        context: "list"
        playlist: list.playlist
        onPlayRequested: list.activate(list.menuAt)
    }
    CollectionMenu {
        id: collectionMenu
        app: list.app
        ui: list.ui
        onOpenRequested: list.activate(list.menuAt)
    }
}
