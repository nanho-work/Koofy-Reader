import {Content, isReleased, visibleInLanguage} from './content';

/** Same release predicate as downloads; scheduled or deleted chapters never count. */
export function releasedEpisodeCounts(items: Content[], language: 'ko'|'en'|'ja', now = new Date()) {
  const counts = new Map<string, number>();
  for (const item of items) {
    if (item.seriesId && item.published && !item.deleting && isReleased(item, now) && visibleInLanguage(item, language)) {
      counts.set(item.seriesId, (counts.get(item.seriesId) ?? 0) + 1);
    }
  }
  return counts;
}
export function nextCatalogChange(items: Content[], now = new Date()): string | null {
  const times = items.flatMap(item => {
    const snapshot = item.publishedContent;
    if (!item.published || item.deleting || !snapshot) return [];
    const gates = [snapshot.releaseAt, snapshot.releaseDate ? `${snapshot.releaseDate}T00:00:00+09:00` : '', snapshot.issueMonth ? `${snapshot.issueMonth}-01T00:00:00+09:00` : ''].map(value=>Date.parse(value||'')).filter(Number.isFinite);
    const time = gates.length ? Math.max(...gates) : NaN;
    return Number.isFinite(time) && time > now.getTime() ? [time] : [];
  });
  return times.length ? new Date(Math.min(...times)).toISOString() : null;
}
