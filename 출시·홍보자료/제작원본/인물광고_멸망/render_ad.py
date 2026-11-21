from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import subprocess

root=Path('/Users/choenamho/Documents/GitHub/Koofy-Reader')
out=root/'출시·홍보자료/제작원본/인물광고_멸망'
a=out/'assets'
font=root/'assets/fonts/NanumGothic-Regular.ttf'
W,H=1080,1920
cream='#F8F7F1'
green='#355B46'
def text(im, words, y, size, fill=green):
 d=ImageDraw.Draw(im)
 f=ImageFont.truetype(str(font),size)
 for line in words.split('\n'):
  box=d.textbbox((0,0),line,font=f)
  d.text(((W-(box[2]-box[0]))/2,y),line,font=f,fill=fill)
  y+=int(size*1.5)
def put(im,p,width,x,y):
 asset=Image.open(p).convert('RGBA')
 asset=asset.resize((width,round(asset.height*width/asset.width)),Image.Resampling.LANCZOS)
 im.paste(asset,(x,y),asset)

bg=Image.new('RGB',(W,H),cream)
put(bg,root/'assets/images/promotions/koofy_reader_wordmark.png',620,230,200)
text(bg,'멸망한 세상의 관리인',460,48)
text(bg,'1화 · 프롤로그',540,30,'#68776D')
bg.save(a/'앱_배경.png')
end=Image.new('RGB',(W,H),cream)
put(end,root/'assets/branding/app_icon.png',220,430,390)
put(end,root/'assets/images/promotions/koofy_reader_wordmark.png',680,200,680)
text(end,'지금 다운로드하세요',990,54)
put(end,a/'app-store-ko.png',420,90,1160)
# Google badge has official built-in clear space. Keep its original aspect ratio.
put(end,a/'google-play-ko.png',480,530,1132)
text(end,'프로필 링크에서 다운로드',1430,38)
end.save(a/'다운로드_안내.png')

def run(args):
 subprocess.run(['ffmpeg','-y','-v','error',*map(str,args)],check=True)
common=['-an','-c:v','libx264','-preset','fast','-crf','19','-pix_fmt','yuv420p','-r','30']
ff=str(font)
for file,duration,caption,target in [('인물_시작.png',4,'잠깐, 뭐 읽을 거 없나?','01.mp4'),('인물_독서.png',6,'무료 소설도, 내 파일도.','03.mp4')]:
 frames=duration*30
 filt=f"scale=2160:3840:force_original_aspect_ratio=increase,crop=2160:3840,zoompan=z='1+0.0005*on':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d={frames}:s=1080x1920:fps=30,drawtext=fontfile='{ff}':text='{caption}':fontsize=48:fontcolor=white:box=1:boxcolor=black@0.48:boxborderw=22:x=(w-tw)/2:y=1540,fade=t=in:st=0:d=0.25,fade=t=out:st={duration-.25}:d=0.25"
 run(['-i',a/file,'-vf',filt,'-t',duration,*common,a/target])
source=root/'출시·홍보자료/제작원본/폴드8_촬영시안/멸망_다운로드와독서_확인용.mp4'
filt=f"[0:v]setpts=PTS/1.23833335,scale=1020:-2[app];[1:v][app]overlay=30:660:shortest=1,drawtext=fontfile='{ff}':text='골라서 다운로드하고':fontsize=46:fontcolor={green}:x=(w-tw)/2:y=1510:enable='lt(t,9)',drawtext=fontfile='{ff}':text='삽화와 함께 읽어요':fontsize=46:fontcolor={green}:x=(w-tw)/2:y=1510:enable='gte(t,9)',fade=t=in:st=0:d=0.25,fade=t=out:st=19.75:d=0.25[out]"
run(['-i',source,'-loop','1','-i',a/'앱_배경.png','-filter_complex',filt,'-map','[out]','-t','20',*common,a/'02.mp4'])
run(['-loop','1','-i',a/'다운로드_안내.png','-vf','fade=t=in:st=0:d=0.3,fade=t=out:st=5.6:d=0.4','-t','6',*common,a/'04.mp4'])
(a/'concat.txt').write_text('\n'.join(f"file '{a / name}'" for name in ['01.mp4','02.mp4','03.mp4','04.mp4']))
run(['-f','concat','-safe','0','-i',a/'concat.txt','-c','copy',a/'映像.mp4'])
# Voice is off-screen narration, placed at each scene's start.
run(['-i',a/'映像.mp4','-i',a/'voice1.aiff','-i',a/'voice2.aiff','-i',a/'voice3.aiff','-i',a/'voice4.aiff','-filter_complex','[1:a]adelay=500:all=1[a1];[2:a]adelay=4400:all=1[a2];[3:a]adelay=24200:all=1[a3];[4:a]adelay=30400:all=1[a4];[a1][a2][a3][a4]amix=inputs=4:duration=longest:normalize=0,apad,alimiter=limit=0.95[a]','-map','0:v','-map','[a]','-c:v','copy','-c:a','aac','-b:a','192k','-t','36','-movflags','+faststart',out/'쿠피리더_멸망_인물광고_초안.mp4'])
print(out/'쿠피리더_멸망_인물광고_초안.mp4')
