import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import test from 'node:test';
import { episodePreview, previewPlacement } from '../src/episode-preview';

test('only a signed reward for the pending next episode grants access and starts the 12-hour limit', async () => {
  const parent = 'a'.repeat(32);
  const first = 'b'.repeat(32);
  const second = 'c'.repeat(32);
  const third = 'd'.repeat(32);
  const asset = { path: 'private/book.epub', sha256: 'a'.repeat(64), size: 123 };
  const series = { id: parent, kind: 'series', published: true, publishedContent: { assets: {} } };
  const chapter = (episodeId: string, number: number, releaseDate: string) => ({
    id: episodeId, kind: 'book', seriesId: parent, published: true,
    publishedContent: {
      title: 'Episode', seriesId: parent, seriesTitle: 'Series',
      episodeNumber: number, language: 'ko', releaseDate, version: 1,
      assets: { cover: asset, epub: asset },
    },
  });
  const records = new Map<string, unknown>([
    ['readerContent/' + parent, series],
    ['readerContent/' + first, chapter(first, 1, '2025-01-01')],
    ['readerContent/' + second, chapter(second, 2, '2099-01-01')],
    ['readerContent/' + third, chapter(third, 3, '2099-01-02')],
  ]);
  const doc = (path: string) => ({
    path,
    get: async () => ({ data: () => records.get(path), exists: records.has(path) }),
  });
  const query = {
    where: () => query,
    select: () => query,
    get: async () => ({ docs: [first, second, third].map(value => ({
      data: () => records.get('readerContent/' + value),
    })) }),
  };
  const transaction = {
    get: async (ref: ReturnType<typeof doc>) => ref.get(),
    getAll: async (...refs: ReturnType<typeof doc>[]) => Promise.all(refs.map(ref => ref.get())),
    set: (ref: ReturnType<typeof doc>, data: unknown) => records.set(ref.path, data),
    create: (ref: ReturnType<typeof doc>, data: unknown) => {
      assert.equal(records.has(ref.path), false);
      records.set(ref.path, data);
    },
  };
  const db = {
    collection: (name: string) => ({ doc: (value: string) => doc(name + '/' + value), where: query.where }),
    runTransaction: (callback: (tx: typeof transaction) => unknown) => callback(transaction),
  };
  const bucket = { file: () => ({ getSignedUrl: async () => ['https://storage.googleapis.com/signed'] }) };
  const api = episodePreview(db as unknown as Parameters<typeof episodePreview>[0], bucket as unknown as Parameters<typeof episodePreview>[1]);
  const credential = 'e'.repeat(64);
  const userId = createHash('sha256').update(credential).digest('hex');
  const request = { credential, platform: 'ios', afterEpisode: 1, episodeId: second };
  assert.equal((await api.request({ ...request, action: 'begin', episodeId: third })).state, 'unavailable');
  const attempt = await api.request({ ...request, action: 'begin' });
  assert.ok('attemptId' in attempt && attempt.attemptId);
  assert.deepEqual(await api.request({ ...request, action: 'claim' }), { state: 'pending' });

  const eventId = 'verifiedEvent01', rewards = '1', timestamp = '202611071400', key = 'test-secret';
  const signature = createHash('md5').update(timestamp + eventId + userId + rewards + key).digest('hex');
  const callback = { userId, eventId, rewards, timestamp, signature, dynamicUserId: attempt.attemptId, placement: previewPlacement };
  await assert.rejects(api.reward({ ...callback, rewards: '2' }, 'ios', key), /Invalid reward signature/);
  await api.reward({ ...callback, placement: 'hide_ads' }, 'ios', key);
  await api.reward({ ...callback, dynamicUserId: '0'.repeat(32) }, 'ios', key);
  assert.deepEqual(await api.request({ ...request, action: 'claim' }), { state: 'pending' });

  const before = Date.now();
  assert.equal(await api.reward(callback, 'ios', key), eventId);
  assert.equal(await api.reward(callback, 'ios', key), eventId);
  const unlocked = await api.request({ ...request, action: 'claim' });
  assert.equal(unlocked.state, 'granted');
  assert.ok('links' in unlocked && unlocked.links?.epub);
  assert.equal((await api.request({ ...request, credential: 'f'.repeat(64), action: 'claim' })).state, 'unavailable');
  const cooldown = await api.request({ ...request, afterEpisode: 2, episodeId: third, action: 'begin' });
  assert.equal(cooldown.state, 'cooldown');
  assert.ok('nextAt' in cooldown && cooldown.nextAt! >= before + 12 * 60 * 60 * 1000);

  records.set('readerContent/' + second, { ...chapter(second, 2, '2099-01-01'), published: false });
  await assert.rejects(api.request({ ...request, action: 'claim' }), /공개된 콘텐츠가 없습니다/);
});
