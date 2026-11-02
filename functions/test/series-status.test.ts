import test from 'node:test';
import assert from 'node:assert/strict';
import { changeSeriesStatus, pendingEpisodes } from '../src/series-status';
import type { Content } from '../src/content';
const base = {id:'series',kind:'series',title:'draft title',author:'Koofy',description:'',license:'',revision:9,seriesStatus:'ongoing',assets:{},published:true,updatedAt:'old',publishedContent:{title:'published title',author:'Koofy',description:'',license:'',version:5,assets:{},seriesStatus:'ongoing',releaseAt:'2026-11-01T09:00:00+09:00'}} as Content;
test('status-only update preserves unpublished edits and published schedules separately',()=>{
 const next=changeSeriesStatus(base,'completed','now');
 assert.equal(next.seriesStatus,'completed');assert.equal(next.revision,10);
 assert.equal(next.publishedContent?.seriesStatus,'completed');assert.equal(next.publishedContent?.version,6);
 assert.equal(next.title,'draft title');assert.equal(next.publishedContent?.title,'published title');
 assert.equal(next.publishedContent?.releaseAt,base.publishedContent?.releaseAt);
 assert.equal(next.publishedContent?.assets,base.publishedContent?.assets);
 assert.equal(next.published,true);assert.equal(base.seriesStatus,'ongoing');
});
test('private drafts stay private, completion is reversible and clean revisions stay aligned',()=>{
 const draft=changeSeriesStatus({...base,published:false,publishedContent:null},'completed','now');
 assert.equal(draft.published,false);assert.equal(draft.publishedContent,null);
 assert.equal(changeSeriesStatus(draft,'ongoing','later').seriesStatus,'ongoing');
 const clean={...base,publishedContent:{...base.publishedContent!,version:base.revision}};
 const next=changeSeriesStatus(clean,'completed','now');assert.equal(next.revision,next.publishedContent?.version);
});
test('rejects books, monthly issues, episodes and deleted works',()=>{
 for(const patch of [{kind:'book'},{issueMonth:'2026-10'},{publishedContent:{...base.publishedContent!,issueMonth:'2026-10'}},{seriesId:'parent'},{deleting:true}])assert.throws(()=>changeSeriesStatus({...base,...patch} as Content,'completed','now'));
});
test('pending counts use the published schedule and ignore deleted episodes',()=>{
 const now=new Date('2026-10-31T00:00:00Z');
 const released={...base,releaseAt:'2027-01-01T00:00:00Z',publishedContent:{...base.publishedContent!,releaseAt:'2026-10-01T00:00:00Z'}};
 assert.deepEqual(pendingEpisodes([base,{...base,published:false},released,{...base,deleting:true}],now),{drafts:1,scheduled:1});
});
