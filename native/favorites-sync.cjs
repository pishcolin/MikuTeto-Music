// Explicit, account-bound writes. Retrying a timeout must not toggle a heart.
module.exports = function extendFavorites(api, provider) {
  const previous = api.mutate.bind(api);
  api.mutate = async (route, values) => {
    if (route !== '/like/set') return previous(route, values);
    if (typeof values?.liked !== 'boolean' || !values.id || !values.account)
      throw new Error('收藏同步信息不完整');
    const [account] = await api.account();
    if (String(account) !== String(values.account))
      throw new Error('账号已变化，收藏仍保留在本地，请切回原账号同步');
    const expected = values.liked ? 'subscribed' : 'not-subscribed';
    const before = await api.subscriptionStatus('song', String(values.id));
    if (!['subscribed', 'not-subscribed'].includes(before))
      throw new Error('平台收藏状态未确认，请稍后重试');
    if (before !== expected) {
      if (provider === 'qq') {
        const song = await api.writableSong(String(values.id), () => true);
        const body = await api.request('/user/song/like', {song, liked:values.liked});
        if (body.liked !== values.liked) throw new Error('QQ 音乐尚未确认收藏结果');
      } else {
        await api.request('/like', {id:String(values.id), like:values.liked, timestamp:Date.now()});
      }
      if (await api.subscriptionStatus('song', String(values.id)) !== expected)
        throw new Error('平台尚未确认收藏结果，可稍后重试');
    }
    return {verified:true, liked:values.liked, state:expected};
  };
  return api;
};
