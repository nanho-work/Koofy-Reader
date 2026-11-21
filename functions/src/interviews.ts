import type { Firestore } from 'firebase-admin/firestore';
import type { getStorage } from 'firebase-admin/storage';
import type { Request } from 'firebase-functions/v2/https';
import type { Response } from 'express';
import { ApiError, id, requireValue, revision } from './content';

type Bucket = ReturnType<ReturnType<typeof getStorage>['bucket']>;
type Block =
  | { type: 'text'; text: string }
  | { type: 'qa'; question: string; answer: string }
  | { type: 'photo'; photo: string; caption: string; alt: string };
type Article = {
  title: string; subtitle: string; person: string; summary: string;
  cover: string; coverAlt: string; releaseAt: string; blocks: Block[];
};
type RecordData = { draft: Article; live: Article | null; revision: number; updatedAt: string };

function line(value: unknown, max: number) {
  requireValue(typeof value === 'string' && value.length <= max, '입력 길이를 확인해 주세요.');
  return value.trim();
}
function hash(value: unknown) {
  requireValue(typeof value === 'string' && /^[a-f0-9]{64}$/.test(value), '사진을 다시 선택해 주세요.');
  return value;
}
function parse(value: Article): Article {
  requireValue(value && Array.isArray(value.blocks) && value.blocks.length <= 100, '본문은 100개 항목까지 등록할 수 있습니다.');
  const releaseAt = line(value.releaseAt, 32);
  requireValue(!releaseAt || /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\+09:00$/.test(releaseAt) && Number.isFinite(Date.parse(releaseAt)), '공개 일시를 확인해 주세요.');
  const blocks = Array.from(value.blocks, (block): Block => {
    if (block?.type === 'text') return { type: 'text', text: line(block.text, 20000) };
    if (block?.type === 'qa') return { type: 'qa', question: line(block.question, 500), answer: line(block.answer, 20000) };
    requireValue(block?.type === 'photo', '본문 항목을 확인해 주세요.');
    return { type: 'photo', photo: block.photo ? hash(block.photo) : '', caption: line(block.caption, 500), alt: line(block.alt, 500) };
  });
  return { title: line(value.title, 160), subtitle: line(value.subtitle, 300), person: line(value.person, 160),
    summary: line(value.summary, 1000), cover: value.cover ? hash(value.cover) : '', coverAlt: line(value.coverAlt, 500),
    releaseAt, blocks };
}
function photos(article: Article) {
  return [...new Set([article.cover, ...article.blocks.flatMap(block => block.type === 'photo' ? [block.photo] : [])].filter(Boolean))];
}

export function interviews(db: Firestore, bucket: Bucket) {
  const collection = db.collection('readerInterviews');
  const asset = async (key: string) => {
    const file = (await db.collection('readerSharedCovers').doc(key).get()).data()?.asset;
    if (!file || !['image/jpeg', 'image/png', 'image/webp'].includes(file.contentType)) throw new ApiError(404, '사진을 찾을 수 없습니다.');
    return file as { path: string; contentType: string };
  };
  return {
    async admin(request: Request, response: Response) {
      if (request.method === 'GET') {
        if (request.query.photo) {
          const photo = await asset(hash(request.query.photo));
          const [url] = await bucket.file(photo.path).getSignedUrl({ action: 'read', version: 'v4', expires: Date.now() + 300000 });
          response.json({ url });
          return;
        }
        const docs = await collection.orderBy('updatedAt', 'desc').get();
        response.json({ items: docs.docs.map(doc => ({ ...doc.data(), id: doc.id })) });
        return;
      }
      if (request.method !== 'POST') throw new ApiError(405, '지원하지 않는 요청입니다.');
      requireValue(request.is('application/json') && request.rawBody.length <= 180 * 1024 && request.body, '원고 요청이 올바르지 않거나 너무 큽니다.');
      const { action, draft: input } = request.body;
      requireValue(['save', 'publish', 'unpublish'].includes(action), '지원하지 않는 작업입니다.');
      const ref = collection.doc(id(request.body.id));
      const expected = request.body.revision === 0 ? 0 : revision(request.body.revision);
      const draft = action === 'unpublish' ? null : parse(input);
      if (draft) {
        requireValue(draft.title, '제목을 입력해 주세요.');
        if (action === 'publish') {
          requireValue(draft.blocks.length && draft.blocks.every(block =>
            block.type === 'photo' ? block.photo : block.type === 'qa' ? block.question && block.answer : block.text), '공개 전에 본문을 채워 주세요.');
        }
        await Promise.all(photos(draft).map(asset));
      }
      const saved = await db.runTransaction(async tx => {
        const current = (await tx.get(ref)).data() as RecordData | undefined;
        if ((current?.revision ?? 0) !== expected) throw new ApiError(409, '다른 변경이 저장됐습니다. 목록을 다시 불러와 주세요.');
        if (!draft && !current) throw new ApiError(404, '기사를 찾을 수 없습니다.');
        const now = new Date().toISOString();
        const next = {
          draft: draft ?? current!.draft,
          live: action === 'publish' && draft ? { ...draft, releaseAt: draft.releaseAt ? new Date(draft.releaseAt).toISOString() : now } : action === 'unpublish' ? null : current?.live ?? null,
          revision: expected + 1, updatedAt: now,
        };
        tx.set(ref, next);
        return { ...next, id: ref.id };
      });
      response.json(saved);
    },
    async public(request: Request, response: Response) {
      response.set('Cache-Control', 'no-store');
      if (request.method !== 'GET') throw new ApiError(405, '지원하지 않는 요청입니다.');
      const now = Date.now();
      const released = (article?: Article | null) => !!article && Date.parse(article.releaseAt) <= now;
      if (request.query.action === 'interviews') {
        const docs = await collection.where('live.releaseAt', '<=', new Date(now).toISOString()).select('live.title', 'live.subtitle', 'live.person', 'live.summary',
          'live.cover', 'live.coverAlt', 'live.releaseAt').get();
        const items = docs.docs.flatMap(doc => {
          const live = doc.get('live') as Article | undefined;
          return live && released(live) ? [{ ...live, id: doc.id }] : [];
        }).sort((a, b) => Date.parse(b.releaseAt) - Date.parse(a.releaseAt));
        response.json({ items });
        return;
      }
      const key = id(request.query.id);
      const live = (await collection.doc(key).get()).get('live') as Article | null;
      if (!live || !released(live)) throw new ApiError(404, '공개된 기사를 찾을 수 없습니다.');
      if (request.query.action === 'interviewPhoto') {
        const key = hash(request.query.photo);
        if (!photos(live).includes(key)) throw new ApiError(404, '공개된 사진을 찾을 수 없습니다.');
        const photo = await asset(key);
        const [bytes] = await bucket.file(photo.path).download();
        response.set('X-Content-Type-Options', 'nosniff').type(photo.contentType).send(bytes);
        return;
      }
      response.json({ ...live, id: key });
    },
  };
}
