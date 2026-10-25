import test from 'node:test';
import assert from 'node:assert/strict';
import { Content, Asset, metadata, seriesMetadata, episodeMetadata, publish, isReleased, compilationReady, publicationDay } from '../src/content';
const base = { title: '월간 쿠피', author: '쿠피랩', description: '', license: '허가', language: 'ko' as const, issueMonth: '2026-02' };
const cover: Asset = { path: 'cover', extension: 'webp', contentType: 'image/webp', size: 1, sha256: 'a'.repeat(64) };
function content(kind: 'book' | 'series', extra: Record<string, unknown> = {}): Content {
  const item: Content = { ...base, id: (kind === 'book' ? 'b' : 'a').repeat(32), kind, revision: 1, assets: kind === 'book' ? { cover, epub: { ...cover, extension: 'epub' } } : { cover }, published: true, publishedContent: null, updatedAt: '2026-02-01', ...extra };
  item.publishedContent = publish(item);
  return item;
}
test('editorial days roll over at Korean midnight, validating real dates', () => {
  assert.equal(publicationDay(new Date('2026-02-01T14:59:59Z')), '2026-02-01');
  assert.equal(publicationDay(new Date('2026-02-01T15:00:00Z')), '2026-02-02');
  for (const releaseDate of ['2026-02-29', '2026-02-31', '2026-13-01', '2026-03-01']) assert.throws(() => metadata({ ...base, releaseDate }));
  assert.equal(metadata({ ...base, issueMonth: '2028-02', releaseDate: '2028-02-29' }).releaseDate, '2028-02-29');
});
test('monthly episodes require date and inherit parent language/month, not compilation link', () => {
  const parent = seriesMetadata({ ...base, compilationId: 'b'.repeat(32) });
  assert.throws(() => episodeMetadata({ title: '첫 이야기', episodeNumber: 1 }, parent, 'a'.repeat(32)));
  const episode = episodeMetadata({ title: '첫 이야기', episodeNumber: 1, releaseDate: '2026-02-01', language: 'ja', issueMonth: '2026-03' }, parent, 'a'.repeat(32));
  assert.equal(episode.language, 'ko'); assert.equal(episode.issueMonth, '2026-02'); assert.equal(episode.compilationId, '');
});
test('future dates use the published snapshot, never draft dates', () => {
  const item = content('book', { releaseDate: '2026-02-02' });
  assert.equal(isReleased(item, new Date('2026-02-01T14:59:59Z')), false);
  assert.equal(isReleased(item, new Date('2026-02-01T15:00:00Z')), true);
  item.releaseDate = '2026-02-01';
  assert.equal(isReleased(item, new Date('2026-02-01T00:00:00Z')), false);
});
test('series retires only with a published same-month same-language EPUB compilation', () => {
  const series = content('series', { seriesStatus: 'completed' });
  const book = content('book');
  assert.equal(compilationReady(series, book), true);
  assert.equal(compilationReady(series, undefined), false);
  assert.equal(compilationReady(series, { ...book, published: false }), false);
  assert.equal(compilationReady(series, { ...book, deleting: true }), false);
  for (const change of [{ language: 'ja' as const }, { issueMonth: '2026-01' }, { seriesId: series.id }, { assets: { cover, txt: cover } }]) {
    assert.equal(compilationReady(series, { ...book, publishedContent: { ...book.publishedContent!, ...change } }), false);
  }
  assert.equal(compilationReady(content('series'), book), false);
});

test('reserved episodes release at the exact Korean minute and ignore draft changes', () => {
  const episode = episodeMetadata({ title: '열 번째 이야기', episodeNumber: 10, releaseAt: '2026-02-03T09:30:00+09:00' }, base, 'a'.repeat(32));
  assert.equal(episode.releaseDate, '2026-02-03');
  assert.equal(episode.episodeNumber, 10);
  const item = content('book', { releaseAt: episode.releaseAt });
  assert.equal(isReleased(item, new Date('2026-02-03T00:29:59.999Z')), false);
  assert.equal(isReleased(item, new Date('2026-02-03T00:30:00Z')), true);
  item.releaseAt = '2026-02-01T09:00:00+09:00';
  assert.equal(isReleased(item, new Date('2026-02-02T00:30:00Z')), false);
});
test('schedule rejects invalid times, dates, timezone and dates outside the issue', () => {
  for (const releaseAt of ['2026-02-30T09:00:00+09:00', '2026-02-03T24:00:00+09:00', '2026-02-03T09:60:00+09:00', '2026-02-03T09:00:00Z', '2026-03-01T09:00:00+09:00', '2026-02-03T09:00']) {
    assert.throws(() => metadata({ ...base, releaseAt }));
  }
  assert.equal(metadata({ ...base, issueMonth: '2028-02', releaseAt: '2028-02-29T23:59:00+09:00' }).releaseDate, '2028-02-29');
});
