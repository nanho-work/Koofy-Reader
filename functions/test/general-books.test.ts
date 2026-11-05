import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { metadata, seriesMetadata, episodeMetadata, isReleased, publish, Content } from '../src/content';
import { validateTranslationGroup } from '../src/translation-groups';
const base = { title: '인어공주', author: 'Andersen', description: '', license: 'Permitted', language: 'ko' as const };
test('general episodes retain classification and obey exact release time without month restriction', () => {
  const parent = metadata({ ...base, collectionType: 'general' });
  const episode = episodeMetadata({ title: '폭풍', episodeNumber: 2, releaseAt: '2026-12-01T09:00:00+09:00' }, parent, 'parent');
  assert.equal(episode.collectionType, 'general');
  const item = { publishedContent: { ...episode, assets: {}, version: 1 } } as Content;
  assert.equal(isReleased(item, new Date('2026-11-30T23:59:59Z')), false);
  assert.equal(isReleased(item, new Date('2026-12-01T00:00:00Z')), true);
});
test('monthly bounds remain enforced and ordinary legacy metadata is unchanged', () => {
  assert.equal(metadata(base).collectionType, undefined);
  assert.throws(() => metadata({ ...base, issueMonth: '2026-11', releaseAt: '2026-12-01T09:00:00+09:00' }));
  assert.throws(() => metadata({ ...base, collectionType: 'unknown' }));
});
test('general books cannot be linked into existing novel groups', () => {
  const a = { ...base, id: 'a', kind: 'book', collectionType: 'general' } as Content;
  const b = { ...base, id: 'b', kind: 'book', language: 'en' } as Content;
  assert.throws(() => validateTranslationGroup([a,b]));
});

test('already published serial novels can reapply schedules in every language without becoming general books', () => {
  const cover={path:'parent/cover',sha256:'a'.repeat(64),size:1,extension:'webp',contentType:'image/webp'};
  const txt={...cover,path:'episode/body',extension:'txt',contentType:'text/plain'};
  for (const language of ['ko','en','ja'] as const) {
    const parent:Content={...seriesMetadata({...base,language}),id:'a'.repeat(32),kind:'series',revision:1,assets:{cover},published:true,publishedContent:null,updatedAt:''};
    parent.publishedContent=publish(parent);
    for(const [number,date] of [[1,'2026-11-05'],[2,'2026-11-06'],[3,'2026-12-01']] as const) {
      const original:Content={...episodeMetadata({title:'기존 회차',episodeNumber:number},parent,parent.id),id:String(number).repeat(32),kind:'book',revision:2,assets:{txt},published:true,publishedContent:null,updatedAt:''};
      original.publishedContent=publish(original,parent);
      const oldSnapshot=JSON.stringify(original.publishedContent);
      const fields=episodeMetadata({title:original.title,episodeNumber:number,releaseAt:date+'T19:36:00+09:00'},parent,parent.id);
      const draft={...original,...fields,revision:3};
      assert.equal(draft.id,original.id);assert.equal(draft.assets,original.assets);
      assert.equal(draft.collectionType,undefined);assert.equal(draft.issueMonth,'');
      assert.equal(JSON.stringify(draft.publishedContent),oldSnapshot);
      const rescheduled={...draft,publishedContent:publish(draft,parent)};
      assert.equal(rescheduled.publishedContent.releaseAt,date+'T19:36:00+09:00');
      assert.equal(isReleased(rescheduled,new Date(date+'T19:35:59+09:00')),false);
      assert.equal(isReleased(rescheduled,new Date(date+'T19:36:00+09:00')),true);
    }
  }
});
test('standalone novels accept schedules but monthly issues still reject dates outside their month', () => {
  assert.equal(metadata({...base,releaseAt:'2026-12-01T09:00:00+09:00'}).releaseDate,'2026-12-01');
  const monthly=seriesMetadata({...base,issueMonth:'2026-11'});
  assert.throws(()=>episodeMetadata({title:'회차',episodeNumber:1,releaseAt:'2026-12-01T09:00:00+09:00'},monthly,'parent'));
  assert.throws(()=>episodeMetadata({title:'회차',episodeNumber:1},monthly,'parent'));
});
