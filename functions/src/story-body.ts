import { createHash } from 'node:crypto';
import { XMLParser } from 'fast-xml-parser';
import type { getStorage } from 'firebase-admin/storage';
import { inspectEpub, limits, normalizeText, requireValue, type Asset, type Snapshot } from './content';

type Bucket = ReturnType<ReturnType<typeof getStorage>['bucket']>;
type Block = { type: 'paragraph' | 'heading'; text: string };
type XmlNode = Record<string, XmlNode[] | string>;

function sourceAsset(snapshot: Snapshot): Asset | undefined {
  return snapshot.sourceTxt || snapshot.assets.txt || snapshot.assets.epub;
}

export function storyBodyPath(contentId: string, snapshot: Snapshot) {
  const asset = sourceAsset(snapshot);
  requireValue(asset && /^[a-f0-9]{64}$/.test(asset.sha256), '웹에서 읽을 수 있는 TXT 또는 EPUB 본문이 필요합니다.');
  const key = createHash('sha256').update(JSON.stringify([asset.sha256, asset.extension, snapshot.title])).digest('hex');
  return `readerContent/${contentId}/story-v1/${key}.json`;
}

const orderedXml = new XMLParser({ preserveOrder: true, removeNSPrefix: true, trimValues: false, parseTagValue: false, htmlEntities: true });
const ignored = new Set(['head', 'nav', 'script', 'style', 'svg', 'math', 'rt', 'rp']);
const blockTags = new Set(['p', 'div', 'section', 'article', 'blockquote', 'li', 'pre', 'figcaption', 'td', 'tr', 'hr', 'br']);

function epubBlocks(nodes: XmlNode[]) {
  const blocks: Block[] = [];
  let pending: string[] = [];
  const flush = (type: Block['type'] = 'paragraph') => {
    const text = pending.join('').replace(/\s+/gu, ' ').trim();
    pending = [];
    if (text) blocks.push({ type, text });
  };
  function walk(entries: XmlNode[], depth: number) {
    requireValue(depth < 128, 'EPUB 본문의 중첩 구조가 너무 깊습니다.');
    for (const entry of entries) {
      for (const [tag, value] of Object.entries(entry)) {
        if (tag === '#text' && typeof value === 'string') pending.push(value);
        else if (!ignored.has(tag) && Array.isArray(value)) {
          const heading = /^h[1-6]$/.test(tag);
          const boundary = heading || blockTags.has(tag);
          if (boundary) flush();
          walk(value, depth + 1);
          if (boundary) flush(heading ? 'heading' : 'paragraph');
        }
      }
    }
  }
  walk(nodes, 0);
  flush();
  return blocks;
}

export async function storyBlocks(asset: Asset, bytes: Buffer, title: string): Promise<Block[]> {
  let blocks: Block[];
  if (asset.extension === 'txt') {
    let text = normalizeText(bytes).toString('utf8').trim();
    const firstLine = text.split('\n', 1)[0];
    if (firstLine.normalize('NFC').trim() === title.normalize('NFC').trim()) text = text.slice(firstLine.length).trim();
    blocks = text.split(/(?=^\[장\]\s+\S)/m).flatMap(chunk => {
      const heading = /^\[장\][^\S\n]+(.+)\n?/.exec(chunk);
      const prose = (heading ? chunk.slice(heading[0].length) : chunk).trim().split(/\n[^\S\n]*\n/).map(p => p.trim()).filter(Boolean);
      return [...(heading ? [{ type: 'heading' as const, text: heading[1].trim() }] : []), ...prose.map(text => ({ type: 'paragraph' as const, text }))];
    });
  } else {
    const epub = await inspectEpub(bytes);
    blocks = epub.spinePaths.flatMap(path => epubBlocks(orderedXml.parse(epub.text(epub.files.get(path)))));
    if (blocks[0]?.type === 'heading' && blocks[0].text === title) blocks.shift();
  }
  requireValue(blocks.some(block => block.type === 'paragraph'), '웹에 표시할 본문 텍스트를 찾을 수 없습니다.');
  return blocks;
}

export async function prepareStoryBody(bucket: Bucket, contentId: string, snapshot: Snapshot) {
  const target = bucket.file(storyBodyPath(contentId, snapshot));
  const [exists] = await target.exists();
  if (exists) return;
  const asset = sourceAsset(snapshot)!;
  requireValue(asset.size > 0 && asset.size <= limits.epub, '웹 공개용 본문의 파일 크기가 올바르지 않습니다.');
  const [bytes] = await bucket.file(asset.path).download();
  requireValue(bytes.length === asset.size && createHash('sha256').update(bytes).digest('hex') === asset.sha256, '공개된 본문 파일의 무결성을 확인해 주세요.');
  const content = Buffer.from(JSON.stringify(await storyBlocks(asset, bytes, snapshot.title)));
  requireValue(content.length <= 4 * 1024 * 1024, '웹에서 읽을 본문은 변환 후 4MB 이하여야 합니다.');
  try {
    await target.save(content, { resumable: false, contentType: 'application/json', preconditionOpts: { ifGenerationMatch: 0 } });
  } catch (error) {
    if (Number((error as { code?: unknown }).code) !== 412) throw error;
  }
}
