import { createHash } from 'node:crypto';
import { create } from 'fontkit';
import sharp from 'sharp';
import { ApiError, Asset, Content, inspectFont, limits, requireValue } from './content';

// Prefer Regular; otherwise choose the closest available weight (lighter on ties).
export function previewFace(item: Content): Asset {
  const faces = Object.entries(item.assets).filter(([slot]) => /^font[1-9]00$/.test(slot));
  faces.sort(([a], [b]) => Math.abs(Number(a.slice(4)) - 400) - Math.abs(Number(b.slice(4)) - 400) || a.localeCompare(b));
  requireValue(item.kind === 'font' && faces.length > 0, '글꼴 파일을 먼저 등록해 주세요.');
  return faces[0][1];
}

/** Render paths, not SVG <text>: no system fonts, external resources or fallback
 * fonts can silently substitute for the uploaded font. Transparent black pixels
 * allow the app to tint the small PNG for both light and dark reader themes. */
export async function renderFontPreview(bytes: Buffer, title: string): Promise<{ bytes: Buffer; asset: Omit<Asset, 'path'> } | null> {
  requireValue(bytes.length <= limits.font && title.trim().length > 0 && title.length <= 160, '미리보기 정보를 확인해 주세요.');
  inspectFont(bytes);
  try {
    const font = create(bytes);
    if (!('layout' in font)) throw new Error('Font collections are not supported');
    const run = font.layout(title);
    // Names containing unsupported characters remain plain text in the app.
    if (run.glyphs.some(glyph => glyph.id === 0)) return null;
    let x = 0, y = 0, minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    const paths: string[] = [];
    for (let i = 0; i < run.glyphs.length; i++) {
      const glyph = run.glyphs[i], position = run.positions[i];
      const dx = x + position.xOffset, dy = y + position.yOffset;
      const path = glyph.path.toSVG();
      if (path) {
        const box = glyph.bbox;
        minX = Math.min(minX, dx + box.minX); maxX = Math.max(maxX, dx + box.maxX);
        minY = Math.min(minY, dy + box.minY); maxY = Math.max(maxY, dy + box.maxY);
        paths.push(`<path transform="translate(${dx} ${dy})" d="${path}"/>`);
      }
      x += position.xAdvance; y += position.yAdvance;
    }
    if (!paths.length) return null;
    const width = maxX - minX, height = maxY - minY;
    requireValue(Number.isFinite(width) && Number.isFinite(height) && width > 0 && height > 0, '글꼴 윤곽을 읽을 수 없습니다.');
    // At most 2048 × 80 pixels and 128 KiB, regardless of font metrics/title.
    const scale = Math.min(72 / height, 2040 / width);
    const pixelWidth = Math.ceil(width * scale) + 8;
    const pixelHeight = Math.ceil(height * scale) + 8;
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${pixelWidth}" height="${pixelHeight}" viewBox="0 0 ${pixelWidth} ${pixelHeight}"><g fill="black" transform="translate(${4 - minX * scale} ${4 + maxY * scale}) scale(${scale} ${-scale})">${paths.join('')}</g></svg>`;
    requireValue(Buffer.byteLength(svg) <= 4 * 1024 * 1024, '미리보기 윤곽이 너무 복잡합니다.');
    const png = await sharp(Buffer.from(svg)).png().toBuffer();
    requireValue(png.length <= 128 * 1024, '미리보기 이미지가 너무 큽니다.');
    return { bytes: png, asset: { sha256: createHash('sha256').update(png).digest('hex'), size: png.length, extension: 'png', contentType: 'image/png' } };
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw new ApiError(400, '글꼴 미리보기를 생성하지 못했습니다. 파일과 글꼴 이름을 확인해 주세요.');
  }
}
