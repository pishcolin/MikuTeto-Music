import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

// Song actions shared by library rows, queue/history rows and now playing.
// context: list | queue | history | now. `playlist` is set only when the song
// is shown inside one of the user's own ordinary playlists.
// The Favorites item comes first and works for any song in either theme: it
// updates Favorites and the song's own platform. Playlist items name their
// platform; for a song from the other platform they stay visible but disabled,
// saying which skin to switch to.
RetroMenu {
    id: sm
    required property var app
    property var song: null
    property var playlist: null
    property string context: "list"
    readonly property var acts: ui.acts
    readonly property bool playable: context !== "now"
    readonly property string songSource: T.providerOf(song)
    readonly property string sourceName: T.sourceLabel(songSource) !== "" ? T.sourceLabel(songSource) : app.providerName
    readonly property bool sameSource: songSource === "" || songSource === app.provider
    readonly property string switchTo: "（切到 " + (T.sourceSkin[songSource] || "") + "）"
    readonly property var album: song && typeof app.albumItem === "function" ? app.albumItem(song) : null
    readonly property var artistList: acts ? acts.artistsOf(song) : []
    readonly property bool faved: { var r = acts ? acts.favRevision : 0; return !!acts && acts.isFavorite(song) }
    readonly property bool favBusy: { var p = acts ? acts.pending : null; return !!acts && acts.isFavPending(song) }
    readonly property var favSync: acts ? acts.syncOf(song) : ({ kind: "", error: "" })
    readonly property bool signedOut: !!acts && acts.providerSync(songSource).state === "signedOut"
    readonly property string listGate: { var c = app.connected, l = app.loggedIn; return acts ? acts.gate("playlistTracks") : "offline" }
    signal playRequested()
    signal removeFromQueueRequested()

    function show(item, anchorItem) {
        if (!app.isSong(item)) return
        song = item
        if (acts) acts.peek(item)
        if (anchorItem) popup(anchorItem, Math.round(anchorItem.width * 0.3), anchorItem.height)
        else popup()
    }

    component ArtistItem: RetroMenuItem {
        property var songMenu: null
        property int slot: 0
        readonly property var who: songMenu && slot < songMenu.artistList.length ? songMenu.artistList[slot] : null
        visible: who !== null
        text: who ? "歌手：" + String(who.title || who.name || "") : ""
        onTriggered: songMenu.acts.openItem(who)
    }

    RetroMenuItem { ui: sm.ui; visible: sm.playable; text: "播放"; onTriggered: sm.playRequested() }
    RetroMenuItem {
        ui: sm.ui
        visible: sm.context === "list" || sm.context === "history"
        text: "下一首播放"
        onTriggered: sm.app.enqueue(sm.song, true)
    }
    RetroMenuItem {
        ui: sm.ui
        visible: sm.context === "list" || sm.context === "history"
        text: "加入播放队列"
        onTriggered: sm.app.enqueue(sm.song, false)
    }
    RetroMenuItem { ui: sm.ui; visible: sm.context === "queue"; text: "从播放队列移除"; onTriggered: sm.removeFromQueueRequested() }
    RetroMenuSeparator { ui: sm.ui; visible: sm.playable }

    // Favorites: any song. Signed out, the change waits here until login.
    RetroMenuItem {
        ui: sm.ui
        text: sm.favBusy ? "正在更新收藏…"
            : (!sm.acts || !sm.acts.favReady) ? "收藏读取中…"
            : sm.signedOut ? (sm.faved ? "移出收藏（登录后同步）" : "加入收藏（登录后同步）")
            : (sm.faved ? "从收藏和" + sm.sourceName + "「我喜欢」移除" : "加入收藏和" + sm.sourceName + "「我喜欢」")
        enabled: !sm.favBusy && !!sm.acts && sm.acts.favReady
        onTriggered: sm.acts.favorite(sm.song)
    }
    RetroMenuItem {
        ui: sm.ui
        visible: sm.favSync.canRetry === true
        text: "重试同步到" + sm.sourceName
        onTriggered: sm.acts.retrySong(sm.song)
    }
    RetroMenuItem {
        ui: sm.ui
        visible: sm.signedOut && !!sm.acts && sm.acts.providerSync(sm.songSource).canLogin === true
        text: "登录" + sm.sourceName
        onTriggered: sm.acts.loginProvider(sm.songSource)
    }
    RetroMenuItem {
        ui: sm.ui
        visible: sm.favSync.kind === "account" || sm.favSync.kind === "error"
        text: "查看待同步改动…"
        onTriggered: sm.acts.openPendingSync()
    }

    // Playlist items, labelled with the platform they write to.
    RetroMenuSeparator { ui: sm.ui }
    RetroMenuItem {
        ui: sm.ui
        text: !sm.sameSource ? sm.sourceName + "歌单" + sm.switchTo
            : sm.listGate === "unsupported" ? sm.sourceName + "歌单（不支持）"
            : "加入" + sm.sourceName + "歌单…"
        enabled: sm.sameSource && sm.listGate !== "unsupported" && sm.listGate !== "offline"
        onTriggered: sm.acts.addToPlaylist(sm.song)
    }
    RetroMenuItem {
        ui: sm.ui
        visible: sm.playlist !== null && sm.playlist !== undefined
        text: sm.playlist ? "从《" + String(sm.playlist.title || "") + "》移除" : ""
        enabled: sm.sameSource && sm.listGate === ""
        onTriggered: sm.acts.removeFrom(sm.playlist, sm.song)
    }
    RetroMenuItem { ui: sm.ui; text: "在" + sm.sourceName + "网页中打开"; onTriggered: sm.app.openTrackPage(sm.song) }

    RetroMenuSeparator { ui: sm.ui; visible: sm.album !== null || sm.artistList.length > 0 }
    RetroMenuItem {
        ui: sm.ui
        visible: sm.album !== null
        text: sm.album ? "专辑：《" + String(sm.album.title || sm.album.name || sm.song.album || "") + "》" : ""
        onTriggered: sm.acts.openItem(sm.album)
    }
    ArtistItem { ui: sm.ui; songMenu: sm; slot: 0 }
    ArtistItem { ui: sm.ui; songMenu: sm; slot: 1 }
    ArtistItem { ui: sm.ui; songMenu: sm; slot: 2 }
    ArtistItem { ui: sm.ui; songMenu: sm; slot: 3 }
    ArtistItem { ui: sm.ui; songMenu: sm; slot: 4 }
    ArtistItem { ui: sm.ui; songMenu: sm; slot: 5 }
}
