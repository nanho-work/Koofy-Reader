import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const sharp=createRequire(import.meta.url)('/Users/choenamho/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root=path.dirname(fileURLToPath(import.meta.url)),repo=path.resolve(root,'../../..');
const uri=p=>'data:image/png;base64,'+fs.readFileSync(path.join(repo,p)).toString('base64');
const logo=uri('assets/images/promotions/koofy_reader_wordmark.png');
const copy={ko:{title:['얼마나 읽었는지,','한눈에.'],sub:'독서 달력과 그래프로 나의 시간을 돌아보세요.',tag:'나의 독서 기록'},en:{title:['Your reading time,','at a glance.'],sub:'Look back on your reading with a calendar and graphs.',tag:'YOUR READING JOURNAL'},ja:{title:['読書の時間を、','ひと目で。'],sub:'カレンダーとグラフで、読書の歩みを振り返る。',tag:'自分だけの読書記録'}};
const formats=[['Android-1080x1920','android',1080,1920],['Android-Tablet-1080x1920','ipad',1080,1920],['iPhone-1320x2868','iphone',1320,2868],['iPhone-1206x2622','iphone',1206,2622],['iPad-2064x2752','ipad',2064,2752],['iPhone-Duo-2853x2007','duo',2853,2007]];
let id=0;const manifest=[];
function frame(lang,device,kind,x,y,w){
 const raw=`출시·홍보자료/제작원본/독서기록_화면캡처/raw/${lang}-${device}-${kind}.png`,m=fs.readFileSync(path.join(repo,raw));
 const h=w*({iphone:956/440,android:864/432,ipad:1376/1032,duo:669/951}[device]);
 const clip=`screen${id++}`;
 return `<g filter="url(#shadow)"><rect x="${x-7}" y="${y-7}" width="${w+14}" height="${h+14}" rx="24" fill="#526353"/><clipPath id="${clip}"><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="18"/></clipPath><image x="${x}" y="${y}" width="${w}" height="${h}" preserveAspectRatio="none" href="data:image/png;base64,${m.toString('base64')}" clip-path="url(#${clip})"/></g>`;
}
for(const lang of ['ko','en','ja'])for(const [format,device,w,h] of formats){
 const H=h/w*1320,wide=device==='duo',tablet=device==='ipad',c=copy[lang];
 const titleY=wide?185:260, size=wide?65:lang==='en'?88:94,step=wide?75:112;
 let content;
 if(wide) content=frame(lang,device,'calendar',65,380,740)+frame(lang,device,'graph',790,470,460);
 else if(tablet) content=frame(lang,device,'calendar',80,610,790)+frame(lang,device,'graph',700,Math.min(H-690,1010),500);
 else content=frame(lang,device,'calendar',85,620,790)+frame(lang,device,'graph',735,Math.min(H-1170,1470),490);
 const font=lang==='ja'?'Hiragino Sans,Apple SD Gothic Neo,sans-serif':'Apple SD Gothic Neo,sans-serif';
 const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 1320 ${H}"><defs><linearGradient id="bg" x2=".6" y2="1"><stop stop-color="#E0EBDC"/><stop offset=".45" stop-color="#F5F4EB"/><stop offset="1" stop-color="#F8F7F1"/></linearGradient><filter id="shadow" x="-.3" y="-.2" width="1.6" height="1.5"><feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#32442F" flood-opacity=".16"/></filter></defs><rect width="1320" height="${H}" fill="url(#bg)"/><image x="78" y="39" width="320" height="105" href="${logo}"/><g font-family="${font}" fill="#253E2E"><text x="85" y="${titleY}" font-size="${size}" font-weight="750" letter-spacing="-2">${c.title[0]}</text><text x="85" y="${titleY+step}" font-size="${size}" font-weight="750" letter-spacing="-2">${c.title[1]}</text><text x="88" y="${titleY+step+(wide?53:78)}" font-size="${wide?28:32}" fill="#60715F">${c.sub}</text></g>${content}<text x="88" y="${H-50}" font-family="${font}" font-size="24" letter-spacing="1" fill="#60715F">${c.tag}</text></svg>`;
 const dir=path.join(root,lang,format);fs.mkdirSync(dir,{recursive:true});const file=path.join(dir,'07-reading-journal.png');
 await sharp(Buffer.from(svg)).flatten({background:'#F8F7F1'}).removeAlpha().png().toFile(file);
 await sharp(file).resize({width:660}).png().toFile(path.join(root,'previews',`${lang}-${format}.png`));
 manifest.push({language:lang,device:format,file:path.relative(root,file),width:w,height:h,source:'Actual Flutter widgets rendered with illustrative local reading history; no production data modified.'});
}
fs.writeFileSync(path.join(root,'manifest.json'),JSON.stringify(manifest,null,2));console.log(`Rendered ${manifest.length} images.`);
