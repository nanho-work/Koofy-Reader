import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { Content, isReleased, contentLanguage } from './content';

export function releaseTimestamp(item: Content, now: number) {
  const s=item.publishedContent!;
  const parsed=Date.parse(s.releaseAt || (s.releaseDate ? `${s.releaseDate}T00:00:00+09:00` : s.issueMonth ? `${s.issueMonth}-01T00:00:00+09:00` : ''));
  return Number.isFinite(parsed)?Math.max(parsed,now):now;
}
export function notificationPayload(item: Content,parent?: Content) {
  const s=item.publishedContent!,language=contentLanguage(s.language);
  const monthly=!!s.issueMonth || !!parent?.publishedContent?.issueMonth;
  const title=language==='ko'?(monthly?'오늘의 월간 쿠피가 도착했어요':'새로운 이야기가 도착했어요'):language==='ja'?(monthly?'月刊クーフィーの新しいお話です':'新しいお話が届きました'):(monthly?'A new Koofy Monthly story':'A new story is here');
  const body=language==='ko'?`「${s.title}」, 잠깐 쉬며 읽어보세요.`:language==='ja'?`「${s.title}」を読んでみませんか。`:`Take a reading break with “${s.title}”.`;
  const work=parent?.publishedContent?.translationGroupId || parent?.id || s.translationGroupId || item.id;
  const bases=monthly?['monthly']:[`work_${work}`,'books'];
  return {condition:bases.map(b=>`'reader_${b}_${language}' in topics`).join(' || '),notification:{title,body},data:{id:item.id,seriesId:s.seriesId||'',language},android:{notification:{tag:`reader-${item.id}`}},apns:{headers:{'apns-collapse-id':`reader-${item.id}`},payload:{aps:{sound:'default'}}}};
}

/** Enqueue once per new publication; edits and republishing old works don't notify. */
export const readerQueueNewStory=onDocumentWritten({document:'readerContent/{contentId}',region:'asia-northeast3',maxInstances:2},async event=>{
  const after=event.data?.after.data() as Content|undefined;
  const before=event.data?.before.data() as Content|undefined;
  if(!after || after.kind!=='book' || !after.published || !after.publishedContent || after.deleting)return;
  const db=getFirestore(),ref=db.collection('readerNotificationQueue').doc(after.id);
  await db.runTransaction(async tx=>{
    // Firestore events can arrive out of order. Schedule from the current
    // published snapshot so an old edit cannot undo a newer release date.
    const live=(await tx.get(db.collection('readerContent').doc(after.id))).data() as Content|undefined;
    if(!live || !live.published || !live.publishedContent || live.deleting)return;
    const existing=await tx.get(ref);
    if(existing.exists) {
      if(existing.data()?.state==='pending')tx.update(ref,{dueAt:releaseTimestamp(live,Date.now())});
      return;
    }
    if(before?.publishedContent)return;
    tx.create(ref,{state:'pending',dueAt:releaseTimestamp(live,Date.now()),createdAt:FieldValue.serverTimestamp()});
  });
});

export const readerSendNewStories=onSchedule({schedule:'every 5 minutes',timeZone:'Asia/Seoul',region:'asia-northeast3',maxInstances:1,timeoutSeconds:120},async()=>{
  const db=getFirestore();
  const rows=await db.collection('readerNotificationQueue').where('state','==','pending').orderBy('dueAt').endAt(Date.now()).limit(100).get();
  for(const row of rows.docs) {
    const contentRef=db.collection('readerContent').doc(row.id);
    const item=(await contentRef.get()).data() as Content|undefined;
    if(!item || item.deleting || !item.published){await row.ref.update({state:'cancelled'});continue;}
    if(!isReleased(item)){await row.ref.update({dueAt:releaseTimestamp(item,Date.now()+60000)});continue;}
    const parent=item.publishedContent?.seriesId?(await db.collection('readerContent').doc(item.publishedContent.seriesId).get()).data() as Content|undefined:undefined;
    if(item.publishedContent?.seriesId && (!parent || !parent.published || parent.deleting)){await row.ref.update({state:'cancelled'});continue;}
    if(parent && !isReleased(parent)){await row.ref.update({dueAt:releaseTimestamp(parent,Date.now()+60000)});continue;}
    const claimed=await db.runTransaction(async tx=>{const current=await tx.get(row.ref);if(current.data()?.state!=='pending')return false;tx.update(row.ref,{state:'dispatching',startedAt:FieldValue.serverTimestamp()});return true;});
    if(!claimed)continue;
    // FCM has no exactly-once topic API. Never automatically retry ambiguous sends.
    try{const messageId=await getMessaging().send(notificationPayload(item,parent));await row.ref.update({state:'sent',messageId,sentAt:FieldValue.serverTimestamp()});}
    catch{await row.ref.update({state:'needsReview',failedAt:FieldValue.serverTimestamp()});}
  }
});
