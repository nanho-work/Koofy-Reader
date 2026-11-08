import test from 'node:test';
import assert from 'node:assert/strict';
import { zipSync, strToU8 } from 'fflate';
import { storyBlocks } from '../src/story-body';
import type { Asset } from '../src/content';

test('web EPUB reading follows spine order and sends text rather than markup', async () => {
  const bytes = Buffer.from(zipSync({
    mimetype: strToU8('application/epub+zip'),
    'META-INF/container.xml': strToU8('<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>'),
    'OPS/book.opf': strToU8('<package version="3.0"><metadata/><manifest><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/><item id="b" href="b.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="b"/><itemref idref="a"/></spine></package>'),
    'OPS/a.xhtml': strToU8('<html><body><p>마지막 문단</p></body></html>'),
    'OPS/b.xhtml': strToU8('<html><head><title>문서 제목</title></head><body><h1>책 제목</h1><p>첫 <strong>문단</strong> &amp; 다음</p></body></html>'),
  }));
  assert.deepEqual(await storyBlocks({ extension: 'epub' } as Asset, bytes, '책 제목'), [
    { type: 'paragraph', text: '첫 문단 & 다음' },
    { type: 'paragraph', text: '마지막 문단' },
  ]);
});
