import type { Firestore } from 'firebase-admin/firestore';
import type { getStorage } from 'firebase-admin/storage';
import type { Request } from 'firebase-functions/v2/https';
import type { Response } from 'express';
import { ApiError, contentLanguage, id, isReleased, type Content, type Snapshot } from './content';
import { storyBodyPath } from './story-body';

type Bucket = ReturnType<ReturnType<typeof getStorage>['bucket']>;
type LiveContent = Content & { publishedContent: Snapshot };
type Language = ReturnType<typeof contentLanguage>;

function released(item: Content | undefined, language: Language, now: Date): item is LiveContent {
  return !!(item?.published && !item.deleting && item.publishedContent && isReleased(item, now) &&
    contentLanguage(item.publishedContent.language) === language);
}

function webEpisode(item: Content | undefined, language: Language, now: Date): item is LiveContent {
  return item?.kind === 'book' && item.webPublic === true && released(item, language, now);
}

function publicStoryItem(item: LiveContent) {
  const snapshot = item.publishedContent;
  return {
    id: item.id,
    title: snapshot.title,
    description: snapshot.description,
    author: snapshot.issueMonth ? snapshot.byline || '' : snapshot.author,
    cover: !!snapshot.assets.cover,
    releasedAt: snapshot.releaseAt || snapshot.releaseDate || snapshot.publishedAt || '',
  };
}

function workDetails(work: LiveContent, episodes: LiveContent[]) {
  const snapshot = work.publishedContent;
  return {
    ...publicStoryItem(work),
    kind: work.kind === 'series' ? 'series' : 'book',
    issueMonth: snapshot.issueMonth || '',
    category: snapshot.category || '',
    status: snapshot.seriesStatus || null,
    episodeCount: episodes.length,
  };
}

function episodeDetails(episode: LiveContent) {
  return { ...publicStoryItem(episode), number: episode.publishedContent.episodeNumber ?? null };
}

export function storyCatalog(db: Firestore, bucket: Bucket) {
  const contents = db.collection('readerContent');
  const get = async (key: string) => (await contents.doc(key).get()).data() as Content | undefined;
  const missing = () => new ApiError(404, '웹에 공개된 작품 또는 회차가 없습니다.');

  return async (request: Request, response: Response) => {
    response.set('Cache-Control', 'no-store');
    if (request.method !== 'GET') throw new ApiError(405, '지원하지 않는 요청입니다.');
    const now = new Date();
    const language = contentLanguage(request.query.language);
    const action = request.query.action || 'list';
    const visible = (item: Content | undefined): item is LiveContent => webEpisode(item, language, now);

    if (action === 'list') {
      const documents = await contents.where('webPublic', '==', true).select('id', 'kind', 'published', 'deleting', 'webPublic',
        'publishedContent.title', 'publishedContent.author', 'publishedContent.description', 'publishedContent.byline',
        'publishedContent.language', 'publishedContent.issueMonth', 'publishedContent.category', 'publishedContent.seriesId',
        'publishedContent.releaseDate', 'publishedContent.releaseAt', 'publishedContent.publishedAt', 'publishedContent.assets.cover').get();
      const episodes = documents.docs.map(doc => doc.data() as Content).filter(visible);
      const byWork = new Map<string, LiveContent[]>();
      for (const episode of episodes) {
        const key = episode.publishedContent.seriesId || episode.id;
        const group = byWork.get(key) || [];
        group.push(episode);
        byWork.set(key, group);
      }
      const parentIds = [...byWork].filter(([key, group]) => key !== group[0].id).map(([key]) => key);
      const parents = new Map<string, LiveContent>();
      for (let offset = 0; offset < parentIds.length; offset += 100) {
        const documents = await db.getAll(...parentIds.slice(offset, offset + 100).map(key => contents.doc(key)));
        for (const doc of documents) {
          const item = doc.data() as Content | undefined;
          if (item?.kind === 'series' && released(item, language, now)) parents.set(doc.id, item);
        }
      }
      const works = [...byWork].flatMap(([key, group]) => {
        const work = group[0].id === key ? group[0] : parents.get(key);
        if (!work) return [];
        const latest = group.map(item => publicStoryItem(item).releasedAt).sort().at(-1) || '';
        return [{ ...workDetails(work, group), releasedAt: latest }];
      });
      works.sort((a, b) => b.releasedAt.localeCompare(a.releasedAt) || a.id.localeCompare(b.id));
      response.json({ works });
      return;
    }

    if (action !== 'work' && action !== 'episode' && action !== 'cover') throw new ApiError(400, '지원하지 않는 조회입니다.');
    const work = await get(id(request.query.work));
    if (!released(work, language, now)) throw missing();
    const episodeId = request.query.episode === undefined ? undefined : id(request.query.episode);
    let episodes: LiveContent[];
    if (work.kind === 'series') {
      if (action === 'cover' && episodeId) {
        const episode = await get(episodeId);
        episodes = visible(episode) && episode.publishedContent.seriesId === work.id ? [episode] : [];
      } else {
        const docs = await contents.where('seriesId', '==', work.id).where('webPublic', '==', true).get();
        episodes = docs.docs.map(doc => doc.data() as Content).filter(visible)
          .filter(item => item.publishedContent.seriesId === work.id)
          .sort((a, b) => (a.publishedContent.episodeNumber ?? 0) - (b.publishedContent.episodeNumber ?? 0) || a.id.localeCompare(b.id));
      }
    } else {
      if (!visible(work) || work.publishedContent.seriesId) throw missing();
      episodes = [work];
    }
    if (!episodes.length) throw missing();

    if (action === 'work') {
      response.json({ work: workDetails(work, episodes), episodes: episodes.map(episodeDetails) });
      return;
    }

    const index = episodeId ? episodes.findIndex(episode => episode.id === episodeId) : -1;
    const episode = episodes[index];
    if (action === 'cover') {
      const asset = (episodeId ? episode : work)?.publishedContent.assets.cover;
      if (!asset || !['image/jpeg', 'image/png', 'image/webp'].includes(asset.contentType)) throw missing();
      const [bytes] = await bucket.file(asset.path).download();
      response.set('X-Content-Type-Options', 'nosniff').type(asset.contentType).send(bytes);
      return;
    }

    if (!episode) throw missing();
    const snapshot = episode.publishedContent;
    const [body] = await bucket.file(storyBodyPath(episode.id, snapshot)).download();
    response.json({
      work: workDetails(work, episodes),
      episode: { ...episodeDetails(episode), cover: !!snapshot.assets.cover && (work.kind === 'book' || snapshot.assets.cover.sha256 !== work.publishedContent.assets.cover?.sha256) },
      blocks: JSON.parse(body.toString('utf8')),
      previous: episodes[index - 1] ? episodeDetails(episodes[index - 1]) : null,
      next: episodes[index + 1] ? episodeDetails(episodes[index + 1]) : null,
    });
  };
}
