import { createHash } from 'node:crypto';
import { Firestore } from 'firebase-admin/firestore';
import { Content, MONTHLY_DEFAULTS, contentLanguage, episodeMetadata, requireValue, seriesMetadata } from './content';
export const monthlyLanguages = ['ko', 'en', 'ja'] as const;
export function issueTitle(month: string, language: typeof monthlyLanguages[number]) {
  requireValue(/^20\d{2}-(0[1-9]|1[0-2])$/.test(month), '발행 연·월을 확인해 주세요.');
  const [year, m] = month.split('-');
  const number = Number(m);
  return language === 'ko' ? `월간 쿠피 ${year}년 ${number}월호` : language === 'ja' ? `月刊クーフィー ${year}年${number}月号` : `Koofy Monthly — ${['January','February','March','April','May','June','July','August','September','October','November','December'][number - 1]} ${year}`;
}
export function matchingIssue(items: Content[], month: string, language: typeof monthlyLanguages[number]) {
  const matches = items.filter(x => x.kind === 'series' && (x.issueMonth || x.publishedContent?.issueMonth) === month && contentLanguage(x.language) === language);
  requireValue(matches.length <= 1, `${month} ${language} 월간호가 여러 개입니다. 기존 개별 관리에서 확인해 주세요. 기존 항목은 변경하지 않았습니다.`);
  requireValue(!matches[0]?.deleting, '삭제 중인 월간호가 있습니다. 삭제 완료 후 다시 시도해 주세요.');
  return matches[0];
}
const key = (value: string) => createHash('sha256').update(value).digest('hex').slice(0, 32);
/** Transactional, retry-safe creation; retain legacy IDs, titles and snapshots. */
export async function ensureMonthlyIssues(db: Firestore, month: string, uid: string) {
  issueTitle(month, 'ko');
  return db.runTransaction(async tx => {
    const collection = db.collection('readerContent');
    const all = await tx.get(collection.where('kind', '==', 'series'));
    const existing = all.docs.map(d => d.data() as Content);
    const items = monthlyLanguages.map(language => matchingIssue(existing, month, language));
    const at = new Date().toISOString();
    return monthlyLanguages.map((language, i) => {
      if (items[i]) return items[i]!;
      const item: Content = { id: key(`monthly:${month}:${language}`), kind: 'series', ...seriesMetadata({ issueMonth: month, language, title: issueTitle(month, language), ...MONTHLY_DEFAULTS[language], description: '', autoCompile: true }), revision: 1, assets: {}, published: false, publishedContent: null, updatedAt: at };
      tx.create(collection.doc(item.id), item);
      tx.create(db.collection('readerAudit').doc(), { contentId: item.id, action: 'ensureMonthlyIssues', uid, at });
      return item;
    });
  });
}
/** Create-or-find a translation slot. Retrying after a lost response cannot duplicate it. */
export async function ensureMonthlyEpisode(db: Firestore, seriesId: string, input: unknown, uid: string) {
  return db.runTransaction(async tx => {
    const contents = db.collection('readerContent');
    const parent = (await tx.get(contents.doc(seriesId))).data() as Content | undefined;
    requireValue(parent?.kind === 'series' && parent.issueMonth && !parent.deleting, '월간호를 선택해 주세요.');
    requireValue(!parent.compilationId && !parent.publishedContent?.compilationId, '합본이 생성된 월간호입니다. 기존 개별 관리에서 확인해 주세요.');
    const fields = episodeMetadata(input, parent, parent.id);
    const existing = await tx.get(contents.where('seriesId', '==', seriesId));
    const found = existing.docs.map(d => d.data() as Content).filter(x => x.episodeNumber === fields.episodeNumber);
    requireValue(found.length <= 1 && !found[0]?.deleting, '해당 회차가 중복되었거나 삭제 중입니다. 기존 개별 관리에서 확인해 주세요.');
    if (found[0]) return found[0];
    const reservation = db.collection('readerEpisodeNumbers').doc(`${seriesId}_${fields.episodeNumber}`);
    requireValue(!(await tx.get(reservation)).exists, '회차 번호가 사용 중입니다. 목록을 새로고침해 주세요.');
    const at = new Date().toISOString();
    const item: Content = { id: key(`monthly-episode:${seriesId}:${fields.episodeNumber}`), kind: 'book', ...fields, revision: 1, assets: {}, published: false, publishedContent: null, updatedAt: at };
    tx.create(contents.doc(item.id), item); tx.set(reservation, { contentId: item.id });
    tx.create(db.collection('readerAudit').doc(), { contentId: item.id, action: 'ensureMonthlyEpisode', uid, at });
    return item;
  });
}
