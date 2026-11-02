import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { metadata, episodeMetadata, isReleased, Content } from '../src/content';
import { validateTranslationGroup } from '../src/translation-groups';
const base = { title: '인어공주', author: 'Andersen', description: '', license: 'Permitted', language: 'ko' as const };
test('general episodes retain classification and obey exact release time without month restriction', () => {
  const parent = metadata({ ...base, collectionType: 'general' });
  const episode = episodeMetadata({ title: '폭풍', episodeNumber: 2, releaseAt: '2026-12-01T09:00:00+09:00' }, parent, 'parent');
  assert.equal(episode.collectionType, 'general');
  const item = { publishedContent: { ...episode, assets: {}, version: 1 } } as Content;
  assert.equal(isReleased(item, new Date('2026-11-30T23:59:59Z')), false);
  assert.equal(isReleased(item, new Date('2026-12-01T00:00:00Z')), true);
});
test('monthly bounds remain enforced and ordinary legacy metadata is unchanged', () => {
  assert.equal(metadata(base).collectionType, undefined);
  assert.throws(() => metadata({ ...base, issueMonth: '2026-11', releaseAt: '2026-12-01T09:00:00+09:00' }));
  assert.throws(() => metadata({ ...base, collectionType: 'unknown' }));
});
test('general books cannot be linked into existing novel groups', () => {
  const a = { ...base, id: 'a', kind: 'book', collectionType: 'general' } as Content;
  const b = { ...base, id: 'b', kind: 'book', language: 'en' } as Content;
  assert.throws(() => validateTranslationGroup([a,b]));
});
