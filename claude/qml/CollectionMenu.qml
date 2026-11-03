import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

// Album / playlist / artist row actions. Saving is offered for albums and
// other people's playlists; rename and delete only for the user's own
// ordinary playlists (delete always goes through its confirmation window).
RetroMenu {
    id: cm
    required property var app
    property var target: null
    readonly property var acts: ui.acts
    readonly property string kind: target && target.kind ? String(target.kind) : ""
    readonly property bool collectible: (kind === "album" || kind === "playlist") && !(target && target.owned)
    readonly property bool editable: kind === "playlist" && !!acts && acts.canEdit(target)
    readonly property string noun: kind === "album" ? "专辑" : "歌单"
    readonly property bool sameSource: T.providerOf(target) === "" || T.providerOf(target) === app.provider
    readonly property string platform: T.sourceLabel(T.providerOf(target)) !== "" ? T.sourceLabel(T.providerOf(target)) : app.providerName
    readonly property string subState: { var s = acts ? acts.states : null; return collectible && acts ? acts.stateOf(target) : "unknown" }
    readonly property bool subBusy: { var p = acts ? acts.pending : null; return !!acts && acts.isPending(target) }
    readonly property string subGate: { var c = app.connected, l = app.loggedIn; return collectible && acts ? acts.gate(acts.subAction(target)) : "" }
    readonly property string editGate: { var c = app.connected, l = app.loggedIn; return editable && acts ? acts.gate("renamePlaylist") : "" }
    readonly property string deleteGate: { var c = app.connected, l = app.loggedIn; return editable && acts ? acts.gate("deletePlaylist") : "" }
    signal openRequested()

    function show(item, anchorItem) {
        target = item
        if (collectible && acts) acts.peek(item)
        if (anchorItem) popup(anchorItem, Math.round(anchorItem.width * 0.3), anchorItem.height)
        else popup()
    }

    RetroMenuItem { ui: cm.ui; text: "打开"; onTriggered: cm.openRequested() }
    RetroMenuItem {
        ui: cm.ui
        visible: cm.collectible
        text: !cm.sameSource ? "在" + cm.platform + "收藏（切到 " + (T.sourceSkin[T.providerOf(cm.target)] || "") + "）"
            : cm.subBusy ? "正在同步" + cm.platform + "…"
            : cm.subGate === "unsupported" ? "在" + cm.platform + "收藏" + cm.noun + "（不支持）"
            : cm.subGate === "login" ? "在" + cm.platform + "收藏" + cm.noun + "（需要登录）"
            : (cm.subState === "subscribed" ? "取消" + cm.platform + "里的收藏" : "在" + cm.platform + "收藏" + cm.noun)
        enabled: cm.sameSource && !cm.subBusy && cm.subGate !== "unsupported" && cm.subGate !== "offline"
        onTriggered: cm.acts.subscribe(cm.target)
    }
    RetroMenuSeparator { ui: cm.ui; visible: cm.editable }
    RetroMenuItem {
        ui: cm.ui
        visible: cm.editable
        text: cm.editGate === "unsupported" ? "重命名（当前不支持）" : "重命名歌单…"
        enabled: cm.editGate !== "unsupported" && cm.editGate !== "offline"
        onTriggered: cm.acts.renamePlaylist(cm.target)
    }
    RetroMenuItem {
        ui: cm.ui
        visible: cm.editable
        text: cm.deleteGate === "unsupported" ? "删除（当前不支持）" : "删除歌单…"
        enabled: cm.deleteGate !== "unsupported" && cm.deleteGate !== "offline"
        onTriggered: cm.acts.deletePlaylist(cm.target)
    }
}
