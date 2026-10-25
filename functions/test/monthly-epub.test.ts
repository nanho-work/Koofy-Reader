import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { unzipSync, strFromU8 } from 'fflate';
import { buildMonthlyEpub } from '../src/monthly-epub';
import { compilationEligibility } from '../src/monthly-publishing';
import { Content, publish, publicItem, validateUpload } from '../src/content';

test('generated EPUB preserves localized stories, images, escaped prose and table of contents', async () => {
  const image = await sharp({ create: { width: 30, height: 20, channels: 3, background: '#ddeeff' } }).jpeg().toBuffer();
  for (const language of ['ko', 'en', 'ja'] as const) {
    const bytes = buildMonthlyEpub('월간 & 쿠피', language, [
      { title: '첫 이야기', text: '첫 이야기\n\n본문 <script> & 문장\n다음 줄\n\n두 번째 문단', image, byline: '홍길동' },
      { title: '두 번째', text: '다른 본문', image },
    ]);
    await validateUpload('book', 'epub', bytes);
    const zip = unzipSync(bytes);
    assert.equal(strFromU8(zip.mimetype), 'application/epub+zip');
    assert.equal(bytes.readUInt16LE(8), 0, 'mimetype is stored uncompressed');
    const first = strFromU8(zip['EPUB/story-1.xhtml']);
    assert(first.indexOf('<figure>') < first.indexOf('<section>'));
    assert(first.indexOf('홍길동') < first.indexOf('<img'));
    assert(first.includes('&lt;script&gt; &amp; 문장<br/>다음 줄'));
    assert(!first.includes('<p>첫 이야기'));
    assert(!strFromU8(zip['EPUB/story-2.xhtml']).includes('<figcaption>'));
    const opf = strFromU8(zip['EPUB/package.opf']);
    assert(opf.includes(`<dc:language>${language}</dc:language>`));
    assert(opf.includes('reference type="cover"'));
    assert(strFromU8(zip['EPUB/nav.xhtml']).includes('story-2.xhtml'));
  }
});

test('compilation waits for the Korean month boundary and complete released content', () => {
  const asset = { path: 'p', sha256: 'a'.repeat(64), size: 1, extension: 'webp', contentType: 'image/webp' };
  const parent: Content = { id: 'a'.repeat(32), kind: 'series', title: '월간 쿠피', author: '쿠피랩', description: '', license: '허가', issueMonth: '2026-11', autoCompile: true, expectedEpisodes: 1, assets: { cover: asset }, revision: 1, published: true, publishedContent: null, updatedAt: '' };
  parent.publishedContent = publish(parent);
  const episode: Content = { ...parent, id: 'b'.repeat(32), kind: 'book', seriesId: parent.id, episodeNumber: 1, releaseDate: '2026-11-30', assets: { cover: asset, txt: { ...asset, extension: 'txt' } } };
  episode.publishedContent = publish(episode, parent);
  assert(compilationEligibility(parent, [episode], new Date('2026-11-30T14:59:59Z')));
  assert.equal(compilationEligibility(parent, [episode], new Date('2026-11-30T15:00:00Z')), null);
  assert(compilationEligibility(parent, [], new Date('2026-12-01T00:00Z')));
  assert(compilationEligibility(parent, [{ ...episode, published: false }], new Date('2026-12-01T00:00Z')));
  const epubOnly = { ...episode, publishedContent: { ...episode.publishedContent!, assets: { cover: asset, epub: asset } } };
  assert(compilationEligibility(parent, [epubOnly], new Date('2026-12-01T00:00Z')));
  episode.publishedContent!.sourceTxt = asset;
  assert(!('sourceTxt' in publicItem(episode)));
  assert(!('autoCompile' in publicItem(parent)));
});

test('monthly selection uses Korean release boundaries and published snapshots, not counts or episode order', async () => {
  const { compilationEpisodes } = await import('../src/monthly-publishing');
  const asset = { path: 'p', sha256: 'a'.repeat(64), size: 1, extension: 'txt', contentType: 'text/plain' };
  const parent: Content = { id: 'a'.repeat(32), kind: 'series', title: '10월호', author: '쿠피랩', description: '', license: '허가', issueMonth: '2026-10', autoCompile: true, assets: { cover: asset }, revision: 1, published: true, publishedContent: null, updatedAt: '' };
  parent.publishedContent = publish(parent); // no expected count required
  function entry(id: string, releaseAt: string, number: number): Content {
    const item = { ...parent, id, kind: 'book' as const, seriesId: parent.id, episodeNumber: number, releaseAt, assets: { txt: asset, cover: asset } };
    // Seed historical dates to exercise boundaries independent of input validation.
    item.publishedContent = { ...parent.publishedContent!, seriesId: parent.id, episodeNumber: number, releaseAt, releaseDate: '', assets: item.assets };
    return item;
  }
  const first = entry('first', '2026-09-30T15:00:00Z', 90);
  const last = entry('last', '2026-10-31T14:59:59Z', 1);
  const before = entry('before', '2026-09-30T14:59:59Z', 2);
  const after = entry('after', '2026-10-31T15:00:00Z', 3);
  const draft = { ...first, id: 'draft', published: false };
  const deleted = { ...first, id: 'deleted', deleting: true };
  const foreign = { ...first, id: 'en', publishedContent: { ...first.publishedContent!, language: 'en' as const } };
  const oldDateOnly = entry('legacy', '', 5); oldDateOnly.publishedContent!.releaseDate = '2026-10-15';
  first.releaseAt = '2026-11-15T09:00:00+09:00'; // unpublished edit cannot change selection
  const all = [last, draft, before, after, deleted, foreign, oldDateOnly, first];
  const now = new Date('2026-11-01T00:00:00Z');
  assert.deepEqual(compilationEpisodes(parent, all, now).map(e => e.id), ['first', 'legacy', 'last']);
  assert.equal(compilationEligibility(parent, all, now), null);
  assert.deepEqual(compilationEpisodes(parent, all, new Date('2026-10-01T00:00:00Z')).map(e => e.id), ['first']);
  parent.publishedContent!.expectedEpisodes = 31; // legacy count must not block
  assert.equal(compilationEligibility(parent, all, now), null);
});

 test('monthly publisher stays internal and optional byline is public', async () => {
  const { metadata, publicItem, MONTHLY_LICENSE } = await import('../src/content');
  const fields = metadata({ issueMonth: '2026-10', title: '월간 쿠피', description: '', author: '', license: '' });
  assert.equal(fields.author, '쿠피랩');
  assert.equal(fields.license, MONTHLY_LICENSE);
  const item = { id: 'monthly', kind: 'series', published: true, publishedContent: { ...fields, assets: {}, version: 1 } } as any;
  assert.equal(publicItem(item).author, '');
  item.publishedContent.byline = '홍길동';
  assert.equal(publicItem(item).author, '홍길동');
  assert.equal(metadata({ ...fields, license: '별도 이용조건' }).license, '별도 이용조건');
});

test('monthly language defaults localize standard text and preserve custom terms', async () => {
  const { metadata, episodeMetadata, MONTHLY_DEFAULTS } = await import('../src/content');
  for (const language of ['ko', 'en', 'ja'] as const) {
    const base = { language, issueMonth: '2026-10', title: 'Monthly', description: '', author: '' };
    for (const license of ['', undefined, MONTHLY_DEFAULTS.ko.license, MONTHLY_DEFAULTS.en.license, MONTHLY_DEFAULTS.ja.license]) {
      const issue = metadata({ ...base, license });
      assert.equal(issue.author, MONTHLY_DEFAULTS[language].author);
      assert.equal(issue.license, MONTHLY_DEFAULTS[language].license);
      const episode = episodeMetadata({ title: 'Story', episodeNumber: 1, releaseDate: '2026-10-01', byline: 'Writer' }, issue, 'a'.repeat(32));
      assert.equal(episode.license, issue.license);
      assert.equal(episode.byline, 'Writer');
    }
    assert.equal(metadata({ ...base, license: 'Custom permission' }).license, 'Custom permission');
  }
});
