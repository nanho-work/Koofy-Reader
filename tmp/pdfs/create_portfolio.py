from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor, Color
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from PIL import Image
import json
from io import BytesIO
ROOT=Path('/Users/choenamho/Documents/GitHub')
R=ROOT/'Koofy-Reader'
OUT=R/'output/pdf/최남호_AI활용_서비스개발_포트폴리오.pdf'
pdfmetrics.registerFont(TTFont('KR',str(R/'assets/fonts/NanumGothic-Regular.ttf')))
pdfmetrics.registerFont(TTFont('Serif',str(R/'assets/fonts/NanumMyeongjo-Regular.ttf')))
W,H=595.28,841.89
ink='#24342F';muted='#66746F';accent='#39775F';paper='#FAFAF6';line='#D8E0DB'
c=canvas.Canvas(str(OUT),pagesize=(W,H),pageCompression=1)
c.setTitle('최남호 | AI 활용 서비스 개발 포트폴리오'); c.setAuthor('최남호')
texts=[]
def txt(t,x,y,size=11,color=ink,font='KR'):
 c.setFillColor(HexColor(color));c.setFont(font,size);c.drawString(x,H-y-size,t);texts.append(t)
def para(t,x,y,w,size=11,color=ink,leading=None):
 st=ParagraphStyle('p',fontName='KR',fontSize=size,leading=leading or size*1.65,textColor=HexColor(color),wordWrap='CJK')
 p=Paragraph(t,st);a,b=p.wrap(w,H);p.drawOn(c,x,H-y-b);texts.append(t);return b

def box(x,y,w,h,fill='#EFF3EF',stroke=None,r=12):
 c.setFillColor(HexColor(fill));c.setStrokeColor(HexColor(stroke or fill));c.roundRect(x,H-y-h,w,h,r,fill=1,stroke=bool(stroke))
def img(p,x,y,w,h):
 im=Image.open(p).convert('RGB'); iw,ih=im.size;s=min(w/iw,h/ih);dw,dh=iw*s,ih*s
 im.thumbnail((int(dw*3),int(dh*3))); buf=BytesIO(); im.save(buf,format="JPEG",quality=91); buf.seek(0)
 c.drawImage(ImageReader(buf),x+(w-dw)/2,H-y-dh,width=dw,height=dh)
 return dh

def link(label,url,x,y):
 txt(label,x,y,9,accent);ww=pdfmetrics.stringWidth(label,'KR',9);c.linkURL(url,(x,H-y-14,x+ww,H-y+2),relative=0,thickness=0)
def head(n,kicker,title,sub):
 c.setFillColor(HexColor(paper));c.rect(0,0,W,H,fill=1,stroke=0)
 txt('CHOI NAMHO  /  PORTFOLIO',40,24,8,muted)
 txt(kicker,40,66,10,accent);txt(title,40,91,25)
 para(sub,40,132,515,10.5,muted)
 c.setStrokeColor(HexColor(line));c.line(40,45,W-40,45)
 txt('최남호  ·  koofylab@gmail.com',40,805,8,muted);txt(f'{n:02d} / 07',510,805,8,muted)
def done():c.showPage()
raw=R/'work/store-refresh-20261021/raw/ko'
monthly=R/'work/monthly-store-20261025/raw/ko/iphone-monthly.png'
imgr=ROOT/'Koofy-Image/store/ios/ko/captures'
# 1
head(1,'AI 활용 웹·앱 개발 / 기획·출시·운영','만들고, 출시하고, 계속 고칩니다.','아이디어를 실제로 사용할 수 있는 서비스로 만드는 최남호입니다.')
txt('최남호',40,170,18,accent)
para('필요한 기능을 정리하고 화면과 데이터 구조를 잡습니다.<br/>AI와 함께 구현한 뒤에는 직접 써 보고, 불편한 부분을 다시 고칩니다.<br/>앱을 올리는 데서 끝내지 않고 운영과 업데이트까지 이어가고 있습니다.',40,206,505,11)
for x,num,lab in [(40,'5개','iOS·Android 출시 앱'),(215,'2곳','웹 외주 프로젝트 운영'),(390,'웹 + 앱','자체 서비스 직접 운영')]:
 box(x,284,165,83);txt(num,x+15,298,23,accent);txt(lab,x+15,338,9.5)
img(monthly,60,396,139,302);img(raw/'iphone-reading.png',229,396,139,302);img(imgr/'04-converted.png',398,396,139,302)
txt('쿠피리더 · 월간 콘텐츠',61,710,9,muted);txt('쿠피리더 · 독서 화면',229,710,9,muted);txt('쿠피 이미지 · 변환 결과',398,710,9,muted)
link('서비스 홈페이지  www.koofy.co.kr','https://www.koofy.co.kr/',40,754)
link('이메일  koofylab@gmail.com','mailto:koofylab@gmail.com',325,754)
done()
# 2
head(2,'출시한 서비스','앱 5개를 만들고 운영하고 있습니다.','게임부터 실용 도구까지, 직접 기획한 서비스를 양대 앱 마켓에 출시했습니다.')
apps=[('01','쿠피리더','TXT·EPUB 독서 도구','글꼴·읽기 설정, TTS, 다국어와 월간 콘텐츠를 연결한 리더.', 'com.koofylab.koofyreader'),('02','쿠피 이미지','이미지 형식 변환·용량 줄이기','사진을 기기 안에서 처리하고, 결과 확인부터 저장까지 간단하게.', 'com.koofylab.koofyimage'),('03','쿠피 스도쿠','스도쿠 퍼즐 게임','일상에서 가볍게 즐기는 숫자 퍼즐 앱.', 'com.koofy.sudoku'),('04','BusPop · 버스퍼즐','버스 퍼즐 게임','퍼즐의 규칙과 조작 흐름을 모바일 게임으로 구현.', 'com.koofylab.buspop'),('05','Zivon · 지본','커뮤니티 앱','사람과 정보를 연결하는 커뮤니티 서비스를 제작·운영.', 'com.zivon.app')]
for i,(num,name,tag,desc,pkg) in enumerate(apps):
 y=188+i*105;box(40,y,515,92,'#FFFFFF',line);txt(num,55,y+15,11,accent);txt(name,90,y+12,16);txt(tag,90,y+36,9,muted);para(desc,90,y+54,360,9.5)
 link('Google Play',f'https://play.google.com/store/apps/details?id={pkg}',471,y+17)
para('대표 사례는 다음 페이지에 담았습니다. 앱 전체 목록과 관련 서비스는 쿠피 홈페이지에서도 확인할 수 있습니다.',40,730,515,10,muted)
link('쿠피 서비스 보러 가기','https://www.koofy.co.kr/',40,770)
done()
# 3
head(3,'대표 사례 01 / 쿠피리더','읽는 사람의 불편에서 시작합니다.','담당: 서비스 기획, UI·UX 방향, AI 활용 개발, 실기기 검증, 스토어 출시·운영')
for x,name,label in [(48,'iphone-library.png','서재와 이어 읽기'),(223,'iphone-settings.png','독서 설정'),(398,'iphone-reading.png','본문 읽기')]:
 img(raw/name,x,188,149,322);txt(label,x,521,10,accent)
items=[('설정이 복잡하고 일관성이 없었습니다.','설정을 오른쪽 슬라이드 패널과 펼침 메뉴로 정리하고, 공통 테마와 버튼 표현을 맞췄습니다.'),('화면과 언어에 따라 경험이 달라졌습니다.','휴대폰·태블릿·폴더블을 고려하고, 한국어·영어·일본어의 문구와 기본 콘텐츠를 연결했습니다.'),('배포 후에도 계속 확인합니다.','책갈피, 목차 대비, 표지 표시와 같은 세부 문제를 실기기로 확인하며 수정했습니다.')]
y=559
for title,desc in items:
 txt(title,40,y,11.5);para(desc,40,y+23,515,10,muted);y+=70
link('App Store','https://apps.apple.com/app/id6814514729',40,777);link('Google Play','https://play.google.com/store/apps/details?id=com.koofylab.koofyreader',121,777)
done()
# 4
head(4,'대표 사례 02 / 월간 쿠피','콘텐츠 운영도 서비스의 일부입니다.','매번 앱을 업데이트하지 않아도, 관리자가 등록한 글이 공개 일정에 맞춰 전달되도록 구성했습니다.')
img(monthly,40,193,215,467)
steps=[('01  관리자 등록','회차 제목·본문·이미지, 언어와 공개일 설정'),('02  공개 일정 처리','공개일 기준으로 노출할 콘텐츠 구분'),('03  앱에서 읽기','월별 묶음, 새 글 배지, 접힘 상태 기억'),('04  월간 합본','월내 공개된 회차와 이미지를 EPUB으로 구성')]
for i,(t,d) in enumerate(steps):
 y=197+i*109;box(283,y,272,88);txt(t,298,y+13,12,accent);para(d,298,y+38,240,10)
 if i<3:txt('↓',412,y+89,13,accent)
box(40,690,515,83,'#E8EFE9')
txt('제가 신경 쓴 부분',55,704,12,accent)
para('한 번 보이는 화면뿐 아니라 등록, 예약 공개, 언어별 노출, 합본까지 운영 순서를 정리했습니다. 반복 작업을 줄이는 기능을 실제 앱과 관리자에 함께 반영했습니다.',55,728,485,10)
done()
# 5
head(5,'대표 사례 03 / 쿠피 이미지','작은 기능도 사용 흐름은 꼼꼼하게.','담당: 제품 기획, 화면·저장 정책 설계, AI 활용 개발, iOS·Android 출시')
img(imgr/'03-convert-options.png',43,192,155,337);img(imgr/'04-converted.png',220,192,155,337);img(imgr/'09-saved.png',397,192,155,337)
for x,s in [(43,'1. 형식과 옵션 선택'),(220,'2. 변환 결과 확인'),(397,'3. 필요한 사진 저장')]:txt(s,x,541,10,accent)
para('“사진 형식 때문에 전달이 안 되거나, 용량이 커서 올리기 불편하다.”<br/>이 문제에 집중해 형식 변환과 용량 줄이기를 간단하게 만들었습니다.',40,581,515,12)
for y,t,d in [(651,'원본을 지키는 처리','한 번에 최대 10장, 기기 내부 처리, 원본 보존.'),(699,'결과를 확인한 뒤 저장','사진별 성공·실패와 저장 상태를 구분하고, 개별 저장과 전체 저장을 제공합니다.')]:
 txt(t,40,y,11.5);para(d,40,y+22,515,10,muted)
link('Google Play','https://play.google.com/store/apps/details?id=com.koofylab.koofyimage',40,771)
done()
# 6
head(6,'외주 프로젝트 / 제작·운영','업종에 맞는 웹사이트를 운영합니다.','방문자가 필요한 정보를 찾고, 상담이나 방문으로 이어질 수 있도록 화면과 동선을 구성합니다.')
img('/private/tmp/koofy-portfolio/tax.png',40,188,260,147)
txt('디 케빈즈 택스랩',322,188,16);para('세무 서비스 소개부터 상담 예약까지 연결하는 홈페이지입니다. 서비스·소개·블로그·FAQ 등 정보 구조를 구성하고 운영하고 있습니다.',322,225,232,10.5)
link('thekevinstaxlab.com','https://www.thekevinstaxlab.com/',322,321)
img('/private/tmp/koofy-portfolio/dining.png',40,386,260,147)
txt('용스다이닝',322,386,16);para('매장의 분위기와 메뉴를 보여주고 예약·길찾기로 이어지는 웹사이트입니다. 실제 운영 중인 매장의 정보와 화면을 관리합니다.',322,423,232,10.5)
link('yongs-dining.com','https://www.yongs-dining.com/',322,519)
box(40,584,515,166)
txt('자체 서비스 사이트 · 쿠피',56,600,15,accent)
para('앱 소개, 이미지 도구, 제품 가이드, 지원·정책 페이지를 함께 운영합니다. 한국어·영어·일본어 경로와 검색에 필요한 메타데이터를 정리하고, 앱과 웹의 연결도 관리합니다.',56,636,483,11)
link('www.koofy.co.kr','https://www.koofy.co.kr/',56,718)
txt('웹 화면: 2026.10.28 공개 사이트 캡처',40,770,8,muted)
done()
# 7
head(7,'일하는 방식','AI는 활용하고, 판단과 확인은 직접.','기능을 빠르게 만드는 것과, 계속 고칠 수 있게 만드는 것을 함께 생각합니다.')
for i,(t,d) in enumerate([
 ('먼저 필요한 것을 정리합니다.','누가 쓰는지, 어떤 불편을 해결할지, 지금 꼭 필요한 기능이 무엇인지부터 정합니다.'),
 ('나중에 수정할 수 있게 나눕니다.','페이지, 공통 UI, 재사용 기능과 데이터 처리를 나누고 공통 규칙을 문서로 남깁니다.'),
 ('AI와 구현하고 직접 확인합니다.','AI에 작업 범위와 기준을 구체적으로 전달합니다. 결과는 실제 화면·기기·테스트로 확인하며 수정합니다.'),
 ('출시 이후의 일도 맡습니다.','스토어 등록, 다국어 설명과 이미지, 개인정보 안내, 분석 설정과 사용자 피드백까지 챙깁니다.')]):
 y=192+i*100;txt(f'0{i+1}',40,y,14,accent);txt(t,80,y,14);para(d,80,y+28,475,11,muted)
box(40,611,515,100)
txt('업무에 사용하는 기술과 도구',56,625,12,accent)
para('React · Next.js · Flutter · SQL / 관계형 DB · AWS · Firebase · Git<br/>AI 코딩 도구를 활용한 구현, 구조 정리, 검증과 문서화',56,655,480,10.5)
para('필요한 기능을 함께 정하고, 실제로 쓰이는 서비스까지 이어가는 일을 하고 싶습니다.',40,735,515,12)
link('koofylab@gmail.com','mailto:koofylab@gmail.com',40,775);link('www.koofy.co.kr','https://www.koofy.co.kr/',400,775)
done();c.save()
(R/'output/pdf/포트폴리오_수정용_원문.txt').write_text('\n\n'.join(texts),encoding='utf-8')
print(OUT)
