import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
const sharp=createRequire(import.meta.url)('/Users/choenamho/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root='출시·홍보자료/제작원본/스토어스크린샷_기본6장',out=`${root}/deliverables`;
const icon=fs.readFileSync('assets/branding/app_icon.png').toString('base64');
const copy={
 ko:[
 ['library',['나만의 서재,','어디서나 펼치다.'],'내 책을 모으고 읽던 곳에서 이어 읽어요.','나만의 서재'],
 ['reading',['이야기에 집중하는,','나만의 시간.'],'편안한 화면에서 한 문장씩 읽어 보세요.','독서에 집중'],
 ['settings',['글꼴부터 크기까지,','내 취향대로.'],'글자 크기와 간격, 글꼴과 배경을 조절해요.','독서 설정'],
 ['dark',['밤의 독서에도','편안한 화면.'],'어두운 배경으로 다음 이야기를 만나세요.','다크 모드'],
 ['books',['다음에 읽을 책을,','여기서 찾아요.'],'공개된 책을 찾아 다운로드하고 읽어 보세요.','도서 다운로드'],
 ['home',['짧은 이야기로,','하루를 열어요.'],'월간 쿠피를 읽고, 나의 사연도 보내 보세요.','월간 쿠피']
 ],
 en:[
  ['library',['Your books.','Your own space.'],'Keep your books together. Pick up where you left off.','YOUR LIBRARY'],
  ['reading',['A little time,','just for reading.'],'A calm, comfortable place for every page.','FOCUS ON THE STORY'],
  ['settings',['Make every page','feel like yours.'],'Adjust text size, spacing, fonts and background.','READING SETTINGS'],
  ['dark',['A softer screen','after dark.'],'Settle into your next chapter with a dark background.','DARK MODE'],
  ['books',['Find your','next read.'],'Browse available books and download them to read offline.','BOOK DOWNLOADS'],
  ['home',['A short story.','A moment for you.'],'Read Koofy Monthly and share your own story.','KOOFY MONTHLY']
 ],
 ja:[
  ['library',['自分だけの本棚を、','いつもそばに。'],'本をひとつにまとめて、読んでいた続きから。','自分の本棚'],
  ['reading',['物語に向き合う、','自分だけの時間。'],'読みやすい画面で、一文ずつゆっくりと。','読書に集中'],
  ['settings',['文字も、背景も、','自分好みに。'],'文字サイズや行間、フォントを自由に調整。','読書設定'],
  ['dark',['夜の読書に、','落ち着いた画面を。'],'暗い背景で、次の一章をゆったり楽しむ。','ダークモード'],
  ['books',['次に読みたい一冊を、','ここで見つけよう。'],'公開中の本を探して、ダウンロードして読む。','本のダウンロード'],
  ['home',['短い物語で、','一日をはじめよう。'],'月刊クーフィーを読んで、あなたの物語も。','月刊クーフィー']
 ]
};
const formats=[['Android-Tablet-1080x1920','fold',1080,1920],['iPhone-1206x2622','iphone',1206,2622],['iPhone-1320x2868','iphone',1320,2868],['iPad-2064x2752','ipad',2064,2752],['iPhone-Duo-2853x2007','duo',2853,2007],['Android-Fold-1768x2208','fold',1768,2208],['Android-1080x1920','android',1080,1920]];
const esc=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;');
let serial=0;
async function frame(lang,device,kind,x,y,w,crop=1){
 const b=await sharp(`${root}/raw/${lang}/${device}-${kind}.png`).resize({width:1320,withoutEnlargement:true}).png().toBuffer(), m=await sharp(b).metadata();
 const h=w*m.height/m.width*crop,id=`clip${serial++}`;
 return `<g><rect x="${x+6}" y="${y+16}" width="${w}" height="${h}" rx="20" fill="#213c2f" opacity=".18" filter="url(#shadow)"/><rect x="${x-5}" y="${y-5}" width="${w+10}" height="${h+10}" rx="14" fill="#314b3c"/><clipPath id="${id}"><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="9"/></clipPath><image x="${x}" y="${y}" width="${w}" height="${w*m.height/m.width}" href="data:image/png;base64,${b.toString('base64')}" clip-path="url(#${id})"/></g>`;
}
let manifest=[];
for(const lang of ['ko','en','ja'])for(const [folder,device,width,height] of formats){
 if(process.env.ONLY_LANG && lang!==process.env.ONLY_LANG) continue;
 if(process.env.ONLY_DEVICE && device!==process.env.ONLY_DEVICE) continue;
 const H=height/width*1320,wide=device==='duo',tablet=device==='ipad';
 const top=wide?180:tablet?240:300,start=wide?360:tablet?550:620;
 const font=lang==='ja'?'Hiragino Sans, sans-serif':lang==='ko'?'Apple SD Gothic Neo, sans-serif':'Arial, sans-serif';
 let cards=copy[lang].filter(c=>['home','books','library'].includes(c[0]) || (['iphone','ipad','android','fold'].includes(device)&&['reading','dark','settings'].includes(c[0])));
 cards.sort((a,b)=>['reading','library','books','home','settings','dark'].indexOf(a[0])-['reading','library','books','home','settings','dark'].indexOf(b[0]));
 for(let i=0;i<cards.length;i++){
  let [kind,lines,sub,tag]=cards[i]; if(kind==='reading'&&['fold','ipad'].includes(device)){[lines,sub]=({ko:[['넓게 펼치고,','책처럼 읽어요.'],'넓은 화면에서 두 페이지로 이어지는 독서.'],en:[['Open wide.','Read two pages.'],'A book-like spread for a larger screen.'],ja:[['大きく開いて、','本のように読む。'],'広い画面で楽しむ、見開きの読書。']})[lang];} const maxH=H-start-90;
  const raw=await sharp(`${root}/raw/${lang}/${device}-${kind}.png`).metadata();
  let content;
  if(kind==='fonts'&&!wide){
   const read=await sharp(`${root}/raw/${lang}/${device}-reading.png`).metadata();
   const w=Math.min(860,maxH*read.width/read.height);
   content=await frame(lang,device,'reading',(1320-w)/2-50,start,w);
   const panelW=tablet?800:850,panelH=panelW*raw.height/raw.width*.34;
   content+=await frame(lang,device,kind,1320-panelW-70,Math.min(start+maxH-panelH-15,start+maxH*.57),panelW,.34);
  } else {
   const w=Math.min(wide?1145:tablet?950:925,maxH*raw.width/raw.height),h=w*raw.height/raw.width;
   content=await frame(lang,device,kind,(1320-w)/2,start,w);
  }
  const size=lang==='ja'?(wide?54:88):(wide?60:100),subSize=lang==='en'?29:34;
  const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 1320 ${H}"><defs><linearGradient id="paper" x2=".8" y2="1"><stop stop-color="#f7f5ee"/><stop offset="1" stop-color="#e5eadc"/></linearGradient><filter id="shadow" x="-20%" y="-20%" width="150%" height="150%"><feGaussianBlur stdDeviation="14"/></filter></defs>
<rect width="1320" height="${H}" fill="#f7f5ee"/><path d="M-100 ${H-150} Q500 ${H-900} 1450 ${H-950}V${H+10}H-100Z" fill="url(#paper)"/>
<g stroke="#d4dccb" fill="none" stroke-width="2">${[0,45,90].map(d=>`<path d="M-150 ${H-250+d} Q500 ${H-880+d} 1470 ${H-800+d}"/>`).join('')}</g>
<image x="85" y="72" width="76" height="76" href="data:image/png;base64,${icon}"/>
<g font-family="${font}" fill="#253c2f"><text x="182" y="125" font-size="39" font-weight="700">${{ko:'쿠피리더',en:'Koofy Reader',ja:'クーフィーリーダー'}[lang]}</text><text x="1235" y="119" text-anchor="end" font-size="22" fill="#71806f" letter-spacing="3">READ YOUR WAY</text>
<text x="85" y="${top}" font-size="${size}" font-weight="700" letter-spacing="-2">${esc(lines[0])}</text><text x="85" y="${top+(wide?65:118)}" font-size="${size}" font-weight="700" letter-spacing="-2">${esc(lines[1])}</text><text x="88" y="${top+(wide?115:193)}" font-size="${subSize}" fill="#697568">${esc(sub)}</text>
${content}
<text x="88" y="${H-42}" font-size="23" fill="#74816f">${esc(tag)}</text><text x="1230" y="${H-42}" text-anchor="end" font-size="23" fill="#74816f">0${i+1} / ${String(cards.length).padStart(2,'0')}</text></g></svg>`;
  const dir=`${out}/${lang}/${folder}`,src=`${root}/sources/${lang}/${folder}`;fs.mkdirSync(dir,{recursive:true});fs.mkdirSync(src,{recursive:true});
  const name=`0${i+1}-${kind}`;fs.writeFileSync(`${src}/${name}.svg`,svg);await sharp(Buffer.from(svg)).removeAlpha().png().toFile(`${dir}/${name}.png`);
  manifest.push({language:lang,device:folder,file:`${lang}/${folder}/${name}.png`,width,height});
 }
 const tw=270,th=Math.round(tw*height/width),gap=18;
 const thumbs=await Promise.all(cards.map(async(c,i)=>({input:await sharp(`${out}/${lang}/${folder}/0${i+1}-${c[0]}.png`).resize(tw,th).toBuffer(),left:gap+(i%3)*(tw+gap),top:gap+Math.floor(i/3)*(th+gap)})));
 fs.mkdirSync(`${root}/previews`,{recursive:true});await sharp({create:{width:3*tw+4*gap,height:Math.ceil(cards.length/3)*th+(Math.ceil(cards.length/3)+1)*gap,channels:3,background:'#dfe4d9'}}).composite(thumbs).png().toFile(`${root}/previews/${lang}-${folder}.png`);
}
if(!process.env.ONLY_DEVICE && !process.env.ONLY_LANG) fs.writeFileSync(`${root}/manifest.json`,JSON.stringify(manifest,null,2));console.log(`Rendered ${manifest.length} localized images.`);
