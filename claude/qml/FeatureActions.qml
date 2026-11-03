import QtQuick
import "theme.js" as T

// Shared write flows, reached from every component as ui.acts.
// Favorites (the heart) is one list for both platforms: liked songs of both
// signed-in accounts merge into it, and a heart click updates it and the song's
// own platform, whichever theme is browsing. A change that cannot reach its
// platform yet stays saved on this computer and is shown as waiting, never as done.
// Album saves and playlists only come from items that name the platform, for
// the platform currently browsed.
// The UI only shows what has been confirmed; platform write errors are left to
// Store.notify, Favorites results are reported here.
Item {
    id: fa
    objectName: "featureActions"
    required property var app
    required property var ui

    property var pending: ({})            // key -> what is in flight
    property var intents: ({})            // key -> { what, item, until }
    property bool blink: true
    property string settingsSection: "quality"
    readonly property var states: app.subscriptionStates
    readonly property int favRevision: typeof app.localFavoritesRevision === "number" ? app.localFavoritesRevision : 0
    readonly property bool favReady: app.localFavoritesReady === true
    readonly property string favError: app.localFavoritesError ? String(app.localFavoritesError) : ""
    readonly property var syncProviders: app.favoritesSyncProviders ? app.favoritesSyncProviders : ({})
    readonly property bool syncBusy: app.favoritesSyncBusy === true
    readonly property int syncPending: T.num(app.favoritesPendingCount)
    readonly property var pendingItems: T.isList(app.favoritesPendingItems) ? app.favoritesPendingItems : []
    readonly property int pendingTotal: Math.max(syncPending, pendingItems.length)
    readonly property bool canRetrySync: {
        if (syncBusy || !has("retryFavoritesSync")) return false
        return providerSync("qq").canRetry === true || providerSync("netease").canRetry === true
    }
    readonly property string syncProblem: {
        var names = ["qq", "netease"], out = []
        for (var i = 0; i < names.length; i++) {
            var s = providerSync(names[i])
            if (s.state === "error" && s.reason !== "account" && s.reason !== "login")
                out.push(T.sourceLabel(names[i]) + "同步失败" + (s.error ? "：" + s.error : ""))
        }
        return out.join("；")
    }
    readonly property bool anyPending: Object.keys(pending).length > 0
    signal confirmed(string key, string what)   // a write finished without error

    Timer {
        interval: 420
        repeat: true
        running: fa.anyPending && !fa.ui.reducedMotion
        onTriggered: fa.blink = !fa.blink
        onRunningChanged: if (!running) fa.blink = true
    }

    // ---------------------------------------------------------------- basics
    function has(name) { return typeof app[name] === "function" }
    function title(it) { return it ? String(it.title || it.name || "") : "" }
    function can(action) { return has("canMutate") && !!app.canMutate(action) }
    function canEdit(pl) { return !!pl && has("canEditPlaylist") && !!app.canEditPlaylist(pl) }
    function subAction(item) { return item && item.kind === "album" ? "subscribeAlbum" : "subscribePlaylist" }
    // Platform actions use the browsed platform's account, so they are offered
    // only for items of that platform; others say which skin to switch to.
    function samePlatform(item) { var p = T.providerOf(item); return !!item && (p === "" || p === app.provider) }
    function switchHint(item) {
        var p = T.providerOf(item)
        var noun = ({ album: "这张专辑", playlist: "这个歌单", artist: "这位歌手" })[item && item.kind] || "这首歌"
        return noun + "来自" + T.sourceLabel(p) + "，切到 " + (T.sourceSkin[p] || "") + " 后才能"
    }

    // "" when a write may start; otherwise offline | login | unsupported.
    function gate(action) {
        if (!app.connected) return "offline"
        if (!app.loggedIn) return "login"
        if (!can(action)) return "unsupported"
        return ""
    }
    // Says why a write cannot start and offers login when that is the reason.
    function blocked(action, what) {
        var r = gate(action)
        if (r === "") return false
        if (r === "login") {
            app.notify("登录" + app.providerName + "后才能" + what, true)
            app.openLogin()
        } else if (r === "offline") {
            app.notify("播放服务还没有就绪，稍后再" + what, true)
        } else {
            app.notify("当前音乐服务不支持" + what, true)
        }
        return true
    }

    // subscribed | not-subscribed | unknown, straight from the Store.
    function stateOf(item) {
        var s = fa.states
        if (!item || !has("subscriptionState")) return "unknown"
        var v = app.subscriptionState(item)
        return v === "subscribed" || v === "not-subscribed" ? v : "unknown"
    }
    function peek(item) {
        if (!item || !app.connected || !app.loggedIn || !has("loadSubscription") || !samePlatform(item)) return
        if (stateOf(item) === "unknown") app.loadSubscription(item)
    }
    function isPending(item) {
        var p = fa.pending
        var k = T.keyOf(item)
        return k !== "" && p[k] !== undefined
    }
    function _mark(key, what) {
        var p = Object.assign({}, fa.pending)
        if (what) p[key] = what
        else delete p[key]
        fa.pending = p
    }
    function _outcome(v, fallback) {
        if (v === true || v === "subscribed") return true
        if (v === false || v === "not-subscribed") return false
        if (v && typeof v === "object" && typeof v.state === "string") return v.state === "subscribed"
        if (v && typeof v.liked === "boolean") return v.liked
        if (v && typeof v.subscribed === "boolean") return v.subscribed
        return fallback
    }

    // ---------------------------------------------------------------- local Favorites
    function isFavorite(song) {
        var r = fa.favRevision
        return has("isLocalFavorite") && app.isSong(song) && !!app.isLocalFavorite(song)
    }
    function isFavPending(song) {
        var p = fa.pending
        var k = T.keyOf(song)
        return k !== "" && p["fav:" + k] !== undefined
    }
    function favorite(song) {
        if (!app.isSong(song)) return
        if (!has("toggleLocalFavorite")) { app.notify("这个版本还不能使用收藏", true); return }
        if (!fa.favReady) {
            app.notify(fa.favError !== "" ? "收藏没有读出来：" + fa.favError : "收藏还在读取，稍后再试", true)
            return
        }
        var key = T.keyOf(song)
        if (key === "" || fa.pending["fav:" + key] !== undefined) return
        var was = isFavorite(song)
        _mark("fav:" + key, was ? "unfav" : "fav")
        app.toggleLocalFavorite(song, function (v, err) {
            fa._mark("fav:" + key, "")
            if (err) { app.notify("收藏没有保存：" + err, true); return }
            var now = v && typeof v.liked === "boolean" ? v.liked : !was
            fa.confirmed(key, now ? "fav" : "unfav")
            var report = fa._favReport(song, now, v)
            app.notify(report.text, report.alarm)
        })
    }
    // Only "ready" may claim the platform was updated; anything else says what
    // is still outstanding.
    function _favReport(song, now, v) {
        var state = v && v.syncState ? String(v.syncState) : ""
        var waiting = !!(v && v.pending)
        var message = v && v.message ? String(v.message) : ""
        var p = v && v.provider ? String(v.provider) : T.providerOf(song)
        var name = T.sourceLabel(p) !== "" ? T.sourceLabel(p) : "所属平台"
        var head = now ? "已加入收藏" : "已移出收藏"
        var named = "：" + title(song)
        if (state === "error")
            return { text: head + named + "。" + (message !== "" ? message : name + "同步失败，可以稍后重试"), alarm: true }
        if (state === "signedOut")
            return { text: head + named + "。" + (message !== "" ? message : "登录" + name + "后再同步"), alarm: false }
        if (waiting || state === "pending")
            return { text: head + named + "。" + (message !== "" ? message : "等待同步到" + name), alarm: false }
        if (state === "syncing" || state === "loading")
            return { text: head + named + "。正在同步到" + name, alarm: false }
        if (state === "ready")
            return { text: (now ? "已加入收藏和" + name + "「我喜欢」" : "已从收藏和" + name + "「我喜欢」移除") + named, alarm: false }
        return { text: head + named, alarm: false }
    }

    // ---------------------------------------------------------------- Favorites sync
    function providerSync(p) {
        var s = fa.syncProviders[p]
        return s && typeof s === "object" ? s
            : ({ state: "", imported: 0, pending: 0, error: "", reason: "", canRetry: false, canLogin: false })
    }
    // Concise status of one account's sync; "" until the service reports it.
    function syncLabel(p) {
        var s = providerSync(p), n = T.num(s.pending), got = T.num(s.imported)
        if (s.state === "syncing") return "同步中"
        if (s.state === "loading") return "正在读取"
        if (s.reason === "account") return n > 0 ? n + " 首属于之前的账号" : "等待切回之前的账号"
        if (s.reason === "offline") return n > 0 ? "等待连接，" + n + " 首待同步" : "等待连接"
        if (s.state === "signedOut") return n > 0 ? "未登录，" + n + " 首待同步" : "未登录"
        if (s.state === "pending") return n > 0 ? n + " 首待同步" : "等待同步"
        if (s.state === "error") return n > 0 ? "同步失败，" + n + " 首待重试" : "同步失败"
        if (s.state === "ready") return got > 0 ? "已同步，合并 " + got + " 首" : "已同步"
        return ""
    }
    function syncColor(p) {
        var s = providerSync(p)
        if (s.reason === "account" || s.reason === "offline") return skinTheme.palette.trial
        if (s.state === "error") return skinTheme.palette.alert
        if (s.state === "pending" || (s.state === "signedOut" && T.num(s.pending) > 0)) return skinTheme.palette.trial
        return skinTheme.palette.inkDim
    }
    // One song: kind is "", syncing, waiting, signedOut, account or error.
    function syncOf(song) {
        // Reading these keeps every caller's binding current with the sync state.
        var seen = [fa.favRevision, fa.syncProviders, fa.syncBusy, fa.syncPending]
        if (!song || !app.isSong(song) || !has("favoriteSyncState")) return { kind: "", error: "", canRetry: false }
        var v = app.favoriteSyncState(song) || {}
        var state = v.state ? String(v.state) : ""
        var reason = v.reason ? String(v.reason) : ""
        var error = v.error ? String(v.error) : ""
        var waiting = !!v.pending || state === "pending"
        var kind = ""
        if (state === "syncing" || state === "loading") kind = "syncing"
        else if (reason === "account") kind = "account"
        else if (reason === "login" || (waiting && (state === "signedOut" || providerSync(T.providerOf(song)).state === "signedOut"))) kind = "signedOut"
        else if (reason === "offline") kind = "waiting"
        else if (state === "error" || error !== "") kind = "error"
        else if (waiting) kind = "waiting"
        return { kind: kind, error: error, canRetry: v.canRetry === true }
    }
    function retrySync() { if (fa.canRetrySync) app.retryFavoritesSync() }
    function retryProvider(p) { if (has("retryFavoritesFor")) app.retryFavoritesFor(p) }
    function loginProvider(p) { if (has("openProviderLogin")) app.openProviderLogin(p) }
    function retryPending(item) { if (item && has("retryFavoriteItem")) app.retryFavoriteItem(item.key) }
    function retrySong(song) { if (has("retryFavoriteItem")) app.retryFavoriteItem(T.keyOf(song)) }
    function openPendingSync() { pendingDialog.open() }

    // What a queued change is waiting for, in the user's terms.
    function pendingStatus(item) {
        var name = T.sourceLabel(item.provider), reason = String(item.reason || "")
        if (item.state === "syncing") return "正在写入" + name
        if (reason === "login") return "登录" + name + "后同步"
        if (reason === "account") return "属于之前的账号，切回后才能同步"
        if (reason === "offline") return "恢复连接后同步"
        if (item.error) return "同步失败：" + item.error
        if (reason === "network") return "网络没有连上，可以重试"
        return "等待同步到" + name
    }
    function pendingColor(item) {
        var reason = String(item.reason || "")
        if (item.state === "syncing") return skinTheme.palette.inkDim
        if (reason === "login" || reason === "account" || reason === "offline") return skinTheme.palette.trial
        return item.error || reason === "network" ? skinTheme.palette.alert : skinTheme.palette.inkDim
    }
    // Abandoning cancels a platform write that has not been sent; it does not
    // touch Favorites and cannot undo anything the platform already received.
    function abandonPending(item) {
        if (!item || item.canDiscard !== true || !has("cancelFavoriteIntent")) return
        var name = T.sourceLabel(item.provider), adding = item.desired === true
        var body = [
            "停止向" + name + "继续重试这一项，平台已经收到的写入不会被撤销。",
            adding ? "这首歌继续留在我的收藏里；如需核对平台状态，请在" + name + "中查看。"
                : "这首歌继续不在我的收藏里；下次导入不会恢复这次移除。"
        ]
        body.push("放弃后这项同步不会再自动进行。")
        confirmDialog.ask({
            title: "ABANDON",
            alarm: true,
            heading: "放弃这项待同步改动？",
            name: title(item.song),
            meta: name + (adding ? "：加入「我喜欢」" : "：移出「我喜欢」"),
            body: body,
            cancel: "保留待同步",
            confirm: "放弃这项同步",
            working: "正在放弃…",
            run: function (done) {
                app.cancelFavoriteIntent(item.key, done)
            }
        })
    }
    function abandonOldAccount() {
        if (!has("cancelFavoriteIntent")) return
        var keys = []
        for (var i = 0; i < fa.pendingItems.length; i++) {
            var it = fa.pendingItems[i]
            if (it.reason === "account" && it.canDiscard === true) keys.push(it.key)
        }
        if (keys.length === 0) return
        confirmDialog.ask({
            title: "ABANDON",
            alarm: true,
            heading: "放弃之前账号的待同步改动？",
            meta: keys.length + " 项改动",
            body: [
                "停止继续向平台重试这些操作，平台已经收到的写入不会被撤销。",
                "我的收藏保持现在的样子；平台的实际状态可登录原账号查看。",
                "放弃后这些同步不会再自动进行。"
            ],
            cancel: "保留待同步",
            confirm: "放弃 " + keys.length + " 项同步",
            working: "正在放弃…",
            run: function (done) {
                var problem = "", remaining = keys.length
                for (var j = 0; j < keys.length; j++) {
                    app.cancelFavoriteIntent(keys[j], function (result, error) {
                        if (error) problem = error
                        remaining--
                        if (!remaining) done(null, problem)
                    })
                }
            }
        })
    }

    // ---------------------------------------------------------------- local playlists
    function saveQueue() {
        if (!has("saveQueueAsPlaylist")) { app.notify("这个版本还不能保存本地歌单", true); return }
        if (app.queue.length === 0) { app.notify("播放队列是空的，没有可保存的歌曲", false); return }
        nameDialog.openSaveQueue(app.queue.length)
    }
    function renameLocalPlaylist(p) { if (p && has("renameLocalPlaylist")) nameDialog.openRenameLocal(p) }

    // ---------------------------------------------------------------- subscriptions
    function subscribe(item) {
        if (!item || (item.kind !== "album" && item.kind !== "playlist")) return
        if (item.kind === "playlist" && item.owned) { app.notify("这是你自己的歌单，不需要收藏", false); return }
        if (!samePlatform(item)) { app.notify(switchHint(item) + "在它的账号里收藏", true); return }
        if (blocked(subAction(item), item.kind === "album" ? "收藏专辑" : "收藏歌单")) return
        var key = T.keyOf(item)
        if (key === "" || fa.pending[key] !== undefined) return
        var s = stateOf(item)
        if (s === "unknown") { _intend(item, "subscribe"); return }
        _toggleSub(item, s === "subscribed")
    }
    function _toggleSub(item, was) {
        var key = T.keyOf(item)
        var noun = item.kind === "album" ? "专辑" : "歌单"
        _mark(key, was ? "unsubscribe" : "subscribe")
        app.toggleSubscription(item, function (v, err) {
            fa._mark(key, "")
            if (err) return
            var now = fa._outcome(v, !was)
            fa.confirmed(key, now ? "subscribe" : "unsubscribe")
            app.notify((now ? "已在" + app.providerName + "收藏" + noun + "：" : "已取消" + app.providerName + "收藏的" + noun + "：") + fa.title(item), false)
        })
    }

    // ---------------------------------------------------------------- unknown → read first
    function _intend(item, what) {
        var key = T.keyOf(item)
        var next = Object.assign({}, fa.intents)
        next[key] = { what: what, item: item, until: Date.now() + 8000 }
        fa.intents = next
        _mark(key, "check")
        if (has("loadSubscription")) app.loadSubscription(item)
    }
    function _resolve() {
        var keys = Object.keys(fa.intents)
        if (keys.length === 0) return
        var keep = {}, now = Date.now(), act = []
        for (var i = 0; i < keys.length; i++) {
            var x = fa.intents[keys[i]]
            var s = stateOf(x.item)
            if (s === "unknown" && now < x.until) { keep[keys[i]] = x; continue }
            act.push({ key: keys[i], x: x, s: s })
        }
        if (act.length === 0) return
        fa.intents = keep
        for (var j = 0; j < act.length; j++) {
            var a = act[j]
            _mark(a.key, "")
            if (a.s === "unknown") {
                app.notify("没有读到《" + title(a.x.item) + "》的收藏状态，请稍后再试", true)
            } else if (a.s === "subscribed") {
                app.notify("已经在" + app.providerName + "收藏过：" + title(a.x.item), false)
            } else {
                _toggleSub(a.x.item, false)
            }
        }
    }
    Connections {
        target: fa.app
        ignoreUnknownSignals: true
        function onSubscriptionStatesChanged() { fa._resolve() }
        function onAccountReloaded() {
            // Album and playlist writes belong to the old account; Favorites saves do not.
            var keep = {}
            for (var k in fa.pending) if (k.indexOf("fav:") === 0) keep[k] = fa.pending[k]
            fa.intents = ({})
            fa.pending = keep
            picker.close()
            if (!nameDialog.local) nameDialog.close()   // local playlists have no account
            confirmDialog.close()
        }
    }
    Timer {
        interval: 600
        repeat: true
        running: Object.keys(fa.intents).length > 0
        onTriggered: fa._resolve()
    }

    // ---------------------------------------------------------------- navigation
    function artistsOf(track) {
        if (!track || !has("artistItems")) return []
        var a = app.artistItems(track)
        return T.isList(a) ? a : []
    }
    function openItem(item) {
        if (!item || typeof item !== "object") return
        if (app.settingsOpen && has("closeSettings")) app.closeSettings()
        app.openDetail(item)
    }
    function openSettings(section) {
        if (section) fa.settingsSection = section
        if (has("openSettings")) app.openSettings()
    }
    function toggleSettings() {
        if (app.settingsOpen) { if (has("closeSettings")) app.closeSettings() }
        else openSettings("")
    }
    function _closeDetailOf(item) {
        var key = T.keyOf(item)
        for (var i = 0; i < app.details.count; i++) {
            var p = null
            try { p = JSON.parse(app.details.get(i).payload) } catch (e) { p = null }
            if (p && T.keyOf(p) === key) { app.closeDetailsFrom(i); return }
        }
    }

    // ---------------------------------------------------------------- own playlists
    function addToPlaylist(song) {
        if (!app.isSong(song)) return
        if (!samePlatform(song)) { app.notify(switchHint(song) + "加入" + T.sourceLabel(T.providerOf(song)) + "歌单", true); return }
        if (blocked("playlistTracks", "把歌曲加入歌单")) return
        picker.show(song)
    }
    function addTo(playlist, song, done) {
        var key = T.keyOf(song) + "@" + T.keyOf(playlist)
        if (fa.pending[key] !== undefined) return
        _mark(key, "add")
        app.addToPlaylist(playlist, song, function (v, err) {
            fa._mark(key, "")
            if (!err) app.notify("已加入《" + fa.title(playlist) + "》：" + fa.title(song), false)
            if (done) done(v, err)
        })
    }
    function removeFrom(playlist, song) {
        if (!app.isSong(song) || !playlist || blocked("playlistTracks", "编辑歌单")) return
        if (!canEdit(playlist)) { app.notify("只能编辑你自己创建的普通歌单", true); return }
        var key = T.keyOf(song) + "@" + T.keyOf(playlist)
        if (fa.pending[key] !== undefined) return
        _mark(key, "remove")
        app.removeFromPlaylist(playlist, song, function (v, err) {
            fa._mark(key, "")
            if (!err) app.notify("已从《" + fa.title(playlist) + "》移除：" + fa.title(song), false)
        })
    }
    function createPlaylist(song) {
        if (blocked("createPlaylist", "新建歌单")) return
        nameDialog.openCreate(app.isSong(song) && samePlatform(song) ? song : null)
    }
    function renamePlaylist(pl) {
        if (!pl || blocked("renamePlaylist", "给歌单改名")) return
        if (!canEdit(pl)) { app.notify("只能给你自己创建的普通歌单改名", true); return }
        nameDialog.openRename(pl)
    }
    // Only opens the confirmation; app.deletePlaylist runs from its button.
    function deletePlaylist(pl) {
        if (!pl || blocked("deletePlaylist", "删除歌单")) return
        if (!canEdit(pl)) { app.notify("只能删除你自己创建的普通歌单", true); return }
        var name = title(pl)
        var known = pl.trackCount !== undefined && pl.trackCount !== null && pl.trackCount !== ""
        confirmDialog.ask({
            title: "DELETE",
            alarm: true,
            heading: "删除这个歌单？",
            name: name,
            meta: (known ? T.num(pl.trackCount) + " 首歌    " : "") + "你创建的歌单",
            body: [
                "歌单会从你的" + app.providerName + "账号里删除，手机和网页上登录同一账号也会看不到它。",
                "里面的歌曲本身不受影响，其他歌单和我的收藏都不会改变。",
                "删除后不能在播放器里撤销。"
            ],
            cancel: "保留歌单",
            confirm: "删除歌单",
            working: "正在删除…",
            run: function (done) {
                app.deletePlaylist(pl, function (v, err) {
                    if (!err) {
                        fa._closeDetailOf(pl)
                        app.notify("已删除歌单《" + name + "》", false)
                    }
                    done(v, err)
                })
            }
        })
    }

    // ---------------------------------------------------------------- account
    function logout() {
        if (!app.connected || !app.loggedIn) return
        if (!has("logout")) { app.notify("这个版本还不能退出登录", true); return }
        confirmDialog.ask({
            title: "LOGOUT",
            alarm: false,
            heading: "退出" + app.providerName + "账号？",
            name: app.nickname !== "" ? app.nickname : app.providerName + "账号",
            meta: app.vip ? "VIP 账号" : "",
            body: [
                "正在播放的歌曲会停止。",
                "播放器保存的登录信息和播放记录会被清除。",
                "我的收藏留在这台电脑上，不会被清除；之后这个平台的改动要等重新登录才会同步。",
                "之后搜索、播放和你的音乐库需要重新扫码登录。"
            ],
            cancel: "取消",
            confirm: "退出登录",
            working: "正在退出…",
            run: function (done) {
                app.logout(function (v, err) {
                    if (!err) app.notify("已退出" + app.providerName + "账号", false)
                    done(v, err)
                })
            }
        })
    }

    PlaylistPicker { id: picker; app: fa.app; ui: fa.ui; acts: fa }
    NameDialog { id: nameDialog; app: fa.app; ui: fa.ui; acts: fa }
    PendingSyncDialog { id: pendingDialog; app: fa.app; ui: fa.ui; acts: fa }
    ConfirmDialog { id: confirmDialog; z: 2; app: fa.app; ui: fa.ui }
}
