import { Content, Metadata, MONTHLY_DEFAULTS, assertRevision, monthlyLicense, requireValue } from './content';

// Correct catalog classification only: preserve files, book IDs and reading locators.
export function correctMonthlyLanguage(issue: Content, episodes: Content[], expected: number, language: unknown, now: string): Content[] {
  requireValue(language === 'ko' || language === 'en' || language === 'ja', '올바른 언어를 선택해 주세요.');
  assertRevision(issue, expected);
  requireValue(issue.kind === 'series' && issue.issueMonth && !issue.deleting, '월간호만 언어를 정정할 수 있습니다.');
  requireValue(!issue.compilationId && !issue.publishedContent?.compilationId, '합본이 연결된 월간호는 언어를 정정할 수 없습니다.');
  requireValue(episodes.length <= 100, '회차가 100개를 초과하여 일괄 정정할 수 없습니다.');
  requireValue(episodes.every(e => e.kind === 'book' && e.seriesId === issue.id && !e.deleting), '회차 상태가 변경되었습니다. 목록을 새로고침해 주세요.');
  const fields = (item: Metadata): Pick<Metadata, 'language' | 'author' | 'license'> => ({ language, author: MONTHLY_DEFAULTS[language].author, license: monthlyLicense(item.license, language) });
  return [issue, ...episodes].map(item => ({ ...item, ...fields(item), revision: item.revision + 1, updatedAt: now,
    publishedContent: item.publishedContent ? { ...item.publishedContent, ...fields(item.publishedContent), version: item.publishedContent.version + 1 } : null,
  }));
}
