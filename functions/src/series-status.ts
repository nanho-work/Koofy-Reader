import { Content, isReleased, requireValue } from './content';

export type SeriesStatus = 'ongoing' | 'completed';
/** Change only the lifecycle flag, preserving unpublished edits and schedules. */
export function changeSeriesStatus(item: Content, status: SeriesStatus, at: string): Content {
  requireValue(item.kind === 'series' && !item.seriesId && !item.issueMonth && !item.publishedContent?.issueMonth && !item.deleting, '일반 회차형 작품만 상태를 변경할 수 있습니다.');
  requireValue(status === 'ongoing' || status === 'completed', '연재 상태를 확인해 주세요.');
  return {
    ...item, seriesStatus: status, revision: item.revision + 1, updatedAt: at,
    publishedContent: item.publishedContent ? {
      ...item.publishedContent, seriesStatus: status, version: item.publishedContent.version + 1,
    } : null,
  };
}
export function pendingEpisodes(episodes: Content[], now: Date) {
  let drafts = 0, scheduled = 0;
  for (const item of episodes) {
    if (item.deleting) continue;
    if (!item.published || !item.publishedContent) drafts++;
    else if (!isReleased(item, now)) scheduled++;
  }
  return { drafts, scheduled };
}
