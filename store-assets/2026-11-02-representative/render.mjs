import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const sharp=createRequire(import.meta.url)('/Users/choenamho/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root=path.dirname(fileURLToPath(import.meta.url)), repo=path.resolve(root,'../..');
const data=p=>`data:image/${p.endsWith('.jpg')?'jpeg':'png'};base64,${fs.readFileSync(path.join(repo,p)).toString('base64')}`;
const bg=data('store-assets/2026-11-02-design-v1/inputs/paper-background.png');
const logo=data('assets/images/promotions/koofy_reader_wordmark.png');
const strings={ko:['펼치면, 책처럼.','펼친 화면에서, 두 페이지로.'],en:['Unfold your next chapter.','Two pages. More room to read.'],ja:['広げれば、本のように。','大きな画面で、見開き読書。']};
function render(lang,w,h,kind){
 const H=h/w*1024, header=kind==='apple-header', search=kind==='apple-search';
 const y=header?175:search?240:190, pw=header?600:680, ph=header?210:search?330:260, x=(1024-pw)/2;
 const suffix=lang==='ko'?'':`_${lang}`;
 const cover=data(`assets/books/sample_mermaid_001${suffix}.jpg`), body=data(`work/store-190/raw/${lang}/ipad-reading.png`);
 const size=lang==='en'?48:lang==='ja'?52:62, titleY=header?116:search?157:121, subY=header?148:search?198:156, logoY=header?-6:search?25:-1;
 return `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${w}" height="${h}" viewBox="0 0 1024 ${H}">
 <defs><linearGradient id="rim" x2="0" y2="1"><stop stop-color="#858884"/><stop offset=".2" stop-color="#252A27"/><stop offset=".9" stop-color="#161C18"/><stop offset="1" stop-color="#8C8F88"/></linearGradient><linearGradient id="crease"><stop stop-color="#000" stop-opacity="0"/><stop offset=".5" stop-color="#000" stop-opacity=".1"/><stop offset="1" stop-color="#000" stop-opacity="0"/></linearGradient><filter id="shadow" x="-.2" y="-.2" width="1.4" height="1.6"><feDropShadow dx="0" dy="7" stdDeviation="5" flood-color="#334831" flood-opacity=".22"/></filter><clipPath id="screen"><rect x="${x+9}" y="${y+8}" width="${pw-18}" height="${ph-19}" rx="23"/></clipPath></defs>
 <rect width="1024" height="${H}" fill="#EDF0E4"/><image width="1024" height="${H}" preserveAspectRatio="xMidYMid slice" opacity=".68" xlink:href="${bg}"/>
 <image x="392" y="${logoY}" width="240" height="80" xlink:href="${logo}"/>
 <g font-family="Apple SD Gothic Neo,Hiragino Sans,sans-serif" text-anchor="middle" fill="#203F2A"><text x="512" y="${titleY}" font-size="${size}" font-weight="800" letter-spacing="${lang==='en'?-1.7:-1.3}">${strings[lang][0]}</text><text x="512" y="${subY}" font-size="20" font-weight="500" fill="#596D55">${strings[lang][1]}</text></g>
 <rect x="${x}" y="${y}" width="${pw}" height="${ph}" rx="32" fill="url(#rim)" stroke="#6E756B" stroke-width="1.5" filter="url(#shadow)"/>
 <g clip-path="url(#screen)"><rect x="${x+8}" y="${y+8}" width="${pw-16}" height="${ph-18}" fill="#F9F8F4"/>
 <image x="${x+27}" y="${y+17}" width="${pw/2-49}" height="${ph-38}" preserveAspectRatio="xMidYMid meet" xlink:href="${cover}"/>
 <svg x="${x+pw/2+19}" y="${y+26}" width="${pw/2-42}" height="${ph-55}" viewBox="55 220 940 ${Math.round((ph-55)/(pw/2-42)*940)}" overflow="hidden"><image width="2064" height="2752" xlink:href="${body}"/></svg>
 <rect x="505" y="${y+8}" width="14" height="${ph-18}" fill="url(#crease)"/>
 </g><path d="M512 ${y} v8 M512 ${y+ph-10} v10" stroke="#BCC0B8" stroke-width="2"/>
 <text x="512" y="${y+ph+27}" text-anchor="middle" font-family="Arial,sans-serif" font-size="12" letter-spacing="1.8" fill="#63765D">TXT · EPUB · TTS</text>
 </svg>`;
}
const manifest=[];
for(const lang of ['ko','en','ja']) for(const [kind,w,h] of [['google-feature',1024,500],['apple-header',3840,1646],['apple-search',1920,1280]]){
 const svg=render(lang,w,h,kind),name=`${lang}-${kind}`;
 fs.writeFileSync(path.join(root,'sources',name+'.svg'),svg);
 await sharp(Buffer.from(svg)).flatten({background:'#EDF0E4'}).removeAlpha().png().toFile(path.join(root,name+'.png'));
 await sharp(path.join(root,name+'.png')).resize({width:1024}).png().toFile(path.join(root,'previews',name+'.png'));
 manifest.push({file:name+'.png',width:w,height:h,language:lang,placement:kind});
}
fs.writeFileSync(path.join(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
console.log(JSON.stringify(manifest));
