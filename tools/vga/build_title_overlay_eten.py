#!/usr/bin/env python3
"""烘《宇宙傳奇 IV》中文標題副標疊圖 sq4_title.ovl(倚天點陣字版)。

為什麼用倚天而不是 TTF:標題 pic 本身是 320×200 的點陣美術,被引擎 2× 放大。副標若用
TTF 抗鋸齒後量化成 ≤16 色,放大後邊緣會出現雜色;倚天是硬邊點陣,2× 放大後跟原畫同一種
質感(方塊像素),看起來才像「當年就有的中文版」。

.ovl 格式(little-endian,與引擎 GfxPaint16::drawChtTitleOverlay 對應):
  u16 width, height, x, y      # x,y = 320×200 邏輯座標(引擎寫 visual plane)
  u16 nColors                  # 內嵌調色盤色數
  nColors × (u8 r, u8 g, u8 b) # 引擎 blit 時 nearest-map 到當下 VGA 螢幕調色盤
  width*height × u8 index      # 0xFF = 透明

配色對齊 SQ4 藍銀色 logo:深藍近黑底板 + 銀藍描邊 + 亮銀字身 + 頂緣白高光。
"""
import os, sys, struct, argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_eten_font import EtenFont, ETEN

# 調色盤(index → RGB)。0 = 底板,1 = 描邊,2 = 字身,3 = 高光。
PALETTE = [
    (8, 8, 40),        # 0 底板:深藍近黑,與標題背景的暗藍暈同色系
    (40, 56, 128),     # 1 描邊
    (196, 212, 255),   # 2 字身:亮銀藍,對齊 SPACE QUEST 字體的冷色高光
    (255, 255, 255),   # 3 高光
]
TRANSPARENT = 0xFF


def render_text(text, font16, spacing=1):
    """把字串畫成 1bpp 遮罩(list of list of bool)。ASCII 走 8×15 半形格。"""
    W, H = 0, font16.h
    cells = []
    for ch in text:
        if ord(ch) < 0x80:
            cells.append(("ascii", ch))
            W += 8 + spacing
        else:
            cells.append(("cjk", ch))
            W += font16.w + spacing
    W = max(W - spacing, 1)
    mask = [[False] * W for _ in range(H)]

    # ASCII 用倚天 ASCFONT 同尺寸的簡單 5×7 內建點陣即可(標題只會用到 I/V 之類)
    ASCII5x7 = {
        "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
        "V": ["10001", "10001", "10001", "10001", "01010", "01010", "00100"],
        " ": ["00000"] * 7,
    }

    x = 0
    for kind, ch in cells:
        if kind == "cjk":
            b5 = ch.encode("big5")
            g = font16.glyph(b5[0], b5[1])
            if g is None:
                x += font16.w + spacing
                continue
            rb = (font16.w + 7) // 8
            for gy in range(font16.h):
                for gx in range(font16.w):
                    if g[gy * rb + (gx >> 3)] & (0x80 >> (gx & 7)):
                        mask[gy][x + gx] = True
            x += font16.w + spacing
        else:
            pat = ASCII5x7.get(ch.upper())
            if pat:
                # 垂直置中、水平置中於 8px 格
                oy = (font16.h - len(pat)) // 2
                for gy, row in enumerate(pat):
                    for gx, c in enumerate(row):
                        if c == "1":
                            mask[oy + gy][x + 1 + gx] = True
            x += 8 + spacing
    return mask, W, H


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--text", default="宇宙傳奇 IV　時空穿越者")
    ap.add_argument("--y", type=int, default=157, help="320×200 邏輯座標的上緣")
    ap.add_argument("--disp-w", type=int, default=320)
    ap.add_argument("--pad", type=int, default=5)
    a = ap.parse_args()

    font16 = EtenFont(os.path.join(ETEN, "STDFONT.15"), os.path.join(ETEN, "SPCFONT.15"), 16, 15)
    mask, tw, th = render_text(a.text, font16)

    pad = a.pad
    W, H = tw + 2 * pad, th + 2 * pad
    if W > a.disp_w:
        sys.exit(f"副標太寬:{W} > {a.disp_w},請縮短文字")

    # 先全透明,再鋪底板(圓角:四角各切 2px)
    px = [[TRANSPARENT] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            cut = 0
            if y < 2:
                cut = 2 - y
            elif y >= H - 2:
                cut = y - (H - 3)
            if x < cut or x >= W - cut:
                continue
            px[y][x] = 0

    # 描邊(字身外擴 1px)→ 字身 → 頂緣高光
    for y in range(th):
        for x in range(tw):
            if not mask[y][x]:
                continue
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + pad + dy, x + pad + dx
                    if 0 <= yy < H and 0 <= xx < W and px[yy][xx] != TRANSPARENT:
                        px[yy][xx] = 1
    for y in range(th):
        for x in range(tw):
            if mask[y][x]:
                px[y + pad][x + pad] = 2
    for y in range(th):
        for x in range(tw):
            if mask[y][x] and (y == 0 or not mask[y - 1][x]):
                px[y + pad][x + pad] = 3

    ox = (a.disp_w - W) // 2
    with open(a.out, "wb") as f:
        f.write(struct.pack("<HHHH", W, H, ox, a.y))
        f.write(struct.pack("<H", len(PALETTE)))
        for r, g, b in PALETTE:
            f.write(bytes((r, g, b)))
        for row in px:
            f.write(bytes(row))
    print(f"{a.out}: {W}×{H} @ ({ox},{a.y})  文字「{a.text}」  {os.path.getsize(a.out)} bytes")


if __name__ == "__main__":
    main()
