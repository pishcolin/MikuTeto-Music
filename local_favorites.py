"""Player-owned mixed favorites. No credentials, audio bytes, or expiring streams."""
from __future__ import annotations
import json
from pathlib import Path
import sqlite3
import time
import uuid

PROVIDERS = {'qq', 'netease'}
TEXT_FIELDS = ('title', 'artist', 'album', 'albumID', 'songID', 'mediaId', 'mid',
               'subtitle', 'alias', 'publishTime', 'type', 'cover')

def normalize_song(song: dict) -> dict:
    if not isinstance(song, dict) or song.get('provider') not in PROVIDERS or song.get('kind') != 'song':
        raise ValueError('只能收藏 QQ 音乐或网易云的歌曲')
    identifier = str(song.get('id') or '').strip()
    if not identifier or len(identifier) > 128 or any(c in identifier for c in '\r\n\x00'):
        raise ValueError('歌曲标识无效')
    result = dict(provider=song['provider'], kind='song', id=identifier,
                  key=f"{song['provider']}:song:{identifier}")
    for key in TEXT_FIELDS:
        value = song.get(key)
        if isinstance(value, (str, int, float)):
            result[key] = str(value)[:4096 if key == 'cover' else 1024]
    if result.get('cover') and not result['cover'].startswith(('https://', 'http://')):
        result.pop('cover')
    for key in ('duration', 'disc', 'track', 'fee', 'copyright', 'songType'):
        value = song.get(key)
        if isinstance(value, (int, float)) and 0 <= value < 1e12:
            result[key] = value
    result['artists'] = [
        {key: str(a[key])[:1024] for key in ('id', 'name', 'title', 'cover') if isinstance(a.get(key), (str, int))}
        for a in song.get('artists', [])[:50] if isinstance(a, dict)
    ] if isinstance(song.get('artists'), list) else []
    if song.get('deferred'): result['deferred'] = True
    return result

class LocalFavorites:
    PAGE_SIZE = 60

    def __init__(self, path: Path):
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(path, timeout=2)
        self.db.execute('PRAGMA cache_size=-2048')
        self.db.execute('PRAGMA synchronous=FULL')
        version = self.db.execute('PRAGMA user_version').fetchone()[0]
        if version not in (0, 1, 2, 3):
            self.db.close()
            raise ValueError('收藏资料版本较新，请使用新版播放器')
        with self.db:
            self.db.execute('CREATE TABLE IF NOT EXISTS favorites ('
                'provider TEXT NOT NULL, id TEXT NOT NULL, song TEXT NOT NULL, '
                'search_text TEXT NOT NULL, added_ns INTEGER NOT NULL, '
                'PRIMARY KEY(provider,id))')
            self.db.execute('CREATE INDEX IF NOT EXISTS favorites_order ON favorites(added_ns DESC)')
            self.db.execute('CREATE TABLE IF NOT EXISTS favorite_intents ('
                'provider TEXT NOT NULL, id TEXT NOT NULL, account TEXT NOT NULL, '
                'desired INTEGER NOT NULL, song TEXT NOT NULL, version INTEGER NOT NULL, '
                'state TEXT NOT NULL, error TEXT NOT NULL, PRIMARY KEY(provider,id))')
            self.db.execute('CREATE TABLE IF NOT EXISTS favorite_accounts ('
                'provider TEXT PRIMARY KEY, account TEXT NOT NULL)')
            if 'origin' not in {r[1] for r in self.db.execute('PRAGMA table_info(favorites)')}:
                self.db.execute("ALTER TABLE favorites ADD COLUMN origin TEXT NOT NULL DEFAULT 'legacy'")
            self.db.execute('CREATE TABLE IF NOT EXISTS local_playlists ('
                'id TEXT PRIMARY KEY, name TEXT NOT NULL COLLATE NOCASE UNIQUE, updated_ns INTEGER NOT NULL)')
            self.db.execute('CREATE TABLE IF NOT EXISTS local_playlist_tracks ('
                'playlist TEXT NOT NULL, position INTEGER NOT NULL, song TEXT NOT NULL, '
                'PRIMARY KEY(playlist,position))')
            self.db.execute('CREATE INDEX IF NOT EXISTS favorite_intents_state '
                            'ON favorite_intents(provider,account,state,version)')
            self.db.execute('PRAGMA user_version=3')

    @property
    def count(self):
        return self.db.execute('SELECT count(*) FROM favorites').fetchone()[0]

    def contains(self, song):
        if not isinstance(song, dict): return False
        return self.db.execute('SELECT 1 FROM favorites WHERE provider=? AND id=?',
            (song.get('provider'), str(song.get('id', '')))).fetchone() is not None

    def toggle(self, song):
        song = normalize_song(song)
        key = (song['provider'], song['id'])
        with self.db:
            if self.contains(song):
                self.db.execute('DELETE FROM favorites WHERE provider=? AND id=?', key)
                return False
            self._put(song, origin='local')
        return True

    def _put(self, song, added_ns=None, origin='local'):
        searchable = ' '.join([song.get('title', ''), song.get('artist', ''), song.get('album', '')] +
            [a.get('name', a.get('title', '')) for a in song['artists']]).casefold()
        encoded = json.dumps(song, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
        before = self.db.total_changes
        self.db.execute('INSERT INTO favorites(provider,id,song,search_text,added_ns,origin) '
            'VALUES (?,?,?,?,?,?) ON CONFLICT(provider,id) DO UPDATE SET '
            'song=excluded.song, search_text=excluded.search_text '
            'WHERE favorites.song != excluded.song OR favorites.search_text != excluded.search_text',
            (song['provider'], song['id'], encoded, searchable,
             added_ns if added_ns is not None else time.time_ns(), origin))
        return self.db.total_changes > before

    def account(self, provider):
        row = self.db.execute('SELECT account FROM favorite_accounts WHERE provider=?', (provider,)).fetchone()
        return row[0] if row else ''

    def remember_account(self, provider, account):
        with self.db:
            self.db.execute('INSERT INTO favorite_accounts VALUES (?,?) ON CONFLICT(provider) '
                'DO UPDATE SET account=excluded.account WHERE favorite_accounts.account!=excluded.account', (provider, account))
            # A click before the very first login is assigned once, never transferred later.
            self.db.execute("UPDATE favorite_intents SET account=? WHERE provider=? AND account=''",
                            (account, provider))

    def set_desired(self, song, desired, account=''):
        song = normalize_song(song)
        key = (song['provider'], song['id'])
        version = max(time.time_ns(), self.intent_revision + 1)
        with self.db:
            old = self.db.execute('SELECT version FROM favorite_intents WHERE provider=? AND id=?', key).fetchone()
            if old: version = max(version, old[0] + 1)
            if desired: self._put(song)
            else: self.db.execute('DELETE FROM favorites WHERE provider=? AND id=?', key)
            self.db.execute('INSERT INTO favorite_intents VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(provider,id) '
                'DO UPDATE SET account=excluded.account, desired=excluded.desired, song=excluded.song, '
                'version=excluded.version, state=excluded.state, error=excluded.error',
                (*key, account, int(desired), json.dumps(song, ensure_ascii=False), version, 'pending', ''))
        return version

    @property
    def intent_revision(self):
        return self.db.execute('SELECT coalesce(max(version),0) FROM favorite_intents').fetchone()[0]

    def intents(self, provider=None, account=None, state=None):
        clauses, values = ["state IN ('pending','error')"], []
        for column, value in (('provider', provider), ('account', account), ('state', state)):
            if value is not None:
                clauses.append(column+'=?'); values.append(value)
        rows = self.db.execute('SELECT provider,id,account,desired,song,version,state,error '
            'FROM favorite_intents WHERE '+' AND '.join(clauses)+' ORDER BY version', values)
        return [dict(provider=r[0], id=r[1], account=r[2], desired=bool(r[3]), song=json.loads(r[4]),
                     version=r[5], state=r[6], error=r[7]) for r in rows]

    def intent(self, provider, identifier):
        row = self.db.execute('SELECT provider,id,account,desired,song,version,state,error '
            'FROM favorite_intents WHERE provider=? AND id=?', (provider, str(identifier))).fetchone()
        return dict(provider=row[0], id=row[1], account=row[2], desired=bool(row[3]), song=json.loads(row[4]),
                    version=row[5], state=row[6], error=row[7]) if row else None

    def cancel_intent(self, job):
        # Keep an explicit local-only tombstone. A later import must not undo it.
        with self.db:
            self.db.execute("UPDATE favorite_intents SET state='cancelled',error='' "
                "WHERE provider=? AND id=? AND version=?", (job['provider'], job['id'], job['version']))

    def retry_intent(self, job):
        with self.db:
            self.db.execute("UPDATE favorite_intents SET state='pending',error='' "
                "WHERE provider=? AND id=? AND version=? AND state='error'",
                (job['provider'], job['id'], job['version']))

    def finish_intent(self, job, error=''):
        with self.db:
            self.db.execute('UPDATE favorite_intents SET state=?,error=? WHERE provider=? AND id=? '
                'AND version=? AND account=?', ('error' if error else 'synced', error[:1000],
                job['provider'], job['id'], job['version'], job['account']))

    def retry_intents(self, provider, account):
        with self.db:
            self.db.execute("UPDATE favorite_intents SET state='pending',error='' "
                "WHERE provider=? AND account=? AND state='error'", (provider, account))

    def merge_page(self, provider, songs, started_ns, order_ns=None, offset=0):
        normalized = [normalize_song(song) for song in songs]
        if any(s['provider'] != provider for s in normalized):
            raise ValueError('收藏歌曲来源不匹配')
        changed = False
        order_ns = time.time_ns() if order_ns is None else order_ns
        with self.db:
            for index, song in enumerate(normalized):
                intent = self.db.execute('SELECT desired,version,state FROM favorite_intents '
                    'WHERE provider=? AND id=?', (provider, song['id'])).fetchone()
                # A late import must never undo a click made while it was loading.
                if intent and not intent[0] and (intent[2] != 'synced' or intent[1] > started_ns):
                    continue
                rank = order_ns - offset - index
                changed = self._put(song, rank, 'import') or changed
                # Repair v2's reverse order once, only for imported/legacy rows
                # with no explicit local action. User-click ordering is preserved.
                if not intent:
                    row = self.db.execute("UPDATE favorites SET added_ns=?,origin='import' "
                        "WHERE provider=? AND id=? AND origin='legacy'",
                        (rank, provider, song['id']))
                    changed = row.rowcount > 0 or changed
        return changed

    def query(self, text='', offset=0):
        text = str(text or '')[:512].casefold()
        pattern = '%' + text.replace('\\','\\\\').replace('%','\\%').replace('_','\\_') + '%'
        offset = max(0,int(offset))
        where, args = (" WHERE search_text LIKE ? ESCAPE '\\'", (pattern,)) if text else ('', ())
        with self.db:
            total = self.db.execute('SELECT count(*) FROM favorites'+where,args).fetchone()[0]
            rows = self.db.execute('SELECT song FROM favorites'+where+
                ' ORDER BY added_ns DESC, provider, id LIMIT ? OFFSET ?',(*args,self.PAGE_SIZE,offset)).fetchall()
        items = [json.loads(row[0]) for row in rows]
        return dict(items=items,total=total,rawCount=len(items),more=offset+len(items)<total)

    def all(self, text=''):
        text = str(text or '')[:512].casefold()
        pattern = '%' + text.replace('\\','\\\\').replace('%','\\%').replace('_','\\_') + '%'
        where, args = (" WHERE search_text LIKE ? ESCAPE '\\'", (pattern,)) if text else ('', ())
        return [json.loads(row[0]) for row in self.db.execute(
            'SELECT song FROM favorites'+where+' ORDER BY added_ns DESC, provider, id', args)]

    def keys(self):
        return {f'{p}:song:{i}': True for p, i in self.db.execute('SELECT provider,id FROM favorites')}

    @staticmethod
    def _name(value):
        value = str(value or '').strip()
        if not 1 <= len(value) <= 40 or any(ord(c) < 32 for c in value):
            raise ValueError('本地歌单名称需要 1–40 字，不能包含换行')
        return value

    def playlists(self):
        return [dict(id=r[0], name=r[1], updatedAt=r[2] // 1000000, count=r[3]) for r in self.db.execute(
            'SELECT p.id,p.name,p.updated_ns,count(t.position) FROM local_playlists p '
            'LEFT JOIN local_playlist_tracks t ON t.playlist=p.id GROUP BY p.id ORDER BY p.updated_ns DESC')]

    def save_playlist(self, name, songs):
        name = self._name(name)
        if not isinstance(songs, list) or not songs: raise ValueError('播放队列还是空的')
        if len(songs) > 20000: raise ValueError('每个本地歌单最多保存 20000 首歌曲')
        items = [normalize_song(song) for song in songs]
        identifier, stamp = uuid.uuid4().hex, time.time_ns()
        try:
            with self.db:
                self.db.execute('INSERT INTO local_playlists VALUES (?,?,?)', (identifier, name, stamp))
                self.db.executemany('INSERT INTO local_playlist_tracks VALUES (?,?,?)',
                    [(identifier, i, json.dumps(song, ensure_ascii=False)) for i, song in enumerate(items)])
        except sqlite3.IntegrityError:
            raise ValueError('已有同名本地歌单，请换个名称') from None
        return dict(id=identifier, name=name, count=len(items), updatedAt=stamp // 1000000)

    def rename_playlist(self, identifier, name):
        name = self._name(name)
        try:
            with self.db:
                row = self.db.execute('UPDATE local_playlists SET name=?,updated_ns=? WHERE id=?',
                                      (name, time.time_ns(), identifier))
                if not row.rowcount: raise ValueError('没有找到这个本地歌单')
        except sqlite3.IntegrityError:
            raise ValueError('已有同名本地歌单，请换个名称') from None
        return next(p for p in self.playlists() if p['id'] == identifier)

    def load_playlist(self, identifier):
        playlist = next((p for p in self.playlists() if p['id'] == identifier), None)
        if not playlist: raise ValueError('没有找到这个本地歌单')
        items = [json.loads(r[0]) for r in self.db.execute('SELECT song FROM local_playlist_tracks '
            'WHERE playlist=? ORDER BY position', (identifier,))]
        return dict(playlist=playlist, items=items)

    def close(self):
        self.db.close()
