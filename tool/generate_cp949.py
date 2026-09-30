"""Generate strict CP949/UHC -> Unicode BMP pairs using Python's standard codec.
Run from the repository root: python3 tool/generate_cp949.py
No runtime network request or Python dependency is used by the app.
"""
from pathlib import Path
import struct
output = bytearray()
for first in range(0x81, 0xFF):
    for second in range(0x41, 0xFF):
        pair = bytes([first, second])
        try:
            value = pair.decode('cp949', errors='strict')
        except UnicodeDecodeError:
            continue
        if len(value) == 1:
            output.extend(struct.pack('>HH', (first << 8) | second, ord(value)))
Path('assets/encoding/cp949.bin').write_bytes(output)
