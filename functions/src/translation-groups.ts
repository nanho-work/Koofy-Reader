import { Content, requireValue } from './content';
/** Admin-only linkage: never replace IDs, files or published snapshots. */
export function validateTranslationGroup(values: Content[], existing: Content[] = []): string {
  requireValue(values.length >= 2 && values.length <= 3, '번역본 2~3개를 선택해 주세요.');
  requireValue(new Set(values.map(x => x.id)).size === values.length, '중복 작품입니다.');
  requireValue(values.every(x => !x.deleting && !x.seriesId && !x.issueMonth && !x.publishedContent?.issueMonth && x.kind !== 'font'), '일반 작품만 연결할 수 있습니다.');
  requireValue(values.every(x => x.kind === values[0].kind), '단권과 연재 작품은 서로 연결할 수 없습니다.');
  const groups = [...new Set(values.map(x => x.translationGroupId).filter(Boolean))];
  requireValue(groups.length <= 1, '이미 다른 번역 묶음에 연결된 작품입니다.');
  const combined = [...existing.filter(x => !values.some(v => v.id === x.id)), ...values];
  requireValue(new Set(combined.map(x => x.language || 'ko')).size === combined.length, '언어마다 한 작품만 연결할 수 있습니다.');
  return groups[0] || values[0].id;
}
