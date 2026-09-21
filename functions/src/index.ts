import { randomUUID, createHash } from 'node:crypto';
import { previewFace, renderFontPreview } from './font-preview';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldPath, getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { onRequest, Request } from 'firebase-functions/v2/https';
import { defineString } from 'firebase-functions/params';
import { logger } from 'firebase-functions';
import { ApiError, Content, assertRevision, bearer, id, kind, metadata, publicItem, publish, replaceAsset, requireSuperAdmin, requireValue, revision, validateUpload } from './content';

const app = initializeApp({ storageBucket: 'koofy-reader.firebasestorage.app' });
// Only this issuer is trusted. The browser cannot choose an issuer/project.
const adminIdentity = initializeApp({ projectId: 'slimestrikeforce' }, 'existing-admin-identity');
const db = getFirestore(app);
const bucket = getStorage(app).bucket();
const contents = db.collection('readerContent');
const origins = defineString('READER_ADMIN_ORIGINS', { default: 'https://admin.koofy.co.kr,http://localhost:3000' });
const options = { region: 'asia-northeast3', maxInstances: 3, minInstances: 0, concurrency: 1, serviceAccount: 'koofy-reader-api@koofy-reader.iam.gserviceaccount.com', memory: '512MiB' as const, timeoutSeconds: 120, invoker: 'public' as const };

function sendError(error: unknown, response: { status: (code: number) => { json: (value: unknown) => unknown } }) {
  if (error instanceof ApiError) response.status(error.status).json({ error: error.message });
  else { logger.error('Reader API failed', error); response.status(500).json({ error: '요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.' }); }
}
function body(request: Request): Record<string, unknown> {
  requireValue(request.is('application/json') && request.body && typeof request.body === 'object' && !Array.isArray(request.body), 'JSON 요청이 필요합니다.');
  requireValue(request.rawBody.length <= 16 * 1024, '요청이 너무 큽니다.');
  return request.body;
}
async function getItem(contentId: string): Promise<Content> {
  const doc = await contents.doc(contentId).get();
  if (!doc.exists) throw new ApiError(404, '콘텐츠를 찾을 수 없습니다.');
  return doc.data() as Content;
}
async function change(contentId: string, expected: number, uid: string, action: string, edit: (item: Content) => Partial<Content>) {
  return db.runTransaction(async transaction => {
    const ref = contents.doc(contentId), doc = await transaction.get(ref);
    if (!doc.exists) throw new ApiError(404, '콘텐츠를 찾을 수 없습니다.');
    const item = doc.data() as Content;
    assertRevision(item, expected);
    const next = { ...item, ...edit(item), revision: item.revision + 1, updatedAt: new Date().toISOString() };
    transaction.set(ref, next);
    transaction.create(db.collection('readerAudit').doc(), { contentId, uid, action, revision: next.revision, at: next.updatedAt });
    return next;
  });
}
function cursor(value: unknown): string | undefined { return value === undefined ? undefined : id(value); }
async function deleteContent(contentId: string, expected: number, uid: string) {
  const ref = contents.doc(contentId);
  // Lock edits and unpublish before touching Storage. A failed cleanup can be
  // retried, but can never republish a partly deleted publication.
  await db.runTransaction(async transaction => {
    const doc = await transaction.get(ref);
    if (!doc.exists) return; // Response loss/repeated delete is safe.
    const item = doc.data() as Content;
    if (item.deleting) return;
    assertRevision(item, expected);
    const at = new Date().toISOString();
    transaction.update(ref, { deleting: true, published: false, revision: item.revision + 1, updatedAt: at });
    transaction.create(db.collection('readerAudit').doc(), { contentId, uid, action: 'deleteStarted', at });
  });
  try {
    // Uploads have server-generated, per-content paths; include replaced and
    // removed draft assets, not just the current published snapshot.
    await bucket.deleteFiles({ prefix: `readerContent/${contentId}/` });
  } catch (error) {
    logger.error('Content file deletion failed', { contentId, error });
    throw new ApiError(503, '다운로드를 차단했지만 파일 정리가 완료되지 않았습니다. 삭제를 다시 시도해 주세요.');
  }
  await db.runTransaction(async transaction => {
    const doc = await transaction.get(ref);
    if (!doc.exists) return;
    requireValue(doc.data()?.deleting === true, '삭제 상태를 확인할 수 없습니다.');
    transaction.delete(ref);
    transaction.create(db.collection('readerAudit').doc(), { contentId, uid, action: 'deleteCompleted', at: new Date().toISOString() });
  });
  return { id: contentId, deleted: true };
}
async function list(contentKind: unknown, after: unknown, publicOnly: boolean, supportsTxt = false) {
  let query = contents.where('kind', '==', kind(contentKind));
  if (publicOnly) query = query.where('published', '==', true);
  query = query.orderBy(FieldPath.documentId()).limit(41);
  const start = cursor(after);
  if (start) query = query.startAfter(start);
  const docs = (await query.get()).docs;
  // Older apps reject unknown asset slots. Keep TXT out of their responses,
  // retaining the raw document cursor even when a page contains only TXT books.
  const visible = docs.slice(0, 40).filter(doc => !publicOnly || supportsTxt || !(doc.data() as Content).publishedContent?.assets.txt);
  return { items: visible.map(doc => publicOnly ? publicItem(doc.data() as Content) : doc.data()), nextCursor: docs.length > 40 ? docs[39].id : null };
}

export const readerAdmin = onRequest(options, async (request, response) => {
  response.set('Cache-Control', 'no-store');
  const origin = request.get('origin');
  if (origin && !origins.value().split(',').map(value => value.trim()).includes(origin)) {
    response.status(403).json({ error: '허용되지 않은 관리자 주소입니다.' }); return;
  }
  if (origin) { response.set('Access-Control-Allow-Origin', origin); response.set('Vary', 'Origin'); }
  response.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  response.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  if (request.method === 'OPTIONS') { response.status(204).send(''); return; }
  try {
    let claims;
    const token = bearer(request.get('authorization'));
    try { claims = await getAuth(adminIdentity).verifyIdToken(token); }
    catch { throw new ApiError(401, '관리자 인증이 만료되었거나 올바르지 않습니다. 다시 로그인해 주세요.'); }
    requireSuperAdmin({ superAdmin: claims.superAdmin });
    if (request.method === 'GET') { response.json(await list(request.query.kind, request.query.after, false)); return; }
    if (request.method !== 'POST') { response.status(405).json({ error: '지원하지 않는 요청입니다.' }); return; }
    if (request.query.action === 'upload') {
      const contentId = id(request.query.id), expected = revision(request.query.revision);
      requireValue(typeof request.query.slot === 'string', '파일 종류가 필요합니다.');
      const slot = request.query.slot;
      const item = await getItem(contentId); assertRevision(item, expected);
      const checked = await validateUpload(item.kind, slot, request.rawBody);
      const path = `readerContent/${contentId}/${randomUUID()}/${slot}.${checked.asset.extension}`;
      const file = bucket.file(path);
      await file.save(checked.bytes, { resumable: false, contentType: checked.asset.contentType, metadata: { cacheControl: 'private, max-age=300' }, preconditionOpts: { ifGenerationMatch: 0 } });
      try {
        const next = await change(contentId, expected, claims.uid, `upload:${slot}`, current => ({ assets: replaceAsset(current, slot, { path, ...checked.asset }) }));
        response.json(next);
      } catch (error) { await file.delete().catch(cleanup => logger.error('Orphan upload cleanup failed', cleanup)); throw error; }
      return;
    }
    const data = body(request);
    if (data.action === 'create') {
      const contentId = randomUUID().replaceAll('-', '');
      const item: Content = { id: contentId, kind: kind(data.kind), ...metadata(data.metadata), revision: 1, assets: {}, published: false, publishedContent: null, updatedAt: new Date().toISOString() };
      const batch = db.batch(); batch.create(contents.doc(contentId), item);
      batch.create(db.collection('readerAudit').doc(), { contentId, uid: claims.uid, action: 'create', revision: 1, at: item.updatedAt });
      await batch.commit(); response.status(201).json(item); return;
    }
    const contentId = id(data.id), expected = revision(data.revision);
    const action = data.action;
    if (action === 'delete') {
      response.json(await deleteContent(contentId, expected, claims.uid)); return;
    }
    // Render before entering the Firestore transaction. Recheck revision when
    // committing so a concurrent rename/upload cannot publish a stale preview.
    if (action === 'publish') {
      const item = await getItem(contentId); assertRevision(item, expected);
      const snapshot = publish(item);
      let previewFile: ReturnType<typeof bucket.file> | undefined;
      if (item.kind === 'font') {
        const face = previewFace(item);
        const [bytes] = await bucket.file(face.path).download();
        requireValue(bytes.length === face.size && createHash('sha256').update(bytes).digest('hex') === face.sha256, '글꼴 파일 검증에 실패했습니다. 다시 업로드해 주세요.');
        const rendered = await renderFontPreview(bytes, item.title);
        if (rendered) {
          const path = `readerContent/${contentId}/${randomUUID()}/preview.png`;
          previewFile = bucket.file(path);
          await previewFile.save(rendered.bytes, { resumable: false, contentType: 'image/png', metadata: { cacheControl: 'private, max-age=300' }, preconditionOpts: { ifGenerationMatch: 0 } });
          snapshot.preview = { path, ...rendered.asset };
        }
      }
      let next: Content;
      try {
        next = await change(contentId, expected, claims.uid, action, () => ({ published: true, publishedContent: snapshot }));
      } catch (error) {
        await previewFile?.delete().catch(cleanup => logger.error('Orphan preview cleanup failed', cleanup));
        throw error;
      }
      response.json(next);
      return;
    }
    requireValue(action === 'save' || action === 'unpublish' || action === 'removeAsset', '지원하지 않는 작업입니다.');
    const next = await change(contentId, expected, claims.uid, action, item => {
      switch (action) {
        case 'save': return metadata(data.metadata);
        case 'unpublish': return { published: false };
        case 'removeAsset': {
          requireValue(typeof data.slot === 'string' && Object.hasOwn(item.assets, data.slot), '등록된 파일이 없습니다.');
          const assets = { ...item.assets }; delete assets[data.slot]; return { assets };
        }
      }
    });
    response.json(next);
  } catch (error) { sendError(error, response); }
});

export const readerCatalog = onRequest({ ...options, concurrency: 20, memory: '256MiB', cors: true }, async (request, response) => {
  response.set('Cache-Control', 'no-store');
  if (request.method !== 'GET') { response.status(405).json({ error: 'GET 요청만 지원합니다.' }); return; }
  try {
    if (request.query.action === 'download') {
      const item = await getItem(id(request.query.id));
      publicItem(item); // Never sign draft/unpublished paths supplied by a caller.
      const snapshot = item.publishedContent!;
      if (Number(request.query.version) !== snapshot.version) throw new ApiError(409, '새 버전이 공개되었습니다. 목록을 새로고침해 주세요.');
      requireValue(typeof request.query.slot === 'string', '파일을 찾을 수 없습니다.');
      const slot = request.query.slot;
      const asset = slot === 'preview' ? snapshot.preview : Object.hasOwn(snapshot.assets, slot) ? snapshot.assets[slot] : undefined;
      requireValue(asset, '파일을 찾을 수 없습니다.');
      const [url] = await bucket.file(asset.path).getSignedUrl({ action: 'read', version: 'v4', expires: Date.now() + 5 * 60 * 1000 });
      response.json({ url, sha256: asset.sha256, size: asset.size }); return;
    }
    response.json(await list(request.query.kind, request.query.after, true, request.query.supportsTxt === '1'));
  } catch (error) { sendError(error, response); }
});
