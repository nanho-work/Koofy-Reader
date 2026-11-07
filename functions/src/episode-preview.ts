import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import type { Firestore } from 'firebase-admin/firestore';
import type { getStorage } from 'firebase-admin/storage';
import { ApiError, Content, id, isReleased, publicItem, upcomingItem, visibleInLanguage } from './content';

export const previewPlacement = 'next_episode_preview';
const cooldownMs = 12 * 60 * 60 * 1000;
const attemptMs = 15 * 60 * 1000;
const hex64 = /^[0-9a-f]{64}$/;
const hex32 = /^[0-9a-f]{32}$/;

type Pending = { attemptId: string; episodeId: string; platform: string; expiresAt: number };
type Grant = { episodeId: string; nextAt: number };
type PreviewState = { pending?: Pending; grant?: Grant };
type Bucket = ReturnType<ReturnType<typeof getStorage>['bucket']>;

export function validPreviewCallback(
  params: Record<string, unknown>,
  key: string,
): params is Record<'userId' | 'eventId' | 'rewards' | 'timestamp' | 'signature', string> & Record<string, unknown> {
  const { userId, eventId, rewards, timestamp, signature } = params;
  if (
    typeof userId !== 'string' || !/^[a-zA-Z0-9]{1,64}$/.test(userId) ||
    typeof eventId !== 'string' || !/^[a-zA-Z0-9]{1,128}$/.test(eventId) ||
    typeof rewards !== 'string' || !/^\d{1,9}$/.test(rewards) || Number(rewards) < 1 ||
    typeof timestamp !== 'string' || !/^\d{12}$/.test(timestamp) ||
    typeof signature !== 'string' || !/^[0-9a-f]{32}$/i.test(signature)
  ) return false;
  // LevelPlay specifies MD5 for its shared-secret callback signature.
  const expected = createHash('md5').update(timestamp + eventId + userId + rewards + key).digest();
  return timingSafeEqual(expected, Buffer.from(signature, 'hex'));
}

function availability(state: PreviewState, episodeId: string, now: number) {
  if (state.grant?.episodeId === episodeId) return { state: 'granted' as const };
  if (state.grant && state.grant.nextAt > now) {
    return { state: 'cooldown' as const, nextAt: state.grant.nextAt };
  }
  return { state: 'available' as const };
}

export function episodePreview(db: Firestore, bucket: Bucket) {
  const contents = db.collection('readerContent');
  const installations = db.collection('readerEpisodePreviewInstallations');
  const events = db.collection('readerEpisodePreviewEvents');

  async function visibleEpisode(episodeId: string) {
    const item = (await contents.doc(episodeId).get()).data() as Content | undefined;
    if (!item || item.kind !== 'book' || !item.publishedContent?.seriesId) {
      throw new ApiError(404, '예정 회차가 없습니다.');
    }
    const info = publicItem(item);
    const parent = (await contents.doc(item.publishedContent.seriesId).get()).data() as Content | undefined;
    if (!parent || parent.kind !== 'series' || !isReleased(parent)) {
      throw new ApiError(404, '공개된 작품이 없습니다.');
    }
    publicItem(parent);
    return { item, info };
  }

  return {
    async request(data: Record<string, unknown>) {
      const { credential, action, platform, afterEpisode } = data;
      if (typeof credential !== 'string' || !hex64.test(credential) ||
          (platform !== 'android' && platform !== 'ios') ||
          (action !== 'status' && action !== 'begin' && action !== 'claim')) {
        throw new ApiError(400, '미리 보기 요청을 확인해 주세요.');
      }
      const episodeId = id(data.episodeId);
      const ref = installations.doc(createHash('sha256').update(credential).digest('hex'));
      const saved = (await ref.get()).data() as PreviewState | undefined ?? {};
      const current = availability(saved, episodeId, Date.now());
      const { item, info } = await visibleEpisode(episodeId);
      const snapshot = item.publishedContent!;
      if (isReleased(item)) return { state: 'released', item: info };

      if (action === 'claim') {
        if (current.state !== 'granted') {
          if (current.state === 'cooldown') return current;
          return { state: saved.pending?.episodeId === episodeId && saved.pending.expiresAt > Date.now()
            ? 'pending' : 'unavailable' };
        }
        const links = await Promise.all(Object.entries(snapshot.assets).map(async ([slot, asset]) => {
          const [url] = await bucket.file(asset.path).getSignedUrl({
            action: 'read', version: 'v4', expires: Date.now() + 5 * 60 * 1000,
          });
          return [slot, { url, sha256: asset.sha256, size: asset.size }] as const;
        }));
        return { state: 'granted', item: info, links: Object.fromEntries(links) };
      }

      upcomingItem(item);
      if (current.state !== 'available') return current;
      if (typeof afterEpisode !== 'number' || !Number.isSafeInteger(afterEpisode) || afterEpisode < 0) {
        return { state: 'unavailable' };
      }
      const siblings = await contents.where('seriesId', '==', snapshot.seriesId!)
        .where('published', '==', true)
        .select('id', 'kind', 'published', 'deleting', 'language', 'publishedContent.language',
          'publishedContent.episodeNumber', 'publishedContent.releaseDate', 'publishedContent.releaseAt')
        .get();
      const language = snapshot.language ?? 'ko';
      const episodes = siblings.docs.map(doc => doc.data() as Content).filter(episode =>
        episode.kind === 'book' && !episode.deleting && episode.publishedContent &&
        visibleInLanguage(episode, language));
      const previous = episodes.find(episode => episode.publishedContent!.episodeNumber === afterEpisode);
      const next = episodes.filter(episode => (episode.publishedContent!.episodeNumber ?? -1) > afterEpisode)
        .sort((a, b) => a.publishedContent!.episodeNumber! - b.publishedContent!.episodeNumber!)[0];
      if (!previous || (!isReleased(previous) && previous.id !== saved.grant?.episodeId) || next?.id !== episodeId) {
        return { state: 'unavailable' };
      }
      if (action === 'status') return current;
      return db.runTransaction(async transaction => {
        const state = (await transaction.get(ref)).data() as PreviewState | undefined ?? {};
        const now = Date.now();
        const result = availability(state, episodeId, now);
        if (result.state !== 'available') return result;
        const pending = state.pending;
        if (pending?.episodeId === episodeId && pending.platform === platform && pending.expiresAt > now) {
          return { ...result, attemptId: pending.attemptId };
        }
        const attemptId = randomBytes(16).toString('hex');
        transaction.set(ref, { ...state, pending: { attemptId, episodeId, platform, expiresAt: now + attemptMs } });
        return { ...result, attemptId };
      });
    },

    async reward(params: Record<string, unknown>, platform: string, key: string) {
      if (!validPreviewCallback(params, key)) throw new ApiError(403, 'Invalid reward signature.');
      const { userId, eventId, dynamicUserId, placement } = params;
      // Acknowledge dashboard tests and rewards from the existing banner-hide placement.
      if (placement !== previewPlacement || params.rewards !== '1' || !hex64.test(userId) ||
          typeof dynamicUserId !== 'string' || !hex32.test(dynamicUserId)) return eventId;
      const installation = installations.doc(userId);
      const event = events.doc(createHash('sha256').update(platform + ':' + eventId).digest('hex'));
      await db.runTransaction(async transaction => {
        const [device, recorded] = await transaction.getAll(installation, event);
        if (recorded.exists) return;
        const state = device.data() as PreviewState | undefined;
        const pending = state?.pending;
        const now = Date.now();
        if (pending?.attemptId !== dynamicUserId || pending.platform !== platform || pending.expiresAt <= now ||
            (state?.grant && state.grant.nextAt > now)) return;
        transaction.create(event, { receivedAt: new Date(now) });
        transaction.set(installation, { grant: { episodeId: pending.episodeId, nextAt: now + cooldownMs } });
      });
      return eventId;
    },
  };
}
