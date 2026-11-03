from pathlib import Path
import json, sqlite3, sys, time, unittest
from collections import deque

work = Path(__file__).resolve().parent
sys.path.insert(0, str(work.parent))
from local_favorites import LocalFavorites
from favorites_sync import FavoritesSync

import tempfile
root = Path(tempfile.mkdtemp(prefix='mikuteto-sync-checks-'))

def song(provider, id):
    return dict(provider=provider, kind='song', id=str(id), title=f'Song {id}', artist='Artist')

class Service:
    def __init__(self, db):
        self.db = db
        self.accounts = {'qq':'Q-A', 'netease':'N-A'}
        self.remote = {'qq':[], 'netease':[]}
        self.queue, self.writes = deque(), []
        self.failure = ''
        self.sync = FavoritesSync(db, self.request, lambda local: None)

    def request(self, p, op, args, cb): self.queue.append((p, op, args, cb))
    def connect(self, epoch=1, qq=True, netease=True):
        self.sync.set_session(True, dict(qq=qq, netease=netease), epoch)

    def step(self):
        p, op, args, cb = self.queue.popleft()
        if op == 'account': cb([self.accounts[p], 'test'], '')
        elif op == 'likedSongs':
            off, size = args[0], (100 if p == 'qq' else 60)
            rows = self.remote[p][off:off+size]
            cb(dict(items=rows, total=len(self.remote[p]), more=off+len(rows)<len(self.remote[p]), rawCount=len(rows)), '')
        else:
            values = args[1]
            self.writes.append((p, dict(values)))
            if self.failure: cb(None, self.failure); return
            assert values['account'] == self.accounts[p]
            rows = self.remote[p]
            rows[:] = [s for s in rows if s['id'] != values['id']]
            if values['liked']: rows.insert(0, song(p, values['id']))
            cb(dict(verified=True, liked=values['liked']), '')

    def drain(self):
        n = 0
        while self.queue:
            self.step(); n += 1
            assert n < 500, 'unbounded retry'

class Checks(unittest.TestCase):
    def setUp(self):
        self.path = root/(self.id().split('.')[-1]+'.sqlite3')
        self.db = LocalFavorites(self.path)
        self.service = Service(self.db)
        self.sync = self.service.sync
    def tearDown(self): self.sync.close(); self.db.close()

    def test_all_pages_union_dedupe_preserve_legacy(self):
        self.db.toggle(song('qq', 'legacy'))
        self.service.remote['qq'] = [song('qq', i) for i in range(205)]
        self.service.remote['netease'] = [song('netease', i) for i in range(125)]
        self.service.connect(); self.service.drain()
        self.assertEqual(self.db.count, 331)
        self.sync.refresh(); self.service.drain()
        self.assertEqual(self.db.count, 331)
        self.assertFalse(self.service.writes)
        self.assertEqual(self.sync.providers['netease']['imported'], 125)

    def test_heart_targets_song_provider_and_rapid_toggle(self):
        self.service.connect(); self.service.drain()
        track = song('netease', '9')
        self.sync.toggle(track)
        self.sync.toggle(track)  # before first platform response
        self.service.drain()
        self.assertFalse(self.db.contains(track))
        self.assertEqual([(p, v['liked']) for p, v in self.service.writes], [('netease',True), ('netease',False)])
        self.assertEqual(self.sync.pending_count, 0)

    def test_failed_write_durable_and_never_sent_to_other_account(self):
        self.service.connect(); self.service.drain()
        self.service.failure = 'offline'
        self.sync.toggle(song('qq', 7)); self.service.drain()
        self.assertEqual(self.sync.pending_count, 1)
        self.assertTrue(self.db.contains(song('qq', 7)))
        self.sync.close(); self.db.close()
        self.db = LocalFavorites(self.path)
        self.service = Service(self.db); self.sync = self.service.sync
        self.service.accounts['qq'] = 'Q-B'
        self.service.connect(); self.service.drain()
        self.assertFalse(self.service.writes)
        self.assertIn('原账号', self.sync.providers['qq']['error'])
        self.service.accounts['qq'] = 'Q-A'
        self.service.connect(epoch=2); self.service.drain()
        self.assertEqual(len(self.service.writes), 1)
        self.assertEqual(self.sync.pending_count, 0)

    def test_signed_out_click_binds_first_login_once(self):
        self.sync.toggle(song('netease', 1))
        self.assertFalse(self.service.queue)
        self.service.connect(); self.service.drain()
        self.assertEqual(self.service.writes[0][1]['account'], 'N-A')

    def test_stale_import_cannot_undo_unlike_after_remote_ack(self):
        track = song('qq', 1)
        self.db.toggle(track)
        self.service.remote['qq'] = [track]
        self.service.connect(netease=False)
        self.service.step()  # account -> queued import
        old = self.service.queue.popleft()
        self.sync.toggle(track)
        self.service.step()  # write succeeds before stale import response
        old[3](dict(items=[track], total=1, rawCount=1, more=False), '')
        self.service.drain()
        self.assertFalse(self.db.contains(track))
        self.assertEqual(self.sync.pending_count, 0)

    def test_logout_cancels_old_account_response(self):
        self.service.connect()
        previous = list(self.service.queue); self.service.queue.clear()
        self.sync.set_session(True, dict(qq=False, netease=False), 2)
        for _p, _op, _args, cb in previous: cb(['old', 'old'], '')
        self.assertFalse(self.service.queue)
        self.assertFalse(self.sync.accounts)
        self.assertFalse(self.sync.busy)

    def test_partial_import_error_keeps_imported_and_legacy(self):
        self.db.toggle(song('netease', 'legacy'))
        self.service.remote['netease'] = [song('netease', i) for i in range(70)]
        self.service.connect(qq=False)
        self.service.step(); self.service.step()
        last = self.service.queue.popleft(); last[3](None, 'offline')
        self.assertEqual(self.db.count, 61)
        self.assertEqual(self.sync.providers['netease']['state'], 'error')
        self.sync.refresh(); self.service.drain()
        self.assertEqual(self.db.count, 71)

    def test_repeat_page_detected(self):
        self.service.connect(netease=False); self.service.step()
        value = dict(items=[song('qq', 1)], rawCount=1, total=100, more=True)
        self.service.queue.popleft()[3](value, '')
        self.service.queue.popleft()[3](value, '')
        self.assertFalse(self.service.queue)
        self.assertEqual(self.sync.providers['qq']['state'], 'error')

    def test_missing_metadata_rows_do_not_stop_pagination(self):
        self.service.connect(netease=False); self.service.step()
        self.service.queue.popleft()[3](dict(items=[],rawCount=100,total=101,more=True), '')
        req = self.service.queue.popleft()
        self.assertEqual(req[2], [100])
        req[3](dict(items=[song('qq',101)],rawCount=1,total=101,more=False), '')
        self.assertEqual(self.db.count, 1)

    def test_import_rejects_misrouted_platform(self):
        self.service.connect(netease=False); self.service.step()
        self.service.queue.popleft()[3](dict(items=[song('netease',1)],rawCount=1,total=1), '')
        self.assertEqual(self.db.count, 0)
        self.assertEqual(self.sync.providers['qq']['state'], 'error')

    def test_force_session_reset_handles_account_replacement_same_epoch(self):
        self.service.connect(); self.service.drain()
        self.service.accounts['qq'] = 'Q-B'
        self.sync.set_session(True, dict(qq=True, netease=True), 1, force=True)
        self.service.drain()
        self.assertEqual(self.sync.accounts['qq'], 'Q-B')

    def test_upgrade_legacy_database_keeps_songs(self):
        legacy = root/'old-v1.sqlite3'
        con = sqlite3.connect(legacy)
        con.execute('CREATE TABLE favorites(provider TEXT,id TEXT,song TEXT,search_text TEXT,added_ns INTEGER,PRIMARY KEY(provider,id))')
        con.execute('INSERT INTO favorites VALUES (?,?,?,?,?)', ('qq','old',json.dumps(song('qq','old')),'old',1))
        con.execute('PRAGMA user_version=1'); con.commit(); con.close()
        db = LocalFavorites(legacy)
        self.assertEqual(db.count, 1)
        self.assertEqual(db.db.execute('PRAGMA user_version').fetchone()[0], 3)
        db.close()

    def test_import_order_is_stable_and_unchanged_sync_has_zero_writes(self):
        tracks = [song('qq', i) for i in range(130)]
        self.service.remote['qq'] = tracks
        changes = []
        self.sync.changed = changes.append
        self.service.connect(netease=False); self.service.drain()
        self.assertEqual([s['id'] for s in self.db.all()], [s['id'] for s in tracks])
        before = self.db.db.total_changes; changes.clear()
        self.sync.refresh(); self.service.drain()
        self.assertEqual(self.db.db.total_changes, before)
        self.assertNotIn(True, changes)
        self.assertEqual(len(self.db.all('Song')), 130)
        self.assertEqual(len(self.db.query('Song')['items']), 60)

    def test_one_time_legacy_order_repair_keeps_explicit_local_order(self):
        tracks = [song('qq', i) for i in range(5)]
        self.db.merge_page('qq', tracks, 0)
        self.db.db.execute("UPDATE favorites SET origin='legacy',added_ns=cast(id AS INTEGER)")
        self.db.db.commit()
        self.db.set_desired(tracks[3], True, 'Q-A')
        stamp = 10000
        self.db.merge_page('qq', tracks[:2], self.db.intent_revision, stamp, 0)
        self.db.merge_page('qq', tracks[2:], self.db.intent_revision, stamp, 2)
        self.assertEqual([s['id'] for s in self.db.all()], ['0','1','2','4','3'])
        before = self.db.db.total_changes
        self.db.merge_page('qq', tracks, self.db.intent_revision, 20000, 0)
        self.assertEqual(before, self.db.db.total_changes)

    def test_background_tick_does_not_import_idle_library(self):
        self.service.connect(); self.service.drain()
        self.sync.refresh(import_all=False)
        self.assertFalse(self.service.queue)

    def test_pending_management_never_transfers_accounts(self):
        self.service.connect(); self.service.drain()
        self.service.failure = 'offline'
        track = song('qq', 7)
        self.sync.toggle(track); self.service.drain()
        self.service.accounts['qq'] = 'Q-B'
        self.service.connect(epoch=2); self.service.drain()
        status = self.sync.pending_items[0]
        self.assertEqual(status['reason'], 'account')
        self.assertFalse(status['canRetry']); self.assertTrue(status['canDiscard'])
        with self.assertRaises(ValueError): self.sync.manage(status['key'])
        self.sync.manage(status['key'], cancel=True)
        self.assertTrue(self.db.contains(track)); self.assertEqual(self.sync.pending_count, 0)
        self.service.failure = ''; self.sync.refresh(); self.service.drain()
        self.assertEqual(len(self.service.writes), 1)
        self.assertEqual(self.sync.song_state(track)['state'], 'local')

    def test_cannot_cancel_active_write_and_cancelled_unlike_stays_local(self):
        self.service.connect(); self.service.drain()
        track = song('qq', 5)
        self.sync.toggle(track)
        status = self.sync.pending_items[0]
        self.assertEqual(status['state'], 'syncing'); self.assertFalse(status['canDiscard'])
        with self.assertRaises(ValueError): self.sync.manage(status['key'], cancel=True)
        self.service.drain()
        self.service.failure = 'offline'
        self.sync.toggle(track); self.service.drain()
        self.sync.manage(status['key'], cancel=True)
        self.db.merge_page('qq', [track], self.db.intent_revision)
        self.assertFalse(self.db.contains(track))

    def test_named_mixed_playlists_persist_and_keep_order_without_credentials(self):
        items = [song('qq', 'same'), dict(song('netease', 'same'), token='secret', url='audio')]
        saved = self.db.save_playlist('夜间混合', items)
        second = self.db.save_playlist('通勤', list(reversed(items)))
        self.assertEqual(len(self.db.playlists()), 2)
        self.assertEqual(self.db.load_playlist(saved['id'])['items'][1]['provider'], 'netease')
        self.assertNotIn('secret', json.dumps(self.db.load_playlist(saved['id'])))
        self.db.rename_playlist(saved['id'], '夜间电台')
        with self.assertRaises(ValueError): self.db.rename_playlist(saved['id'], '通勤')
        self.db.close(); self.db = LocalFavorites(self.path)
        self.assertEqual(self.db.load_playlist(saved['id'])['playlist']['name'], '夜间电台')
        self.assertEqual(self.db.load_playlist(second['id'])['items'][0]['provider'], 'netease')
        self.assertEqual(self.db.count, 0)

    def test_expired_session_exposes_login_and_blocks_pending_write(self):
        self.service.connect(); self.service.drain()
        self.sync.refresh('qq')
        request = self.service.queue.popleft()
        request[3]({'authExpired': True}, '登录已失效')
        self.assertEqual(self.sync.providers['qq']['reason'], 'login')
        self.assertTrue(self.sync.providers['qq']['canLogin'])
        self.assertFalse(self.sync.providers['qq']['canRetry'])
        self.sync.toggle(song('qq', 8))
        self.assertFalse(self.service.queue)
        self.assertFalse(self.service.writes)
        self.assertEqual(self.sync.pending_items[0]['reason'], 'login')

if __name__ == '__main__': unittest.main(verbosity=2)
