import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import sharp from 'sharp';
import { unzipSync, strFromU8 } from 'fflate';
import { monthlyPublisher } from '../src/monthly-publishing';
import { Content, Asset, publish, validateUpload } from '../src/content';

test('standalone TXT publishes image-first localized EPUB while retaining source and chapters', async () => {
  for (const language of ['ko', 'en', 'ja'] as const) {
    const files = new Map<string, Buffer>();
    const asset = (path: string, bytes: Buffer, extension: string): Asset => {
      files.set(path, bytes);
      return { path, size: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex'), extension, contentType: extension === 'txt' ? 'text/plain' : 'image/webp' };
    };
    const txt = asset('text', Buffer.from('겨울옷\n\n[장] 첫날\n본문 <&>\n\n[장] 다음 날\n마지막 문장'), 'txt');
    const cover = asset('cover', await sharp({ create: { width: 30, height: 20, channels: 3, background: '#ddeeff' } }).webp().toBuffer(), 'webp');
    const publisher = monthlyPublisher({ collection: () => ({}) } as never, { file: (path: string) => ({ download: async () => [files.get(path)], save: async (bytes: Buffer) => { files.set(path, bytes); } }) } as never);
    const item: Content = { id: 'c'.repeat(32), kind: 'book', title: '겨울옷', author: '작가', description: '', license: '허가', language, revision: 1, published: false, publishedContent: null, updatedAt: '', assets: { txt, cover } };
    const snapshot = publish(item);
    const result = await publisher.episode(item, snapshot);
    assert(result);
    assert.equal(item.assets.txt, txt, 'draft TXT must remain editable');
    assert.equal(snapshot.sourceTxt, txt);
    assert(!snapshot.assets.txt);
    const bytes = files.get(result.path)!;
    await validateUpload('book', 'epub', bytes);
    const zip = unzipSync(bytes);
    const body = strFromU8(zip['EPUB/story-1.xhtml']);
    assert(body.indexOf('<img') < body.indexOf('<section>'));
    assert(body.includes('작가'));
    assert(body.includes('&lt;&amp;&gt;'));
    assert(!body.includes('[장]'));
    assert(strFromU8(zip['EPUB/nav.xhtml']).includes('story-1.xhtml#chapter-2'));
    assert(strFromU8(zip['EPUB/package.opf']).includes(`<dc:language>${language}</dc:language>`));
    assert.equal(await publisher.episode({ ...item, assets: snapshot.assets }, { ...snapshot }), undefined, 'authored EPUB is never rebuilt');
    assert.equal(await publisher.episode(item, { ...publish(item), seriesId: 'a'.repeat(32) }), undefined, 'regular serial TXT remains unchanged');
  }
});
