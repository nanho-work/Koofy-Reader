import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { validateTranslationGroup } from '../src/translation-groups';
import { Content } from '../src/content';
const book = (id: string, language: 'ko' | 'en' | 'ja'): Content => ({ id, language, kind: 'book', title: id, author: 'a', license: 'l', description: '', revision: 2, assets: {}, published: false, publishedContent: null, updatedAt: '' });
test('linkage preserves input records and reuses existing group', () => {
  const ko = { ...book('a', 'ko'), translationGroupId: 'g' }, en = book('b', 'en');
  const before = JSON.stringify([ko, en]); assert.equal(validateTranslationGroup([ko, en]), 'g'); assert.equal(JSON.stringify([ko, en]), before);
});
test('rejects duplicate languages including unselected existing members', () => {
  assert.throws(() => validateTranslationGroup([book('a','ko'), book('b','ko')]));
  assert.throws(() => validateTranslationGroup([book('a','ko'), book('b','en')], [book('c','en')]));
});
test('rejects monthly, child episodes, mixed kinds and merging groups', () => {
  for (const patch of [{ issueMonth: '2026-11' }, { seriesId: 'parent' }, { kind: 'series' as const }, { deleting: true }]) assert.throws(() => validateTranslationGroup([book('a','ko'), { ...book('b','en'), ...patch }]));
  assert.throws(() => validateTranslationGroup([{ ...book('a','ko'), translationGroupId:'g' }, { ...book('b','en'), translationGroupId:'h' }]));
});
