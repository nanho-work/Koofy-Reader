"""Regenerated store artwork -> organized public output. Default: list only."""
from pathlib import Path
import json, shutil, sys, hashlib
ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / '출시·홍보자료'
records = json.loads((BASE / '이미지/최종이미지목록.json').read_text())
moves = json.loads((BASE / '보관자료/자료이동목록.json').read_text())['moved']
folders = sorted(((a,b) for a,b in moves.items() if (ROOT/b).is_dir()), key=lambda x:len(x[0]), reverse=True)
count = 0
for item in records:
    original = item['origin']
    for old,new in folders:
        if original.startswith(old + '/'):
            src = ROOT / (new + original[len(old):])
            break
    else:
        continue
    if not src.is_file():
        continue
    dest = BASE / item['file']
    print(f'{src.relative_to(BASE)} -> {item["file"]}')
    if '--apply' in sys.argv:
        dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(src,dest)
        item['sha256'] = hashlib.sha256(dest.read_bytes()).hexdigest()
    count += 1
if '--apply' in sys.argv:
    (BASE / '이미지/최종이미지목록.json').write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n')
print(f'{count} files; ' + ('applied' if '--apply' in sys.argv else 'preview only'))
