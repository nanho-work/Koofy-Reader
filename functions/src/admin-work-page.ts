import { Content, requireValue } from './content';

export type AdminWorkScope = 'general' | 'monthly' | 'novel' | undefined;
export function inAdminWorkScope(item: Content, scope: AdminWorkScope): boolean {
  if (item.seriesId || item.deleting) return false;
  const month = item.issueMonth || item.publishedContent?.issueMonth;
  return scope === 'monthly' ? !!month : scope === 'general'
    ? item.collectionType === 'general' && !month
    : scope === 'novel' ? !item.collectionType && !month : true;
}
export function adminWorkKey(item: Content, scope: AdminWorkScope): string {
  return scope === 'monthly' ? `month:${item.issueMonth || item.publishedContent?.issueMonth}`
    : item.translationGroupId || item.id;
}

/** Slice after scope filtering and translation expansion, not after raw document reads.
 * Old records need no migration. A cursor always names the last returned work's
 * canonical (smallest) document ID, so later translations cannot repeat a work.
 */
export async function adminWorkPage(options: {
  scope: AdminWorkScope; after?: string; size?: number;
  read: (after?: string) => Promise<{ items: Content[]; nextCursor: string | null }>;
  expand: (item: Content) => Promise<Content[]>;
}) {
  const size = options.size ?? 24;
  const items: Content[] = [], works = new Set<string>(), visited = new Set<string>();
  let cursor = options.after, last: string | null = null;
  while (true) {
    const page = await options.read(cursor);
    const seeds = page.items.filter(item => inAdminWorkScope(item, options.scope));
    const expanded = await Promise.all(seeds.map(options.expand));
    for (let i = 0; i < seeds.length; i++) {
      const seed = seeds[i];
      const key = adminWorkKey(seed, options.scope);
      const members = expanded[i].filter(item => item.kind === seed.kind && inAdminWorkScope(item, options.scope) && adminWorkKey(item, options.scope) === key)
        .sort((a, b) => a.id.localeCompare(b.id));
      if (!members.length || members[0].id !== seed.id) continue;
      if (options.after && seed.id <= options.after) continue;
      if (works.has(key)) continue;
      // Look ahead to a real, unseen work before exposing a More button.
      if (works.size === size) return { items, nextCursor: last };
      works.add(key); items.push(...members); last = seed.id;
    }
    if (!page.nextCursor) return { items, nextCursor: null };
    requireValue(page.nextCursor !== cursor && !visited.has(page.nextCursor), '목록의 다음 페이지를 확인하지 못했습니다.');
    visited.add(page.nextCursor); cursor = page.nextCursor;
  }
}
