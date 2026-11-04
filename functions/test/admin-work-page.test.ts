import test from 'node:test';
import assert from 'node:assert/strict';
import { Content } from '../src/content';
import { adminWorkPage, inAdminWorkScope, type AdminWorkScope } from '../src/admin-work-page';

function book(number: number, extra: Partial<Content> = {}): Content {
  return { id: number.toString(16).padStart(32, '0'), kind: 'book', title: `책 ${number}`,
    author: '', description: '', license: '', revision: 1, assets: {},
    published: false, publishedContent: null, updatedAt: '', ...extra };
}
function fixture(records: Content[], rawSize = 4) {
  const sorted = [...records].sort((a, b) => a.id.localeCompare(b.id));
  return {
    read: async (after?: string) => {
      const remaining = sorted.filter(item => !after || item.id > after);
      return { items: remaining.slice(0, rawSize), nextCursor: remaining.length > rawSize ? remaining[rawSize - 1].id : null };
    },
    expand: async (seed: Content) => sorted.filter(item =>
      seed.issueMonth ? item.issueMonth === seed.issueMonth : seed.translationGroupId
        ? item.translationGroupId === seed.translationGroupId : item.id === seed.id),
  };
}

test('menu pagination fills with real works despite many off-menu and child records', async () => {
  const records = Array.from({ length: 75 }, (_, i) => book(i + 1, { collectionType: 'general', seriesId: 'parent' }));
  const expected = [book(76), book(100), book(170), book(200), book(230)];
  records.push(...expected);
  const first = await adminWorkPage({ scope: 'novel', size: 3, ...fixture(records) });
  assert.deepEqual(first.items.map(item => item.id), expected.slice(0, 3).map(item => item.id));
  assert.equal(first.nextCursor, expected[2].id);
  const second = await adminWorkPage({ scope: 'novel', size: 3, after: first.nextCursor!, ...fixture(records) });
  assert.deepEqual(second.items.map(item => item.id), expected.slice(3).map(item => item.id));
  assert.equal(second.nextCursor, null);
});

test('translations across raw pages stay together and do not create empty More pages', async () => {
  const a = 'a'.repeat(32), b = 'b'.repeat(32);
  const records = [book(1, { translationGroupId: a }), book(2), book(20, { translationGroupId: b }),
    book(30, { translationGroupId: a, language: 'en' }), book(60, { translationGroupId: b, language: 'ja' })];
  const first = await adminWorkPage({ scope: 'novel', size: 2, ...fixture(records, 2) });
  assert.deepEqual(first.items.map(item => item.id), [book(1).id, book(30).id, book(2).id]);
  const second = await adminWorkPage({ scope: 'novel', size: 2, after: first.nextCursor!, ...fixture(records, 2) });
  assert.deepEqual(second.items.map(item => item.id), [book(20).id, book(60).id]);
  assert.equal(second.nextCursor, null);
});

test('monthly pagination counts a month once even across languages and translation groups', async () => {
  const records = [book(1, { kind: 'series', issueMonth: '2026-10' }),
    book(2, { kind: 'series', issueMonth: '2026-11' }),
    book(12, { kind: 'series', issueMonth: '2026-10', language: 'en', translationGroupId: 'a'.repeat(32) })];
  const first = await adminWorkPage({ scope: 'monthly', size: 1, ...fixture(records, 1) });
  assert.equal(first.items.length, 2);
  const second = await adminWorkPage({ scope: 'monthly', size: 1, after: first.nextCursor!, ...fixture(records, 1) });
  assert.deepEqual(second.items.map(item => item.issueMonth), ['2026-11']);
  assert.equal(second.nextCursor, null);
});

test('changing poetry genre never changes the admin menu; empty menus have no next page', async () => {
  const poem = book(1, { category: '시' });
  assert.equal(inAdminWorkScope(poem, 'novel'), true);
  assert.equal(inAdminWorkScope({ ...poem, category: '소설' }, 'novel'), true);
  assert.equal(inAdminWorkScope({ ...poem, collectionType: 'general' }, 'general'), true);
  for (const scope of ['general', 'monthly'] as AdminWorkScope[]) {
    assert.deepEqual(await adminWorkPage({ scope, ...fixture([poem]) }), { items: [], nextCursor: null });
  }
});

test('repeating raw cursor fails instead of hanging or showing an empty next page', async () => {
  await assert.rejects(adminWorkPage({ scope: 'novel', read: async () => ({ items: [], nextCursor: book(1).id }), expand: async seed => [seed] }), /다음 페이지/);
});
