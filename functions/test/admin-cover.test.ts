import test from 'node:test';
import assert from 'node:assert/strict';
import {adminCoverAsset} from '../src/admin-cover';
import type {Content} from '../src/content';
const cover={path:'readerContent/book1/asset/cover.png',sha256:'a'.repeat(64),size:100,extension:'png',contentType:'image/png'};
const item={id:'book1',kind:'book',revision:2,assets:{cover},published:false,publishedContent:null} as unknown as Content;
test('only an authenticated super-admin policy can preview a private draft cover',()=>{
 for(const superAdmin of [undefined,false,'true',1])assert.throws(()=>adminCoverAsset(item,2,{superAdmin}));
 assert.equal(adminCoverAsset(item,2,{superAdmin:true}),cover);
});
test('reject stale, deleted, missing cover, non-image and unrelated storage paths',()=>{
 assert.throws(()=>adminCoverAsset(item,1,{superAdmin:true}));
 for(const patch of [{deleting:true},{assets:{}},{kind:'font'},{assets:{cover:{...cover,contentType:'text/plain'}}},{assets:{cover:{...cover,path:'private/other/secret'}}}])assert.throws(()=>adminCoverAsset({...item,...patch} as Content,2,{superAdmin:true}));
});
test('uses draft cover instead of an older publication, and supports shared cover assets',()=>{
 const withSnapshot={...item,publishedContent:{...item,version:1,assets:{cover:{...cover,path:'readerContent/book1/old.png'}}}} as Content;
 assert.equal(adminCoverAsset(withSnapshot,2,{superAdmin:true}),cover);
 const shared={...cover,path:'readerSharedCovers/hash/cover.png'};
 assert.equal(adminCoverAsset({...item,assets:{cover:shared}},2,{superAdmin:true}),shared);
});
