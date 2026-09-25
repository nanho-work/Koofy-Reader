import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { ApiError, validateUpload } from '../src/content';

// Tiny stored ZIP builder; fixtures contain no external executable dependencies.
function zip(entries: Record<string, string | Buffer>): Buffer {
  const local: Buffer[] = [], central: Buffer[] = []; let offset = 0;
  for (const [path, content] of Object.entries(entries)) {
    const name = Buffer.from(path), bytes = Buffer.from(content);
    let crc = 0xffffffff;
    for (const byte of bytes) {
      crc ^= byte;
      for (let bit = 0; bit < 8; bit++) crc = crc & 1 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
    }
    crc = (crc ^ 0xffffffff) >>> 0;
    const header = Buffer.alloc(30); header.writeUInt32LE(0x04034b50); header.writeUInt16LE(20, 4);
    header.writeUInt32LE(crc, 14); header.writeUInt32LE(bytes.length, 18); header.writeUInt32LE(bytes.length, 22); header.writeUInt16LE(name.length, 26);
    local.push(header, name, bytes);
    const directory = Buffer.alloc(46); directory.writeUInt32LE(0x02014b50); directory.writeUInt16LE(20, 6);
    directory.writeUInt32LE(crc, 16); directory.writeUInt32LE(bytes.length, 20); directory.writeUInt32LE(bytes.length, 24); directory.writeUInt16LE(name.length, 28); directory.writeUInt32LE(offset, 42);
    central.push(directory, name); offset += header.length + name.length + bytes.length;
  }
  const end = Buffer.alloc(22), directory = Buffer.concat(central);
  end.writeUInt32LE(0x06054b50); end.writeUInt16LE(central.length / 2, 8); end.writeUInt16LE(central.length / 2, 10); end.writeUInt32LE(directory.length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...local, directory, end]);
}
function entries(body = '<p>본문</p>'): Record<string, string | Buffer> {
  return {
    mimetype: 'application/epub+zip',
    'META-INF/container.xml': '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
    'OPS/book.opf': '<package version="3.0"><metadata/><manifest><item id="ch" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="ch"/></spine></package>',
    'OPS/chapter.xhtml': `<html xmlns="http://www.w3.org/1999/xhtml"><head/><body>${body}</body></html>`,
  };
}
const check = (files: Record<string, string | Buffer>) => validateUpload('book', 'epub', zip(files));
test('catalog rejects the audit external-resource reproduction', async () => {
  await assert.rejects(validateUpload('book', 'epub', readFileSync('../docs/audits/2026-09-25/remote-resource-fixture.epub')), ApiError);
});
test('local text and entity-encoded text remain valid', async () => {
  await check(entries('<p>봄 &amp; 여름</p>'));
});
test('markup and repeated style blocks cannot load remote or executable resources', async () => {
  for (const body of [
    '<img src="https://example.invalid/image.png"/>',
    '<img src="https&#58;//example.invalid/image.png"/>',
    '<script>alert(1)</script>', '<p onclick="alert(1)">text</p>',
    '<style>p {color:red}</style><style>p {background:url(https://example.invalid/x)}</style>',
    '<style>p {background:url(h\\74 tps://example.invalid/x)}</style>',
  ]) await assert.rejects(check(entries(body)), ApiError, body);
});
test('missing manifest resources and broken spine are rejected before publication', async () => {
  const missing = entries(); delete missing['OPS/chapter.xhtml'];
  await assert.rejects(check(missing), ApiError);
  const spine = entries(); spine['OPS/book.opf'] = String(spine['OPS/book.opf']).replace('idref="ch"', 'idref="missing"');
  await assert.rejects(check(spine), ApiError);
});
test('CRC corruption and malformed Unicode cannot pass upload inspection', async () => {
  const bytes = zip(entries()); const marker = Buffer.from('본문');
  bytes[bytes.indexOf(marker)] ^= 1;
  await assert.rejects(validateUpload('book', 'epub', bytes), ApiError);
  const unicode = entries(); unicode['OPS/chapter.xhtml'] = Buffer.from([0xff, 0x01]);
  await assert.rejects(check(unicode), ApiError);
});
test('entry count and document expansion limits match supported reader bounds', async () => {
  const many = entries(); for (let i = 0; i < 4093; i++) many[`extra/${i}`] = '';
  await assert.rejects(check(many), ApiError);
  const big = entries(); big['OPS/chapter.xhtml'] = 'x'.repeat(4 * 1024 * 1024 + 1);
  await assert.rejects(check(big), ApiError);
});
