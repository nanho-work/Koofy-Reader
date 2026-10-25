import test from 'node:test';
import assert from 'node:assert/strict';
import { Content } from '../src/content';
import { correctMonthlyLanguage } from '../src/monthly-language';
const issue: Content = { id: 'issue', kind: 'series', issueMonth: '2026-10', language: 'ko', title: 'Japanese issue', author: '쿠피랩', license: 'custom', description: '', revision: 2, updatedAt: 'before', assets: {}, published: true, publishedContent: { issueMonth: '2026-10', title: 'Japanese issue', author: '쿠피랩', license: 'custom', description: '', language: 'ko', assets: {}, version: 1 } };
const episode: Content = { ...issue, id: 'ep', kind: 'book', seriesId: 'issue', episodeNumber: 1 };
test('corrects draft and public language together while preserving identity, assets and custom terms', () => {
  const result = correctMonthlyLanguage(issue, [episode], 2, 'ja', 'now');
  assert.deepEqual(result.map(x => x.language), ['ja', 'ja']);
  assert.equal(result[1].publishedContent?.language, 'ja');
  assert.equal(result[1].id, episode.id);
  assert.equal(result[1].assets, episode.assets);
  assert.equal(result[1].license, 'custom');
  assert.equal(result[1].revision, 3);
  assert.equal(result[1].publishedContent?.version, 2);
  assert.equal(issue.language, 'ko');
});
test('rejects stale revision, compiled issue, unrelated or deleting episodes, and invalid language', () => {
  assert.throws(() => correctMonthlyLanguage(issue, [episode], 1, 'ja', 'now'));
  assert.throws(() => correctMonthlyLanguage({...issue, compilationId:'compiled'}, [episode], 2, 'ja', 'now'));
  assert.throws(() => correctMonthlyLanguage(issue, [{...episode, seriesId:'other'}], 2, 'ja', 'now'));
  assert.throws(() => correctMonthlyLanguage(issue, [{...episode, deleting:true}], 2, 'ja', 'now'));
  assert.throws(() => correctMonthlyLanguage(issue, [episode], 2, 'jp', 'now'));
});
