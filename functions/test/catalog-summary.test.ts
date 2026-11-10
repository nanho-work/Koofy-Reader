import test from 'node:test';
import assert from 'node:assert/strict';
import type {Content} from '../src/content';
import {compatibleEpisode,nextCatalogChange,releasedEpisodeSummaries} from '../src/catalog-summary';
const now=new Date('2026-11-01T00:00:00Z');
const base={id:'a',kind:'book',seriesId:'parent',title:'draft',author:'',description:'',license:'',revision:1,assets:{},published:true,updatedAt:'',publishedContent:{title:'live',author:'',description:'',license:'',version:1,assets:{},language:'ko',releaseAt:'2026-11-01T09:00:00+09:00'}} as Content;
test('batch counts use published language and the exact scheduled instant',()=>{
 const future={...base,id:'future',publishedContent:{...base.publishedContent!,releaseAt:'2026-11-01T09:01:00+09:00'}};
 const japanese={...base,id:'ja',language:'ko',publishedContent:{...base.publishedContent!,language:'ja'}} as Content;
 const items=[base,future,japanese,{...base,id:'deleted',deleting:true},{...base,id:'draft',published:false},{...base,id:'other',seriesId:'other'}];
 const summary = {count:1,latestAt:now.getTime()};
 assert.deepEqual([...releasedEpisodeSummaries(items,'ko',now)],[['parent',summary],['other',summary]]);
 assert.deepEqual([...releasedEpisodeSummaries(items,'ja',now)],[['parent',summary]]);
 assert.equal(nextCatalogChange(items,now),'2026-11-01T00:01:00.000Z');
 const next = new Date('2026-11-01T00:01:00Z');
 assert.deepEqual(releasedEpisodeSummaries([base,future],'ko',next).get('parent'),{count:2,latestAt:next.getTime()});
});
test('cache expiration includes editorial month/date and ignores private or deleted drafts',()=>{
 const monthly={...base,publishedContent:{...base.publishedContent!,issueMonth:'2026-12',releaseAt:'',releaseDate:''}};
 assert.equal(nextCatalogChange([monthly],now),'2026-11-30T15:00:00.000Z');
 assert.equal(nextCatalogChange([{...monthly,published:false},{...monthly,deleting:true}],now),null);
 assert.equal(releasedEpisodeSummaries([monthly],'ko',now).size,0);
});

test('prologues are withheld from older apps without hiding other episodes or books',()=>{
 const prologue={...base,publishedContent:{...base.publishedContent!,episodeNumber:0}};
 assert.equal(compatibleEpisode(prologue,false),false);
 assert.equal(compatibleEpisode(prologue,true),true);
 assert.equal(compatibleEpisode({...prologue,publishedContent:{...prologue.publishedContent,episodeNumber:1}},false),true);
 assert.equal(compatibleEpisode(base,false),true);
});
