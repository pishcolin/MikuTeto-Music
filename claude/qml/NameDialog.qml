import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

// Name entry for platform playlists and local playlists. Only the length rule
// is checked here; the service decides everything else and a refusal is shown
// in the window, which stays open for another try.
Popup {
    id: nd
    objectName: "nameDialog"
    required property var app
    required property var ui
    required property var acts
    property string mode: "create"        // create | rename | saveQueue | renameLocal
    property var playlist: null
    property var song: null               // create, then add this song
    property string oldName: ""
    property bool busy: false
    property string error: ""
    property int queueCount: 0
    readonly property bool local: mode === "saveQueue" || mode === "renameLocal"
    readonly property bool renaming: mode === "rename" || mode === "renameLocal"
    readonly property int limit: local ? 40 : 20
    readonly property string name: field.text.trim()
    readonly property int count: name.replace(/[\uDC00-\uDFFF]/g, "").length    // code points
    readonly property string problem: count === 0 ? "empty"
        : (count > limit ? "long" : (renaming && name === oldName ? "same" : ""))

    function openCreate(s) {
        mode = "create"
        playlist = null
        song = s || null
        oldName = ""
        _reset("")
    }
    function openRename(p) {
        mode = "rename"
        playlist = p
        song = null
        oldName = p ? String(p.title || p.name || "") : ""
        _reset(oldName)
    }
    function openSaveQueue(n) {
        mode = "saveQueue"
        playlist = null
        song = null
        oldName = ""
        queueCount = n
        _reset(Qt.formatDate(new Date(), "M月d日") + "的队列")
    }
    function openRenameLocal(p) {
        mode = "renameLocal"
        playlist = p
        song = null
        oldName = p ? String(p.name || "") : ""
        _reset(oldName)
    }
    function _reset(t) {
        busy = false
        error = ""
        field.text = t
        open()
        Qt.callLater(function () { field.forceActiveFocus(); field.selectAll() })
    }
    function submit() {
        if (busy || problem !== "") return
        var n = name, s = song, p = playlist, m = mode, total = queueCount
        busy = true
        error = ""
        var done = function (v, err) {
            nd.busy = false
            if (err) { nd.error = String(err); return }
            nd.close()
            if (m === "saveQueue") { nd.app.notify("已保存本地歌单《" + n + "》，共 " + total + " 首", false); return }
            if (m === "rename" || m === "renameLocal") { nd.app.notify("歌单已改名为《" + n + "》", false); return }
            nd.app.notify("已创建歌单《" + n + "》", false)
            if (!s) return
            if (v && typeof v === "object" && (v.dirId !== undefined || v.kind === "playlist")) nd.acts.addTo(v, s)
            else {
                nd.app.notify("已创建歌单《" + n + "》，在列表里选它来加入这首歌", false)
                nd.acts.addToPlaylist(s)
            }
        }
        if (m === "saveQueue") app.saveQueueAsPlaylist(n, function (err, result) { done(result, err) })
        else if (m === "renameLocal") app.renameLocalPlaylist(p.id, n, function (err, result) { done(result, err) })
        else if (m === "rename") app.renamePlaylist(p, n, done)
        else app.createPlaylist(n, done)
    }

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    modal: true
    focus: true
    padding: 0
    closePolicy: busy ? Popup.NoAutoClose : Popup.CloseOnEscape
    background: Item {}
    Overlay.modal: Rectangle { color: skinTheme.palette.modalVeil }

    contentItem: RetroPane {
        ui: nd.ui
        framed: true
        title: nd.renaming ? "RENAME" : (nd.mode === "saveQueue" ? "SAVE LIST" : "NEW LIST")
        implicitWidth: Math.min(Math.round(380 * nd.ui.fs), nd.parent ? nd.parent.width - 4 * nd.ui.pad : 380)
        implicitHeight: nd.ui.titleH + nd.ui.border * 3 + body.implicitHeight + 2 * nd.ui.pad
        tools: [
            PixelButton {
                anchors.verticalCenter: parent.verticalCenter
                ui: nd.ui
                tone: "solid"
                glyph: "{x}"
                tip: "关闭"
                enabled: !nd.busy
                onClicked: nd.close()
            }
        ]

        Column {
            id: body
            x: nd.ui.pad
            y: nd.ui.pad
            width: parent.width - 2 * nd.ui.pad
            spacing: nd.ui.pad

            Text {
                width: parent.width
                text: nd.renaming ? "给《" + nd.oldName + "》改名" : (nd.mode === "saveQueue" ? "把当前队列存成本地歌单" : "新建歌单")
                color: skinTheme.palette.ink
                font.pixelSize: nd.ui.fBody + 2
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }
            Text {
                width: parent.width
                visible: text !== ""
                text: nd.mode === "saveQueue" ? "保存现在的 " + nd.queueCount + " 首，之后改动队列不会影响这个歌单。"
                    : (nd.song ? "创建后会把《" + String(nd.song.title || "") + "》加进去。" : "")
                color: skinTheme.palette.inkDim
                font.pixelSize: nd.ui.fSmall
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }

            TextField {
                id: field
                objectName: "playlistNameField"
                width: parent.width
                height: Math.round(34 * nd.ui.fs)
                enabled: !nd.busy
                maximumLength: 60
                placeholderText: "歌单名称"
                placeholderTextColor: skinTheme.palette.inkFaint
                color: skinTheme.palette.ink
                selectionColor: skinTheme.palette.mint
                selectedTextColor: skinTheme.palette.pane
                font.pixelSize: nd.ui.fBody
                leftPadding: nd.ui.px * 4
                rightPadding: nd.ui.px * 4
                verticalAlignment: TextInput.AlignVCenter
                background: Rectangle {
                    color: skinTheme.palette.pane
                    border.width: field.activeFocus ? nd.ui.border : 1
                    border.color: nd.problem === "long" ? skinTheme.palette.alert
                        : (field.activeFocus ? skinTheme.palette.mint : skinTheme.palette.mintDim)
                }
                onAccepted: nd.submit()
                onTextEdited: nd.error = ""
            }

            Item {
                width: parent.width
                height: Math.max(rule.implicitHeight, counter.height)
                Text {
                    id: rule
                    anchors.left: parent.left
                    anchors.right: counter.left
                    anchors.rightMargin: nd.ui.pad
                    anchors.verticalCenter: parent.verticalCenter
                    text: nd.problem === "long" ? "名称最多 " + nd.limit + " 个字"
                        : (nd.problem === "same" ? "名称没有变化" : "1–" + nd.limit + " 个字")
                    color: nd.problem === "long" ? skinTheme.palette.alert : skinTheme.palette.inkFaint
                    font.pixelSize: nd.ui.fSmall
                    elide: Text.ElideRight
                }
                PixelText {
                    id: counter
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: nd.count + "/" + nd.limit
                    px: nd.ui.px
                    color: nd.problem === "long" ? skinTheme.palette.alert : skinTheme.palette.inkDim
                }
            }

            Text {
                width: parent.width
                visible: nd.error !== ""
                text: (nd.renaming ? "没有改名：" : (nd.mode === "saveQueue" ? "没有保存：" : "没有创建：")) + nd.error
                color: skinTheme.palette.alert
                font.pixelSize: nd.ui.fSmall
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }

            Row {
                spacing: nd.ui.px * 3
                PixelButton {
                    ui: nd.ui
                    tone: "primary"
                    size: Math.round(32 * nd.ui.fs)
                    label: nd.busy ? (nd.renaming || nd.mode === "saveQueue" ? "正在保存…" : "正在创建…")
                        : (nd.renaming ? "保存名称" : (nd.mode === "saveQueue" ? "保存歌单" : (nd.song ? "创建并加入" : "创建歌单")))
                    enabled: !nd.busy && nd.problem === ""
                    onClicked: nd.submit()
                }
                PixelButton {
                    ui: nd.ui
                    tone: "line"
                    size: Math.round(32 * nd.ui.fs)
                    label: "取消"
                    enabled: !nd.busy
                    onClicked: nd.close()
                }
            }
        }
    }
}
