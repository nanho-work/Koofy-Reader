"""Render the guide's typographic cover with the existing vector brand mark.

Run on macOS with Pillow; no font files are copied into the app.
"""
from pathlib import Path
import re
import argparse
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--language', choices=['ko', 'en', 'ja'], default='ko')
lang = parser.parse_args().language
labels = {
    'ko': ('쿠피리더', '시작하기', '책 가져오기부터', '나만의 독서 설정까지', '사용자 가이드'),
    'en': ('Getting', 'started', 'From adding books', 'to reading your way', 'USER GUIDE'),
    'ja': ('はじめての', '使い方', '本の追加から', '自分好みの読書設定まで', 'ユーザーガイド'),
}[lang]
SCALE = 2
image = Image.new('RGB', (1024 * SCALE, 1536 * SCALE), '#284B3B')
draw = ImageDraw.Draw(image)
cream, muted, line = '#F7F1DF', '#BDCFBA', '#698771'


def text(x, y, label, size, bold=False, fill=cream):
    font_path = '/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc' if lang == 'ja' else '/System/Library/Fonts/AppleSDGothicNeo.ttc'
    font = ImageFont.truetype(font_path, size * SCALE, index=0 if lang == 'ja' else (6 if bold else 0))
    draw.text((x * SCALE, y * SCALE), label, font=font, fill=fill, anchor='lt')


def rule(x1, y1, x2, y2, fill=line, width=2):
    draw.line(tuple(v * SCALE for v in (x1, y1, x2, y2)),
              fill=fill, width=width * SCALE)


draw.rectangle((32 * SCALE, 32 * SCALE, 992 * SCALE, 1504 * SCALE),
               outline=line, width=2 * SCALE)
text(100, 111, 'KOOFY READER', 29, fill=muted)
rule(100, 183, 924, 183)
text(94, 264, labels[0], 140, bold=True)
text(94, 426, labels[1], 140, bold=True)
text(100, 633, labels[2], 36, fill=muted)
text(100, 687, labels[3], 36, fill=muted)

# Reuse the supplied book.svg geometry without its embedded Adobe metadata.
svg = ET.parse(ROOT / 'assets/branding/book.svg').getroot()
_, _, vw, vh = map(float, svg.attrib['viewBox'].split())
scale = 580 / vw
ox, oy = (1024 - 580) / 2, 893
for element in svg.findall('{http://www.w3.org/2000/svg}path'):
    tokens = re.findall(r'[a-zA-Z]|[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?', element.attrib['d'])
    points, i, x, y = [], 0, 0.0, 0.0
    while i < len(tokens):
        if tokens[i].isalpha():
            command = tokens[i]
            i += 1
        op = command.upper()
        if op == 'Z':
            continue
        n = {'M': 2, 'L': 2, 'C': 6}[op]
        nums = list(map(float, tokens[i:i+n]))
        i += n
        if command.islower():
            nums = [v + (x if j % 2 == 0 else y) for j, v in enumerate(nums)]
        if op in ('M', 'L'):
            x, y = nums
            points.append((x, y))
        else:
            x0, y0 = x, y
            a, b, c, d, x, y = nums
            for step in range(1, 65):
                t, u = step / 64, 1 - step / 64
                points.append((u**3*x0 + 3*u*u*t*a + 3*u*t*t*c + t**3*x,
                               u**3*y0 + 3*u*u*t*b + 3*u*t*t*d + t**3*y))
        if op == 'M':
            command = 'l' if command.islower() else 'L'
    draw.polygon([((ox + x * scale) * SCALE, (oy + y * scale) * SCALE)
                  for x, y in points], fill=cream)

rule(100, 1332, 924, 1332)
text(100, 1380, labels[4], 29, fill=muted)
image.resize((1024, 1536), Image.Resampling.LANCZOS).save(
    ROOT / ('assets/books/reader_guide.png' if lang == 'ko' else f'assets/books/reader_guide_{lang}.png'), optimize=True)
print(f'Generated guide cover: {lang}')
