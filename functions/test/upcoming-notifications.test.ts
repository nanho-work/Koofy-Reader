import test from 'node:test';
import assert from 'node:assert/strict';
import {upcomingItem,Content} from '../src/content';
import {notificationPayload,releaseTimestamp} from '../src/reader-notifications';
const cover={path:'secret/cover',size:10,sha256:'a'.repeat(64),extension:'webp',contentType:'image/webp'};
const base={id:'a'.repeat(32),kind:'book',seriesId:'b'.repeat(32),published:true,deleting:false,revision:1,assets:{},updatedAt:'',title:'draft secret',author:'',description:'',license:'',publishedContent:{title:'Scheduled title',description:'private synopsis',author:'author',license:'license',language:'ko',seriesId:'b'.repeat(32),seriesTitle:'A story',episodeNumber:3,version:2,releaseAt:'2099-01-02T09:00:00+09:00',assets:{cover,txt:{...cover,path:'secret/manuscript',extension:'txt'}},sourceTxt:cover}} as Content;
test('scheduled preview exposes only published title/cover, never body or draft',()=>{
 const preview=upcomingItem(base);
 assert.equal(preview.upcoming,true);assert.equal(preview.title,'Scheduled title');assert.deepEqual(Object.keys(preview.assets),['cover']);
 const encoded=JSON.stringify(preview);assert.ok(!encoded.includes('secret/'));assert.ok(!encoded.includes('private synopsis'));assert.ok(!encoded.includes('sourceTxt'));assert.ok(!encoded.includes('draft secret'));
 assert.throws(()=>upcomingItem({...base,published:false}));assert.throws(()=>upcomingItem({...base,deleting:true}));
 assert.throws(()=>upcomingItem({...base,publishedContent:{...base.publishedContent!,releaseAt:'2000-01-01T00:00:00+09:00'}}));
});
test('notification topics follow language and work identity; monthly follows across issues',()=>{
 for(const language of ['ko','en','ja'] as const){
  const item={...base,publishedContent:{...base.publishedContent!,language,issueMonth:'2026-11'}};
  const payload=notificationPayload(item);assert.equal(payload.condition,`'reader_monthly_${language}' in topics`);assert.equal(payload.data.id,item.id);
 }
 const parent={...base,id:'b'.repeat(32),kind:'series',publishedContent:{...base.publishedContent!,translationGroupId:'c'.repeat(32)}} as Content;
 assert.match(notificationPayload(base,parent).condition,/reader_work_cccccccccccccccccccccccccccccccc_ko/);
 assert.equal(releaseTimestamp(base,0),Date.parse(base.publishedContent!.releaseAt!));
});
test('linked translations expose stable public work identity and retain old topic aliases',async()=>{
 const {publicItem}=await import('../src/content');
 const group='c'.repeat(32);
 const parent={...base,id:'b'.repeat(32),kind:'series',translationGroupId:group,publishedContent:{...base.publishedContent!,seriesId:undefined}} as Content;
 assert.equal(publicItem(parent).translationGroupId,group);
 const condition=notificationPayload(base,parent).condition;
 assert.match(condition,new RegExp(`reader_work_${group}_ko`));
 assert.match(condition,new RegExp(`reader_work_${parent.id}_ko`));
 assert.match(condition,/reader_books_ko/); // legacy explicit all-story opt-ins only
});
