import QtQuick
import "theme.js" as T

// All native traffic, playback mirroring, account and QR login state.
Item {
    id: store
    visible: false

    readonly property bool connected: backend.connected
    readonly property string serviceError: backend.error
    readonly property bool serviceReconnecting: backend.serviceReconnecting
    function reconnectService() { backend.reconnectService() }

    readonly property string provider: backend.provider
    readonly property string providerName: provider === "netease" ? "网易云音乐" : "QQ 音乐"
    readonly property string playingProvider: current && current.provider ? String(current.provider) : ""
    readonly property int localFavoritesCount: backend.localFavoritesCount
    readonly property int localFavoritesRevision: backend.localFavoritesRevision
    readonly property bool localFavoritesReady: backend.localFavoritesReady
    readonly property string localFavoritesError: backend.localFavoritesError
    readonly property bool favoritesSyncBusy: backend.favoritesSyncBusy
    readonly property int favoritesPendingCount: backend.favoritesPendingCount
    readonly property var favoritesSyncProviders: backend.favoritesSyncProviders
    readonly property var favoritesPendingItems: backend.favoritesPendingItems
    readonly property var favoriteSyncStates: backend.favoriteSyncStates
    readonly property var localFavoriteKeys: backend.localFavoriteKeys
    property int favoritesSyncRevision: 0
    function retryFavoritesSync() { backend.retryFavoritesSync() }
    function retryFavoritesFor(source) { backend.retryFavoritesFor(source) }
    function retryFavoriteItem(key) { _pending[backend.retryFavoriteItem(key)] = reportError }
    function cancelFavoriteIntent(key, done) { _pending[backend.cancelFavoriteIntent(key)] = done || reportError }
    function favoriteSyncState(song) {
        var revision = favoritesSyncRevision
        return favoriteSyncStates[T.keyOf(song)] || {state: "local", pending: false, error: ""}
    }
    signal localFavoritesChanged()
    onLocalFavoritesRevisionChanged: localFavoritesChanged()

    function isLocalFavorite(song) { return !!song && !!localFavoriteKeys[T.keyOf(song)] }
    function toggleLocalFavorite(song, done) {
        var id = backend.toggleLocalFavorite(song || {})
        if (done) _pending[id] = done
        return id
    }
    function queryLocalFavorites(text, offset, done) {
        var id = backend.queryLocalFavorites(text || "", offset || 0)
        if (done) _pending[id] = done
        return id
    }
    function playLocalFavorites(text) { playLocalFavoritesFrom(null, text) }
    function playLocalFavoritesFrom(song, text) {
        var id = backend.allLocalFavorites(text || "")
        _pending[id] = function (items, error) {
            if (error) { store.notify(error, true); return }
            if (!T.isList(items) || !items.length) { store.notify("收藏还是空的", false); return }
            var at = 0
            if (song) {
                at = -1
                for (var i = 0; i < items.length; i++) if (T.keyOf(items[i]) === T.keyOf(song)) { at = i; break }
                if (at < 0) { store.playSingle(song); return }
            }
            store.control("player.play", {track: items[at], source: items, index: at}, store.reportError)
        }
    }
    readonly property var localPlaylists: backend.localPlaylists
    readonly property bool localPlaylistsReady: localFavoritesReady
    property string localPlaylistsError: backend.localFavoritesError
    function refreshLocalPlaylists() { localPlaylistsError = backend.localFavoritesError; backend.refreshLocalPlaylists() }
    function _playlistRequest(id, done) {
        _pending[id] = function (result, error) {
            store.localPlaylistsError = error || ""
            if (done) done(error || "", result)
            else if (error) store.notify(error, true)
        }
    }
    function saveQueueAsPlaylist(name, done) { _playlistRequest(backend.saveLocalPlaylist(name, queue), done) }
    function renameLocalPlaylist(id, name, done) { _playlistRequest(backend.renameLocalPlaylist(id, name), done) }
    function loadLocalPlaylist(id, done) { _playlistRequest(backend.loadLocalPlaylist(id), done) }
    function playLocalPlaylist(id) {
        loadLocalPlaylist(id, function (error, result) {
            if (error) { store.notify(error, true); return }
            if (result.items.length) store.control("player.play", {track: result.items[0], source: result.items}, store.reportError)
        })
    }
    readonly property string loginHint: provider === "netease" ? "用网易云音乐手机端扫码登录" : "用手机 QQ 或微信扫码登录"
    signal platformReset()
    signal platformReady()
    signal accountReloaded()
    signal activateRequested()
    signal libraryChanged()
    signal providerLibraryChanged(string source)

    // ---------------------------------------------------------------- notices
    property string noticeText: ""
    property bool noticeError: false
    property int noticeSerial: 0
    function notify(text, isError) {
        if (!text) return
        noticeText = String(text)
        noticeError = !!isError
        noticeSerial++
    }
    function reportError(value, error) { if (error) store.notify(error, true) }
    function needsLogin(error) { return !!error && String(error).indexOf("登录") >= 0 }

    // ---------------------------------------------------------------- requests
    property var _pending: ({})
    function _unavailable(callback) {
        if (callback) Qt.callLater(function () { callback(null, "播放服务还没有就绪") })
        return ""
    }
    function query(operation, args, callback) {
        if (!backend.connected) return _unavailable(callback)
        var id = backend.query(operation, args || [])
        if (callback) _pending[id] = callback
        return id
    }
    function queryFor(source, operation, args, callback) {
        if (!backend.connected) return _unavailable(callback)
        var id = backend.queryProvider(source || provider, operation, args || [])
        if (callback) _pending[id] = callback
        return id
    }
    function control(command, args, callback) {
        if (!backend.connected) return _unavailable(callback)
        var id = backend.control(command, args || {})
        if (callback) _pending[id] = callback
        return id
    }
    function loginCall(route, params, callback) {
        if (!backend.connected) return _unavailable(callback)
        var id = backend.loginRequest(route, params || {})
        if (callback) _pending[id] = callback
        return id
    }
    function _dispatch(id, json, error) {
        var callback = _pending[id]
        if (callback === undefined) return
        delete _pending[id]
        var value = null
        if (json && json !== "null") {
            try { value = JSON.parse(json) } catch (e) { if (!error) error = "音乐接口返回的数据无法读取" }
        }
        callback(value, error || "")
    }

    // ---------------------------------------------------------------- playback mirror
    property var current: null
    property string currentKey: ""
    property string _currentSig: ""
    property var queue: []
    property var queueKeys: []
    property string _queueSig: ""
    property var history: []
    property string _historySig: ""
    property int index: -1
    readonly property int queueIndex: index
    property string mode: "all"
    property var radio: ({active: false, phase: "idle", upcoming: 0, error: ""})
    readonly property bool radioActive: connected && !!radio.active
    function startRadio(song) { control("player.radioStart", song ? {provider: provider, track: song} : {provider: provider}, reportError) }
    function stopRadio() { control("player.radioStop", {}, reportError) }
    function retryRadio() { control("player.radioRetry", {}, reportError) }
    property bool playing: false
    property real positionMs: 0
    property real durationMs: 0
    property real displayMs: 0
    property real _stamp: 0
    property bool seekable: false
    property real volume: 1
    property bool buffering: false
    property bool requested: false
    property bool recoverable: false
    property string playError: ""
    property bool loading: false
    property bool failed: false
    property bool trial: false
    property var preview: null
    property string status: ""
    property string quality: ""
    property string actualQuality: ""
    property bool credentialQQ: false
    property bool credentialNetease: false
    property string _epoch: ""

    readonly property bool hasTrack: current !== null && currentKey !== ""
    readonly property bool canControl: connected && (hasTrack || queue.length > 0)
    readonly property real fraction: durationMs > 0 ? T.clamp(displayMs / durationMs, 0, 1) : 0
    readonly property string coverUrl: hasTrack && current.cover ? String(current.cover) : ""

    // lyrics (fields confirmed: line = {startMs,endMs,text,translation,words})
    property var lyricLines: []
    property string _lyricSig: ""
    property string lyricTiming: "none"
    property string lyricPlain: ""
    property int lyricIndex: -1
    property string lyricStatus: ""
    property string lyricMessage: ""
    property real lyricDocOffset: 0
    property real lyricOffset: 0
    property real lyricGlobalOffset: 0
    readonly property bool lyricSynced: lyricTiming !== "none" && lyricLines.length > 0

    function _text(v) { return (typeof v === "string" || typeof v === "number") ? String(v) : "" }

    property var _mirroredSnapshot: ({})
    function _sync() {
        var update = backend.snapshotUpdate
        if (update === undefined) update = backend.snapshot || {}
        var s = backend.snapshotIsPatch === true ? Object.assign({}, _mirroredSnapshot, update) : update
        _mirroredSnapshot = s
        var st = s.state || {}
        var cur = s.current || null
        var key = cur ? T.keyOf(cur) : ""
        var sig = cur ? key + "|" + (cur.cover || "") + "|" + (cur.title || "") + "|" + (cur.duration || 0) : ""
        if (update.hasOwnProperty("current") || sig !== _currentSig) { _currentSig = sig; currentKey = key; current = cur }

        if (backend.snapshotIsPatch !== true || update.hasOwnProperty("queue")) {
            var q = T.isList(s.queue) ? s.queue : []
            var keys = []
            for (var i = 0; i < q.length; i++) keys.push(T.keyOf(q[i]))
            _queueSig = keys.join("\n")
            queue = q
            queueKeys = keys
        }
        if (backend.snapshotIsPatch !== true || update.hasOwnProperty("history")) {
            history = T.isList(s.history) ? s.history : []
        }

        index = typeof s.index === "number" ? s.index : -1
        mode = s.mode ? String(s.mode) : "all"
        if (backend.snapshotIsPatch !== true || update.hasOwnProperty("radio"))
            radio = s.radio || {active: false, phase: "idle", upcoming: 0, error: ""}
        playing = connected && !!st.playing
        durationMs = T.num(st.duration) || (cur ? T.num(cur.duration) : 0)
        seekable = !!st.seekable
        buffering = connected && !!st.buffering
        requested = !!st.requested
        recoverable = !!st.recoverable
        playError = _text(st.error)
        if (Date.now() >= _volUntil && st.volume !== undefined) volume = T.clamp(T.num(st.volume), 0, 1)
        loading = !!s.loading
        failed = !!s.failed
        trial = !!s.trial
        preview = s.preview ? s.preview : null
        status = _text(s.status)
        if (cur && !playing && !loading && status.indexOf("正在播放") === 0)
            status = "已暂停：" + _text(cur.title)
        quality = s.qualities ? _text(s.qualities[provider]) : _text(s.quality)
        actualQuality = _text(s.actualQuality)
        credentialQQ = !!(s.credentials && s.credentials.qq)
        credentialNetease = !!(s.credentials && s.credentials.netease)

        var pos = T.num(st.position)
        positionMs = pos
        _stamp = Date.now()
        if (_seekTarget >= 0 && (Math.abs(pos - _seekTarget) < 1500 || Date.now() > _seekUntil)) _seekTarget = -1
        if (_seekTarget < 0) displayMs = pos

        var epoch = s.accountEpoch === undefined || s.accountEpoch === null ? "" : String(s.accountEpoch)
        if (epoch !== _epoch) {
            var had = _epoch !== ""
            _epoch = epoch
            if (had && connected) Qt.callLater(store.refreshAccount)
        }
        _syncLyrics(s.lyrics || {})
    }

    function _syncLyrics(L) {
        var doc = L.document || {}
        var lines = T.isList(doc.lines) ? doc.lines : []
        var first = lines.length ? lines[0] || {} : {}
        var sig = String(L.key || "") + "|" + (doc.timing || "") + "|" + lines.length + "|" + T.num(first.startMs) + "|" + (first.text || "") + "|" + (doc.plainText ? String(doc.plainText).length : 0)
        if (sig !== _lyricSig) {
            _lyricSig = sig
            var out = []
            for (var i = 0; i < lines.length; i++) {
                var ln = lines[i] || {}
                out.push({ start: T.num(ln.startMs), end: T.num(ln.endMs), text: _text(ln.text), tr: _text(ln.translation) })
            }
            lyricTiming = doc.timing ? String(doc.timing) : "none"
            lyricPlain = _text(doc.plainText)
            lyricLines = out
        }
        lyricDocOffset = T.num(doc.offsetMs)
        lyricOffset = T.num(L.offsetMs)
        lyricGlobalOffset = T.num(L.globalOffsetMs)
        lyricIndex = typeof L.index === "number" ? L.index : -1
        lyricStatus = _text(L.status)
        lyricMessage = _text(L.message)
    }

    // Smooth the clock between real snapshot reports only while actually playing.
    Timer {
        interval: 250
        repeat: true
        running: store.connected && store.playing && !store.buffering && store.durationMs > 0
        onTriggered: {
            if (store._seekTarget >= 0) return
            store.displayMs = Math.min(store.durationMs, store.positionMs + (Date.now() - store._stamp))
        }
    }

    property real _seekTarget: -1
    property real _seekUntil: 0
    function seekMs(ms) {
        if (!seekable || durationMs <= 0) return
        ms = T.clamp(ms, 0, durationMs)
        _seekTarget = ms
        _seekUntil = Date.now() + 2000
        displayMs = ms
        control("player.seek", { value: T.clamp(ms / durationMs, 0, 1) }, function (v, error) {
            if (error) { store._seekTarget = -1; store.notify(error, true) }
        })
    }
    function seekBy(delta) { if (hasTrack) seekMs(displayMs + delta) }
    function seekLyric(i) {
        var line = lyricLines[i]
        if (!line || !lyricSynced) return
        seekMs(line.start - lyricDocOffset - lyricOffset)
    }

    property real _volTarget: -1
    property real _volUntil: 0
    function setVolume(v) {
        if (!connected) return
        v = T.clamp(v, 0, 1)
        volume = v
        _volTarget = v
        _volUntil = Date.now() + 1500
        if (!volumeTimer.running) volumeTimer.start()
    }
    Timer {
        id: volumeTimer
        interval: 70
        onTriggered: {
            if (store._volTarget < 0) return
            store.control("player.volume", { value: store._volTarget }, store.reportError)
            store._volTarget = -1
        }
    }

    function isSong(it) { return !!it && (it.kind === "song" || (!it.kind && !!(it.songID || it.mediaId))) }
    function toggle() { if (canControl) control("player.toggle", {}, reportError) }
    function step(direction) { if (canControl) control("player.next", { direction: direction }, reportError) }
    function cycleMode() {
        var next = mode === "all" ? "one" : (mode === "one" ? "shuffle" : "all")
        control("player.mode", { value: next }, reportError)
    }
    // Play a song from a catalog list: the source contains only song items.
    function playAt(list, at, allIds) {
        if (!T.isList(list)) return
        var songs = [], idx = -1
        for (var i = 0; i < list.length; i++) {
            if (!isSong(list[i])) continue
            if (i === at) idx = songs.length
            songs.push(list[i])
        }
        if (idx < 0) return
        if (T.isList(allIds) && allIds.length) {
            var selected = T.keyOf(songs[idx]), complete = collectionSongs(songs, allIds)
            for (var j = 0; j < complete.length; j++) {
                if (T.keyOf(complete[j]) === selected) { songs = complete; idx = j; break }
            }
        }
        if (preferences["single-play-mode"] === "append")
            control("player.play", { track: songs[idx] }, reportError)
        else
            control("player.play", { track: songs[idx], source: songs, index: idx }, reportError)
    }
    function playQueueAt(i) {
        if (i < 0 || i >= queue.length) return
        control("player.playIndex", { index: i, key: T.keyOf(queue[i]) }, reportError)
    }
    function moveQueue(from, to) {
        if (from < 0 || from >= queue.length || to < 0 || to >= queue.length) return
        control("player.move", { from: from, to: to, key: T.keyOf(queue[from]) }, reportError)
    }
    // Match the original player's directory queue: retain every ID, fetching
    // unloaded metadata lazily in the native service. Play-all always replaces.
    function collectionSongs(loaded, ids) {
        var known = {}, result = [], seen = {}
        loaded = T.isList(loaded) ? loaded : []
        var source = loaded.length && loaded[0].provider ? loaded[0].provider : store.provider
        for (var i = 0; i < loaded.length; i++)
            if (isSong(loaded[i])) known[String(loaded[i].id)] = loaded[i]
        if (!T.isList(ids) || ids.length === 0) return loaded.filter(isSong)
        for (var j = 0; j < ids.length; j++) {
            var id = String(ids[j])
            if (!id || seen[id]) continue
            seen[id] = true
            result.push(known[id] || { provider: source, kind: "song", id: id,
                key: source + ":song:" + id, title: "待读取曲目", deferred: true })
        }
        return result
    }
    function playCollection(loaded, ids) {
        var songs = collectionSongs(loaded, ids)
        if (songs.length) control("player.play", { track: songs[0], source: songs, index: 0 }, reportError)
    }
    function playSingle(item) { if (isSong(item)) control("player.play", { track: item }, reportError) }
    function enqueue(item, next) {
        if (!isSong(item)) return
        control("player.enqueue", { track: item, next: !!next }, function (v, error) {
            if (error) store.notify(error, true)
            else store.notify((next ? "下一首播放：" : "已加入播放队列：") + (item.title || ""), false)
        })
    }
    function removeAt(i) { if (i >= 0 && i < queue.length) control("player.remove", { index: i }, reportError) }
    function retry() {
        if (!hasTrack) return
        if (index >= 0 && index < queue.length && T.keyOf(queue[index]) === currentKey)
            playQueueAt(index)
        else
            control("player.play", { track: current }, reportError)
    }
    function setLyricOffset(ms) { control("lyrics.offset", { value: Math.round(ms - lyricOffset) }, reportError) }
    function resetLyricOffset() { control("lyrics.reset", {}, reportError) }
    function useLyricOffsetGlobally() { control("lyrics.global", {}, reportError) }
    function openTrackPage(item) {
        if (!isSong(item)) return
        queryFor(item.provider, "trackPage", [item], function (v, error) {
            var url = typeof v === "string" ? v : (v && v.url ? String(v.url) : "")
            var lower = url.toLowerCase()
            if (lower.indexOf("https://") === 0 || lower.indexOf("http://") === 0) Qt.openUrlExternally(url)
            else store.notify(error || "这首歌没有可以打开的网页", true)
        })
    }

    // ---------------------------------------------------------------- detail windows
    property ListModel details: ListModel {}
    readonly property int detailCount: {
        var count = 0, revision = details.count
        for (var i = 0; i < details.count; i++) if (details.get(i).scope === provider) count++
        return count
    }
    function detailRank(at) {
        var n = 0
        for (var i = 0; i < at; i++) if (details.get(i).scope === provider) n++
        return n
    }
    property int _detailSerial: 0
    function openDetail(item) {
        if (!item || typeof item !== "object") return
        if (detailCount >= 6) {
            for (var i = 0; i < details.count; i++) if (details.get(i).scope === provider) { details.remove(i); break }
        }
        _detailSerial++
        details.append({ uid: _detailSerial, payload: JSON.stringify(item), scope: provider })
    }
    function closeDetailsFrom(i) {
        for (var at = details.count - 1; at >= i && i >= 0; at--)
            if (details.get(at).scope === provider) details.remove(at)
    }
    function popDetail() {
        for (var i = details.count - 1; i >= 0; i--) if (details.get(i).scope === provider) { details.remove(i); return true }
        return false
    }
    function clearDetails() { closeDetailsFrom(0) }

    function albumItem(track) {
        if (!track || !track.albumID) return null
        return { provider: track.provider, kind: "album", id: String(track.albumID), key: track.provider + ":album:" + track.albumID,
                 title: track.album || "专辑", artist: T.artists(track), artists: track.artists || [], cover: track.cover || "" }
    }
    function artistItems(track) {
        var out = [], seen = {}, rows = track && T.isList(track.artists) ? track.artists : []
        for (var i = 0; i < rows.length; i++) {
            var a = rows[i]
            if (!a || !a.id || seen[String(a.id)]) continue
            seen[String(a.id)] = true
            out.push({ provider: track.provider, kind: "artist", id: String(a.id), key: track.provider + ":artist:" + a.id,
                       title: a.name || a.title || "歌手", cover: a.cover || "" })
        }
        return out
    }

    // ---------------------------------------------------------------- library writes
    readonly property bool writeBusy: backend.writeBusy
    readonly property string writeError: backend.writeError
    property var subscriptionStates: ({})
    property var _subscriptionPending: ({})
    property int _subscriptionGeneration: 0
    property var ownedPlaylists: []
    property bool ownedPlaylistsBusy: false
    property string ownedPlaylistsError: ""
    property int _ownedGeneration: 0
    property bool _ownedLoaded: false
    readonly property var _writeCapabilities: ({
        like: ["mutations", "likeSong"], subscribeAlbum: ["mutations", "subscribeAlbum"],
        subscribePlaylist: ["mutations", "subscribePlaylist"], playlistTracks: ["mutations", "updatePlaylistTracks"],
        createPlaylist: ["playlistManagement", "createPlaylist"], renamePlaylist: ["playlistManagement", "renamePlaylist"],
        deletePlaylist: ["playlistManagement", "deletePlaylist"]
    })
    function canMutate(action) {
        var path = _writeCapabilities[action]
        return !!(connected && loggedIn && path && caps[path[0]] && caps[path[0]][path[1]] === true)
    }
    function canEditPlaylist(item) {
        if (!loggedIn || !item || item.kind !== "playlist" || item.provider !== provider || !item.owned) return false
        if (provider === "netease") return String(item.creatorID) === String(userId) && Number(item.specialType || 0) !== 5
        var directory = Number(item.dirId)
        return String(item.creatorID) === String(userId) && isFinite(directory) && Math.floor(directory) === directory
            && directory >= 1 && directory <= 199
    }
    function subscriptionState(item) { return subscriptionStates[T.keyOf(item)] || "unknown" }
    function rememberSubscribed(items) {
        var states = Object.assign({}, subscriptionStates)
        for (var i = 0; i < items.length; i++) {
            var key = T.keyOf(items[i])
            if (key) states[key] = "subscribed"
        }
        subscriptionStates = states
    }
    function _clearSubscriptions() {
        _subscriptionGeneration++
        subscriptionStates = ({})
        _subscriptionPending = ({})
    }
    function loadSubscription(item, force) {
        if (!loggedIn || !item || item.provider !== provider || !item.id || ["song", "album", "playlist"].indexOf(item.kind) < 0) return
        var key = T.keyOf(item), gen = _subscriptionGeneration
        if (_subscriptionPending[key] || (!force && ["subscribed", "not-subscribed"].indexOf(subscriptionStates[key]) >= 0)) return
        _subscriptionPending[key] = true
        query("subscriptionStatus", [item.kind, item.id], function (value, error) {
            if (gen !== store._subscriptionGeneration) return
            delete store._subscriptionPending[key]
            var state = !error && (value === "subscribed" || value === "not-subscribed") ? value : "unknown"
            var states = Object.assign({}, store.subscriptionStates)
            states[key] = state
            store.subscriptionStates = states
        })
    }
    onCurrentChanged: if (loggedIn) loadSubscription(current)
    function loadOwnedPlaylists() {
        _ownedGeneration++
        var gen = _ownedGeneration
        ownedPlaylistsError = ""
        if (!loggedIn) { ownedPlaylists = []; ownedPlaylistsBusy = false; return }
        ownedPlaylistsBusy = true
        query("userPlaylists", [userId], function (value, error) {
            if (gen !== store._ownedGeneration) return
            store.ownedPlaylistsBusy = false
            store._ownedLoaded = true
            store.ownedPlaylistsError = error || ""
            var result = [], items = value && T.isList(value.items) ? value.items : []
            for (var i = 0; i < items.length; i++) if (store.canEditPlaylist(items[i])) result.push(items[i])
            store.ownedPlaylists = result
        })
    }
    function _writeFailure(error, done) {
        notify(error, true)
        if (done) Qt.callLater(function () { done(null, error) })
        return ""
    }
    function _write(action, args, item, done) {
        if (!canMutate(action)) return _writeFailure(loggedIn ? "当前平台未开放此编辑功能" : "请先登录" + providerName, done)
        if (writeBusy) return _writeFailure("上一项修改尚未完成，请稍候", done)
        var gen = _accountGen
        _clearSubscriptions()
        var id = backend.mutate(action, args)
        _pending[id] = function (value, error) {
            if (gen !== store._accountGen) {
                if (done) done(null, "账号已变化，请重新读取")
                return
            }
            store._clearSubscriptions()
            // Includes uncertain failures: refresh reads, never repeat a write.
            store.libraryChanged()
            if (store._ownedLoaded) store.loadOwnedPlaylists()
            if (item) store.loadSubscription(item, true)
            store.loadSubscription(store.current, true)
            if (error) store.notify(error, true)
            else if (!done) store.notify("已同步至" + store.providerName, false)
            if (done) done(value, error || "")
        }
        return id
    }
    function toggleLike(song, done) {
        if (!isSong(song)) return _writeFailure("请选择歌曲", done)
        return toggleLocalFavorite(song, done)
    }
    function toggleSubscription(item, done) {
        if (!item || item.provider !== provider || ["album", "playlist"].indexOf(item.kind) < 0)
            return _writeFailure("请选择" + providerName + "专辑或歌单", done)
        return _write(item.kind === "album" ? "subscribeAlbum" : "subscribePlaylist", { id: item.id }, item, done)
    }
    function _playlistName(name) {
        name = String(name || "").trim()
        var characters = 0
        for (var i = 0; i < name.length; i++) {
            var first = name.charCodeAt(i)
            if (first >= 0xD800 && first <= 0xDBFF && i + 1 < name.length) {
                var second = name.charCodeAt(i + 1)
                if (second >= 0xDC00 && second <= 0xDFFF) i++
            }
            characters++
        }
        return characters >= 1 && characters <= 20 ? name : ""
    }
    function createPlaylist(name, done) {
        name = _playlistName(name)
        if (!name) return _writeFailure("歌单名称需要 1–20 字", done)
        return _write("createPlaylist", { name: name }, null, function (value, error) {
            var playlist = !error && value && value.playlist ? Object.assign({}, value.playlist, { creatorID: String(store.userId) }) : null
            if (done) done(playlist, error)
        })
    }
    function renamePlaylist(playlist, name, done) {
        if (!canEditPlaylist(playlist)) return _writeFailure("只能编辑自己创建的普通歌单", done)
        name = _playlistName(name)
        if (!name) return _writeFailure("歌单名称需要 1–20 字", done)
        return _write("renamePlaylist", { id: playlist.id, name: name }, playlist, done)
    }
    function deletePlaylist(playlist, done) {
        if (!canEditPlaylist(playlist)) return _writeFailure("只能删除自己创建的普通歌单", done)
        return _write("deletePlaylist", { id: playlist.id }, null, done)
    }
    function _playlistTrack(playlist, song, remove, done) {
        if (!canEditPlaylist(playlist)) return _writeFailure("请选择自己创建的普通歌单", done)
        if (!isSong(song) || song.provider !== provider) return _writeFailure("请选择当前平台的普通曲库歌曲", done)
        return _write("playlistTracks", { pid: playlist.id, tracks: song.id, op: remove ? "del" : "add" }, null, done)
    }
    function addToPlaylist(playlist, song, done) { return _playlistTrack(playlist, song, false, done) }
    function removeFromPlaylist(playlist, song, done) { return _playlistTrack(playlist, song, true, done) }

    // ---------------------------------------------------------------- settings
    property bool settingsOpen: false
    readonly property var preferences: backend.preferences
    readonly property bool preferencesReady: backend.preferencesReady
    readonly property bool preferencesBusy: backend.preferencesBusy
    readonly property string preferencesError: backend.preferencesError
    readonly property var qualityOptions: provider === "netease" ? [
        { value: "standard", label: "标准" }, { value: "exhigh", label: "HQ 高品质" },
        { value: "lossless", label: "SQ 无损" }, { value: "hires", label: "Hi-Res" },
        { value: "jymaster", label: "超清母带" }
    ] : [
        { value: "best", label: "自动最高可用" }, { value: "standard", label: "标准" },
        { value: "exhigh", label: "HQ 高品质" }, { value: "lossless", label: "SQ 无损 / FLAC" },
        { value: "ape", label: "SQ 无损 / APE" }
    ]
    function openSettings() { settingsOpen = true; if (!preferencesReady && !preferencesBusy) refreshPreferences() }
    function closeSettings() { settingsOpen = false }
    function refreshPreferences() {
        var id = backend.refreshPreferences()
        _pending[id] = reportError
        return id
    }
    function setPreference(key, value, done) {
        var id = backend.setPreference(key, value)
        _pending[id] = function (result, error) {
            if (error) store.notify(error, true)
            if (done) done(result, error)
        }
        return id
    }
    function setQuality(value, done) {
        return control("player.quality", { value: value }, function (result, error) {
            if (error) store.notify(error, true)
            if (done) done(result, error)
        })
    }
    function logout(done) {
        if (writeBusy) return _writeFailure("请等待当前修改完成后再退出账号", done)
        closeLogin()
        return control("host.logout", {}, function (value, error) {
            if (error) store.notify(error, true)
            else {
                store._clearSubscriptions()
                store.clearDetails()
                store.refreshAccount()
            }
            if (done) done(value, error)
        })
    }

    // ---------------------------------------------------------------- account
    property bool accountChecked: false
    property string accountState: "loading"
    property string accountError: ""
    property var _accounts: ({})
    property var _catalogSource: ""
    property string _loginTarget: ""
    property bool loggedIn: false
    property var userId: null
    property string nickname: ""
    property bool vip: false
    property var caps: ({})
    property var categories: []
    property int _accountGen: 0

    function _resetPlatform() {
        // Catalog callbacks carry generation guards. Playback and local-library
        // callbacks remain alive when the browsing theme changes.
        _accountGen++
        qrOpen = false; _qrGen++; qrPoll.stop(); _qrKey = ""; qrImage = ""; qrPhase = "idle"
        _seekTarget = -1; _volTarget = -1; volumeTimer.stop()
        _accounts[provider] = {loggedIn: loggedIn, userId: userId, nickname: nickname, vip: vip,
            accountState: accountState, accountChecked: accountChecked, accountError: accountError,
            caps: caps, categories: categories}
        _clearSubscriptions(); _ownedGeneration++
        ownedPlaylists = []; ownedPlaylistsBusy = false; _ownedLoaded = false
        accountChecked = false; loggedIn = false; userId = null; nickname = ""; vip = false
        caps = ({}); categories = []
        platformReset()
    }
    function _onReady() {
        var switched = _catalogSource !== provider
        _catalogSource = provider
        var saved = _accounts[provider]
        if (switched && saved) {
            loggedIn = saved.loggedIn; userId = saved.userId; nickname = saved.nickname; vip = saved.vip
            accountState = saved.accountState; accountChecked = saved.accountChecked; accountError = saved.accountError
            caps = saved.caps; categories = saved.categories
        }
        qrChannel = provider === "netease" ? "netease" : "qq"
        qrChannels = provider === "netease" ? ["netease"] : ["qq", "wechat"]
        _sync()
        if (switched) platformReady()
        refreshAccount()
        query("capabilities", [], function (v, error) { if (!error && v && typeof v === "object") store.caps = v })
        query("categories", [], function (v, error) { if (!error && T.isList(v)) store.categories = v })
        if (_loginTarget === provider) { _loginTarget = ""; Qt.callLater(store.openLogin) }
    }
    function refreshAccount() {
        _accountGen++
        var gen = _accountGen
        accountState = "loading"
        accountError = ""
        query("account", [], function (v, error) {
            if (gen !== store._accountGen) return
            store.accountChecked = true
            var hasCredential = store.provider === "netease" ? store.credentialNetease : store.credentialQQ
            if (error && !(v && v.authExpired) && (hasCredential || store.loggedIn)) {
                store.accountState = "error"
                store.accountError = error
                // Keep last verified identity. A timeout is not a logout.
                store.accountReloaded()
                return
            }
            var oldUser = store.userId
            if (!T.isList(v) || v[0] === undefined || v[0] === null || v[0] === "") {
                store.accountState = "signedOut"
                store.loggedIn = false
                store.userId = null
                store.nickname = ""
                store.vip = false
            } else {
                store.accountState = "ready"
                store.loggedIn = true
                store.userId = v[0]
                store.nickname = v.length > 1 && v[1] ? String(v[1]) : ""
                store.query("vip", [], function (vv, e2) { if (gen === store._accountGen) store.vip = !e2 && !!vv && !!vv.isVip })
            }
            if (oldUser && String(oldUser) !== String(store.userId)) store.clearDetails()
            store._clearSubscriptions()
            store._ownedGeneration++
            store.ownedPlaylists = []
            store.ownedPlaylistsBusy = false
            store.ownedPlaylistsError = ""
            store._ownedLoaded = false
            store.accountReloaded()
            store.loadSubscription(store.current, true)
        })
    }

    // ---------------------------------------------------------------- QR login
    property bool qrOpen: false
    property string qrChannel: "qq"
    property var qrChannels: ["qq", "wechat"]
    property string qrPhase: "idle"     // loading | waiting | scanned | expired | success | error
    property string qrImage: ""
    property string qrMessage: ""
    property int _qrGen: 0
    property string _qrKey: ""
    property int _qrPolls: 0
    property int _qrErrors: 0

    function openLogin() {
        if (!connected) { notify("播放服务还没有就绪，稍后再登录", true); return }
        if (writeBusy) { notify("请等待当前修改完成后再登录", true); return }
        qrOpen = true
        _fetchChannels()
        qrStart(qrChannel)
    }
    function openProviderLogin(source) {
        if (["qq", "netease"].indexOf(source) < 0) return
        if (!connected) { notify("请先重新连接播放服务", true); return }
        if (writeBusy) { notify("请等待当前修改完成", true); return }
        if (source === provider) openLogin()
        else { _loginTarget = source; backend.selectPlatform(source) }
    }
    function closeLogin() {
        qrOpen = false
        _qrInvalidate()
        qrPhase = "idle"
        qrImage = ""
    }
    function _qrInvalidate() {
        _qrGen++
        qrPoll.stop()
        if (_qrKey !== "" && connected) loginCall("/login/qr/cancel", { key: _qrKey }, null)
        _qrKey = ""
    }
    function _qrFail(message) {
        qrPoll.stop()
        qrPhase = "error"
        qrMessage = message || "登录没有完成，请刷新二维码"
    }
    function _fetchChannels() {
        loginCall("/login/channels", {}, function (v, error) {
            if (error || !v) return
            var text = JSON.stringify(v).toLowerCase()
            var list = []
            if (text.indexOf("netease") >= 0) list.push("netease")
            if (text.indexOf("qq") >= 0) list.push("qq")
            if (text.indexOf("wechat") >= 0 || text.indexOf("weixin") >= 0) list.push("wechat")
            if (list.length) {
                store.qrChannels = list
                if (list.indexOf(store.qrChannel) < 0 && store.qrOpen) store.qrStart(list[0])
            }
        })
    }
    function qrStart(channel) {
        _qrInvalidate()
        var gen = _qrGen
        qrChannel = channel
        qrPhase = "loading"
        qrImage = ""
        qrMessage = ""
        _qrPolls = 0
        _qrErrors = 0
        loginCall("/login/qr/key", { channel: channel, timestamp: Date.now() }, function (v, error) {
            if (gen !== store._qrGen) return
            var key = v ? (v.unikey || (v.data && v.data.unikey)) : ""
            if (error || !key) { store._qrFail(error || "没有拿到登录二维码"); return }
            store._qrKey = String(key)
            store.loginCall("/login/qr/create", { key: store._qrKey, qrimg: true, timestamp: Date.now() }, function (c, e2) {
                if (gen !== store._qrGen) return
                var img = c ? ((c.data && c.data.qrimg) || c.qrimg) : ""
                if (e2 || typeof img !== "string" || img.indexOf("data:image/") !== 0) { store._qrFail(e2 || "二维码图片无效"); return }
                store.qrImage = img
                store.qrPhase = "waiting"
                qrPoll.gen = gen
                qrPoll.restart()
            })
        })
    }
    Timer {
        id: qrPoll
        property int gen: 0
        interval: 1000
        repeat: false
        onTriggered: store._qrCheck(gen)
    }
    function _qrCheck(gen) {
        if (gen !== _qrGen || !qrOpen || _qrKey === "") return
        _qrPolls++
        if (_qrPolls > 300) {
            qrPhase = "expired"
            qrMessage = "等待时间过长，请刷新二维码"
            return
        }
        loginCall("/login/qr/check", { key: _qrKey, timestamp: Date.now() }, function (v, error) {
            if (gen !== store._qrGen) return
            if (error) {
                store._qrErrors++
                if (store._qrErrors >= 3) { store._qrFail(error); return }
                qrPoll.gen = gen
                qrPoll.restart()
                return
            }
            store._qrErrors = 0
            var code = v ? Number(v.code) : 0
            if (code === 803) store._qrSuccess(gen)
            else if (code === 800) { store.qrPhase = "expired"; store.qrMessage = "二维码已过期" }
            else {
                store.qrPhase = code === 802 ? "scanned" : "waiting"
                qrPoll.gen = gen
                qrPoll.restart()
            }
        })
    }
    function _qrSuccess(gen) {
        qrPoll.stop()
        qrPhase = "success"
        qrMessage = "已确认，正在读取账号"
        _qrKey = ""   // consumed by a successful login; never cancel it
        query("account", [], function (v, error) {
            if (gen !== store._qrGen) return
            if (error || !T.isList(v) || v[0] === undefined || v[0] === null || v[0] === "") {
                store._qrFail(error || "已扫码，但没有读到账号信息")
                return
            }
            store.control("host.saveCredential", {}, function (r, e2) {
                if (gen !== store._qrGen) return
                var saveError = e2 || (r && r.value ? String(r.value) : "")
                store.closeLogin()
                store.refreshAccount()
                if (saveError) store.notify("已登录，但账号没有保存：" + saveError, true)
                else store.notify("已登录" + store.providerName, false)
            })
        })
    }

    // ---------------------------------------------------------------- wiring
    Connections {
        target: backend
        function onResponse(requestId, resultJson, error) { store._dispatch(requestId, resultJson, error) }
        function onSnapshotChanged() { store._sync() }
        function onConnectedChanged() {
            if (!backend.connected) { store.playing = false; store.buffering = false; store.loading = false; store.requested = false }
        }
        function onFavoritesSyncChanged() { store.favoritesSyncRevision++ }
        function onFavoritePlatformChanged(source, id, liked) {
            store.providerLibraryChanged(source)
            if (source !== store.provider) return
            var states = Object.assign({}, store.subscriptionStates)
            states[source + ":song:" + id] = liked ? "subscribed" : "not-subscribed"
            store.subscriptionStates = states
            store.libraryChanged()
        }
        function onPlatformReset() { store._resetPlatform() }
        function onReady() { store._onReady() }
        function onActivateRequested() { store.activateRequested() }
        function onErrorChanged() { if (backend.error) store.notify(backend.error, true) }
    }
    Component.onCompleted: {
        _sync()
        if (backend.connected) _onReady()
    }
}
