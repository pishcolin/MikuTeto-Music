import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

// "Add to playlist" chooser. Lists only the user's own ordinary playlists
// (Store.ownedPlaylists); the window closes only after the service confirms.
Popup {
    id: pk
    objectName: "playlistPicker"
    required property var app
    required property var ui
    required property var acts
    property var song: null
    property string busyKey: ""
    property string error: ""
    readonly property var lists: T.isList(app.ownedPlaylists) ? app.ownedPlaylists : []
    readonly property string phase: !app.connected ? "offline"
        : (!app.loggedIn ? "login"
        : (app.ownedPlaylistsBusy && lists.length === 0 ? "busy"
        : (app.ownedPlaylistsError && lists.length === 0 ? "error"
        : (lists.length === 0 ? "empty" : ""))))

    function show(s) {
        song = s
        busyKey = ""
        error = ""
        if (typeof app.loadOwnedPlaylists === "function") app.loadOwnedPlaylists()
        open()
        Qt.callLater(function () { choices.forceActiveFocus() })
    }
    function pick(pl) {
        if (busyKey !== "" || !song || !pl) return
        busyKey = T.keyOf(pl)
        error = ""
        acts.addTo(pl, song, function (v, err) {
            pk.busyKey = ""
            if (err) pk.error = String(err)
            else pk.close()
        })
    }
    Connections {
        target: pk.app
        ignoreUnknownSignals: true
        function onLibraryChanged() { if (pk.opened && pk.busyKey === "" && typeof pk.app.loadOwnedPlaylists === "function") pk.app.loadOwnedPlaylists() }
    }

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    modal: true
    focus: true
    padding: 0
    closePolicy: busyKey !== "" ? Popup.NoAutoClose : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)
    background: Item {}
    Overlay.modal: Rectangle { color: skinTheme.palette.modalVeil }

    contentItem: RetroPane {
        ui: pk.ui
        framed: true
        title: "ADD TO"
        implicitWidth: Math.min(Math.round(400 * pk.ui.fs), pk.parent ? pk.parent.width - 4 * pk.ui.pad : 400)
        implicitHeight: pk.ui.titleH + pk.ui.border * 3 + body.implicitHeight + 2 * pk.ui.pad
        tools: [
            PixelButton {
                anchors.verticalCenter: parent.verticalCenter
                ui: pk.ui
                tone: "solid"
                glyph: "{x}"
                tip: "关闭"
                enabled: pk.busyKey === ""
                onClicked: pk.close()
            }
        ]

        Column {
            id: body
            x: pk.ui.pad
            y: pk.ui.pad
            width: parent.width - 2 * pk.ui.pad
            spacing: pk.ui.pad

            Column {
                width: parent.width
                spacing: pk.ui.px
                Text {
                    width: parent.width
                    text: pk.song ? "把《" + String(pk.song.title || "") + "》加入" + pk.app.providerName + "歌单" : "加入" + pk.app.providerName + "歌单"
                    color: skinTheme.palette.ink
                    font.pixelSize: pk.ui.fBody + 1
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: T.artists(pk.song)
                    color: skinTheme.palette.inkDim
                    font.pixelSize: pk.ui.fSmall
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }

            PixelButton {
                ui: pk.ui
                tone: "line"
                glyph: "+"
                label: "新建歌单并加入"
                size: Math.round(28 * pk.ui.fs)
                enabled: pk.busyKey === "" && pk.acts.gate("createPlaylist") !== "unsupported"
                onClicked: {
                    var s = pk.song
                    pk.close()
                    pk.acts.createPlaylist(s)
                }
            }

            Rectangle {
                width: parent.width
                height: Math.round(236 * pk.ui.fs)
                color: skinTheme.palette.pane
                border.width: 1
                border.color: skinTheme.palette.mintDim

                ListView {
                    id: choices
                    anchors.fill: parent
                    anchors.margins: 1
                    visible: pk.phase === ""
                    model: pk.lists
                    clip: true
                    activeFocusOnTab: true
                    keyNavigationEnabled: true
                    boundsBehavior: Flickable.StopAtBounds
                    currentIndex: -1
                    ScrollBar.vertical: PixelScrollBar { ui: pk.ui }
                    Keys.onReturnPressed: if (currentIndex >= 0) pk.pick(pk.lists[currentIndex])
                    Keys.onEnterPressed: if (currentIndex >= 0) pk.pick(pk.lists[currentIndex])
                    delegate: Rectangle {
                        id: prow
                        required property int index
                        required property var modelData
                        readonly property bool adding: pk.busyKey !== "" && pk.busyKey === T.keyOf(modelData)
                        readonly property bool focusRow: ListView.isCurrentItem && choices.activeFocus
                        width: choices.width
                        height: Math.round(pk.ui.rowH * 0.9)
                        color: prow.adding || focusRow ? skinTheme.palette.select
                            : (phov.hovered && pk.busyKey === "" ? skinTheme.palette.hover : "transparent")
                        opacity: pk.busyKey !== "" && !prow.adding ? 0.45 : 1
                        HoverHandler { id: phov; cursorShape: pk.busyKey === "" ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler {
                            onTapped: {
                                choices.currentIndex = prow.index
                                pk.pick(prow.modelData)
                            }
                        }
                        Rectangle {
                            id: pthumb
                            x: pk.ui.pad
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.height - pk.ui.px * 4
                            height: width
                            color: skinTheme.palette.raised
                            PixelText {
                                anchors.centerIn: parent
                                visible: pimg.status !== Image.Ready
                                text: "P"
                                px: pk.ui.px
                                color: skinTheme.palette.inkFaint
                            }
                            Image {
                                id: pimg
                                anchors.fill: parent
                                visible: status === Image.Ready
                                source: prow.modelData && prow.modelData.cover ? String(prow.modelData.cover) : ""
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 96
                                sourceSize.height: 96
                            }
                        }
                        PixelText {
                            id: pstate
                            anchors.right: parent.right
                            anchors.rightMargin: pk.ui.pad
                            anchors.verticalCenter: parent.verticalCenter
                            text: prow.adding ? "ADDING" : "+"
                            px: pk.ui.px
                            visible: prow.adding || phov.hovered || prow.focusRow
                            color: prow.adding ? (pk.acts.blink ? skinTheme.palette.mint : skinTheme.palette.inkFaint) : skinTheme.palette.mint
                        }
                        Column {
                            anchors.left: pthumb.right
                            anchors.leftMargin: pk.ui.pad
                            anchors.right: pstate.left
                            anchors.rightMargin: pk.ui.pad
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: pk.ui.px
                            Text {
                                width: parent.width
                                text: prow.modelData ? String(prow.modelData.title || prow.modelData.name || "") : ""
                                color: skinTheme.palette.ink
                                font.pixelSize: pk.ui.fBody
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                            }
                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: prow.modelData && prow.modelData.trackCount !== undefined && prow.modelData.trackCount !== null ? T.num(prow.modelData.trackCount) + " 首" : ""
                                color: skinTheme.palette.inkDim
                                font.pixelSize: pk.ui.fSmall
                            }
                        }
                    }
                }

                StatePanel {
                    anchors.fill: parent
                    ui: pk.ui
                    visible: pk.phase !== ""
                    alarm: pk.phase === "error"
                    glyph: ({ offline: "OFFLINE", login: "LOGIN", busy: "LOADING", error: "ERROR", empty: "EMPTY" })[pk.phase] || ""
                    heading: pk.phase === "offline" ? "播放服务还没有就绪"
                        : pk.phase === "login" ? "登录后才能把歌曲加入歌单"
                        : pk.phase === "busy" ? "正在读取你创建的歌单"
                        : pk.phase === "error" ? "歌单列表没有读出来"
                        : pk.phase === "empty" ? "还没有你自己创建的歌单" : ""
                    detail: pk.phase === "error" ? String(pk.app.ownedPlaylistsError)
                        : pk.phase === "empty" ? "先用上面的按钮新建一个。" : ""
                    action: pk.phase === "error" ? "重新读取" : (pk.phase === "login" ? "扫码登录" : "")
                    onActed: {
                        if (pk.phase === "login") { pk.close(); pk.app.openLogin() }
                        else if (typeof pk.app.loadOwnedPlaylists === "function") pk.app.loadOwnedPlaylists()
                    }
                }
            }

            Text {
                width: parent.width
                visible: pk.error !== ""
                text: "没有加入：" + pk.error
                color: skinTheme.palette.alert
                font.pixelSize: pk.ui.fSmall
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }

            Text {
                width: parent.width
                text: "这里只列出你在" + pk.app.providerName + "创建的普通歌单。想收藏这首歌，点歌曲旁的心形。"
                color: skinTheme.palette.inkFaint
                font.pixelSize: pk.ui.fSmall
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }
        }
    }
}
