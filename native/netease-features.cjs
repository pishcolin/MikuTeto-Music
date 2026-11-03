// UI contract adapter only. Authentication, encryption and streaming stay in Rhine.
module.exports = function extendNetEase(api, parse) {
  const rows = (raw, kind) => (raw || []).map(x => parse(x, kind)).filter(Boolean);
  const page = (items, total = items.length, more = false, rawCount = items.length) => ({items,total,more,rawCount});
  const request = (route, params = {}) => api.request(route, {...params, timestamp: Date.now()});
  const baseDetail = api.detail.bind(api);
  const baseSearch = api.search.bind(api);
  const basePlayback = api.playback.bind(api);
  const rawPlaylists = async () => {
    const [uid] = await api.account();
    return {uid, raw: (await request('/user/playlist', {uid, limit: 2000})).playlist || []};
  };
  const playlist = (raw, uid) => {
    const p = parse(raw, 'playlist');
    return p && {...p, specialType: Number(raw.specialType || 0),
      owned: String(raw.creator?.userId) === String(uid) && Number(raw.specialType || 0) !== 5};
  };
  api.capabilities = async () => ({
    mutations: {likeSong: true, subscribeAlbum: true, subscribePlaylist: true, updatePlaylistTracks: true},
    playlistManagement: {createPlaylist: true, renamePlaylist: true, deletePlaylist: true}
  });
  api.vip = async () => { const b = await request('/user/account'); return {isVip: Number(b.profile?.vipType) > 0}; };
  api.trackPage = async value => `https://music.163.com/#/${value.kind || 'song'}?id=${encodeURIComponent(value.id)}`;
  api.playback = (track, quality, alternative, valid) => basePlayback(track,
    ({best:'lossless', ape:'lossless'})[quality] || quality, false, valid);
  api.preview = (...args) => api.playback(...args);
  // NetEase search often omits album artwork; hydrate the small result page so
  // the native player and the cassette receive the same complete song object.
  api.search = async (text, kind, offset = 0) => {
    const result = await baseSearch(text, kind, offset);
    if (kind === 'song' && result.items.length) {
      const songs = await api.songs(result.items.map(s => s.id));
      const known = new Map(songs.map(s => [s.id, s]));
      result.items = result.items.map(s => known.get(s.id) || s);
    }
    return result;
  };
  api.userPlaylists = async uid => {
    const raw = (await request('/user/playlist', {uid, limit: 2000})).playlist || [];
    return page(raw.map(p => playlist(p, uid)).filter(Boolean));
  };
  api.detail = async value => {
    if (value.kind !== 'playlist') return baseDetail(value);
    const b = (await request('/playlist/detail', {id: value.id})).playlist || {};
    const p = {...(parse(b, 'playlist') || value), specialType: Number(b.specialType || 0),
      owned: !!value.owned && String(value.creatorID) === String(b.creator?.userId)};
    return [p, rows(b.tracks, 'song'), (b.trackIds || []).map(x => String(x.id))];
  };
  api.likedSongs = async (offset = 0) => {
    const [uid] = await api.account();
    const ids = await api.likedIDs(uid);
    const slice = ids.slice(offset, offset + 60);
    const songs = await api.songs(slice);
    const known = new Map(songs.map(s => [s.id, s]));
    return page(slice.map(id => known.get(id)).filter(Boolean), ids.length,
      offset + slice.length < ids.length, slice.length);
  };
  api.likedAlbums = async (offset = 0) => {
    const b = await request('/album/sublist', {limit: 60, offset});
    return page(rows(b.data, 'album'), b.count || 0, !!b.hasMore || offset + (b.data || []).length < b.count);
  };
  api.categories = async () => {
    const b = await request('/playlist/catlist');
    return (b.sub || []).filter(x => x.name).map(x => ({id:x.name, name:x.name}));
  };
  api.discover = async (type, offset = 0, category = '全部') => {
    if (type === 'charts') return page(rows((await request('/toplist')).list, 'playlist'));
    if (type === 'playlists' || type === 'categories') {
      const b = await request('/top/playlist', {cat: category, limit: 30, offset});
      return page(rows(b.playlists, 'playlist'), b.total || 0, !!b.more);
    }
    if (type === 'albums') return page(rows((await request('/album/newest')).albums, 'album'));
    if (type === 'daily') return page(rows((await request('/recommend/songs')).data?.dailySongs, 'song'));
    throw new Error('当前平台未提供这个推荐栏目');
  };
  api.subscriptionStatus = async (kind, id) => {
    let found;
    if (kind === 'song') {
      const [uid] = await api.account();
      found = (await request('/likelist', {uid})).ids?.some(x => String(x) === String(id));
    } else if (kind === 'playlist') {
      const b = (await request('/playlist/detail', {id})).playlist;
      if (typeof b?.subscribed !== 'boolean') return 'unknown';
      found = b.subscribed;
    } else if (kind === 'album') {
      let offset = 0;
      do {
        const b = await request('/album/sublist', {limit: 500, offset});
        if (!Array.isArray(b.data)) return 'unknown';
        if (b.data.some(x => String(x.id) === String(id))) { found = true; break; }
        offset += b.data.length;
        if (!b.data.length || (!b.hasMore && offset >= Number(b.count || 0))) { found = false; break; }
      } while (offset < 10000);
    }
    return found === undefined ? 'unknown' : found ? 'subscribed' : 'not-subscribed';
  };
  const owned = async id => {
    const {uid, raw} = await rawPlaylists();
    const p = raw.find(x => String(x.id) === String(id));
    if (!p || String(p.creator?.userId) !== uid || Number(p.specialType) === 5)
      throw new Error('只能编辑自己创建的普通歌单');
    return p;
  };
  api.mutate = async (route, values) => {
    if (!api.host.authenticated()) throw new Error('请先登录网易云音乐');
    if (['/like', '/album/sub', '/playlist/subscribe'].includes(route)) {
      const kind = route === '/like' ? 'song' : route.split('/')[1];
      const state = await api.subscriptionStatus(kind, values.id);
      if (state === 'unknown') throw new Error('收藏状态尚未确认，请刷新后重试');
      const enable = state !== 'subscribed';
      await request(route, {...values, ...(kind === 'song' ? {like: enable} : {t: enable ? 1 : 2})});
      const actual = await api.subscriptionStatus(kind, values.id);
      if (actual !== (enable ? 'subscribed' : 'not-subscribed'))
        throw new Error('平台尚未确认修改结果，请刷新核实，不要重复提交');
      return {verified: true, state: actual};
    }
    if (route === '/playlist/create') {
      const b = await request(route, {name: values.name, privacy: 0});
      if (!b.playlist?.id) throw new Error('创建结果未确认，请刷新歌单核实');
      const p = await owned(b.playlist.id);
      return {playlist: playlist(p, p.creator?.userId), verified: true};
    }
    const id = values.pid || values.id;
    await owned(id);
    if (route === '/playlist/delete') {
      await request(route, {id});
      const {raw} = await rawPlaylists();
      if (raw.some(x => String(x.id) === String(id))) throw new Error('删除结果未确认，请刷新核实');
    } else if (route === '/playlist/name/update') {
      await request(route, values);
      if ((await owned(id)).name !== values.name) throw new Error('改名结果未确认，请刷新核实');
    } else if (route === '/playlist/tracks') {
      await request(route, values);
      const b = (await request('/playlist/detail', {id})).playlist;
      const present = b?.trackIds?.some(x => String(x.id) === String(values.tracks));
      if (present === undefined || present !== (values.op === 'add')) throw new Error('歌单修改未确认，请刷新核实');
    } else throw new Error('不支持此编辑操作');
    return {verified: true};
  };
  return api;
};
