import { createHash } from 'node:crypto';
import sharp from 'sharp';
import yauzl from 'yauzl';
import { XMLParser, XMLValidator } from 'fast-xml-parser';
import iconv from 'iconv-lite';

export class ApiError extends Error {
  constructor(readonly status: number, message: string) { super(message); }
}
export function requireValue(value: unknown, message: string): asserts value {
  if (!value) throw new ApiError(400, message);
}
export type Kind = 'book' | 'font';
export interface Asset { path: string; sha256: string; size: number; contentType: string; extension: string; weight?: number }
export interface Metadata { title: string; author: string; description: string; license: string; category?: string; source?: string }
export interface Snapshot extends Metadata { assets: Record<string, Asset>; version: number; preview?: Asset }
export interface Content extends Metadata {
  id: string; kind: Kind; revision: number; assets: Record<string, Asset>;
  published: boolean; publishedContent: Snapshot | null; updatedAt: string;
  deleting?: boolean;
}
export function kind(value: unknown): Kind {
  requireValue(value === 'book' || value === 'font', '콘텐츠 종류를 확인해 주세요.');
  return value;
}
export function id(value: unknown): string {
  requireValue(typeof value === 'string' && /^[a-f0-9]{32}$/.test(value), '잘못된 콘텐츠 ID입니다.');
  return value;
}
export function metadata(input: unknown): Metadata {
  requireValue(input && typeof input === 'object', '제목과 제작자 정보를 입력해 주세요.');
  const data = input as Record<string, unknown>;
  function field(key: string, max: number, required = false) {
    const value = data[key];
    requireValue(typeof value === 'string' && value.trim().length <= max && (!required || value.trim().length > 0), `${key} 입력을 확인해 주세요.`);
    return value.trim();
  }
  const category = data.category === undefined ? '기타' : categoryName(data.category);
  const source = data.source === undefined ? '' : field('source', 500);
  return { category, source, title: field('title', 160, true), author: field('author', 120, true), description: field('description', 2000), license: field('license', 2000, true) };
}
export const defaultCategories = ['시', '소설', '에세이', '기타'];
export function categoryName(value: unknown): string {
  requireValue(typeof value === 'string', '도서 분류를 입력해 주세요.');
  const name = value.normalize('NFC').trim();
  requireValue(name.length > 0 && name.length <= 40 && !/[\u0000-\u001f\u007f]/.test(name), '도서 분류는 줄바꿈 없이 1~40자로 입력해 주세요.');
  return name;
}
export function revision(value: unknown): number {
  const result = typeof value === 'string' && /^\d+$/.test(value) ? Number(value) : value;
  requireValue(typeof result === 'number' && Number.isSafeInteger(result) && result >= 1, '버전 정보를 확인해 주세요.');
  return result;
}
export function assertRevision(item: Content, expected: number) {
  if (item.deleting) throw new ApiError(409, '삭제 중인 콘텐츠입니다. 삭제를 다시 시도해 주세요.');
  if (item.revision !== expected) throw new ApiError(409, '다른 변경이 저장되었습니다. 목록을 새로고침한 뒤 다시 시도해 주세요.');
}
export function publish(item: Content): Snapshot {
  requireValue(item.kind === 'book' ? Boolean(item.assets.epub) !== Boolean(item.assets.txt) && item.assets.cover : Object.keys(item.assets).some(key => /^font[1-9]00$/.test(key)),
    item.kind === 'book' ? 'EPUB 또는 TXT 한 개와 표지를 먼저 업로드해 주세요.' : '글꼴 파일을 하나 이상 업로드해 주세요.');
  const fields = metadata(item);
  return { ...fields, assets: item.assets, version: item.revision + 1 };
}
export function publicItem(item: Content) {
  if (item.deleting || !item.published || !item.publishedContent) throw new ApiError(404, '공개된 콘텐츠가 없습니다.');
  const snapshot = item.publishedContent;
  const assets = Object.fromEntries(Object.entries(snapshot.assets).map(([key, { path: _path, ...asset }]) => [key, asset]));
  const { preview, ...fields } = snapshot;
  return { id: item.id, kind: item.kind, ...fields, assets, ...(preview ? { preview: { sha256: preview.sha256, size: preview.size, extension: preview.extension } } : {}) };
}
export function requireSuperAdmin(claims: { superAdmin?: unknown }) {
  if (claims.superAdmin !== true) throw new ApiError(403, '총괄 관리자 권한이 필요합니다.');
}
export function bearer(header: string | undefined): string {
  if (!header || !/^Bearer \S+$/.test(header)) throw new ApiError(401, '관리자 로그인이 필요합니다.');
  return header.slice(7);
}
export const limits = { epub: 20 * 1024 * 1024, txt: 20 * 1024 * 1024, cover: 5 * 1024 * 1024, font: 10 * 1024 * 1024 };

// One body per book. Replacing its format changes only the draft; published
// assets remain immutable until the administrator publishes again.
export function replaceAsset(item: Content, slot: string, asset: Asset): Record<string, Asset> {
  const assets = { ...item.assets, [slot]: asset };
  if (item.kind === 'book' && slot === 'txt') delete assets.epub;
  if (item.kind === 'book' && slot === 'epub') delete assets.txt;
  return assets;
}

export function normalizeText(bytes: Buffer): Buffer {
  requireValue(bytes.length > 0 && bytes.length <= limits.txt, 'TXT는 20MB 이하여야 합니다.');
  const bomEncoding = bytes[0] === 0xff && bytes[1] === 0xfe ? 'utf-16le'
    : bytes[0] === 0xfe && bytes[1] === 0xff ? 'utf-16be'
    : bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf ? 'utf-8' : null;
  let text: string;
  try {
    if (bomEncoding) text = new TextDecoder(bomEncoding, { fatal: true }).decode(bytes);
    else {
      try { text = new TextDecoder('utf-8', { fatal: true }).decode(bytes); }
      catch {
        text = iconv.decode(bytes, 'cp949');
        // Do not silently replace undecodable bytes or guess a lossy encoding.
        if (!iconv.encode(text, 'cp949').equals(bytes)) throw new Error('Invalid CP949');
      }
    }
  } catch { throw new ApiError(400, 'TXT 인코딩을 읽을 수 없습니다. UTF-8로 저장한 뒤 다시 등록해 주세요.'); }
  requireValue(text.trim().length > 0, '내용이 있는 TXT 파일을 선택해 주세요.');
  requireValue(!/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f\ufffe\uffff]/.test(text), '일반 텍스트 파일이 아닙니다. TXT 파일을 확인해 주세요.');
  const output = Buffer.from(text.replace(/\r\n?/g, '\n'), 'utf8');
  requireValue(output.length <= limits.txt, 'UTF-8 변환 후 TXT 크기가 20MB를 넘습니다. 파일을 나누어 등록해 주세요.');
  return output;
}


const crcTable = Array.from({ length: 256 }, (_, value) => {
  for (let bit = 0; bit < 8; bit++) value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
  return value >>> 0;
});
function localEpubPath(base: string, reference: unknown): string {
  requireValue(typeof reference === 'string' && reference.length > 0 &&
    !/^[a-z][a-z0-9+.-]*:|^\/|\?|\\/i.test(reference), '외부 EPUB 리소스는 지원하지 않습니다.');
  let path: string;
  try { path = decodeURIComponent(reference.split('#')[0]); } catch { throw new ApiError(400, 'EPUB 경로를 확인해 주세요.'); }
  requireValue(!/[\\:\0]/.test(path), 'EPUB 경로를 확인해 주세요.');
  const parts: string[] = [];
  for (const part of (base + path).split('/')) {
    if (!part || part === '.') continue;
    if (part === '..') { requireValue(parts.length, 'EPUB 바깥 경로는 지원하지 않습니다.'); parts.pop(); }
    else parts.push(part);
  }
  requireValue(parts.length, '빈 EPUB 경로입니다.');
  return parts.join('/');
}
function inspectCss(css: string) {
  const decoded = css.replace(/\\([0-9a-fA-F]{1,6})\s?|\\(.)/g, (_, hex, char) => {
    const code = hex ? parseInt(hex, 16) : 0;
    return hex ? code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : '' : char ?? '';
  }).replace(/\/\*[\s\S]*?\*\//g, '').replace(/\s+/g, '').toLowerCase();
  requireValue(!['http:', 'https:', 'url(//', 'url("//', "url('//", 'javascript:', 'data:', 'file:', 'ftp:', 'expression(', '@import'].some(s => decoded.includes(s)),
    '외부 리소스 또는 실행 가능한 CSS는 지원하지 않습니다.');
}
function inspectMarkup(value: unknown) {
  if (Array.isArray(value)) { value.forEach(inspectMarkup); return; }
  if (!value || typeof value !== 'object') return;
  for (const [key, child] of Object.entries(value)) {
    const name = key.toLowerCase();
    requireValue(!['script','iframe','object','embed','form','base','animate','animatetransform','animatemotion','set'].includes(name), '실행 가능한 EPUB은 지원하지 않습니다.');
    if (name.startsWith('@_')) {
      const attr = name.slice(2), text = String(child).replace(/[\u0000-\u0020]/g, '').toLowerCase();
      requireValue(!attr.startsWith('on') && attr !== 'base' && !/^(javascript|vbscript):/.test(text), '실행 가능한 EPUB 속성입니다.');
      if (['src','href','srcset','poster','data','action'].includes(attr)) {
        requireValue(!/(^|,)[a-z][a-z0-9+.-]*:|^\/|\\/.test(text), '외부 리소스 EPUB은 지원하지 않습니다.');
      }
      if (attr === 'style') inspectCss(String(child));
    }
    if (name === 'style') {
      for (const style of Array.isArray(child) ? child : [child]) inspectCss(typeof style === 'string' ? style : String((style as any)?.['#text'] ?? ''));
    }
    if (name === 'meta') {
      const rows = Array.isArray(child) ? child : [child];
      requireValue(!rows.some(row => String(row?.['@_http-equiv']).toLowerCase() === 'refresh'), '자동 이동 EPUB은 지원하지 않습니다.');
    }
    inspectMarkup(child);
  }
}

// Inspect every ZIP entry without extracting it to disk. Bounded decompression
// prevents a small compressed upload from exhausting the function's memory.
async function inspectEpub(bytes: Buffer): Promise<void> {
  const entryNames = new Set<string>();
  const files = await new Promise<Map<string, Buffer>>((resolve, reject) => {
    yauzl.fromBuffer(bytes, { lazyEntries: true, validateEntrySizes: true }, (error, zip) => {
      if (error || !zip) { reject(new ApiError(400, '올바른 EPUB ZIP 파일이 아닙니다.')); return; }
      let count = 0, total = 0, metadataBytes = 0;
      const all = entryNames, xml = new Map<string, Buffer>();
      let stopped = false;
      const fail = (error: unknown) => { if (!stopped) { stopped = true; zip.close(); reject(error); } };
      zip.on('error', fail);
      zip.on('end', () => { if (!stopped) resolve(xml); });
      zip.on('entry', (entry: yauzl.Entry) => {
        try {
          const name = entry.fileName;
          requireValue(++count <= 4096 && !all.has(name) && !name.includes('\\') && !name.startsWith('/') && !name.includes(':') && !name.includes('\0') && !name.split('/').some(p => p === '..' || p === '.') && ((entry.externalFileAttributes >>> 16) & 0xf000) !== 0xa000, 'EPUB 파일 경로가 올바르지 않습니다.');
          all.add(name);
          total += entry.uncompressedSize;
          requireValue(total <= 128 * 1024 * 1024 && entry.uncompressedSize <= 30 * 1024 * 1024 && !(entry.generalPurposeBitFlag & 1), 'EPUB 압축 해제 크기 또는 암호화를 확인해 주세요.');
          const keep = name === 'mimetype' || name === 'META-INF/container.xml' || name === 'META-INF/encryption.xml' || /\.(opf|xhtml|html|htm|svg|css)$/i.test(name);
          if (keep) metadataBytes += entry.uncompressedSize;
          requireValue(!keep || (entry.uncompressedSize <= 4 * 1024 * 1024 && metadataBytes <= 128 * 1024 * 1024), 'EPUB 메타데이터가 너무 큽니다.');
          zip.openReadStream(entry, (error, stream) => {
            if (error || !stream) { fail(error); return; }
            const chunks: Buffer[] = []; let length = 0, checksum = 0xffffffff;
            stream.on('data', (chunk: Buffer) => {
              length += chunk.length;
              for (const byte of chunk) checksum = crcTable[(checksum ^ byte) & 255] ^ (checksum >>> 8);
              if (length > entry.uncompressedSize) { stream.destroy(); fail(new ApiError(400, 'EPUB 메타데이터가 너무 큽니다.')); }
              else if (keep) chunks.push(chunk);
            });
            stream.on('error', fail);
            stream.on('end', () => {
              if (stopped) return;
              if (length !== entry.uncompressedSize || ((checksum ^ 0xffffffff) >>> 0) !== entry.crc32) {
                fail(new ApiError(400, 'EPUB 파일 무결성이 올바르지 않습니다.')); return;
              }
              if (keep) xml.set(name, Buffer.concat(chunks));
              zip.readEntry();
            });
          });
        } catch (error) { fail(error); }
      });
      zip.readEntry();
    });
  });
  requireValue(files.get('mimetype')?.toString() === 'application/epub+zip', 'EPUB mimetype이 없습니다.');
  // Initial catalog accepts unencrypted EPUBs only, including no obfuscated fonts.
  requireValue(!files.has('META-INF/encryption.xml'), '암호화된 EPUB는 등록할 수 없습니다.');
  const text = (file: Buffer | undefined): string => {
    requireValue(file, 'EPUB 문서가 없습니다.');
    const encoding = file[0] === 0xff && file[1] === 0xfe ? 'utf-16le'
      : file[0] === 0xfe && file[1] === 0xff ? 'utf-16be' : 'utf-8';
    try { return new TextDecoder(encoding, { fatal: true }).decode(file); }
    catch { throw new ApiError(400, 'EPUB 문서 인코딩을 확인해 주세요.'); }
  };
  const parse = (file: Buffer | undefined) => {
    const source = text(file);
    requireValue(!/<!DOCTYPE|<!ENTITY/i.test(source), 'EPUB XML을 확인해 주세요.');
    requireValue(XMLValidator.validate(source) === true, 'EPUB XML 형식이 올바르지 않습니다.');
    return new XMLParser({ ignoreAttributes: false, removeNSPrefix: true, processEntities: true, htmlEntities: true }).parse(source);
  };
  const container = parse(files.get('META-INF/container.xml'));
  const roots = container.container?.rootfiles?.rootfile;
  const root = (Array.isArray(roots) ? roots[0] : roots)?.['@_full-path'];
  requireValue(typeof root === 'string' && files.has(root), 'EPUB 패키지를 찾을 수 없습니다.');
  const opf = parse(files.get(root));
  requireValue(opf.package?.manifest && opf.package?.spine, 'EPUB 목차 구조가 올바르지 않습니다.');
  const meta = opf.package.metadata?.meta;
  const metas = Array.isArray(meta) ? meta : [meta];
  requireValue(!metas.some(item => item?.['@_property'] === 'rendition:layout' && item['#text'] === 'pre-paginated'), '현재 배포 목록은 가변 레이아웃 EPUB만 지원합니다.');
  requireValue(['2.0', '3.0'].includes(String(opf.package?.['@_version'])), '지원하는 EPUB 버전이 아닙니다.');
  const array = (value: any): any[] => value == null ? [] : Array.isArray(value) ? value : [value];
  const manifest = new Map<string, any>();
  const base = root.includes('/') ? root.slice(0, root.lastIndexOf('/') + 1) : '';
  for (const item of array(opf.package.manifest.item)) {
    const key = item['@_id'];
    requireValue(typeof key === 'string' && key && !manifest.has(key), 'EPUB manifest ID를 확인해 주세요.');
    const path = localEpubPath(base, item['@_href']);
    requireValue(entryNames.has(path), 'EPUB 리소스가 누락되었습니다.');
    requireValue(!/\b(scripted|remote-resources)\b/.test(item['@_properties'] ?? ''), '스크립트 또는 외부 리소스 EPUB은 지원하지 않습니다.');
    if (['application/xhtml+xml', 'image/svg+xml', 'text/css'].includes(item['@_media-type'])) {
      requireValue(files.has(path), '본문과 스타일은 XHTML, SVG, CSS 확장자를 사용해 주세요.');
    }
    manifest.set(key, item);
  }
  const spine = array(opf.package.spine.itemref);
  requireValue(spine.length > 0, 'EPUB 본문이 없습니다.');
  for (const item of spine) {
    requireValue(manifest.get(item['@_idref'])?.['@_media-type'] === 'application/xhtml+xml' &&
      !String(item['@_properties'] ?? '').includes('rendition:layout-pre-paginated'), '지원하는 EPUB 본문 순서가 아닙니다.');
  }
  requireValue(!entryNames.has('META-INF/license.lcpl') && !entryNames.has('META-INF/rights.xml'), 'DRM EPUB은 지원하지 않습니다.');
  requireValue(!metas.some(item => item?.['@_name'] === 'fixed-layout' && item['@_content'] === 'true'), '고정 레이아웃은 지원하지 않습니다.');
  for (const [name, data] of files) {
    if (/\.(xhtml|html|htm|svg)$/i.test(name)) inspectMarkup(parse(data));
    else if (/\.css$/i.test(name)) inspectCss(text(data));
  }

}
export function inspectFont(bytes: Buffer): 'otf' | 'ttf' {
  requireValue(bytes.length >= 12, '글꼴 파일이 너무 짧습니다.');
  const otf = bytes.subarray(0, 4).toString('ascii') === 'OTTO';
  requireValue(otf || bytes.readUInt32BE(0) === 0x00010000, 'OTF 또는 TTF 파일을 선택해 주세요.');
  const count = bytes.readUInt16BE(4);
  requireValue(count > 0 && count <= 200 && bytes.length >= 12 + count * 16, '글꼴 테이블이 올바르지 않습니다.');
  const tags = new Set<string>();
  for (let i = 0; i < count; i++) {
    const offset = 12 + i * 16;
    const tag = bytes.subarray(offset, offset + 4).toString('ascii');
    const start = bytes.readUInt32BE(offset + 8), length = bytes.readUInt32BE(offset + 12);
    requireValue(!tags.has(tag) && start >= 12 + count * 16 && start + length <= bytes.length, '글꼴 테이블 범위를 확인해 주세요.');
    tags.add(tag);
  }
  requireValue(['head', 'name', 'cmap'].every(tag => tags.has(tag)) && (tags.has('CFF ') || tags.has('CFF2') || tags.has('glyf')), '지원하는 글꼴 테이블이 없습니다.');
  requireValue(!tags.has('fvar'), '가변 글꼴은 정적 OTF/TTF로 변환한 뒤 등록해 주세요.');
  return otf ? 'otf' : 'ttf';
}
export async function validateUpload(contentKind: Kind, slot: string, bytes: Buffer) {
  let output = bytes, extension: string, contentType: string, weight: number | undefined;
  if (contentKind === 'book' && slot === 'epub') {
    requireValue(bytes.length > 0 && bytes.length <= limits.epub, 'EPUB는 20MB 이하여야 합니다.');
    try { await inspectEpub(bytes); }
    catch (error) { throw error instanceof ApiError ? error : new ApiError(400, 'EPUB 압축 파일을 읽을 수 없습니다.'); }
    extension = 'epub'; contentType = 'application/epub+zip';
  } else if (contentKind === 'book' && slot === 'txt') {
    output = normalizeText(bytes);
    extension = 'txt'; contentType = 'text/plain; charset=utf-8';
  } else if (contentKind === 'book' && slot === 'cover') {
    requireValue(bytes.length > 0 && bytes.length <= limits.cover, '표지는 5MB 이하여야 합니다.');
    try {
      const source = sharp(bytes, { limitInputPixels: 25_000_000, animated: false });
      const info = await source.metadata();
      requireValue(['jpeg', 'png', 'webp'].includes(info.format ?? '') && (info.pages ?? 1) === 1, 'PNG, JPG, WebP 정지 이미지를 선택해 주세요.');
      output = await source.rotate().resize({ width: 900, height: 1200, fit: 'inside', withoutEnlargement: true }).webp({ quality: 85 }).toBuffer();
    } catch { throw new ApiError(400, '표지 이미지를 읽을 수 없습니다. PNG, JPG, WebP를 확인해 주세요.'); }
    extension = 'webp'; contentType = 'image/webp';
  } else if (contentKind === 'font' && /^font[1-9]00$/.test(slot)) {
    requireValue(bytes.length > 0 && bytes.length <= limits.font, '글꼴은 파일당 10MB 이하여야 합니다.');
    extension = inspectFont(bytes); contentType = extension === 'otf' ? 'font/otf' : 'font/ttf'; weight = Number(slot.slice(4));
  } else throw new ApiError(400, '지원하지 않는 파일 종류입니다.');
  return { bytes: output, asset: { sha256: createHash('sha256').update(output).digest('hex'), size: output.length, contentType, extension, ...(weight ? { weight } : {}) } };
}
