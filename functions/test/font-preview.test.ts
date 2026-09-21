import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import sharp from 'sharp';
import { renderFontPreview, previewFace } from '../src/font-preview';
import { Content, publicItem, publish } from '../src/content';
const light = readFileSync('../assets/fonts/Maplestory OTF Light.otf');
const bold = readFileSync('../assets/fonts/Maplestory OTF Bold.otf');

test('preview uses real Korean glyphs, transparent bounded PNG and changes with font and title', async () => {
  const one = await renderFontPreview(light, '메이플스토리');
  const two = await renderFontPreview(bold, '메이플스토리');
  const renamed = await renderFontPreview(light, '다른 글꼴 이름');
  assert(one && two && renamed);
  assert.notEqual(one.asset.sha256, two.asset.sha256);
  assert.notEqual(one.asset.sha256, renamed.asset.sha256);
  const info = await sharp(one.bytes).metadata();
  assert.equal(info.format, 'png'); assert.equal(info.hasAlpha, true);
  assert(info.width! <= 2048 && info.height! <= 80);
  assert(one.bytes.length < 128 * 1024);
  const stats = await sharp(one.bytes).stats();
  assert(stats.channels[3].min === 0 && stats.channels[3].max > 0);
  const hugeTitle = await renderFontPreview(light, '가'.repeat(160));
  assert(hugeTitle);
  assert((await sharp(hugeTitle.bytes).metadata()).width! <= 2048);
});
test('unsupported title glyphs fall back instead of rendering tofu or another font', async () => {
  assert.equal(await renderFontPreview(light, '\u{10ffff}'), null);
  await assert.rejects(renderFontPreview(Buffer.from('not a font'), '이름'));
});
test('regular weight is preferred and preview stays out of font assets and public storage paths', () => {
  const asset = { path: 'private/font', sha256: 'a'.repeat(64), size: 100, extension: 'otf', contentType: 'font/otf' };
  const item: Content = { id: 'a'.repeat(32), kind: 'font', title: '이름', author: '작가', description: '', license: '허가', revision: 1, assets: { font300: { ...asset, weight: 300 }, font700: { ...asset, weight: 700 } }, published: false, publishedContent: null, updatedAt: '' };
  assert.equal(previewFace(item).weight, 300);
  item.assets.font400 = { ...asset, weight: 400 };
  assert.equal(previewFace(item).weight, 400);
  const preview = { ...asset, path: 'private/preview.png', extension: 'png', contentType: 'image/png' };
  const snapshot = { ...publish(item), preview };
  const output = publicItem({ ...item, published: true, publishedContent: snapshot });
  assert.equal(output.preview?.extension, 'png');
  assert(!('path' in output.preview!)); assert(!('preview' in output.assets));
  assert.equal(publicItem({ ...item, published: true, publishedContent: publish(item) }).preview, undefined);
});
