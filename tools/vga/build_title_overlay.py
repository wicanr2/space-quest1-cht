#!/usr/bin/env python3
"""烘《羅賓漢傳奇》中文標題副標疊圖 longbow_title.ovl。

VGA(SCI1) 版:與 KQ4(EGA) 不同——EGA 版 .ovl 存 EGA 16 色索引直寫 visual plane;
VGA 的 visual plane 是 256 色索引,直接寫死索引會對到錯的顏色。故本 .ovl **內嵌自己的
小調色盤(RGB)**,由引擎 drawChtTitleOverlay 在 blit 時 nearest-map 到當下 pic 96 的
VGA 螢幕調色盤(⑦「VGA 內嵌 ≤16 色調色盤 + 引擎 nearest-map」)。

.ovl 格式(little-endian):
  u16 width, u16 height, u16 x, u16 y      # x,y = 320x200 邏輯座標(引擎寫 visual plane)
  u16 nColors                              # 調色盤色數(≤64)
  nColors × (u8 r, u8 g, u8 b)             # 調色盤
  width*height × u8 index                  # 0xFF=透明,否則 0..nColors-1

風格對齊金色哥德 logo:黑色圓角 plaque 底板 + 深棕描邊 + 金黃字身 + 上緣白高光。
字型用 Pillow(AR PL UMing)。用法:build_title_overlay.py <out.ovl> [--text 羅賓漢傳奇] ...
"""
import sys, struct, argparse
from PIL import Image, ImageFont, ImageDraw

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--text", default="羅賓漢傳奇")
    ap.add_argument("--font", default="/usr/share/fonts/truetype/arphic/uming.ttc")
    ap.add_argument("--face", type=int, default=2)
    ap.add_argument("--size", type=int, default=18)   # 320x200 邏輯尺度(引擎寫 visual 後 2x upscale)
    ap.add_argument("--disp-w", type=int, default=320)
    ap.add_argument("--disp-h", type=int, default=200)
    ap.add_argument("--y", type=int, default=172)     # 底部深色葉叢區(logo 下方)
    ap.add_argument("--ncolors", type=int, default=16)
    a = ap.parse_args()

    font = ImageFont.truetype(a.font, a.size, index=a.face)
    tmp = Image.new("RGB", (10, 10)); d = ImageDraw.Draw(tmp)
    bbox = d.textbbox((0, 0), a.text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    pad = 8
    W, H = tw + 2 * pad, th + 2 * pad
    img = Image.new("RGB", (W, H), (0, 0, 0))
    mask = Image.new("L", (W, H), 0)      # plaque 範圍(非透明)
    dd = ImageDraw.Draw(img); dm = ImageDraw.Draw(mask)
    ox, oy = pad - bbox[0], pad - bbox[1]
    # 0) 黑色圓角 plaque(金字在任何底色上都乾淨可讀)
    dd.rounded_rectangle([0, 0, W - 1, H - 1], radius=8, fill=(0, 0, 0))
    dm.rounded_rectangle([0, 0, W - 1, H - 1], radius=8, fill=255)
    # 1) 深棕描邊(logo 陰影感)
    for dx in (-2, -1, 0, 1, 2):
        for dy in (-2, -1, 0, 1, 2):
            if dx or dy:
                dd.text((ox + dx, oy + dy), a.text, font=font, fill=(150, 75, 0))
    # 2) 金黃字身
    dd.text((ox, oy), a.text, font=font, fill=(255, 215, 60))
    # 3) 上緣白高光(往上偏 1px)
    hi = Image.new("L", (W, H), 0); dh_ = ImageDraw.Draw(hi)
    dh_.text((ox, oy - 1), a.text, font=font, fill=255)

    # 量化到小調色盤
    q = img.quantize(colors=a.ncolors, method=Image.MEDIANCUT)
    pal = q.getpalette()  # [r,g,b, r,g,b, ...]
    qpx = q.load(); pm = mask.load(); ph = hi.load()
    ncol = min(a.ncolors, len(pal) // 3)

    x = (a.disp_w - W) // 2
    data = bytearray()
    for yy in range(H):
        for xx in range(W):
            if pm[xx, yy] == 0:
                data.append(0xFF)          # plaque 外 = 透明
            else:
                data.append(qpx[xx, yy])   # 調色盤索引

    with open(a.out, "wb") as f:
        f.write(struct.pack("<HHHH", W, H, x, a.y))
        f.write(struct.pack("<H", ncol))
        for i in range(ncol):
            f.write(bytes(pal[i * 3:i * 3 + 3]))
        f.write(bytes(data))

    used = sorted(set(b for b in data if b != 0xFF))
    print(f"標題疊圖 {W}x{H} @({x},{a.y}) 調色盤 {ncol} 色,用到 {len(used)} 色,{len(data)} px → {a.out}")

if __name__ == "__main__":
    main()
