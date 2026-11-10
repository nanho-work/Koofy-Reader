import {Content, isReleased, visibleInLanguage} from './content';

/** Same release predicate as downloads; scheduled or deleted chapters never count. */
export function releasedEpisodeSummaries(items: Content[], language: 'ko'|'en'|'ja', now = new Date()) {
  const summaries = new Map<string, { count: number; latestAt: number }>();
  for (const item of items) {
    const snapshot = item.publishedContent;
    if (!item.seriesId || !item.published || item.deleting || !snapshot ||
        !isReleased(item, now) || !visibleInLanguage(item, language)) continue;
    const releasedAt = Date.parse(snapshot.releaseAt ||
      (snapshot.releaseDate ? `${snapshot.releaseDate}T00:00:00+09:00` : snapshot.publishedAt || ''));
    const summary = summaries.get(item.seriesId) ?? { count: 0, latestAt: 0 };
    summary.count++;
    if (Number.isFinite(releasedAt)) summary.latestAt = Math.max(summary.latestAt, releasedAt);
    summaries.set(item.seriesId, summary);
  }
  return summaries;
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

/** Older installed apps reject episode zero while parsing a whole catalog page. */
export function compatibleEpisode(item: Content, supportsPrologue: boolean) {
  return supportsPrologue || item.publishedContent?.episodeNumber !== 0;
}
