#!/usr/bin/env python3
"""用倚天點陣字把中文副標渲染成 640x400 透明 PNG，供 build_title_overlay.py 烘成 .ovl。

為什麼不用 TTF：標題 logo 是 1986 年的硬邊點陣美術，副標用抗鋸齒字會格格不入。
AGI 軌 _chtEnabled 時 display 是 640x400，所以這張圖就以 640x400 為準（與 SCI 軌不同）。
"""
import sys, os, argparse
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_eten_font import EtenFont, ETEN

ap = argparse.ArgumentParser()
ap.add_argument("out")
ap.add_argument("--text", required=True)
ap.add_argument("--y", type=int, default=330, help="640x400 座標的上緣")
ap.add_argument("--rgb", default="255,85,85", help="字色（預設 EGA 亮紅，對齊 logo）")
a = ap.parse_args()

f = EtenFont(os.path.join(ETEN, "stdfont.24"), os.path.join(ETEN, "SPCFONT.24"), 24, 24)
col = tuple(int(v) for v in a.rgb.split(","))

# 先量寬度（ASCII 佔半格）
cells = []
for ch in a.text:
    b5 = ch.encode("big5", errors="ignore")
    cells.append((ch, b5 if len(b5) == 2 else None))
w = sum(24 if c[1] else 12 for c in cells)

img = Image.new("RGBA", (640, 400), (0, 0, 0, 0))
px = img.load()
x = (640 - w) // 2
for ch, b5 in cells:
    if b5:
        g = f.glyph(b5[0], b5[1])
        if g:
            # glyph() 回的是原始點陣 bytes：每列 ceil(W/8) bytes、MSB 在左，
            # 不是一個 pixel 一個元素的陣列。
            rb = (24 + 7) // 8
            for yy in range(24):
                for xx in range(24):
                    if g[yy * rb + (xx >> 3)] & (0x80 >> (xx & 7)):
                        px[x + xx, a.y + yy] = (*col, 255)
        x += 24
    else:
        x += 12
img.save(a.out)
print(f"{a.out}: 文字寬 {w}px，置中於 x={(640 - w) // 2}, y={a.y}")
