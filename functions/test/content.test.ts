import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { ApiError, Content, assertRevision, bearer, categoryName, id, inspectFont, metadata, publicItem, publish, requireSuperAdmin, validateUpload } from '../src/content';
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

test('TXT normalizes Unicode and Korean legacy encodings to UTF-8', async () => {
  const { createHash } = await import('node:crypto');
  const text = '한글 본문 😀\r\n두 번째 줄';
  const utf16 = Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from(text, 'utf16le')]);
  const bigEndian = Buffer.from(utf16); bigEndian.swap16();
  for (const bytes of [Buffer.from(text), Buffer.from('\ufeff' + text), utf16, bigEndian]) {
    const result = await validateUpload('book', 'txt', bytes);
    assert.equal(result.bytes.toString('utf8'), text.replace('\r\n', '\n'));
    assert.equal(result.asset.extension, 'txt');
    assert.equal(result.asset.contentType, 'text/plain; charset=utf-8');
    assert.equal(result.asset.size, result.bytes.length);
    assert.equal(result.asset.sha256, createHash('sha256').update(result.bytes).digest('hex'));
  }
  const korean = await validateUpload('book', 'txt', Buffer.from([0xb0, 0xa1, 0x0d, 0x0a, 0xb3, 0xaa]));
  assert.equal(korean.bytes.toString('utf8'), '가\n나');
  const extended = await validateUpload('book', 'txt', Buffer.from([0x8c, 0x63]));
  assert.equal(extended.bytes.toString('utf8'), '똠');
});

test('TXT rejects empty, binary, invalid encoding and oversized uploads', async () => {
  for (const bytes of [Buffer.alloc(0), Buffer.from(' \n\t'), Buffer.from([0xff]), Buffer.from([0xef, 0xbb, 0xbf, 0xb0, 0xa1]), Buffer.from('본문\uffff'), Buffer.from('본문\x00'), readFileSync('test/fixtures/valid.epub'), Buffer.alloc(20 * 1024 * 1024 + 1)]) {
    await assert.rejects(validateUpload('book', 'txt', bytes), ApiError);
  }
  await assert.rejects(validateUpload('font', 'txt', Buffer.from('본문')), ApiError);
});

test('format replacement is exclusive and does not mutate published files', async () => {
  const { replaceAsset } = await import('../src/content');
  const epub = { path: 'epub/original', ...(await validateUpload('book', 'epub', readFileSync('test/fixtures/valid.epub'))).asset };
  const txt = { path: 'txt/new', ...(await validateUpload('book', 'txt', Buffer.from('본문'))).asset };
  const cover = { ...epub, path: 'cover/original', extension: 'webp' };
  const uploaded = { ...item, assets: { epub, cover } };
  const publishedContent = publish(uploaded);
  const original = { ...uploaded, published: true, publishedContent };
  const assets = replaceAsset(original, 'txt', txt);
  assert.equal(assets.epub, undefined);
  assert.deepEqual(assets.txt, txt);
  assert.deepEqual(publicItem(original).assets.epub.sha256, epub.sha256);
  assert.equal(publish({ ...original, assets }).assets.txt, txt);
  assert.throws(() => publish({ ...original, assets: { ...assets, epub } }), ApiError);
  assert.throws(() => publish({ ...original, assets: { txt } }), ApiError);
  assert.equal(replaceAsset({ ...original, assets }, 'epub', epub).txt, undefined);
});


test('catalog category and source are optional for old clients and survive publishing', () => {
  const legacy = metadata(item);
  assert.equal(legacy.category, '기타');
  assert.equal(legacy.source, '');
  const updated = metadata({ ...item, category: '시', source: '  https://example.org/poem  ' });
  assert.equal(updated.category, '시');
  assert.equal(updated.source, 'https://example.org/poem');
  assert.throws(() => metadata({ ...item, category: '' }), ApiError);
  assert.throws(() => metadata({ ...item, source: 'a'.repeat(501) }), ApiError);
  const asset = { path: 'private/path', sha256: 'b'.repeat(64), size: 100, extension: 'epub', contentType: 'application/epub+zip' };
  const uploaded = { ...item, ...updated, assets: { epub: asset, cover: { ...asset, extension: 'webp' } } };
  const result = publicItem({ ...uploaded, published: true, publishedContent: publish(uploaded) });
  assert.equal(result.category, '시');
  assert.equal(result.source, updated.source);
});

test('custom categories normalize Unicode and reject empty or invalid names', () => {
  assert.equal(metadata({ ...item, category: '  역사  ' }).category, '역사');
  assert.equal(categoryName('동화'.normalize('NFD')), '동화');
  assert.equal(metadata(item).category, '기타');
  for (const value of ['', ' ', 'a'.repeat(41), '시\n소설', 123, null]) {
    assert.throws(() => categoryName(value), ApiError);
  }
});
