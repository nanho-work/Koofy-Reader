import { createHash } from 'node:crypto';
import { strToU8, zipSync, Zippable } from 'fflate';
import { requireValue, limits } from './content';

export interface MonthlyStory { title: string; text: string; byline?: string; image: Buffer }
const xml = (s: string) => s.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&apos;');
const page = (title: string, language: string, body: string) => `<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="${language}" xml:lang="${language}"><head><title>${xml(title)}</title><link rel="stylesheet" type="text/css" href="style.css"/></head><body>${body}</body></html>`;
/** Fixed illustrations, reflowable prose. The first illustration occupies one reader column. */
export function buildMonthlyEpub(title: string, language: 'ko' | 'en' | 'ja', stories: MonthlyStory[]): Buffer {
  requireValue(stories.length > 0 && stories.length <= 100, '합본은 1~100개 회차로 만들 수 있습니다.');
  const files: Zippable = { mimetype: [strToU8('application/epub+zip'), { level: 0 }] };
  const put = (path: string, text: string) => { files[path] = strToU8(text); };
  put('META-INF/container.xml', '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>');
  put('EPUB/style.css', 'body{margin:0;padding:0}figure{margin:0;height:95vh;max-height:95vh;display:flex;flex-direction:column;align-items:center;justify-content:center;break-after:column;page-break-after:always;-webkit-column-break-after:always;break-inside:avoid}figure img{display:block;max-width:100%;max-height:85vh;object-fit:contain;min-height:0}figcaption{margin:0 0 1em;text-align:center}h1{font-size:1.4em}p{white-space:normal;line-height:1.7}');
  const manifest: string[] = [], spine: string[] = [], nav: string[] = [];
  stories.forEach((story, i) => {
    requireValue(story.text.trim() && story.image.length, '본문과 회차 이미지가 필요합니다.');
    const name = `story-${i + 1}`;
    files[`EPUB/${name}.jpg`] = story.image;
    // A repeated first-line title in uploaded TXT is metadata, not another heading.
    let text = story.text.replace(/\r\n?/g, '\n').trim();
    if (text.split('\n')[0].normalize('NFC').trim() === story.title.normalize('NFC').trim()) text = text.includes('\n') ? text.slice(text.indexOf('\n') + 1).trim() : '';
    requireValue(text, '제목 외에 본문을 입력해 주세요.');
    const paragraphs = text.split(/\n\s*\n/).map(p => `<p>${xml(p.trim()).replace(/\n/g, '<br/>')}</p>`).join('');
    const byline = story.byline ? `<figcaption>${xml(({ ko: '글쓴이: ', en: 'By ', ja: '文：' })[language] + story.byline)}</figcaption>` : '';
    put(`EPUB/${name}.xhtml`, page(story.title, language, `<figure>${byline}<img src="${name}.jpg" alt="${xml(story.title)}"/></figure><section><h1>${xml(story.title)}</h1>${paragraphs}</section>`));
    manifest.push(`<item id="${name}" href="${name}.xhtml" media-type="application/xhtml+xml"/><item id="image-${i}" href="${name}.jpg" media-type="image/jpeg"${i === 0 ? ' properties="cover-image"' : ''}/>`);
    spine.push(`<itemref idref="${name}"/>`);
    nav.push(`<li><a href="${name}.xhtml">${xml(story.title)}</a></li>`);
  });
  put('EPUB/nav.xhtml', page(title, language, `<nav epub:type="toc" id="toc"><h1>${xml(title)}</h1><ol>${nav.join('')}</ol></nav>`));
  const identifier = createHash('sha256').update(title).update(language).update(stories.map(s => s.title + s.text + s.byline).join('\n')).digest('hex');
  put('EPUB/package.opf', `<?xml version="1.0" encoding="UTF-8"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">urn:sha256:${identifier}</dc:identifier><dc:title>${xml(title)}</dc:title><dc:language>${language}</dc:language><meta property="dcterms:modified">${new Date().toISOString().replace(/\.\d+Z$/, 'Z')}</meta></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="style" href="style.css" media-type="text/css"/>${manifest.join('')}</manifest><spine>${spine.join('')}</spine><guide><reference type="cover" title="Cover" href="story-1.xhtml"/></guide></package>`);
  const bytes = Buffer.from(zipSync(files));
  requireValue(bytes.length <= limits.epub, '생성된 EPUB이 20MB를 넘습니다. 회차 이미지 용량을 줄여 주세요.');
  return bytes;
}
