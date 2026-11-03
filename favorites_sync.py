"""Small callback-driven, account-bound favorites synchronizer (no extra process)."""
from __future__ import annotations
import time

PROVIDERS = ('qq', 'netease')


class FavoritesSync:
    def __init__(self, db, request, changed):
        self.db, self.request, self.changed = db, request, changed
        self.generation = 0
        self.session = None
        self.connected = False
        self.credentials = {}
        self.accounts = {}
        self.loading, self.importing, self.writing = set(), set(), {}
        self.errors = {}
        self.login_required = set()
        self.reimport = set()
        self.imported = {p: 0 for p in PROVIDERS}
        self.closed = False

    def set_session(self, connected, credentials, epoch, force=False):
        signature = (bool(connected), epoch, *(bool(credentials.get(p)) for p in PROVIDERS))
        if (signature == self.session and not force) or self.closed:
            return
        self.session = signature
        self.connected, self.credentials = bool(connected), dict(credentials)
        self.generation += 1
        self.accounts.clear()
        self.loading.clear(); self.importing.clear(); self.writing.clear(); self.errors.clear(); self.reimport.clear()
        self.login_required.clear()
        self.refresh()

    @property
    def busy(self):
        return bool(self.loading or self.importing or self.writing)

    @property
    def pending_count(self):
        return len(self.db.intents())

    def _job_status(self, job):
        provider = job['provider']
        active = self.writing.get(provider)
        writing = bool(active and active['id'] == job['id'])
        mismatch = bool(self.accounts.get(provider) and job['account'] not in ('', self.accounts[provider]))
        reason = ('offline' if not self.connected else 'login' if not self.credentials.get(provider) or provider in self.login_required
                  else 'account' if mismatch else 'network' if job['error'] else '')
        error = ('等待切回原账号同步' if mismatch else job['error'])
        return dict(state='syncing' if writing else 'error' if error else 'pending',
                    error=error, reason=reason, pending=True,
                    canRetry=bool(self.connected and self.credentials.get(provider) and provider not in self.login_required and not mismatch
                                  and provider not in self.writing and provider not in self.loading),
                    canDiscard=not writing)

    @property
    def pending_items(self):
        return [dict(key=j['song']['key'], song=j['song'], provider=j['provider'], desired=j['desired'],
                     **self._job_status(j)) for j in self.db.intents()]

    @property
    def states(self):
        return {j['song']['key']: self._job_status(j) for j in self.db.intents()}

    def manage(self, key, cancel=False):
        job = next((j for j in self.db.intents() if j['song']['key'] == key), None)
        if not job: return
        status = self._job_status(job)
        if cancel:
            if not status['canDiscard']: raise ValueError('平台写入中，请等待结果后再操作')
            self.db.cancel_intent(job)
        else:
            if not status['canRetry']: raise ValueError('请先连接服务并登录这项操作原来绑定的账号')
            self.db.retry_intent(job)
            if self.accounts.get(job['provider']): self._pump(job['provider'])
            else: self._load_account(job['provider'], import_all=False)
        self.changed(False)

    @property
    def providers(self):
        out = {}
        jobs = self.db.intents()
        for provider in PROVIDERS:
            pending = [j for j in jobs if j['provider'] == provider]
            error = self.errors.get(provider, '') or next((j['error'] for j in pending if j['error']), '')
            if (self.accounts.get(provider) and any(j['account'] and j['account'] != self.accounts[provider]
                                                  for j in pending)):
                error = '部分操作等待切回原账号后同步'
            state = ('syncing' if provider in self.writing else
                     'loading' if provider in self.loading or provider in self.importing else
                     'signedOut' if not self.credentials.get(provider) or provider in self.login_required else
                     'error' if error else 'pending' if pending else 'ready')
            if not self.connected and self.credentials.get(provider):
                state, error = 'error', '播放服务未连接，收藏已保存在本地'
            reason = ('offline' if not self.connected else 'login' if not self.credentials.get(provider) or provider in self.login_required
                      else 'account' if pending and all(self._job_status(j)['reason'] == 'account' for j in pending)
                      else 'network' if error else '')
            busy = provider in self.writing or provider in self.loading or provider in self.importing
            out[provider] = dict(state=state, imported=self.imported[provider],
                                 pending=len(pending), error=error, reason=reason,
                                 canRetry=bool(self.connected and self.credentials.get(provider) and not busy
                                               and reason not in ('account', 'login')),
                                 canLogin=bool(self.connected and not busy and
                                               (reason in ('login', 'account') or provider not in self.accounts)))
        return out

    def song_state(self, song):
        provider, identifier = song.get('provider'), str(song.get('id', ''))
        job = self.db.intent(provider, identifier)
        if not job or job['state'] in ('synced', 'cancelled'):
            # Legacy local-only favorites have never been uploaded automatically.
            return dict(state='synced' if job and job['state'] == 'synced' else 'local', pending=False, error='')
        return self._job_status(job)

    def toggle(self, song):
        provider = song.get('provider')
        desired = not self.db.contains(song)
        self.db.set_desired(song, desired, self.accounts.get(provider) or self.db.account(provider))
        self.changed(True)
        self._pump(provider)
        return dict(liked=desired, provider=provider, pending=True, syncState='pending',
                    message='已保存到本地，正在同步平台' if self.connected and self.credentials.get(provider)
                    else '已保存到本地，登录歌曲所属平台后同步')

    def _valid(self, generation):
        return not self.closed and self.connected and generation == self.generation

    def refresh(self, provider=None, import_all=True):
        if self.closed:
            return
        if self.connected:
            for provider in ([provider] if provider in PROVIDERS else PROVIDERS):
                if (self.credentials.get(provider) and provider not in self.loading
                        and provider not in self.importing and provider not in self.writing):
                    if import_all or self.db.intents(provider):
                        self._load_account(provider, import_all)
        self.changed(False)

    def _load_account(self, provider, import_all=True):
        generation = self.generation
        self.loading.add(provider)
        self.errors.pop(provider, None)
        self.changed(False)

        def loaded(value, error):
            if not self._valid(generation): return
            self.loading.discard(provider)
            account = str(value[0]) if isinstance(value, list) and value and value[0] else ''
            if error or not account:
                if (isinstance(value, dict) and value.get('authExpired')) or (not error and not account):
                    self.login_required.add(provider)
                self.errors[provider] = error or '没有读到平台账号，请重新登录'
                self.changed(False)
                return
            try:
                self.accounts[provider] = account
                self.login_required.discard(provider)
                self.db.remember_account(provider, account)
                self.db.retry_intents(provider, account)
            except Exception as exc:
                self.errors[provider] = '本地同步状态未保存：' + str(exc)
                self.changed(False)
                return
            self._pump(provider)
            if import_all: self._import(provider)

        self.request(provider, 'account', [], loaded)

    def _pump(self, provider):
        if self.closed or not self.connected or provider in self.writing or provider not in self.accounts or provider in self.login_required:
            return
        account = self.accounts[provider]
        jobs = self.db.intents(provider, account, 'pending')
        if not jobs:
            self.changed(False)
            return
        generation, job = self.generation, jobs[0]
        self.writing[provider] = job
        self.changed(False)

        def written(value, error):
            if not self._valid(generation): return
            self.writing.pop(provider, None)
            if error and isinstance(value, dict) and value.get('authExpired'): self.login_required.add(provider)
            if not error and (not isinstance(value, dict) or value.get('verified') is not True
                              or value.get('liked') is not job['desired']):
                error = '平台尚未确认收藏结果，请稍后重试'
            try:
                self.db.finish_intent(job, error)
            except Exception as exc:
                self.errors[provider] = '本地同步状态未保存：' + str(exc)
                self.changed(False)
                return
            self.changed(False)
            if not error and provider in self.importing:
                self.reimport.add(provider)
            # Failed jobs wait for a refresh; subsequent new user intents still run.
            self._pump(provider)

        self.request(provider, 'mutate', ['/like/set', dict(id=job['id'], liked=job['desired'],
                                                           account=account)], written)

    def _import(self, provider):
        generation, started, order_ns = self.generation, self.db.intent_revision, time.time_ns()
        self.importing.add(provider)
        self.imported[provider] = 0
        seen, fingerprints = set(), set()
        self.changed(False)

        def finish(error=''):
            self.importing.discard(provider)
            if error: self.errors[provider] = error
            else: self.errors.pop(provider, None)
            self.changed(False)
            if provider in self.reimport:
                self.reimport.discard(provider)
                self._import(provider)

        def page(offset):
            def received(value, error):
                if not self._valid(generation): return
                if error:
                    if isinstance(value, dict) and value.get('authExpired'): self.login_required.add(provider)
                    finish(error); return
                if not isinstance(value, dict) or not isinstance(value.get('items'), list):
                    finish('平台收藏数据格式不完整'); return
                items = value['items']
                try:
                    raw_count = int(value.get('rawCount', len(items)))
                    total = int(value.get('total', 0))
                    if raw_count < len(items) or raw_count < 0:
                        raise ValueError('收藏分页数量无效')
                    keys = tuple(str(s.get('id', '')) for s in items if isinstance(s, dict))
                    if keys and keys in fingerprints:
                        raise ValueError('平台重复返回同一页收藏，请稍后重试')
                    fingerprints.add(keys)
                    changed = self.db.merge_page(provider, items, started, order_ns, offset)
                    seen.update(keys)
                    self.imported[provider] = len(seen)
                    self.changed(changed)
                    more = bool(value.get('more')) or offset + raw_count < total
                    if more and (not raw_count or offset + raw_count > 200000):
                        raise ValueError('平台收藏分页未完成，请稍后重试')
                except Exception as exc:
                    finish(str(exc)); return
                if more: page(offset + raw_count)
                else: finish()
            self.request(provider, 'likedSongs', [offset], received)
        page(0)

    def close(self):
        self.closed = True
        self.generation += 1
