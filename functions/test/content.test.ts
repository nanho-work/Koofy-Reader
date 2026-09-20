import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { ApiError, Content, assertRevision, bearer, id, inspectFont, metadata, publicItem, publish, requireSuperAdmin, validateUpload } from '../src/content';
const item: Content = { id: 'a'.repeat(32), kind: 'book', title: '책', author: '작가', description: '', license: '배포 허가', revision: 2, assets: {}, published: false, publishedContent: null, updatedAt: '2026-09-20' };
test('admin requires a bearer token and exact superAdmin boolean', () => {
  for (const header of [undefined, '', 'token', 'Bearer ', 'Bearer a b']) assert.throws(() => bearer(header), ApiError);
  assert.equal(bearer('Bearer jwt'), 'jwt');
  for (const superAdmin of [undefined, false, 'true', 1]) assert.throws(() => requireSuperAdmin({ superAdmin }), ApiError);
  requireSuperAdmin({ superAdmin: true });
});
test('input rejects paths, missing license and stale updates', () => {
  assert.throws(() => id('../other'));
  assert.throws(() => metadata({ ...item, license: '' }));
  assert.throws(() => assertRevision(item, 1), (e: unknown) => e instanceof ApiError && e.status === 409);
  assertRevision(item, 2);
});
test('publishing requires files and public output never includes draft paths', () => {
  assert.throws(() => publish(item));
  assert.throws(() => publicItem(item));
  const asset = { path: 'private/path', sha256: 'b'.repeat(64), size: 100, extension: 'epub', contentType: 'application/epub+zip' };
  const uploaded = { ...item, assets: { epub: asset, cover: { ...asset, extension: 'webp' } } };
  const snapshot = publish(uploaded);
  const draftEdited = { ...uploaded, title: '아직 미공개 제목', published: true, publishedContent: snapshot };
  const result = publicItem(draftEdited);
  assert.equal(result.title, '책');
  assert.equal(result.version, 3);
  assert.equal('path' in result.assets.epub, false);
  assert.throws(() => publicItem({ ...draftEdited, published: false }));
});
test('invalid and oversize assets never pass upload validation', async () => {
  await assert.rejects(validateUpload('book', 'epub', Buffer.from('not zip')));
  await assert.rejects(validateUpload('book', 'epub', Buffer.alloc(20 * 1024 * 1024 + 1)));
  await assert.rejects(validateUpload('font', 'font350', Buffer.alloc(20)));
  await assert.rejects(validateUpload('book', 'cover', Buffer.from('<svg/>')));
  assert.throws(() => inspectFont(Buffer.alloc(100)));
});
test('real bundled OTF is accepted and bounds corruption rejected', () => {
  const catalog = JSON.parse(readFileSync('../assets/fonts/catalog.json', 'utf8'));
  const font = readFileSync(`../assets/fonts/${catalog.families[0].faces[0].file}`);
  assert.equal(inspectFont(font), 'otf');
  const damaged = Buffer.from(font); damaged.writeUInt32BE(0xffffffff, 20);
  assert.throws(() => inspectFont(damaged));
});
test('valid EPUB is accepted; encrypted and unsafe ZIP entries are rejected', async () => {
  const valid = await validateUpload('book', 'epub', readFileSync('test/fixtures/valid.epub'));
  assert.equal(valid.asset.extension, 'epub');
  await assert.rejects(validateUpload('book', 'epub', readFileSync('test/fixtures/encrypted.epub')), ApiError);
  await assert.rejects(validateUpload('book', 'epub', readFileSync('test/fixtures/unsafe-path.epub')), ApiError);
});
test('cover is decoded, resized and re-encoded to a safe static format', async () => {
  const sharp = (await import('sharp')).default;
  const input = await sharp({ create: { width: 1800, height: 2400, channels: 3, background: '#f7f5ee' } }).png().toBuffer();
  const checked = await validateUpload('book', 'cover', input);
  const info = await sharp(checked.bytes).metadata();
  assert.equal(info.format, 'webp'); assert.equal(info.width, 900); assert.equal(info.height, 1200);
});
