// Scoped, repeatable publication of the owner-supplied Mermaid translations.
// Run from repository root. Requires Google application-default credentials.
// node tool/publish_novel_translations.cjs MANIFEST BACKUP [--apply]
const fs=require('node:fs');const path=require('node:path');
const {createHash}=require('node:crypto');const req=require('node:module').createRequire(path.resolve('functions/package.json'));
const {initializeApp}=req('firebase-admin/app');const {getFirestore}=req('firebase-admin/firestore');const {getStorage}=req('firebase-admin/storage');
const {validateUpload,publish,episodeMetadata,seriesMetadata}=require('../functions/lib/src/content.js');
const PROJECT='koofy-reader', KO='11b62a009f794bc7bab1d5c6b42a53c2';
const hash=b=>createHash('sha256').update(b).digest('hex');
const stable=s=>hash(`koofy-mermaid-localization-v1:${s}`).slice(0,32);
const titles={en:'The Mermaid Princess Cuts the Waves',ja:'人魚姫は波を斬る'};
const licenses={en:'Original work by the author. Free download and personal reading in Koofy Reader are permitted. Unauthorized redistribution is prohibited.',ja:'著者本人の創作作品です。Koofy Readerでの無料ダウンロードと個人での鑑賞を許可します。無断再配布は禁止します。'};
(async()=>{
 const [manifestPath,backupPath]=process.argv.slice(2);if(!manifestPath||!backupPath)throw Error('Provide manifest and backup paths');
 const apply=process.argv.includes('--apply');
 const rows=JSON.parse(fs.readFileSync(manifestPath));const backup=JSON.parse(fs.readFileSync(backupPath));
 const oldSeries=backup.find(x=>x.id===KO);if(!oldSeries?.publishedContent)throw Error('Missing Korean series backup');
 for(const lang of ['ko','en','ja']) {
  const numbers=rows.filter(x=>x.language===lang).map(x=>x.number).sort((a,b)=>a-b);
  if(JSON.stringify(numbers)!==JSON.stringify(Array.from({length:40},(_,i)=>i+1)))throw Error(`Invalid episode sequence: ${lang}`);
 }
 // Verify the entire source set before any remote writes.
 for(const row of rows)for(const [field,digest]of [['text','sourceSha256'],['cover','coverSha256']]) {
  if(hash(fs.readFileSync(row[field]))!==row[digest])throw Error(`Source changed: ${row.language}/${row.number}/${field}`);
 }
 const app=initializeApp({projectId:PROJECT,storageBucket:`${PROJECT}.firebasestorage.app`});
 const db=getFirestore(app),bucket=getStorage(app).bucket();const current=(await db.collection('readerContent').get()).docs.map(d=>d.data());
 const existing=new Map(current.map(x=>[x.id,x]));
 const planned=[];const assets=[];const now=new Date().toISOString();
 async function prepareAsset(kind,slot,file,id){
  const validated=await validateUpload(kind,slot,fs.readFileSync(file));
  const asset={...validated.asset,path:`readerContent/${id}/localized-${validated.asset.sha256}/${slot}.${validated.asset.extension}`};
  assets.push({asset,bytes:validated.bytes});return asset;
 }
 function add(next){
  const before=existing.get(next.id);
  if(before && JSON.stringify({...next,revision:0,publishedContent:{...next.publishedContent,version:0},updatedAt:''})===JSON.stringify({...before,revision:0,publishedContent:{...before.publishedContent,version:0},updatedAt:''}))return;
  planned.push({before,next});
 }
 // Keep Korean episodes 1–4 and existing cover assets untouched.
 for(const row of rows.filter(x=>x.language==='ko'&&x.number>=5)){
  const before=current.find(x=>x.seriesId===KO&&x.episodeNumber===row.number);
  const original=backup.find(x=>x.id===before?.id);
  if(!before||!original||before.revision!==original.revision||before.revision!==before.publishedContent?.version)throw Error(`Korean draft/revision conflict: ${row.number}`);
  const txt=await prepareAsset('book','txt',row.text,before.id);
  const fields=episodeMetadata({...before,title:row.title},oldSeries.publishedContent,KO);
  if(before.publishedContent.assets.txt?.sha256===txt.sha256&&before.title===row.title)continue;
  const next={...before,...fields,assets:{...before.assets,txt},updatedAt:now};delete next.assets.epub;
  next.publishedContent=publish(next,oldSeries);next.revision=next.publishedContent.version;next.published=true;add(next);
 }
 for(const language of ['en','ja']){
  const id=stable(language);const before=existing.get(id);
  if(before)throw Error(`Translation already exists (${language}); inspect rather than overwrite published translations`);
  const first=rows.find(x=>x.language===language&&x.number===1);
  const fields=seriesMetadata({...oldSeries.publishedContent,language,title:titles[language],license:licenses[language]});
  const series={id,kind:'series',...fields,revision:1,published:false,publishedContent:null,updatedAt:now,assets:{cover:await prepareAsset('series','cover',first.cover,id)}};
  series.publishedContent=publish(series);series.revision=series.publishedContent.version;series.published=true;add(series);
  for(const row of rows.filter(x=>x.language===language)){
   const bookId=stable(`${language}:${row.number}`);if(existing.has(bookId))throw Error('Existing translated episode');
   const episode={id:bookId,kind:'book',...episodeMetadata({title:row.title,description:'',episodeNumber:row.number},series.publishedContent,id),revision:1,published:false,publishedContent:null,updatedAt:now,assets:{txt:await prepareAsset('book','txt',row.text,bookId),cover:await prepareAsset('book','cover',row.cover,bookId)}};
   episode.publishedContent=publish(episode,series);episode.revision=episode.publishedContent.version;episode.published=true;add(episode);
  }
 }
 const plan=planned.map(({before,next})=>({id:next.id,language:next.language,kind:next.kind,episodeNumber:next.episodeNumber,title:next.title,previousRevision:before?.revision??null,revision:next.revision,sha256:next.assets.txt?.sha256}));
 fs.writeFileSync(path.join(path.dirname(manifestPath),'publication-plan.json'),JSON.stringify(plan,null,2));
 console.log('Prepared',planned.length,'content changes;',assets.length,'validated assets;',apply?'APPLY':'DRY RUN');
 if(!apply)return;
 // Content-addressed files are immutable. No live metadata points at them until
 // the final transaction commits. Existing source objects are never removed.
 let count=0;
 for(const {asset,bytes}of assets){
  const file=bucket.file(asset.path);const [exists]=await file.exists();
  if(!exists)await file.save(bytes,{resumable:false,contentType:asset.contentType,metadata:{cacheControl:'private, max-age=300'},preconditionOpts:{ifGenerationMatch:0}});
  else {const [stored]=await file.download();if(hash(stored)!==asset.sha256)throw Error('Existing immutable asset hash mismatch');}
  if(++count%20===0)console.log('Assets staged',count,'/',assets.length);
 }
 await db.runTransaction(async tx=>{
  const refs=planned.map(x=>db.collection('readerContent').doc(x.next.id));
  const reservationRows=planned.filter(x=>!x.before&&x.next.seriesId);
  const reservations=reservationRows.map(x=>db.collection('readerEpisodeNumbers').doc(`${x.next.seriesId}_${x.next.episodeNumber}`));
  const docs=await tx.getAll(...refs,...reservations,db.collection('readerContent').doc(KO));
  if(docs.at(-1).data()?.revision!==oldSeries.revision)throw Error('Parent series changed');
  planned.forEach(({before},i)=>{if(before?docs[i].data()?.revision!==before.revision:docs[i].exists)throw Error('Concurrent content change');});
  for(let i=0;i<reservations.length;i++)if(docs[refs.length+i].exists)throw Error('Episode number already reserved');
  planned.forEach(({next},i)=>{
   tx.set(refs[i],next);
   tx.create(db.collection('readerAudit').doc(),{contentId:next.id,action:'ownerLocalizedPublication',uid:'operator-adc',revision:next.revision,at:now});
  });
  reservations.forEach((ref,i)=>tx.create(ref,{contentId:reservationRows[i].next.id}));
 });
 fs.writeFileSync(path.join(path.dirname(manifestPath),'published.json'),JSON.stringify({at:now,project:PROJECT,items:plan},null,2));
 console.log('Published atomically:',planned.length,'documents');
})().catch(e=>{console.error(e.message);process.exit(1)});
