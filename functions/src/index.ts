import {upcomingItem} from './content';
import {releasedEpisodeCounts, nextCatalogChange} from './catalog-summary';
import { changeSeriesStatus, pendingEpisodes } from './series-status';
import {adminCoverAsset} from './admin-cover';
import { validateTranslationGroup } from './translation-groups';
import { ensureMonthlyIssues, ensureMonthlyEpisode } from './monthly-groups';
import { correctMonthlyLanguage } from './monthly-language';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { monthlyPublisher } from './monthly-publishing';
import { randomUUID, createHash } from 'node:crypto';
import { previewFace, renderFontPreview } from './font-preview';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldPath, Transaction, getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { onRequest, Request } from 'firebase-functions/v2/https';
import { defineString } from 'firebase-functions/params';
import { logger } from 'firebase-functions';
import { assertDraftDeletion, ApiError, Content, compilationReady, isReleased, catalogLanguage, contentLanguage, visibleInLanguage, assertRevision, bearer, categoryName, defaultCategories, episodeMetadata, id, kind, metadata, seriesMetadata, publicItem, publish, replaceAsset, requireSuperAdmin, requireValue, revision, validateUpload } from './content';

const app = initializeApp({ storageBucket: 'koofy-reader.firebasestorage.app' });
// Only this issuer is trusted. The browser cannot choose an issuer/project.
const adminIdentity = initializeApp({ projectId: 'slimestrikeforce' }, 'existing-admin-identity');
const db = getFirestore(app);
const bucket = getStorage(app).bucket();
const contents = db.collection('readerContent');
const monthlyPublishing = monthlyPublisher(db, bucket);
const episodeNumbers = db.collection('readerEpisodeNumbers');
const categorySettings = db.collection('readerSettings').doc('bookCategories');
function categoryList(data: FirebaseFirestore.DocumentData | undefined): string[] {
  return [...new Set([...defaultCategories, ...(Array.isArray(data?.names) ? data.names.map(categoryName) : [])])];
}
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
async function change(contentId: string, expected: number, uid: string, action: string, edit: (item: Content, transaction: Transaction) => Partial<Content> | Promise<Partial<Content>>) {
  return db.runTransaction(async transaction => {
    const ref = contents.doc(contentId), doc = await transaction.get(ref);
    if (!doc.exists) throw new ApiError(404, '콘텐츠를 찾을 수 없습니다.');
    const item = doc.data() as Content;
    assertRevision(item, expected);
    const next = { ...item, ...await edit(item, transaction), revision: item.revision + 1, updatedAt: new Date().toISOString() };
    transaction.set(ref, next);
    transaction.create(db.collection('readerAudit').doc(), { contentId, uid, action, revision: next.revision, at: next.updatedAt });
    return next;
  });
}
function cursor(value: unknown): string | undefined { return value === undefined ? undefined : id(value); }
async function seriesInTransaction(transaction: Transaction, seriesId: string) {
  const doc = await transaction.get(contents.doc(seriesId));
  const series = doc.data() as Content | undefined;
  requireValue(series?.kind === 'series' && !series.deleting, '등록 가능한 연재 작품을 선택해 주세요.');
  return series;
}
async function reserveEpisode(transaction: Transaction, contentId: string, seriesId: string, number: number, previous?: number) {
  const ref = episodeNumbers.doc(`${seriesId}_${number}`);
  const reserved = await transaction.get(ref);
  if (reserved.exists && reserved.data()?.contentId !== contentId) throw new ApiError(409, '이미 등록된 회차 번호입니다. 다른 번호를 입력해 주세요.');
  transaction.set(ref, { contentId });
  if (previous !== undefined && previous !== number) transaction.delete(episodeNumbers.doc(`${seriesId}_${previous}`));
}
async function requirePublishedSeries(item: Content) {
  if (!item.seriesId) return;
  const parent = await getItem(item.seriesId);
  if (parent.kind !== 'series') throw new ApiError(404, '공개된 작품이 없습니다.');
  publicItem(parent);
  requireValue(isReleased(parent), '아직 발행되지 않은 작품입니다.');
}
async function deleteContent(contentId: string, expected: number, uid: string, draftOnly = false) {
  const ref = contents.doc(contentId);
  // Lock edits and unpublish before touching Storage. A failed cleanup can be
  // retried, but can never republish a partly deleted publication.
  await db.runTransaction(async transaction => {
    const doc = await transaction.get(ref);
    if (!doc.exists) return; // Response loss/repeated delete is safe.
    const item = doc.data() as Content;
    if (draftOnly) assertDraftDeletion(item);
    if (item.deleting) return;
    assertRevision(item, expected);
    if (item.kind === 'series') {
      const children = await transaction.get(contents.where('seriesId', '==', contentId).limit(1));
      requireValue(children.empty, '회차가 있는 작품은 삭제할 수 없습니다. 공개를 중단하려면 비공개로 전환해 주세요.');
    }
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
    const item = doc.data() as Content;
    if (item.seriesId) transaction.delete(episodeNumbers.doc(`${item.seriesId}_${item.episodeNumber}`));
    transaction.delete(ref);
    transaction.create(db.collection('readerAudit').doc(), { contentId, uid, action: 'deleteCompleted', at: new Date().toISOString() });
  });
  return { id: contentId, deleted: true };
}
async function list(contentKind: unknown, after: unknown, publicOnly: boolean, supportsTxt = false, seriesId?: unknown, grouped = false, language: 'ko' | 'en' | 'ja' = 'ko', supportsUpcoming = false) {
  const selectedKind = kind(contentKind);
  let query = grouped && selectedKind === 'book' && publicOnly
    ? contents.where('kind', 'in', ['book', 'series']) : contents.where('kind', '==', selectedKind);
  if (seriesId !== undefined) {
    requireValue(selectedKind === 'book', '도서 회차만 조회할 수 있습니다.');
    const parent = await getItem(id(seriesId));
    requireValue(parent.kind === 'series' && !parent.deleting, '작품을 찾을 수 없습니다.');
    if (publicOnly) { publicItem(parent); requireValue(isReleased(parent), '아직 발행되지 않은 작품입니다.'); }
    query = query.where('seriesId', '==', parent.id);
  }
  if (publicOnly) query = query.where('published', '==', true);
  query = query.orderBy(FieldPath.documentId()).limit(41);
  const start = cursor(after);
  if (start) query = query.startAfter(start);
  const docs = (await query.get()).docs;
  // Older apps reject unknown asset slots. Keep TXT out of their responses,
  // retaining the raw document cursor even when a page contains only TXT books.
  const visible = docs.slice(0, 40).map(doc => doc.data() as Content).filter(item =>
    (!publicOnly || (visibleInLanguage(item, language) && (isReleased(item) || (supportsUpcoming && !!seriesId && !!item.publishedContent)))) &&
    (!grouped || selectedKind !== 'book' || !item.seriesId) &&
    (!publicOnly || supportsTxt || !item.publishedContent?.assets.txt));
  // Legacy apps still receive complete individual books. A private parent also
  // hides its episodes from legacy lists and blocks fresh download links.
  const parents = [...new Set(visible.flatMap(item => publicOnly && item.seriesId ? [item.seriesId] : []))];
  const parentDocs = parents.length ? await db.getAll(...parents.map(value => contents.doc(value))) : [];
  const available = new Set(parentDocs.filter(doc => doc.data()?.kind === 'series' && doc.data()?.published && !doc.data()?.deleting && isReleased(doc.data() as Content)).map(doc => doc.id));
  const countIds = publicOnly ? visible.filter(item => item.kind === 'series').map(item => item.id) : [];
  const countDocuments: Content[] = [];
  for (let offset = 0; offset < countIds.length; offset += 30) {
    const result = await contents.where('seriesId', 'in', countIds.slice(offset, offset + 30)).where('published', '==', true)
      .select('id','kind','seriesId','published','deleting','language','publishedContent.language','publishedContent.issueMonth','publishedContent.releaseAt','publishedContent.releaseDate').get();
    countDocuments.push(...result.docs.map(doc => doc.data() as Content));
  }
  const counts = releasedEpisodeCounts(countDocuments, language);
  const compilationIds = publicOnly ? [...new Set(visible.map(item => item.publishedContent?.compilationId).filter((value): value is string => !!value))] : [];
  const compilations = compilationIds.length ? await db.getAll(...compilationIds.map(value => contents.doc(value))) : [];
  const compiled = new Map(compilations.map(doc => [doc.id, doc.data() as Content | undefined]));
  const items = await Promise.all(visible.filter(item => !publicOnly || !item.seriesId || available.has(item.seriesId)).map(async item => {
    if (!publicOnly) return item;
    const result = !isReleased(item) ? upcomingItem(item) : publicItem(item);
    if (item.kind !== 'series') return result;
    const compilationId = item.publishedContent?.compilationId;
    if (compilationId && compilationReady(item, compiled.get(compilationId))) return null;
    const episodeCount = counts.get(item.id) ?? 0;
    if (item.publishedContent?.issueMonth && !episodeCount) return null;
    return { ...result, episodeCount };
  }));
  return { items: items.filter(Boolean), nextCursor: docs.length > 40 ? docs[39].id : null, nextChangeAt: publicOnly ? nextCatalogChange([...docs.map(doc => doc.data() as Content), ...countDocuments]) : null };
}

async function monthly(language: 'ko' | 'en' | 'ja') {
  const documents = await contents.where('kind', '==', 'series').where('published', '==', true).get();
  const changes = documents.docs.map(doc => doc.data() as Content);
  const issues = changes.filter(item =>
    !item.deleting && item.publishedContent?.issueMonth && visibleInLanguage(item, language) && isReleased(item))
    .sort((a, b) => b.publishedContent!.issueMonth!.localeCompare(a.publishedContent!.issueMonth!) || a.id.localeCompare(b.id));
  const items: ReturnType<typeof publicItem>[] = [];
  let activeFound = false;
  // A future/empty prepared issue must not hide the current readable issue.
  const noticeStart = Date.now() - 30 * 24 * 60 * 60 * 1000;
  for (const issue of issues) {
    const snapshot = issue.publishedContent!;
    const compiled = snapshot.compilationId ? (await contents.doc(snapshot.compilationId).get()).data() as Content | undefined : undefined;
    if (compilationReady(issue, compiled)) {
      if (Date.parse(snapshot.compilationLinkedAt ?? '') >= noticeStart) items.push(publicItem(compiled!));
      // A completed newer issue must not resurrect older unfinished issues.
      activeFound = true;
      continue;
    }
    if (activeFound) continue;
    const episodeDocuments = (await contents.where('seriesId', '==', issue.id).where('published', '==', true).get()).docs.map(doc => doc.data() as Content);
    changes.push(...episodeDocuments);
    const episodes = episodeDocuments.filter(item => !item.deleting && isReleased(item) && visibleInLanguage(item, language))
      .sort((a, b) => (b.publishedContent!.releaseAt || `${b.publishedContent!.releaseDate || ''}T00:00:00+09:00`).localeCompare(a.publishedContent!.releaseAt || `${a.publishedContent!.releaseDate || ''}T00:00:00+09:00`) || b.episodeNumber! - a.episodeNumber!);
    if (!episodes.length) continue;
    items.push(publicItem(issue), publicItem(episodes[0]));
    activeFound = true;
  }
  return { items, nextCursor: null, nextChangeAt: nextCatalogChange(changes) };
}


// The mobile and legacy editor APIs remain unchanged. Saved-work pages expand
// translation groups before returning them, so pagination never splits a work.
async function adminWorks(contentKind: unknown, after: unknown, scope: unknown) {
  requireValue(scope === undefined || ['general','monthly','novel'].includes(String(scope)), '목록 구분을 확인해 주세요.');
  const page = await list(contentKind, after, false, true, undefined, true);
  const inScope = (item: Content) => !item.seriesId && !item.deleting &&
    (scope === 'general' ? item.collectionType === 'general' && !item.issueMonth && !item.publishedContent?.issueMonth : scope === 'monthly' ? !!(item.issueMonth || item.publishedContent?.issueMonth) : scope === 'novel' ? !item.collectionType && !item.issueMonth && !item.publishedContent?.issueMonth : true);
  const seeds = page.items.filter((item): item is Content => !!item && inScope(item as Content));
  const groupIds = [...new Set(seeds.map(item => item.translationGroupId).filter((value): value is string => !!value))];
  const items = new Map(seeds.map(item => [item.id, item]));
  for (let offset = 0; offset < groupIds.length; offset += 30) {
    const linked = await contents.where('translationGroupId','in',groupIds.slice(offset,offset + 30)).get();
    for (const doc of linked.docs) { const item = doc.data() as Content; if(item.kind === kind(contentKind) && inScope(item)) items.set(item.id,item); }
  }
  if (scope === 'monthly') {
    const months = [...new Set(seeds.map(item=>item.issueMonth || item.publishedContent?.issueMonth).filter((value):value is string=>!!value))];
    for(let offset=0;offset<months.length;offset+=10){
      const slice=months.slice(offset,offset+10);
      const versions=await Promise.all(['issueMonth','publishedContent.issueMonth'].map(field=>contents.where('kind','==','series').where(field,'in',slice).get()));
      for(const version of versions)for(const doc of version.docs){const item=doc.data() as Content;if(inScope(item))items.set(item.id,item);}
    }
  }
  return {...page, items:[...items.values()]};
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
    if (request.method === 'GET') {
      if (request.query.action === 'works') { response.json(await adminWorks(request.query.kind, request.query.after, request.query.scope)); return; }
      if (request.query.action === 'work') {
        const item = await getItem(id(request.query.id));
        requireValue(!item.seriesId && !item.deleting, '작품을 찾을 수 없습니다.');
        const month=item.issueMonth || item.publishedContent?.issueMonth;
        const monthlyVersions=month?await Promise.all(['issueMonth','publishedContent.issueMonth'].map(field=>contents.where('kind','==','series').where(field,'==',month).get())):[];
        const linked = month?[...new Map(monthlyVersions.flatMap(version=>version.docs.map(doc=>[doc.id,doc.data() as Content] as const))).values()]:item.translationGroupId ? (await contents.where('translationGroupId','==',item.translationGroupId).get()).docs.map(doc=>doc.data() as Content) : [item];
        response.json({items:linked.filter(value=>!value.seriesId && !value.deleting && value.kind===item.kind)}); return;
      }
      if(request.query.action==='coverPreview'){
        const item=await getItem(id(request.query.id));
        const asset=adminCoverAsset(item,revision(request.query.revision),{superAdmin:claims.superAdmin});
        const expiresAt=Date.now()+5*60*1000;
        const [url]=await bucket.file(asset.path).getSignedUrl({action:'read',version:'v4',expires:expiresAt});
        response.json({url,expiresAt});return;
      }
      if (request.query.action === 'categories') {
        response.json({ categories: categoryList((await categorySettings.get()).data()) }); return;
      }
      response.json(await list(request.query.kind, request.query.after, false, true, request.query.seriesId, request.query.topLevel === '1')); return;
    }
    if (request.method !== 'POST') { response.status(405).json({ error: '지원하지 않는 요청입니다.' }); return; }
    if (request.query.action === 'uploadSharedCover') {
      const checked = await validateUpload('book', 'cover', request.rawBody);
      const hash = checked.asset.sha256;
      const path = `readerSharedCovers/${hash}/cover.${checked.asset.extension}`;
      const file = bucket.file(path);
      try {
        await file.save(checked.bytes, { resumable: false, contentType: checked.asset.contentType, preconditionOpts: { ifGenerationMatch: 0 } });
      } catch (error) { if (Number((error as { code?: number }).code) !== 412) throw error; }
      await db.collection('readerSharedCovers').doc(hash).set({ asset: { path, ...checked.asset } });
      response.json({ hash }); return;
    }
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
    if (data.action === 'correctMonthlyLanguage') {
      const contentId = id(data.id), expected = revision(data.revision);
      const corrected = await db.runTransaction(async transaction => {
        const issueDoc = await transaction.get(contents.doc(contentId));
        requireValue(issueDoc.exists, '월간호를 찾지 못했습니다.');
        const issue = issueDoc.data() as Content;
        const children = await transaction.get(contents.where('seriesId', '==', contentId));
        const at = new Date().toISOString();
        const updates = correctMonthlyLanguage(issue, children.docs.map(doc => doc.data() as Content), expected, data.language, at);
        for (const item of updates) transaction.set(contents.doc(item.id), item);
        transaction.create(db.collection('readerAudit').doc(), { uid: claims.uid, action: 'correctMonthlyLanguage', contentId,
          from: issue.language || 'ko', to: data.language, count: updates.length - 1, at });
        return updates[0];
      });
      response.json(corrected); return;
    }
    if (data.action === 'addCategory') {
      const name = categoryName(data.name);
      const categories = await db.runTransaction(async transaction => {
        const current = categoryList((await transaction.get(categorySettings)).data());
        if (current.includes(name)) return current;
        requireValue(current.length < 100, '분류는 최대 100개까지 등록할 수 있습니다.');
        const names = [...current, name];
        const at = new Date().toISOString();
        transaction.set(categorySettings, { names, updatedAt: at });
        transaction.create(db.collection('readerAudit').doc(), { uid: claims.uid, action: 'addCategory', name, at });
        return names;
      });
      response.json({ categories }); return;
    }
    if (data.action === 'attachSharedCover') {
      const contentId = id(data.id), expected = revision(data.revision);
      requireValue(typeof data.hash === 'string' && /^[a-f0-9]{64}$/.test(data.hash), '공통 이미지 ID를 확인해 주세요.');
      const shared = (await db.collection('readerSharedCovers').doc(data.hash).get()).data();
      requireValue(shared?.asset, '공통 이미지를 다시 업로드해 주세요.');
      const next = await change(contentId, expected, claims.uid, 'attachSharedCover', item => {
        requireValue(item.kind === 'book' && !!item.seriesId, '회차에만 공통 이미지를 연결할 수 있습니다.');
        return { assets: replaceAsset(item, 'cover', shared.asset) };
      });
      response.json(next); return;
    }
    if (data.action === 'setSeriesStatus') {
      requireValue(Array.isArray(data.items) && data.items.length >= 1 && data.items.length <= 3, '작품의 언어 목록을 확인해 주세요.');
      requireValue(data.status === 'ongoing' || data.status === 'completed', '연재 상태를 확인해 주세요.');
      const status = data.status;
      const refs = data.items.map((entry: {id: unknown; revision: unknown}) => ({id:id(entry.id),revision:revision(entry.revision)}));
      requireValue(new Set(refs.map(x=>x.id)).size === refs.length, '중복된 작품입니다.');
      const result = await db.runTransaction(async transaction => {
        const docs = await transaction.getAll(...refs.map(x=>contents.doc(x.id)));
        const at = new Date().toISOString();
        const values = docs.map((doc,i)=>{requireValue(doc.exists,'작품을 찾을 수 없습니다.');const item=doc.data() as Content;assertRevision(item,refs[i].revision);changeSeriesStatus(item,status,at);return item;});
        const group = values[0].translationGroupId;
        requireValue(values.every(x=>x.translationGroupId===group && x.collectionType===values[0].collectionType) && (!!group || values.length===1), '같은 작품의 번역본만 함께 변경할 수 있습니다.');
        if(group){
          const linked=await transaction.get(contents.where('translationGroupId','==',group));
          requireValue(linked.docs.length===values.length && linked.docs.every(doc=>refs.some(x=>x.id===doc.id)), '번역본 구성이 바뀌었습니다. 목록을 새로고침해 주세요.');
        }
        const children = await Promise.all(values.map(x=>transaction.get(contents.where('seriesId','==',x.id))));
        const pending = pendingEpisodes(children.flatMap(query=>query.docs.map(doc=>doc.data() as Content)),new Date(at));
        if(data.preview===true)return {pending,items:values};
        requireValue(status!=='completed' || !(pending.drafts+pending.scheduled) || data.acknowledgePending===true, '미공개·예약 회차가 남아 있습니다. 확인 후 다시 변경해 주세요.');
        const next=values.map(item=>changeSeriesStatus(item,status,at));
        next.forEach(item=>transaction.update(contents.doc(item.id),{seriesStatus:item.seriesStatus,revision:item.revision,updatedAt:at,publishedContent:item.publishedContent}));
        transaction.create(db.collection('readerAudit').doc(),{action:'setSeriesStatus',uid:claims.uid,ids:next.map(x=>x.id),status,pending,at});
        return {pending,items:next};
      });
      response.json(result);return;
    }
    if (data.action === 'linkTranslations') {
      requireValue(Array.isArray(data.items) && data.items.length >= 2 && data.items.length <= 3, '연결할 번역본 2~3개를 선택해 주세요.');
      const refs = data.items.map((entry: { id: unknown; revision: unknown }) => ({ id: id(entry.id), revision: revision(entry.revision) }));
      requireValue(new Set(refs.map(x => x.id)).size === refs.length, '같은 작품을 중복 선택할 수 없습니다.');
      const items = await db.runTransaction(async transaction => {
        const docs = await transaction.getAll(...refs.map(x => contents.doc(x.id)));
        const values = docs.map((doc, i) => {
          requireValue(doc.exists, '작품을 찾을 수 없습니다.');
          const item = doc.data() as Content; assertRevision(item, refs[i].revision);
          requireValue(!item.deleting && !item.seriesId && !item.issueMonth && !item.publishedContent?.issueMonth && item.kind !== 'font', '일반 작품만 연결할 수 있습니다.');
          return item;
        });
        const groupId = validateTranslationGroup(values);
        const existing = await transaction.get(contents.where('translationGroupId', '==', groupId));
        validateTranslationGroup(values, existing.docs.map(d => d.data() as Content));
        const at = new Date().toISOString();
        const next = values.map(x => ({ ...x, translationGroupId: groupId, revision: x.revision + 1, updatedAt: at }));
        next.forEach(x => transaction.update(contents.doc(x.id), { translationGroupId: groupId, revision: x.revision, updatedAt: at }));
        transaction.create(db.collection('readerAudit').doc(), { action: 'linkTranslations', uid: claims.uid, ids: next.map(x => x.id), groupId, at });
        return next;
      });
      response.json({ items }); return;
    }
    if (data.action === 'ensureMonthlyIssues') {
      requireValue(typeof data.issueMonth === 'string', '발행 연·월이 필요합니다.');
      response.json({ items: await ensureMonthlyIssues(db, data.issueMonth, claims.uid) }); return;
    }
    if (data.action === 'ensureMonthlyEpisode') {
      response.json(await ensureMonthlyEpisode(db, id(data.seriesId), data.metadata, claims.uid)); return;
    }
    if (data.action === 'create') {
      const contentId = randomUUID().replaceAll('-', '');
      const contentKind = kind(data.kind);
      const item = await db.runTransaction(async transaction => {
        let fields;
        if (data.seriesId !== undefined) {
          requireValue(contentKind === 'book', '작품에는 도서 회차만 추가할 수 있습니다.');
          const parent = await seriesInTransaction(transaction, id(data.seriesId));
          fields = episodeMetadata(data.metadata, parent, parent.id);
          await reserveEpisode(transaction, contentId, parent.id, fields.episodeNumber!);
        } else fields = contentKind === 'series' ? seriesMetadata(data.metadata) : metadata(data.metadata);
        const next: Content = { id: contentId, kind: contentKind, ...fields, revision: 1, assets: {}, published: false, publishedContent: null, updatedAt: new Date().toISOString() };
        transaction.create(contents.doc(contentId), next);
        transaction.create(db.collection('readerAudit').doc(), { contentId, uid: claims.uid, action: 'create', revision: 1, at: next.updatedAt });
        return next;
      });
      response.status(201).json(item); return;
    }
    const contentId = id(data.id), expected = revision(data.revision);
    const action = data.action;
    if (action === 'compileMonthly') {
      response.json(await monthlyPublishing.compile(contentId, expected)); return;
    }
    if (action === 'delete') {
      response.json(await deleteContent(contentId, expected, claims.uid, data.draftOnly === true)); return;
    }
    // Render before entering the Firestore transaction. Recheck revision when
    // committing so a concurrent rename/upload cannot publish a stale preview.
    if (action === 'publish') {
      const item = await getItem(contentId); assertRevision(item, expected);
      const parent = item.seriesId ? await getItem(item.seriesId) : undefined;
      const snapshot = publish(item, parent);
      if (snapshot.compilationId) {
        const compiled = (await contents.doc(snapshot.compilationId).get()).data() as Content | undefined;
        requireValue(compilationReady({ ...item, publishedContent: snapshot }, compiled), '같은 월·언어의 공개된 EPUB 합본을 연결하고 연재 상태를 완결로 선택해 주세요.');
      }
      const generatedEpub = await monthlyPublishing.episode(item, snapshot);
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
        next = await change(contentId, expected, claims.uid, action, async (_, transaction) => {
          if (parent) {
            const current = await seriesInTransaction(transaction, parent.id);
            assertRevision(current, parent.revision);
            publicItem(current);
          }
          if (snapshot.compilationId) {
            const compiled = (await transaction.get(contents.doc(snapshot.compilationId))).data() as Content | undefined;
            requireValue(compilationReady({ ...item, publishedContent: snapshot }, compiled), '합본 공개 상태가 변경되었습니다. 다시 확인해 주세요.');
          }
          return { published: true, publishedContent: snapshot };
        });
      } catch (error) {
        if (generatedEpub) await bucket.file(generatedEpub.path).delete().catch(cleanup => logger.error('Orphan monthly EPUB cleanup failed', cleanup));
        await previewFile?.delete().catch(cleanup => logger.error('Orphan preview cleanup failed', cleanup));
        throw error;
      }
      response.json(next);
      return;
    }
    requireValue(action === 'save' || action === 'unpublish' || action === 'removeAsset', '지원하지 않는 작업입니다.');
    const next = await change(contentId, expected, claims.uid, action, async (item, transaction) => {
      switch (action) {
        case 'save': {
          if (!item.seriesId) {
            const input = { language: item.language ?? 'ko', ...(data.metadata as Record<string, unknown>), ...(item.collectionType ? { collectionType: item.collectionType } : {}) };
            const fields = item.kind === 'series' ? seriesMetadata(input) : metadata(input);
            requireValue(!item.publishedContent || fields.language === contentLanguage(item.publishedContent.language), '공개된 콘텐츠의 언어는 변경할 수 없습니다. 번역본은 별도로 등록해 주세요.');
            requireValue(!item.publishedContent || (fields.issueMonth || '') === (item.publishedContent.issueMonth || ''), '공개된 월간호의 발행 월은 변경할 수 없습니다. 새 작품을 등록해 주세요.');
            return fields;
          }
          const parent = await seriesInTransaction(transaction, item.seriesId);
          const fields = episodeMetadata(data.metadata, parent, parent.id);
          requireValue(!item.publishedContent || fields.episodeNumber === item.publishedContent.episodeNumber, '공개 이력이 있는 회차의 번호는 변경할 수 없습니다. 제목과 본문은 수정할 수 있습니다.');
          await reserveEpisode(transaction, item.id, parent.id, fields.episodeNumber!, item.episodeNumber);
          return fields;
        }
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
      requireValue(isReleased(item) || (request.query.slot === 'cover' && !!item.seriesId), '아직 발행되지 않은 콘텐츠입니다.');
      await requirePublishedSeries(item);
      const snapshot = item.publishedContent!;
      if (Number(request.query.version) !== snapshot.version) throw new ApiError(409, '새 버전이 공개되었습니다. 목록을 새로고침해 주세요.');
      requireValue(typeof request.query.slot === 'string', '파일을 찾을 수 없습니다.');
      const slot = request.query.slot;
      const asset = slot === 'preview' ? snapshot.preview : Object.hasOwn(snapshot.assets, slot) ? snapshot.assets[slot] : undefined;
      requireValue(asset, '파일을 찾을 수 없습니다.');
      const [url] = await bucket.file(asset.path).getSignedUrl({ action: 'read', version: 'v4', expires: Date.now() + 5 * 60 * 1000 });
      response.json({ url, sha256: asset.sha256, size: asset.size }); return;
    }
    if (request.query.action === 'monthly') { response.json(await monthly(catalogLanguage(request.query.language))); return; }
    response.json(await list(request.query.kind, request.query.after, true, request.query.supportsTxt === '1', request.query.seriesId, request.query.supportsSeries === '1' && request.query.seriesId === undefined, catalogLanguage(request.query.language), request.query.supportsUpcoming === '1'));
  } catch (error) { sendError(error, response); }
});


// No mobile update is needed when a new issue is finalized. Publish both documents atomically.
export const readerMonthlyCompilation = onSchedule({
  schedule: 'every 60 minutes', timeZone: 'Asia/Seoul', region: options.region,
  serviceAccount: options.serviceAccount, memory: '1GiB', timeoutSeconds: 540, maxInstances: 1,
}, async () => {
  const month = new Date(Date.now() + 9 * 3600000).toISOString().slice(0, 7);
  const series = await contents.where('kind', '==', 'series').where('published', '==', true).get();
  for (const doc of series.docs) {
    const item = doc.data() as Content;
    const snapshot = item.publishedContent;
    if (!snapshot?.autoCompile || !snapshot.issueMonth || snapshot.issueMonth >= month || snapshot.compilationId || item.deleting) continue;
    try { await monthlyPublishing.compile(item.id); }
    catch (error) {
      logger.error('Monthly compilation deferred', { id: item.id, error });
      const message = error instanceof ApiError ? error.message : '합본 생성에 실패했습니다. 다음 실행에서 다시 시도합니다.';
      // Do not overwrite a successful concurrent compilation or edit.
      await db.runTransaction(async transaction => {
        const ref = contents.doc(item.id), current = await transaction.get(ref);
        if (current.exists && current.data()?.revision === item.revision && !current.data()?.publishedContent?.compilationId) transaction.update(ref, { compilationError: message });
      });
    }
  }
});

export {readerQueueNewStory,readerSendNewStories} from './reader-notifications';
