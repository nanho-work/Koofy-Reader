import test from 'node:test';
import assert from 'node:assert/strict';
import { catalogLanguage, contentLanguage, episodeMetadata, metadata, publicItem, visibleInLanguage, Content } from '../src/content';
const base = { title: 'Story', author: 'Author', description: '', license: 'Permission' };
test('legacy is Korean; unsupported requested language falls back to English', () => {
  assert.equal(catalogLanguage(undefined),'ko');
  assert.equal(catalogLanguage('fr'),'en');
  assert.equal(catalogLanguage('ja'),'ja');
  assert.equal(contentLanguage(undefined),'ko');
  assert.throws(() => metadata({...base,language:'fr'}));
});
test('episode language follows parent, never the supplied episode language', () => {
  const fields=episodeMetadata({title:'Chapter',episodeNumber:5,language:'ko'}, {...base,language:'en'}, 'a'.repeat(32));
  assert.equal(fields.language,'en');
});
test('filter uses published language; fonts remain available to all languages', () => {
  const item = {...base,id:'a'.repeat(32),kind:'book',revision:2,assets:{},published:true,publishedContent:{...base,assets:{},version:2,language:'ja'},updatedAt:'now',language:'en'} as Content;
  assert.equal(visibleInLanguage(item,'en'),false);
  assert.equal(visibleInLanguage(item,'ja'),true);
  assert.equal(visibleInLanguage({...item,kind:'font'},'en'),true);
  assert.equal(visibleInLanguage({...item,publishedContent:{...base,assets:{},version:2}},'ko'),true);
});
test('episode labels match their published language', () => {
  for(const [language,label] of [['en','Chapter 3'],['ja','第3話'],['ko','3화']] as const) {
    const item={...base,id:'a'.repeat(32),kind:'book',revision:2,assets:{},published:true,updatedAt:'now',publishedContent:{...base,assets:{},version:2,language,seriesId:'b'.repeat(32),seriesTitle:'Story',episodeNumber:3}} as Content;
    assert.ok(publicItem(item).title.includes(label));
  }
});
