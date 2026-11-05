import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const sharp=createRequire(import.meta.url)('/Users/choenamho/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root=path.dirname(fileURLToPath(import.meta.url));
const data=name=>`data:image/png;base64,${fs.readFileSync(path.join(root,'inputs',name)).toString('base64')}`;
const bg=data('paper-background.png'),logo=data('wordmark.png'),android=data('android-fold-reading.png'),ipad=data('ipad-reading.png'),content=data('reader-content-reference.png');
const ink='#243D2C',secondary='#586E57';
function document(w,h,body){return `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}"><defs><filter id="shadow" x="-30%" y="-20%" width="160%" height="160%"><feDropShadow dx="0" dy="16" stdDeviation="18" flood-color="#40563C" flood-opacity="0.14"/></filter><linearGradient id="fade" x1="0" y1="0" x2="0" y2="1"><stop offset="0.84" stop-color="white"/><stop offset="1" stop-color="black"/></linearGradient><mask id="excerptFade" maskContentUnits="objectBoundingBox"><rect width="1" height="1" fill="url(#fade)"/></mask><clipPath id="book"><rect x="0" y="0" width="1768" height="2208" rx="25"/></clipPath></defs><rect width="100%" height="100%" fill="#DBE6D1"/><image x="0" y="0" width="${w}" height="${h}" preserveAspectRatio="xMidYMid slice" opacity="0.62" xlink:href="${bg}"/><g font-family="Apple SD Gothic Neo, Noto Sans CJK KR, sans-serif" fill="${ink}">${body}</g></svg>`;}
function banner(){return document(1024,500,`
<image x="397" y="8" width="230" height="76.67" xlink:href="${logo}"/>
<text x="512" y="138" text-anchor="middle" font-size="66" font-weight="800" letter-spacing="-2.4">펼치면, 책처럼.</text>
<text x="512" y="177" text-anchor="middle" font-size="19" font-weight="500" fill="${secondary}">넓은 화면에 펼쳐지는 두 페이지 독서</text>
<rect x="162" y="205" width="700" height="254" rx="13" fill="#F9F8F4" filter="url(#shadow)"/>
<svg x="162" y="205" width="700" height="254" viewBox="280 300 2320 841.83" overflow="hidden" mask="url(#excerptFade)"><image width="2853" height="2007" xlink:href="${content}"/></svg>
<rect x="162" y="205" width="700" height="254" rx="13" fill="none" stroke="#AFC0A9" stroke-width="1"/>
<text x="512" y="485" text-anchor="middle" font-size="13" font-weight="600" letter-spacing="1.2" fill="${secondary}">TXT · EPUB · TTS</text>`);}
function portrait(){return document(1080,1920,`
<image x="83" y="55" width="292" height="97.33" xlink:href="${logo}"/>
<text x="96" y="294" font-size="119" font-weight="800" letter-spacing="-4">펼치면,</text>
<text x="96" y="430" font-size="119" font-weight="800" letter-spacing="-4">책처럼.</text>
<text x="100" y="509" font-size="34" font-weight="500" fill="${secondary}">넓은 화면에서도 편안하게.</text>
<rect x="106" y="621" width="868" height="1084" rx="18" fill="#F9F8F4" filter="url(#shadow)"/>
<image x="108" y="623" width="864" height="1079.02" preserveAspectRatio="xMidYMid meet" xlink:href="${android}"/>
<rect x="106" y="621" width="868" height="1084" rx="18" fill="none" stroke="#B0C1AA" stroke-width="2"/>
<text x="98" y="1814" font-size="27" font-weight="600" fill="${secondary}">휴대전화 · 폴더블 · 태블릿</text>
<text x="982" y="1814" text-anchor="end" font-size="25" font-weight="600" fill="${secondary}">TXT · EPUB · TTS</text>`);}
function applePortrait(){return document(1320,2868,`
<image x="129" y="88" width="358" height="119.33" xlink:href="${logo}"/>
<text x="144" y="399" font-size="154" font-weight="800" letter-spacing="-5">펼치면,</text>
<text x="144" y="574" font-size="154" font-weight="800" letter-spacing="-5">책처럼.</text>
<text x="148" y="690" font-size="43" font-weight="500" fill="${secondary}">넓은 화면에서도 편안하게.</text>
<rect x="118" y="930" width="1084" height="1444" rx="23" fill="#F9F8F4" filter="url(#shadow)"/>
<image x="120" y="932" width="1080" height="1440" preserveAspectRatio="xMidYMid meet" xlink:href="${ipad}"/>
<rect x="118" y="930" width="1084" height="1444" rx="23" fill="none" stroke="#B0C1AA" stroke-width="2"/>
<text x="146" y="2656" font-size="34" font-weight="600" fill="${secondary}">휴대전화 · 폴더블 · 태블릿</text>
<text x="1174" y="2656" text-anchor="end" font-size="31" font-weight="600" fill="${secondary}">TXT · EPUB · TTS</text>`);}
function appleWide(){return document(2853,2007,`
<image x="179" y="102" width="442" height="147.33" xlink:href="${logo}"/>
<text x="196" y="673" font-size="206" font-weight="800" letter-spacing="-7">펼치면,</text>
<text x="196" y="912" font-size="206" font-weight="800" letter-spacing="-7">책처럼.</text>
<text x="204" y="1051" font-size="52" font-weight="500" fill="${secondary}">넓은 화면에서도 편안하게.</text>
<text x="204" y="1736" font-size="38" font-weight="600" fill="${secondary}">휴대전화 · 폴더블 · 태블릿</text>
<text x="204" y="1812" font-size="34" font-weight="600" fill="${secondary}">TXT · EPUB · TTS</text>
<rect x="1429" y="255" width="1182" height="1574.67" rx="28" fill="#F9F8F4" filter="url(#shadow)"/>
<image x="1431" y="257" width="1178" height="1570.67" preserveAspectRatio="xMidYMid meet" xlink:href="${ipad}"/>
<rect x="1429" y="255" width="1182" height="1574.67" rx="28" fill="none" stroke="#B0C1AA" stroke-width="2"/>`);}
for(const [name,svg,width] of [['01-google-feature-1024x500',banner(),1024],['02-play-intro-1080x1920',portrait(),540],['03-apple-intro-1320x2868',applePortrait(),540],['04-apple-wide-2853x2007',appleWide(),1100]]){
 fs.writeFileSync(path.join(root,'sources',`${name}.svg`),svg);
 await sharp(Buffer.from(svg)).flatten({background:'#DBE6D1'}).removeAlpha().png().toFile(path.join(root,`${name}.png`));
 await sharp(path.join(root,`${name}.png`)).resize({width}).png().toFile(path.join(root,'previews',`${name}.png`));
}
// Crop checks simulate narrower cards; these are review files, not upload assets.
const feature=path.join(root,'01-google-feature-1024x500.png');
for(const [name,width] of [['16x9',889],['4x3',667]])await sharp(feature).extract({left:Math.floor((1024-width)/2),top:0,width,height:500}).resize(416).png().toFile(path.join(root,'previews',`crop-${name}.png`));
const outputs=[];for(const file of fs.readdirSync(root).filter(name=>name.endsWith('.png'))){const info=await sharp(path.join(root,file)).metadata();outputs.push({file,width:info.width,height:info.height,hasAlpha:info.hasAlpha});}fs.writeFileSync(path.join(root,'manifest.json'),JSON.stringify(outputs,null,2)+'\n');console.log(JSON.stringify(outputs));
