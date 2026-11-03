"""One-time, backed-up migration from two theme queues to a shared queue."""
from pathlib import Path
import json
from PySide6.QtCore import QSaveFile, QIODevice, QSettings
from local_favorites import normalize_song

def _write(path, value):
    data = json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode()
    f = QSaveFile(str(path))
    if not f.open(QIODevice.WriteOnly) or f.write(data) != len(data) or not f.commit():
        raise OSError('未能保存混合队列升级资料')

def migrate_legacy_sessions(directory: Path):
    marker = directory / 'miku-mixed-queue-v1.json'
    if marker.exists(): return
    directory.mkdir(parents=True, exist_ok=True)
    bookmarks = directory / 'miku-platform-sessions.json'
    if not bookmarks.exists():
        _write(marker, {'version': 1, 'legacyQueues': False})
        return
    saved = json.loads(bookmarks.read_text('utf-8'))
    sessions = saved.get('sessions', {})
    if saved.get('version') != 1 or not isinstance(sessions, dict):
        raise ValueError('旧版播放记录格式无法识别，原资料已保留')
    playback_path = directory / 'playback-session.json'
    active = json.loads(playback_path.read_text('utf-8')) if playback_path.exists() else {}
    if not isinstance(active, dict): raise ValueError('旧版队列格式无法识别，原资料已保留')
    backup = directory / 'miku-playback-before-mixed.json'
    if not backup.exists(): _write(backup, active)
    queue, seen = [], set()
    candidates = list(active.get('queue') or [])
    current = active.get('current') or {}
    if current and not candidates: candidates.insert(0, current)
    for provider in ('qq', 'netease'):
        session = sessions.get(provider) or {}
        if not isinstance(session, dict): continue
        candidates.extend(session.get('queue') or [])
    for track in candidates:
        try: song = normalize_song(track)
        except (ValueError, TypeError): continue
        key = song['key']
        if key not in seen: queue.append(song); seen.add(key)
    index = next((i for i, t in enumerate(queue) if t['provider'] == current.get('provider')
                  and t['id'] == str(current.get('id', ''))), -1)
    if current and index < 0:
        song = normalize_song(current); queue.insert(0, song); index = 0
    active.update(queue=queue, index=index, requested=False)
    active.setdefault('position', 0)
    active.setdefault('mode', 'all')
    _write(playback_path, active)
    settings = QSettings(str(directory/'settings.ini'), QSettings.IniFormat)
    for provider in ('qq', 'netease'):
        quality = (sessions.get(provider) or {}).get('quality')
        key = 'panel/quality-' + provider
        if quality and not settings.contains(key): settings.setValue(key, quality)
    settings.sync()
    _write(marker, {'version': 1, 'legacyQueues': True, 'mergedTracks': len(queue)})
