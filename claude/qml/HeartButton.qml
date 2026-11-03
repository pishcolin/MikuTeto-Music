import QtQuick
import "theme.js" as T

// Favorites toggle for one song, from either platform. A click updates Favorites
// and the song's own platform, whichever theme is browsing. Without login or
// connection the change is kept here and the heart turns the waiting colour until
// it reaches the platform. Faint while the list loads; blinks while a change saves.
PixelButton {
    id: hb
    property var item: null
    property bool reveal: true          // list rows show the outline only on hover
    readonly property var acts: ui.acts
    readonly property string key: T.keyOf(item)
    readonly property bool ready: !!acts && acts.favReady
    readonly property bool faved: { var r = acts ? acts.favRevision : 0; return !!acts && !!item && acts.isFavorite(item) }
    readonly property bool busy: { var p = acts ? acts.pending : null; return !!acts && !!item && acts.isFavPending(item) }
    readonly property var sync: acts && item ? acts.syncOf(item) : ({ kind: "", error: "" })
    readonly property string sourceName: T.sourceLabel(T.providerOf(item)) !== "" ? T.sourceLabel(T.providerOf(item)) : "所属平台"
    readonly property bool signedOut: !!acts && !!item && acts.providerSync(T.providerOf(item)).state === "signedOut"
    readonly property string doneText: faved ? "已加入收藏" : "已移出收藏"

    tone: "tab"
    glyph: faved ? "{heart}" : "{hearto}"
    visible: !!item && (faved || busy || reveal || sync.kind !== "")
    glyphColor: busy ? (acts.blink ? skinTheme.palette.mint : skinTheme.palette.inkFaint)
        : sync.kind === "error" ? skinTheme.palette.alert
        : (sync.kind === "waiting" || sync.kind === "signedOut" || sync.kind === "account") ? skinTheme.palette.trial
        : (faved ? skinTheme.palette.mint
        : (!ready ? skinTheme.palette.inkFaint
        : (hovered ? skinTheme.palette.ink : skinTheme.palette.inkDim)))
    tip: !ready ? (acts && acts.favError !== "" ? "收藏没有读出来" : "收藏读取中")
        : busy ? "正在更新收藏…"
        : sync.kind === "error" ? doneText + "，同步到" + sourceName + "失败" + (sync.error !== "" ? "：" + sync.error : "")
        : sync.kind === "signedOut" ? doneText + "，登录" + sourceName + "后同步"
        : sync.kind === "account" ? doneText + "，切回之前的账号后才能同步"
        : sync.kind === "waiting" ? doneText + "，等待同步到" + sourceName
        : sync.kind === "syncing" ? "正在同步到" + sourceName
        : signedOut ? (faved ? "移出收藏（登录" : "加入收藏（登录") + sourceName + "后同步）"
        : faved ? "移出收藏，并从" + sourceName + "「我喜欢」移除"
        : "加入收藏，并加入" + sourceName + "「我喜欢」"
    Accessible.name: faved ? "移出收藏" : "加入收藏"
    onClicked: if (acts && item) acts.favorite(item)

    // A short pixel pop once the save is confirmed.
    SequentialAnimation {
        id: pop
        NumberAnimation { target: hb.contentItem; property: "scale"; to: 1.45; duration: 70 }
        NumberAnimation { target: hb.contentItem; property: "scale"; to: 1; duration: 150; easing.type: Easing.OutBack }
    }
    Connections {
        target: hb.acts
        function onConfirmed(key, what) {
            if (key === hb.key && what === "fav" && !hb.ui.reducedMotion) pop.restart()
        }
    }
}
