"""Transport for the Miku QML interface and the original Rhine service.

No UI, credentials, audio decoding, provider protocol, or generated artwork lives
here. The official RhinePlaybackService owns the account and playback state.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from typing import Callable

from PySide6.QtCore import QObject, Property, QTimer, Signal, Slot
from PySide6.QtNetwork import QLocalSocket
from local_favorites import LocalFavorites
from favorites_sync import FavoritesSync
from mixed_migration import migrate_legacy_sessions
import sqlite3


class NativeBridge(QObject):
    snapshotChanged = Signal()
    connectedChanged = Signal()
    errorChanged = Signal()
    ready = Signal()
    activateRequested = Signal()
    quitRequested = Signal()
    response = Signal(str, str, str)  # request ID, JSON value, human-readable error
    writeBusyChanged = Signal()
    writeErrorChanged = Signal()
    preferencesChanged = Signal()
    preferencesStatusChanged = Signal()
    providerChanged = Signal()
    switchingChanged = Signal()
    platformReset = Signal()
    localFavoritesChanged = Signal()
    favoritesSyncChanged = Signal()
    favoritePlatformChanged = Signal(str, str, bool)
    localPlaylistsChanged = Signal()

    @Property('QVariantMap', notify=localFavoritesChanged)
    def localFavoriteKeys(self): return self._favorite_keys

    @Property('QVariantMap', notify=favoritesSyncChanged)
    def favoriteSyncStates(self): return self._favorites_sync.states if self._favorites_sync else {}

    @Property('QVariantList', notify=favoritesSyncChanged)
    def favoritesPendingItems(self): return self._favorites_sync.pending_items if self._favorites_sync else []

    @Property('QVariantList', notify=localPlaylistsChanged)
    def localPlaylists(self): return self._favorites.playlists() if self._favorites else []

    @Slot(str)
    def retryFavoritesFor(self, provider):
        if provider not in ('qq', 'netease') or not self._favorites_sync: return
        if not self._connected:
            self.start()
            return
        self._send('host.invalidateMetadata', {}, lambda _v, _e: self._favorites_sync.refresh(provider), 10)

    @Slot(str, result=str)
    def retryFavoriteItem(self, key):
        return self._local_request(lambda: self._favorites_sync.manage(key))

    @Slot(str, result=str)
    def cancelFavoriteIntent(self, key):
        return self._local_request(lambda: self._favorites_sync.manage(key, cancel=True))

    @Slot(str, 'QVariantList', result=str)
    def saveLocalPlaylist(self, name, songs):
        def save():
            value = self._favorites.save_playlist(name, songs)
            self.localPlaylistsChanged.emit()
            return value
        return self._local_request(save)

    @Slot(str, str, result=str)
    def renameLocalPlaylist(self, identifier, name):
        def rename():
            value = self._favorites.rename_playlist(identifier, name)
            self.localPlaylistsChanged.emit()
            return value
        return self._local_request(rename)

    @Slot(str, result=str)
    def loadLocalPlaylist(self, identifier):
        return self._local_request(lambda: self._favorites.load_playlist(identifier))

    @Slot()
    def refreshLocalPlaylists(self): self.localPlaylistsChanged.emit()

    @Property(bool, notify=favoritesSyncChanged)
    def favoritesSyncBusy(self): return bool(self._favorites_sync and self._favorites_sync.busy)

    @Property(int, notify=favoritesSyncChanged)
    def favoritesPendingCount(self): return self._favorites_sync.pending_count if self._favorites_sync else 0

    @Property('QVariantMap', notify=favoritesSyncChanged)
    def favoritesSyncProviders(self): return self._favorites_sync.providers if self._favorites_sync else {}

    @Slot('QVariantMap', result='QVariantMap')
    def favoriteSyncState(self, song):
        return self._favorites_sync.song_state(song) if self._favorites_sync else dict(state='error', pending=False, error=self._favorites_error)

    @Slot()
    def retryFavoritesSync(self):
        if not self._favorites_sync or self._closing: return
        if self._connected:
            self._send('host.invalidateMetadata', {}, lambda _v, _e: self._favorites_sync.refresh(), 10)
        else:
            self.start()

    def _favorites_changed(self, local=False):
        if self._closing: return
        if local:
            self._favorites_count = self._favorites.count
            self._favorite_keys = self._favorites.keys()
            self._favorites_revision += 1
            self.localFavoritesChanged.emit()
        self.favoritesSyncChanged.emit()

    def _favorites_session(self):
        if self._favorites_sync and not self._closing:
            self._favorites_sync.set_session(self._connected, self._snapshot.get('credentials', {}),
                                             self._snapshot.get('accountEpoch'))

    def _favorites_request(self, provider, operation, arguments, callback):
        epoch = self._snapshot.get('accountEpoch')
        def completed(value, error, _deliver):
            if operation == 'mutate':
                def invalidated(_value, _error):
                    if (not error and not self._closing and epoch == self._snapshot.get('accountEpoch')
                            and isinstance(value, dict) and value.get('verified')):
                        self.favoritePlatformChanged.emit(provider, str(arguments[1]['id']), bool(value['liked']))
                    callback(value, error)
                self._send('host.invalidateMetadata', {}, invalidated, 10)
            else:
                callback(value, error)
        self._metadata('/native/' + provider + '/' + operation, {'args': arguments}, True, {200},
                       still_current=lambda: not self._closing and epoch == self._snapshot.get('accountEpoch'),
                       on_complete=completed, catalog=False)

    @Property(bool, notify=localFavoritesChanged)
    def localFavoritesReady(self): return self._favorites is not None

    @Property(str, notify=localFavoritesChanged)
    def localFavoritesError(self): return self._favorites_error

    @Property(int, notify=localFavoritesChanged)
    def localFavoritesCount(self): return self._favorites_count

    @Property(int, notify=localFavoritesChanged)
    def localFavoritesRevision(self): return self._favorites_revision

    @Slot('QVariantMap', result=bool)
    def isLocalFavorite(self, song):
        return bool(self._favorites and self._favorites.contains(song))

    def _local_request(self, work, change=False):
        self._serial += 1
        key = str(self._serial)
        def run():
            try:
                if not self._favorites: raise ValueError(self._favorites_error or '本地收藏尚未就绪')
                value = work()
                self._favorites_error = ''
                if change:
                    self._favorites_count = self._favorites.count
                    self._favorites_revision += 1
                    self.localFavoritesChanged.emit()
                self.response.emit(key, json.dumps(value, ensure_ascii=False), '')
            except (OSError, ValueError, sqlite3.Error) as exc:
                self._favorites_error = str(exc)
                self.localFavoritesChanged.emit()
                self.response.emit(key, 'null', '本地收藏操作失败：' + str(exc))
        QTimer.singleShot(0, run)
        return key

    @Slot('QVariantMap', result=str)
    def toggleLocalFavorite(self, song):
        return self._local_request(lambda: self._favorites_sync.toggle(song))

    @Slot(str, int, result=str)
    def queryLocalFavorites(self, text, offset):
        return self._local_request(lambda: self._favorites.query(text, offset))

    @Slot(result=str)
    @Slot(str, result=str)
    def allLocalFavorites(self, text=''):
        return self._local_request(lambda: self._favorites.all(text))

    READ_OPERATIONS = frozenset({
        "search", "songs", "detail", "artistAlbums", "account", "userPlaylists",
        "likedIDs", "likedSongs", "likedAlbums", "discover", "categories",
        "lyrics", "subscriptionStatus", "capabilities", "vip", "trackPage",
    })
    LOGIN_ROUTES = frozenset({
        "/login/qr/key", "/login/qr/create", "/login/qr/check", "/login/qr/cancel",
        "/login/channels",
    })
    CONTROLS = frozenset({
        "player.radioStart", "player.radioStop", "player.radioRetry",
        "player.play", "player.enqueue", "player.toggle", "player.pause",
        "player.seek", "player.volume", "player.next", "player.remove",
        "player.stop", "player.quality", "player.mode", "player.move", "player.playIndex", "lyrics.offset",
        "lyrics.reset", "lyrics.global", "host.saveCredential", "host.logout",
    })
    MUTATIONS = {
        "like": ("/like", ("id",)),
        "subscribeAlbum": ("/album/sub", ("id",)),
        "subscribePlaylist": ("/playlist/subscribe", ("id",)),
        "createPlaylist": ("/playlist/create", ("name",)),
        "renamePlaylist": ("/playlist/name/update", ("id", "name")),
        "deletePlaylist": ("/playlist/delete", ("id",)),
        "playlistTracks": ("/playlist/tracks", ("pid", "tracks", "op")),
    }
    PREFERENCE_OPTIONS = {
        "close-behavior": ("quit", "tray"),
        "single-play-mode": ("replace", "append"),
        "motion": ("full", "reduced"),
    }

    def __init__(self, runtime: Path, parent: QObject | None = None, *, provider="qq"):
        super().__init__(parent)
        self.runtime = runtime.resolve()
        self._provider = provider if provider in ("qq", "netease") else "qq"
        self._switching = False
        self._platform_generation = 0
        self._favorites = None
        self._favorites_error = ""
        self._favorites_count = 0
        self._favorites_revision = 1
        self._favorite_keys = {}
        try:
            self._favorites = LocalFavorites(self.runtime / "data/miku-favorites.sqlite3")
            self._favorites_count = self._favorites.count
            self._favorite_keys = self._favorites.keys()
        except (OSError, ValueError, sqlite3.Error) as exc:
            self._favorites_error = "本地收藏无法读取，原资料已保留：" + str(exc)
        scope = (self.runtime / "data").as_posix()
        self.endpoint = "rhine-playback-" + hashlib.sha256(scope.encode()).hexdigest()[:24]
        self._snapshot: dict = {}
        self._snapshot_update: dict | None = None
        self._snapshot_is_patch = False
        self._error = ""
        self._connected = False
        self._attached = False
        self._closing = False
        self._buffer = bytearray()
        self._serial = 0
        self._pending: dict[str, tuple[Callable, float]] = {}
        self._process: subprocess.Popen | None = None
        self._attempts = 0
        self._spawned_this_attempt = False
        self._login_generation = 0
        self._login_key = ""
        self._write_busy = False
        self._write_error = ""
        self._preferences = {key: options[0] for key, options in self.PREFERENCE_OPTIONS.items()}
        self._preferences_ready = False
        self._preferences_busy = False
        self._preferences_error = ""
        self._preference_generation = 0
        self.socket = QLocalSocket(self)
        self.socket.readyRead.connect(self._read)
        self.socket.disconnected.connect(self._disconnected)
        self._timeouts = QTimer(self)
        self._timeouts.setInterval(1000)
        self._timeouts.timeout.connect(self._expire)
        self._timeouts.start()
        self._favorites_sync = FavoritesSync(self._favorites, self._favorites_request,
                                            self._favorites_changed) if self._favorites else None
        self.snapshotChanged.connect(self._favorites_session)
        self.connectedChanged.connect(self._favorites_session)
        self._favorites_timer = QTimer(self)
        self._favorites_timer.setInterval(300000)
        self._favorites_timer.timeout.connect(lambda: self._favorites_sync.refresh(import_all=False)
                                              if self._favorites_sync else None)
        self._favorites_timer.start()

    @Property("QVariantMap", notify=snapshotChanged)
    def snapshot(self):
        return self._snapshot

    @Property("QVariantMap", notify=snapshotChanged)
    def snapshotUpdate(self):
        # Progress updates must not re-convert hundreds of queue/history items
        # into temporary QML objects every tick. Keep the original native patch.
        return self._snapshot if self._snapshot_update is None else self._snapshot_update

    @Property(bool, notify=snapshotChanged)
    def snapshotIsPatch(self):
        return self._snapshot_is_patch

    @Property(bool, notify=connectedChanged)
    def connected(self):
        return self._connected and not self._switching

    @Property(bool, notify=connectedChanged)
    def serviceReconnecting(self): return bool(self._attempts and not self._connected)

    @Slot()
    def reconnectService(self): self.start()

    @Property(str, notify=providerChanged)
    def provider(self):
        return self._provider

    @Property(bool, notify=switchingChanged)
    def switching(self):
        return self._switching

    @Slot(str)
    def selectPlatform(self, provider):
        if provider not in ("qq", "netease") or provider == self._provider or not self.connected:
            return
        if self._write_busy:
            self._set_error("请等待当前修改完成后再切换平台")
            return
        old_provider, key = self._provider, self._login_key
        self._platform_generation += 1
        self._login_generation += 1
        self._login_key = ""
        self.platformReset.emit()
        self._provider = provider
        self.providerChanged.emit()
        self._send("host.selectCatalog", {"provider": provider})
        self._send("host.setPreference", {"key": "provider", "value": provider})
        if old_provider == "qq" and key:
            self._send("host.request", {"route": "/qq/login/qr/cancel", "values": {"key": key}}, timeout=5)
        self._set_error("")
        self.ready.emit()

    @Property(str, notify=errorChanged)
    def error(self):
        return self._error

    @Property(bool, notify=writeBusyChanged)
    def writeBusy(self):
        return self._write_busy

    @Property(str, notify=writeErrorChanged)
    def writeError(self):
        return self._write_error

    @Property("QVariantMap", notify=preferencesChanged)
    def preferences(self):
        return dict(self._preferences)

    @Property(bool, notify=preferencesStatusChanged)
    def preferencesReady(self):
        return self._preferences_ready

    @Property(bool, notify=preferencesStatusChanged)
    def preferencesBusy(self):
        return self._preferences_busy

    @Property(str, notify=preferencesStatusChanged)
    def preferencesError(self):
        return self._preferences_error

    def _set_error(self, value):
        self._error = value
        self.errorChanged.emit()

    @Slot()
    def start(self):
        if self._connected or self._closing or self._attempts:
            return
        executable = self.runtime / "RhinePlaybackService.exe"
        resources = self.runtime / "resources"
        if not executable.is_file() or not resources.is_dir():
            self._set_error("缺少原项目的后台播放组件，请检查 runtime 文件夹")
            return
        self._attempts = 1
        self._spawned_this_attempt = False
        self._buffer.clear()
        self._set_error('')
        self.connectedChanged.emit()
        self.socket.connectToServer(self.endpoint)
        if self.socket.waitForConnected(80):
            self._hello()
            return
        self.socket.abort()
        if self._process is not None and self._process.poll() is None:
            QTimer.singleShot(120, self._connect_attempt)
            return
        if not self._launch_service(): return
        QTimer.singleShot(120, self._connect_attempt)

    def _launch_service(self):
        try:
            self._spawned_this_attempt = True
            migrate_legacy_sessions(self.runtime / "data")
            gui = Path(sys.executable) if getattr(sys, "frozen", False) else self.runtime / "RHINE MUSIC DATABASE.exe"
            self._process = subprocess.Popen(
                [str(self.runtime / 'RhinePlaybackService.exe'), "--resources", str(self.runtime / 'resources'), "--gui",
                 str(gui)],
                cwd=self.runtime,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        except (OSError, ValueError) as exc:
            self._set_error(f"后台播放组件无法启动：{exc}")
            self._attempts = 0
            self.connectedChanged.emit()
            return False
        return True

    def _connect_attempt(self):
        if self._closing:
            return
        if not self._spawned_this_attempt and (self._process is None or self._process.poll() is not None):
            if not self._launch_service(): return
        self.socket.abort()
        self.socket.connectToServer(self.endpoint)
        if self.socket.waitForConnected(40):
            self._hello()
            return
        self._attempts += 1
        if self._attempts < 65:
            QTimer.singleShot(120, self._connect_attempt)
        else:
            self._set_error("播放服务连接超时，请稍后重新连接")
            self._attempts = 0
            self.connectedChanged.emit()

    def _hello(self):
        def checked(value, error):
            if error or value.get("protocol") != 3:
                self._set_error(error or "后台播放协议不兼容")
                self._attempts = 0
                self.connectedChanged.emit()
                return
            self._send("attach", {"pid": os.getpid()}, attached)

        def attached(value, error):
            if error:
                self._set_error(error)
                self._attempts = 0
                self.connectedChanged.emit()
                return
            if value.get("existing"):
                self.quitRequested.emit()
                return
            self._attached = True
            if not self._snapshot.get("mixedQueue"):
                self._set_error("后台组件需要与混合队列版本一起更新")
                return
            self._send("host.selectCatalog", {"provider": self._provider})
            self._send("host.setPreference", {"key": "provider", "value": self._provider})
            self._send("player.alternative", {"enabled": False})
            self._send("interface.ready", {})
            self._connected = True
            self._attempts = 0
            self._set_error('')
            self.connectedChanged.emit()
            self.refreshPreferences()
            self.ready.emit()

        self._send("hello", {}, checked)

    def _send(self, method, arguments, callback=None, timeout=90):
        self._serial += 1
        request_id = str(self._serial)
        callback = callback or (lambda _value, _error: None)
        if self.socket.state() != QLocalSocket.ConnectedState:
            QTimer.singleShot(0, lambda: callback({}, "后台播放组件未连接"))
            return request_id
        self._pending[request_id] = (callback, time.monotonic() + timeout)
        message = {"id": request_id, "method": method, "arguments": arguments}
        self.socket.write((json.dumps(message, ensure_ascii=False, separators=(",", ":")) + "\n").encode())
        self.socket.flush()
        return request_id

    def _read(self):
        self._buffer.extend(bytes(self.socket.readAll()))
        if len(self._buffer) > 64 * 1024 * 1024:
            self.socket.abort()
            self._set_error("后台播放数据超出大小限制")
            return
        while b"\n" in self._buffer:
            line, _, tail = self._buffer.partition(b"\n")
            self._buffer = bytearray(tail)
            try:
                message = json.loads(line)
            except (ValueError, UnicodeError):
                self._set_error("后台播放数据格式无效")
                continue
            if isinstance(message.get("snapshot"), dict):
                self._snapshot = message["snapshot"]
                self._snapshot_update = self._snapshot
                self._snapshot_is_patch = False
                self.snapshotChanged.emit()
            if isinstance(message.get("patch"), dict):
                self._snapshot_update = message["patch"]
                self._snapshot_is_patch = True
                self._snapshot = {**self._snapshot, **self._snapshot_update}
                self.snapshotChanged.emit()
            if message.get("event") == "activate":
                self.activateRequested.emit()
            elif message.get("event") == "quit":
                self.quitRequested.emit()
            entry = self._pending.pop(message.get("id"), None)
            if entry:
                entry[0](message.get("result", {}), message.get("error", ""))

    def _disconnected(self):
        if self._closing:
            return
        if self._connected or self._attached:
            self._connected = False
            self._attached = False
            self._attempts = 0
            state = {**self._snapshot.get('state', {}), 'playing': False, 'buffering': False,
                     'requested': False, 'error': '播放服务已断开，请重新连接'}
            self._snapshot_update = {'state': state, 'loading': False}
            self._snapshot = {**self._snapshot, **self._snapshot_update}
            self._snapshot_is_patch = True
            self.connectedChanged.emit()
            self.snapshotChanged.emit()
            self._set_error("播放服务已断开，请重新连接")
        pending, self._pending = self._pending, {}
        for callback, _deadline in pending.values():
            callback({}, "后台播放已断开")

    def _expire(self):
        now = time.monotonic()
        for request_id, (callback, deadline) in list(self._pending.items()):
            if deadline <= now:
                self._pending.pop(request_id, None)
                callback({}, "音乐请求超时，请稍后重试")

    def _reject(self, message):
        self._serial += 1
        request_id = str(self._serial)
        QTimer.singleShot(0, lambda: self.response.emit(request_id, "null", message))
        return request_id

    def _metadata(self, route, values, adapted, allowed, still_current=None, on_result=None, on_complete=None, catalog=True):
        request_id = ""
        epoch = self._snapshot.get("accountEpoch")
        generation = self._platform_generation

        def complete(value, error):
            def deliver():
                self.response.emit(request_id, json.dumps(value, ensure_ascii=False), error)
            if on_complete is not None:
                on_complete(value, error, deliver)
            else:
                deliver()

        def received(result, error):
            # Ignore a late QR success before accepting its cookies. UI-only
            # generation guards would run after that irreversible handoff.
            if (catalog and generation != self._platform_generation) or (still_current is not None and not still_current()):
                complete(None, "这次登录已取消")
                return
            if epoch != self._snapshot.get("accountEpoch"):
                complete(None, "账号已变化，请重新读取")
                return
            body = result.get("body")
            if error or not isinstance(body, dict):
                complete(None, error or "音乐接口数据格式无效")
                return
            if body.get("code", 200) not in allowed:
                complete({'authExpired': True} if body.get('authExpired') is True else None,
                         body.get("message") or body.get("msg") or "音乐接口暂时不可用")
                return
            if on_result is not None:
                on_result(body)
            def accepted(_value, accept_error):
                if (catalog and generation != self._platform_generation) or (still_current is not None and not still_current()):
                    complete(None, "平台或登录状态已变化")
                    return
                # Login cookies and private credential keys never reach QML.
                value = body.get("value") if adapted else {
                    key: val for key, val in body.items()
                    if key.lower() not in {"cookie", "cookies", "token", "qqsessions", "kugoucredentials"}
                }
                complete(value, accept_error)
            self._send("host.acceptCookies", {
                "json": json.dumps(result.get("cookies", [])),
                "epoch": result.get("_epoch", -1),
                "credentialKey": result.get("_credentialKey", ""),
            }, accepted)

        request_id = self._send("host.request", {"route": route, "values": values}, received)
        return request_id

    @Slot(str, "QVariantMap", result=str)
    def mutate(self, action, arguments):
        """Explicit write API; never smuggle writes through the read-query allowlist."""
        if not self.connected or not self._snapshot.get("credentials", {}).get(self._provider):
            return self._reject("请先登录当前平台")
        if self._write_busy:
            return self._reject("上一项修改尚未完成，请稍候")
        spec = self.MUTATIONS.get(action)
        if spec is None:
            return self._reject("不支持此编辑操作")
        route, required = spec
        values = {key: str(arguments.get(key, "")).strip() for key in required}
        if any(not value for value in values.values()):
            return self._reject("编辑信息不完整")
        if "name" in values and not 1 <= len(values["name"]) <= 20:
            return self._reject("歌单名称需要 1–20 字")
        if "op" in values and values["op"] not in {"add", "del"}:
            return self._reject("不支持此歌单操作")
        if any(len(values[key]) > 128 or any(c in values[key] for c in ",\r\n")
               for key in ("id", "pid", "tracks") if key in values):
            return self._reject("歌曲或歌单标识无效")
        self._write_busy = True
        self._write_error = ""
        self.writeBusyChanged.emit()
        self.writeErrorChanged.emit()

        def completed(value, error, deliver):
            # A failed write may have reached QQ. Invalidate cached reads, report
            # the result once, and require a fresh user action instead of retrying.
            self._write_error = error
            self.writeErrorChanged.emit()

            def invalidated(_value, _error):
                self._write_busy = False
                self.writeBusyChanged.emit()
                deliver()

            self._send("host.invalidateMetadata", {}, invalidated, 10)

        return self._metadata("/native/" + self._provider + "/mutate", {"args": [route, values]}, True, {200},
                              on_complete=completed)

    @Slot(result=str)
    def refreshPreferences(self):
        if not self.connected:
            return self._reject("播放服务尚未就绪")
        if self._preferences_busy:
            return self._reject("设置正在更新，请稍候")
        self._serial += 1
        request_id = str(self._serial)
        self._preference_generation += 1
        generation = self._preference_generation
        self._preferences_busy = True
        self._preferences_error = ""
        self.preferencesStatusChanged.emit()
        remaining = set(self.PREFERENCE_OPTIONS)
        values, errors = {}, []

        def received(key, result, error):
            if generation != self._preference_generation:
                return
            if error:
                errors.append(error)
            else:
                raw = str(result.get("value", ""))
                values[key] = raw if raw in self.PREFERENCE_OPTIONS[key] else self.PREFERENCE_OPTIONS[key][0]
            remaining.discard(key)
            if remaining:
                return
            self._preferences.update(values)
            self._preferences_busy = False
            self._preferences_ready = not errors
            self._preferences_error = errors[0] if errors else ""
            self.preferencesChanged.emit()
            self.preferencesStatusChanged.emit()
            self.response.emit(request_id, json.dumps(self._preferences), self._preferences_error)

        for key in self.PREFERENCE_OPTIONS:
            self._send("host.preference", {"key": key}, lambda result, error, k=key: received(k, result, error), 10)
        return request_id

    @Slot(str, str, result=str)
    def setPreference(self, key, value):
        if not self.connected:
            return self._reject("播放服务尚未就绪")
        if key not in self.PREFERENCE_OPTIONS or value not in self.PREFERENCE_OPTIONS[key]:
            return self._reject("不支持此设置")
        if self._preferences_busy:
            return self._reject("设置正在更新，请稍候")
        self._preferences_busy = True
        self._preferences_error = ""
        self.preferencesStatusChanged.emit()
        request_id = ""

        def received(result, error):
            self._preferences_busy = False
            self._preferences_error = error
            if not error:
                self._preferences[key] = value
                self.preferencesChanged.emit()
            self.preferencesStatusChanged.emit()
            self.response.emit(request_id, json.dumps({"key": key, "value": value}), error)

        request_id = self._send("host.setPreference", {"key": key, "value": value}, received, 10)
        return request_id

    @Slot(str, "QVariantList", result=str)
    def query(self, operation, args):
        if operation not in self.READ_OPERATIONS or not self.connected:
            return self._reject("音乐接口尚未就绪或不支持此操作")
        return self._metadata("/native/" + self._provider + "/" + operation, {"args": args}, True, {200})

    @Slot(str, str, 'QVariantList', result=str)
    def queryProvider(self, provider, operation, args):
        if provider not in ('qq', 'netease') or operation not in self.READ_OPERATIONS or not self.connected:
            return self._reject('音乐接口尚未就绪或不支持此操作')
        return self._metadata('/native/' + provider + '/' + operation, {'args': args}, True, {200}, catalog=False)

    @Slot(str, "QVariantMap", result=str)
    def loginRequest(self, route, parameters):
        if route not in self.LOGIN_ROUTES or not self.connected:
            return self._reject("登录接口尚未就绪或不支持此操作")
        allowed = {800, 801, 802, 803} if route == "/login/qr/check" else {200}
        prefix = "/qq" if self._provider == "qq" else ""
        if route == "/login/channels":
            return self._metadata(prefix + route, parameters, False, allowed)
        if route == "/login/qr/key":
            self._login_generation += 1
            self._login_key = ""
        elif route == "/login/qr/cancel":
            # An old dialog must not cancel a newer session owned by this UI.
            if parameters.get("key") == self._login_key:
                self._login_generation += 1
                self._login_key = ""
            return self._metadata(prefix + route, parameters, False, allowed)
        elif not self._login_key or parameters.get("key") != self._login_key:
            return self._reject("这次登录已取消，请重新生成二维码")
        generation = self._login_generation

        def remember_key(body):
            if route == "/login/qr/key":
                data = body.get("data") or {}
                self._login_key = body.get("unikey") or data.get("unikey") or ""

        return self._metadata(prefix + route, parameters, False, allowed,
                              lambda: generation == self._login_generation,
                              remember_key)

    @Slot(str, "QVariantMap", result=str)
    def control(self, command, arguments):
        if command not in self.CONTROLS or not self.connected:
            return self._reject("播放控制尚未就绪或不支持此操作")
        if command == 'player.radioStart':
            source = arguments.get('provider')
            if source not in ('qq', 'netease'):
                return self._reject('请选择电台所属平台')
            track = arguments.get('track')
            if track and (not isinstance(track, dict) or track.get('provider') != source or track.get('kind') != 'song'):
                return self._reject('请选择当前平台的推荐歌曲')
        if command in {"player.play", "player.enqueue"}:
            tracks = [arguments.get("track", {})] + arguments.get("source", [])
            if any(not isinstance(track, dict) or track.get("provider") not in ("qq", "netease") or track.get("kind") != "song" for track in tracks):
                return self._reject("请选择 QQ 音乐或网易云的歌曲")
        if command in {"host.logout", "player.quality"}:
            arguments = {**arguments, "provider": self._provider}
        if command == "host.logout":
            if self._write_busy:
                return self._reject("请等待当前修改完成后再退出账号")
            self._login_generation += 1
            self._login_key = ""
        request_id = ""
        def replied(value, error):
            if command == 'host.saveCredential' and not error and self._favorites_sync:
                # A fresh QR login may replace an account without changing the
                # public credential-presence booleans or the native epoch.
                self._favorites_sync.set_session(self._connected, self._snapshot.get('credentials', {}),
                                                 self._snapshot.get('accountEpoch'), force=True)
            self.response.emit(request_id, json.dumps(value, ensure_ascii=False), error)
        request_id = self._send(command, arguments, replied, 30)
        return request_id

    @Slot()
    def shutdown(self):
        if self._closing:
            return
        self._closing = True
        self._favorites_timer.stop()
        if self._favorites_sync: self._favorites_sync.close()
        if self._favorites:
            self._favorites.close()
            self._favorites = None
        self._timeouts.stop()
        if self._attached and self.socket.state() == QLocalSocket.ConnectedState:
            self._send("quit", {})
            self.socket.waitForBytesWritten(500)
        self.socket.disconnectFromServer()
        self._pending.clear()
        if self._process:
            try:
                self._process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self._process.terminate()
