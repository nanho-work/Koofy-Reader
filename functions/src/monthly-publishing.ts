import { createHash, randomUUID } from 'node:crypto';
import { Firestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import sharp from 'sharp';
import { Asset, Content, Snapshot, ApiError, assertRevision, isReleased, normalizeText, publicationDay, publish, requireValue, validateUpload } from './content';
import { buildMonthlyEpub, MonthlyStory } from './monthly-epub';

type Bucket = ReturnType<ReturnType<typeof getStorage>['bucket']>;
// Use editorial release time, not upload time or the draft's edited date.
export function compilationEpisodes(series: Content, episodes: Content[], now = new Date()): Content[] {
  const month = series.publishedContent?.issueMonth;
  if (!month) return [];
  const start = Date.parse(`${month}-01T00:00:00+09:00`);
  const [year, number] = month.split('-').map(Number);
  const end = Date.UTC(year, number, 1) - 9 * 3600000;
  const time = (e: Content) => Date.parse(e.publishedContent?.releaseAt || `${e.publishedContent?.releaseDate || ''}T00:00:00+09:00`);
  return episodes.filter(e => e.kind === 'book' && e.published && !e.deleting && e.publishedContent?.seriesId === series.id &&
    (e.publishedContent.language || 'ko') === (series.publishedContent?.language || 'ko') &&
    time(e) >= start && time(e) < end && time(e) <= now.getTime() && isReleased(e, now))
    .sort((a, b) => time(a) - time(b) || (a.publishedContent!.episodeNumber || 0) - (b.publishedContent!.episodeNumber || 0) || a.id.localeCompare(b.id));
}
export function compilationEligibility(series: Content, episodes: Content[], now = new Date(), manual = false): string | null {
  const snapshot = series.publishedContent;
  if (series.kind !== 'series' || series.deleting || !series.published || !snapshot?.issueMonth) return '공개된 월간호가 필요합니다.';
  if (snapshot.compilationId) return '이미 합본이 연결되어 있습니다.';
  if (!manual && (!snapshot.autoCompile || snapshot.issueMonth >= publicationDay(now).slice(0, 7))) return '자동 합본 마감 시각 전입니다.';
  const included = compilationEpisodes(series, episodes, now);
  if (!included.length) return '해당 월에 공개된 회차가 없어 합본을 만들지 않았습니다.';
  if (included.some(e => !(e.publishedContent?.sourceTxt || e.publishedContent?.assets.txt))) return '합본 대상 회차에 TXT 원본이 없습니다. 해당 회차에 TXT를 올리고 다시 공개해 주세요.';
  return null;
}
export function monthlyPublisher(db: Firestore, bucket: Bucket) {
  const contents = db.collection('readerContent');
  async function read(asset: Asset): Promise<Buffer> {
    requireValue(asset.size > 0 && asset.size <= 20 * 1024 * 1024, '원본 파일 크기가 올바르지 않습니다.');
    const [bytes] = await bucket.file(asset.path).download();
    requireValue(bytes.length === asset.size && createHash('sha256').update(bytes).digest('hex') === asset.sha256, '원본 파일이 변경되었거나 손상되었습니다. 다시 올려 주세요.');
    return bytes;
  }
  async function story(snapshot: Snapshot): Promise<MonthlyStory> {
    const source = snapshot.sourceTxt || snapshot.assets.txt;
    requireValue(source && snapshot.assets.cover, '회차 TXT와 이미지가 필요합니다.');
    const normalized = normalizeText(await read(source));
    requireValue(normalized.length <= 1024 * 1024, '월간 회차 본문은 UTF-8 기준 1MB 이하로 등록해 주세요.');
    const text = normalized.toString('utf8');
    const image = await sharp(await read(snapshot.assets.cover)).rotate().resize({ width: 1200, height: 1200, fit: 'inside', withoutEnlargement: true }).flatten({ background: '#ffffff' }).jpeg({ quality: 80 }).toBuffer();
    return { title: snapshot.title, text, byline: snapshot.byline, image };
  }
  async function store(contentId: string, bytes: Buffer): Promise<Asset> {
    const validated = await validateUpload('book', 'epub', bytes);
    const path = `readerContent/${contentId}/${randomUUID()}/monthly.epub`;
    await bucket.file(path).save(validated.bytes, { resumable: false, contentType: 'application/epub+zip', metadata: { cacheControl: 'private, max-age=300' }, preconditionOpts: { ifGenerationMatch: 0 } });
    return { ...validated.asset, path };
  }
  async function episode(item: Content, snapshot: Snapshot): Promise<Asset | undefined> {
    if (!snapshot.issueMonth || !snapshot.seriesId || !snapshot.assets.txt) return;
    requireValue(item.assets.cover, '월간 회차에는 회차별 이미지를 올려 주세요.');
    const epub = await store(item.id, buildMonthlyEpub(snapshot.title, snapshot.language || 'ko', [await story(snapshot)]));
    snapshot.sourceTxt = snapshot.assets.txt;
    snapshot.assets = { cover: snapshot.assets.cover, epub };
    return epub;
  }
  async function compile(seriesId: string, expectedRevision?: number): Promise<Content> {
    const parentDoc = await contents.doc(seriesId).get();
    requireValue(parentDoc.exists, '월간호가 없습니다.');
    const series = parentDoc.data() as Content;
    if (expectedRevision !== undefined) assertRevision(series, expectedRevision);
    const children = await contents.where('seriesId', '==', seriesId).get();
    const episodes = children.docs.map(d => d.data() as Content);
    const problem = compilationEligibility(series, episodes, new Date(), expectedRevision !== undefined);
    requireValue(!problem, problem || '합본을 만들 수 없습니다.');
    const included = compilationEpisodes(series, episodes);
    const snapshot = series.publishedContent!;
    const stories: MonthlyStory[] = [];
    // Sequential decoding bounds peak memory even for a full month of illustrations.
    let total = 0;
    for (const child of included) {
      const next = await story(child.publishedContent!);
      total += Buffer.byteLength(next.text) + next.image.length;
      requireValue(total <= 32 * 1024 * 1024, '합본 원본 총량이 32MB를 넘습니다. 이미지 또는 본문 용량을 줄여 주세요.');
      stories.push(next);
    }
    const bookId = createHash('sha256').update(`monthly-compilation:${seriesId}`).digest('hex').slice(0, 32);
    const epub = await store(bookId, buildMonthlyEpub(snapshot.title, snapshot.language || 'ko', stories));
    try {
      return await db.runTransaction(async transaction => {
        const currentDoc = await transaction.get(contents.doc(seriesId));
        const current = currentDoc.data() as Content;
        requireValue(current, '월간호가 삭제되었습니다.');
        assertRevision(current, series.revision);
        const currentChildren = await transaction.get(contents.where('seriesId', '==', seriesId));
        const fresh = currentChildren.docs.map(d => d.data() as Content);
        requireValue(fresh.length === episodes.length && fresh.every(e => episodes.some(old => old.id === e.id && old.revision === e.revision)), '회차가 변경되었습니다. 다시 합본을 만들어 주세요.');
        const error = compilationEligibility(current, fresh, new Date(), expectedRevision !== undefined);
        requireValue(!error, error || '합본 조건이 바뀌었습니다.');
        const currentIncluded = compilationEpisodes(current, fresh);
        requireValue(currentIncluded.map(e => e.id).join(',') === included.map(e => e.id).join(','), '합본 대상이 변경되었습니다. 다시 시도해 주세요.');
        const bookRef = contents.doc(bookId);
        if ((await transaction.get(bookRef)).exists) throw new ApiError(409, '이미 생성된 합본이 있습니다. 관리자에서 연결 상태를 확인해 주세요.');
        const now = new Date().toISOString();
        const book: Content = { id: bookId, kind: 'book', revision: 1, updatedAt: now, title: snapshot.title, author: snapshot.author, license: snapshot.license, description: snapshot.description, language: snapshot.language || 'ko', issueMonth: snapshot.issueMonth, assets: { epub, cover: snapshot.assets.cover }, published: true, publishedContent: null };
        book.publishedContent = publish(book);
        book.revision = book.publishedContent.version;
        const linked: Content = { ...current, revision: current.revision + 1, updatedAt: now, compilationId: bookId, seriesStatus: 'completed', compilationError: '', publishedContent: { ...snapshot, version: current.revision + 1, compilationId: bookId, seriesStatus: 'completed', compilationLinkedAt: now } };
        transaction.create(bookRef, book);
        transaction.set(contents.doc(seriesId), linked);
        transaction.create(db.collection('readerAudit').doc(), { contentId: seriesId, action: 'compileMonthly', revision: linked.revision, at: now, episodeIds: included.map(e => e.id) });
        return linked;
      });
    } catch (error) { await bucket.file(epub.path).delete().catch(() => undefined); throw error; }
  }
  return { episode, compile };
}
