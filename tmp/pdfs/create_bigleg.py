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
OUT=R/'output/pdf/최남호_빅레그지원_포트폴리오.pdf'
pdfmetrics.registerFont(TTFont('KR',str(R/'assets/fonts/NanumGothic-Regular.ttf')))
pdfmetrics.registerFont(TTFont('Serif',str(R/'assets/fonts/NanumMyeongjo-Regular.ttf')))
W,H=595.28,841.89
ink='#24342F';muted='#66746F';accent='#39775F';paper='#FAFAF6';line='#D8E0DB'
c=canvas.Canvas(str(OUT),pagesize=(W,H),pageCompression=1)
c.setTitle('최남호 | 빅레그 지원 포트폴리오'); c.setAuthor('최남호')
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
head(1,'빅레그 지원 / AI 활용 개발·업무 시스템 운영','필요한 기능을 만들고, 계속 고칩니다.','업무 흐름을 이해하고, 실제로 사용하는 시스템으로 연결하는 최남호입니다.')
txt('최남호',40,188,24,accent)
para('저는 필요한 기능이나 불편한 점이 있으면 직접 만들어보는 편입니다.<br/>지금도 실제 업체가 사용하는 업무관리 시스템을 개발·운영하고 있고,<br/>직접 만든 앱 5개를 양대 앱 마켓에 출시해 운영하고 있습니다.',40,238,515,12)
for y,title,desc in [(345,'내부 업무 시스템 · 현재 개발·운영 중','세무사무소의 거래처·권한·문서·협업 기능을 연결하고, 운영 중 필요한 기능을 추가하거나 개선합니다.'),(458,'서비스 출시 · 앱 5개와 자체 웹사이트','구현 이후 심사·배포·분석·다국어·사용자 피드백까지 직접 다룹니다.'),(571,'AI 활용 · 구조 설계와 검증을 함께','요구사항과 작업 범위를 먼저 정하고 AI와 구현합니다. 직접 써 보고 수정하며, 다음 작업을 위한 구조와 기록을 남깁니다.')]:
 box(40,y,515,94);txt(title,56,y+15,13,accent);para(desc,56,y+43,483,11)
para('빅레그에서도 기존 업무와 프로그램부터 이해하고, 반복되는 불편을 줄이는 기능을 만들어 운영까지 이어가고 싶습니다.',40,704,515,11)
link('koofylab@gmail.com','mailto:koofylab@gmail.com',40,775);link('www.koofy.co.kr','https://www.koofy.co.kr/',400,775)
done()
# 2
head(2,'대표 프로젝트 / 현재 개발·운영 중','세무사무소 내부 업무관리 시스템','디케빈즈택스랩 · 실제 업무에 사용하는 시스템을 지속적으로 개발하고 있습니다.')
para('외부 홈페이지와 별도로, 사무소 안에서 사용하는 업무관리 시스템을 만들고 있습니다. 누가 어떤 정보를 보고 처리해야 하는지 정리하고, 화면과 API, 데이터베이스와 파일 저장소를 연결했습니다.',40,188,515,12)
items=[('거래처와 사용자','거래처 정보 관리, 직원·고객·회사별 계정과 접근 권한'),('내부 협업','업무 공지와 지시, 채팅, 일정·근태·연차 관리'),('문서와 파일','폴더·파일 관리, 업로드·다운로드, 이동과 휴지통·복구'),('메일과 반복 처리','메일 연동과 동기화·발송 큐, 예약 실행 및 운영 점검')]
for i,(t,d) in enumerate(items):
 y=293+i*89;box(40,y,515,74,'#FFFFFF',line);txt(t,56,y+12,13,accent);para(d,56,y+38,483,10.5)
para('제 역할은 요구사항 정리와 구조 기획, AI를 활용한 구현, 수정·검증과 운영입니다. 완성 후 넘기는 작업이 아니라, 실제 사용 과정에서 생기는 요구를 반영하며 계속 개선하고 있습니다.',40,672,515,11)
para('운영 업체의 정보 보호를 위해 실제 시스템 화면과 업무 데이터는 공개하지 않습니다.',40,764,515,9,muted)
done()
# 3
head(3,'내부 업무관리 시스템 / 구조와 유지보수','화면 뒤의 흐름까지 연결합니다.','프로젝트의 핵심 구성만 정리한 구조도입니다. 운영 주소와 내부 데이터는 포함하지 않았습니다.')
box(40,193,515,75);txt('사용자 화면  |  React · Next.js',57,206,14,accent);para('직원·고객·회사별 업무 화면과 관리자 기능',57,236,480,11)
txt('↓  API 요청',246,280,10,muted)
box(40,312,515,88);txt('업무 처리  |  Python · FastAPI',57,326,14,accent);para('사용자 인증·권한 확인, 업무 로직, 문서·메일 처리<br/>라우터와 서비스 로직을 나누어 관리',57,352,480,10.5)
txt('↓',162,411,14,accent);txt('↓',425,411,14,accent)
box(40,446,248,85);txt('MySQL · SQLAlchemy',55,461,13,accent);para('사용자·거래처·업무 데이터 관리',55,491,218,10)
box(307,446,248,85);txt('AWS S3',322,461,13,accent);para('문서·첨부파일 저장과 접근 제어',322,491,218,10)
txt('운영하면서 중요하게 보는 부분',40,568,15)
for y,t,d in [(605,'권한과 데이터 범위','화면에서 숨기는 것뿐 아니라 서버에서 접근 범위를 확인하는 구조를 둡니다.'),(666,'변경과 유지보수','공통 로직을 분리하고 SQL 변경·점검 스크립트와 작업 내용을 남깁니다.'),(727,'기존 흐름과의 연결','새 기능이 기존 화면과 데이터 처리에 미치는 영향을 함께 확인하며 수정합니다.')]:
 txt(t,40,y,11,accent);para(d,40,y+22,515,10.5)
done()
head(4,'자체 서비스 / 쿠피리더·월간 쿠피','콘텐츠 운영도 서비스의 일부입니다.','매번 앱을 업데이트하지 않아도, 관리자가 등록한 글이 공개 일정에 맞춰 전달되도록 구성했습니다.')
img(monthly,40,193,215,467)
steps=[('01  관리자 등록','회차 제목·본문·이미지, 언어와 공개일 설정'),('02  공개 일정 처리','공개일 기준으로 노출할 콘텐츠 구분'),('03  앱에서 읽기','월별 묶음, 새 글 배지, 접힘 상태 기억'),('04  월간 합본','월내 공개된 회차와 이미지를 EPUB으로 구성')]
for i,(t,d) in enumerate(steps):
 y=197+i*109;box(283,y,272,88);txt(t,298,y+13,12,accent);para(d,298,y+38,240,10)
 if i<3:txt('↓',412,y+89,13,accent)
box(40,690,515,83,'#E8EFE9')
txt('제가 신경 쓴 부분',55,704,12,accent)
para('한 번 보이는 화면뿐 아니라 등록, 예약 공개, 언어별 노출, 합본까지 운영 순서를 정리했습니다. 반복 작업을 줄이는 기능을 실제 앱과 관리자에 함께 반영했습니다.',55,728,485,10)
done()
head(5,'출시한 서비스','앱 5개를 만들고 운영하고 있습니다.','게임부터 실용 도구까지, 직접 기획한 서비스를 양대 앱 마켓에 출시했습니다.')
apps=[('01','쿠피리더','TXT·EPUB 독서 도구','글꼴·읽기 설정, TTS, 다국어와 월간 콘텐츠를 연결한 리더.', 'com.koofylab.koofyreader'),('02','쿠피 이미지','이미지 형식 변환·용량 줄이기','사진을 기기 안에서 처리하고, 결과 확인부터 저장까지 간단하게.', 'com.koofylab.koofyimage'),('03','쿠피 스도쿠','스도쿠 퍼즐 게임','일상에서 가볍게 즐기는 숫자 퍼즐 앱.', 'com.koofy.sudoku'),('04','BusPop · 버스퍼즐','버스 퍼즐 게임','퍼즐의 규칙과 조작 흐름을 모바일 게임으로 구현.', 'com.koofylab.buspop'),('05','Zivon · 지본','커뮤니티 앱','사람과 정보를 연결하는 커뮤니티 서비스를 제작·운영.', 'com.zivon.app')]
for i,(num,name,tag,desc,pkg) in enumerate(apps):
 y=188+i*105;box(40,y,515,92,'#FFFFFF',line);txt(num,55,y+15,11,accent);txt(name,90,y+12,16);txt(tag,90,y+36,9,muted);para(desc,90,y+54,360,9.5)
 link('Google Play',f'https://play.google.com/store/apps/details?id={pkg}',471,y+17)
para('앱 전체 목록과 관련 서비스는 쿠피 홈페이지에서도 확인할 수 있습니다.',40,730,515,10,muted)
link('쿠피 서비스 보러 가기','https://www.koofy.co.kr/',40,770)
done()
# 6
head(6,'웹 프로젝트 / 제작·운영','서비스 소개부터 사용과 지원까지.','업종과 서비스 목적에 맞춰 페이지를 구성하고, 운영 중 필요한 내용을 개선합니다.')
for y,t,d,url,label in [(190,'디케빈즈택스랩 · 기업 홈페이지','내부 업무관리 시스템과 별도로 세무사무소 홈페이지를 제작·운영합니다. 서비스 소개, 블로그, FAQ와 상담 연결 동선을 구성했습니다.','https://www.thekevinstaxlab.com/','thekevinstaxlab.com'),(366,'용스다이닝 · 매장 홈페이지','메뉴와 매장 분위기를 보여주고, 예약과 길찾기로 이어지는 웹사이트를 제작·운영하고 있습니다.','https://www.yongs-dining.com/','yongs-dining.com'),(542,'쿠피 · 자체 서비스 사이트','앱 소개와 이미지 도구, 제품 가이드, 지원·정책 페이지를 운영합니다. 한국어·영어·일본어 경로와 메타데이터를 정리하고 앱과 웹을 연결합니다.','https://www.koofy.co.kr/','www.koofy.co.kr')]:
 box(40,y,515,151,'#FFFFFF',line);txt(t,56,y+17,15,accent);para(d,56,y+50,480,11);link(label,url,56,y+122)
para('현재 진행 중인 외주 프로젝트는 화면 대신 공개 링크와 담당 범위로 소개합니다.',40,741,515,10,muted)
done()
# 7
head(7,'빅레그에서의 업무 접근','빠르게 구현하고, 실제 업무로 확인합니다.','AI를 활용하되, 무엇을 만들고 어떻게 검증할지는 직접 판단합니다.')
for i,(t,d) in enumerate([('먼저 업무를 이해하겠습니다.','현재 사용하는 프로그램과 자료 흐름, 반복 입력과 확인 작업부터 파악하겠습니다.'),('작은 범위부터 연결하겠습니다.','자주 발생하는 불편부터 우선순위를 정하고, 기존 데이터와 처리 흐름에 맞춰 구현하겠습니다.'),('사용하는 사람과 확인하겠습니다.','성공하는 경우뿐 아니라 누락·중복·실패 상황도 살펴보고, 사용 의견을 받아 수정하겠습니다.'),('이후에도 고칠 수 있게 남기겠습니다.','페이지와 공통 기능을 분리하고 변경 내용과 사용 방법을 정리해 유지보수에 활용하겠습니다.')]):
 y=192+i*101;txt(f'0{i+1}',40,y,14,accent);txt(t,80,y,14);para(d,80,y+29,475,11,muted)
box(40,615,515,105);txt('활용 기술과 작업 도구',56,630,12,accent)
para('React · Next.js · Flutter · Python / FastAPI<br/>SQL · MySQL · AWS S3 · Firebase · Git<br/>AI 코딩 도구를 활용한 구현, 검증과 문서화',56,657,480,10.5)
para('실제로 쓰이는 기능을 만들고, 운영하면서 계속 개선하는 개발자로 일하고 싶습니다.',40,744,515,11)
link('koofylab@gmail.com','mailto:koofylab@gmail.com',40,779);link('www.koofy.co.kr','https://www.koofy.co.kr/',400,779)
done();c.save()
(R/'output/pdf/빅레그지원_포트폴리오_수정용.txt').write_text('\n\n'.join(texts),encoding='utf-8')
print(OUT)
