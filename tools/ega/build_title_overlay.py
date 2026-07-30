#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把設計師的「幻想空間」中文標題透明 PNG，烘成引擎可疊繪的 .ovl 索引點陣圖。

用法:
  build_title_overlay.py <in.png> <out.ovl> --palette ega|vga

.ovl 格式（big-endian）:
  magic  "CHTO"           (4 bytes)
  version 1               (1 byte)
  palType 0=EGA / 1=VGA   (1 byte)
  origin_x, origin_y      (u16, u16)  非透明像素外接框左上角
  width,   height         (u16, u16)  外接框尺寸
  [palType==1 才有] numColors(1 byte) + numColors*3 bytes 內嵌 RGB 調色盤
  pixels  width*height    每 byte 一像素：0xFF=透明，否則索引
                          EGA(palType0)：索引=EGA 16 色索引(引擎直接寫 display)
                          VGA(palType1)：索引=內嵌調色盤 index(引擎端 nearest-map 到當前 SCI palette)

EGA：量化到標準 16 色 EGA 調色盤（索引 0-15），對齊 ScummVM AGI hi-res(640x400) display buffer。
VGA：PIL 量化到 <=numColors 內嵌自有調色盤，SCI 端載入後 nearest-map 到當前遊戲 palette。
"""
import sys, struct, argparse
from PIL import Image

# 標準 EGA 16 色（ScummVM AGI 使用）
EGA = [
    (0x00,0x00,0x00),(0x00,0x00,0xAA),(0x00,0xAA,0x00),(0x00,0xAA,0xAA),
    (0xAA,0x00,0x00),(0xAA,0x00,0xAA),(0xAA,0x55,0x00),(0xAA,0xAA,0xAA),
    (0x55,0x55,0x55),(0x55,0x55,0xFF),(0x55,0xFF,0x55),(0x55,0xFF,0xFF),
    (0xFF,0x55,0x55),(0xFF,0x55,0xFF),(0xFF,0xFF,0x55),(0xFF,0xFF,0xFF),
]

def nearest(pal, r, g, b):
    best, bi = 1<<30, 0
    for i,(pr,pg,pb) in enumerate(pal):
        d = (pr-r)**2 + (pg-g)**2 + (pb-b)**2
        if d < best:
            best, bi = d, i
    return bi

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("infile"); ap.add_argument("outfile")
    ap.add_argument("--palette", choices=["ega","vga"], default="ega")
    ap.add_argument("--alpha-threshold", type=int, default=128)
    ap.add_argument("--colors", type=int, default=16, help="VGA 內嵌調色盤色數上限")
    a = ap.parse_args()

    img = Image.open(a.infile).convert("RGBA")
    W, H = img.size
    px = img.load()
    palType = 0 if a.palette == "ega" else 1

    # 先找非透明像素外接框
    minx, miny, maxx, maxy = W, H, -1, -1
    for y in range(H):
        for x in range(W):
            if px[x,y][3] >= a.alpha_threshold:
                if x<minx: minx=x
                if y<miny: miny=y
                if x>maxx: maxx=x
                if y>maxy: maxy=y
    if maxx < 0:
        print("!! 圖內沒有非透明像素", file=sys.stderr); sys.exit(1)
    ow, oh = maxx-minx+1, maxy-miny+1

    embed_pal = []   # VGA 內嵌調色盤 [(r,g,b),...]
    if palType == 1:
        # 用 PIL 量化非透明區的 RGB 到 <=colors 個色，取得內嵌調色盤
        crop = img.crop((minx, miny, maxx+1, maxy+1))
        rgb = crop.convert("RGB").quantize(colors=a.colors, method=Image.MEDIANCUT)
        ppal = rgb.getpalette()
        nc = a.colors
        embed_pal = [(ppal[i*3], ppal[i*3+1], ppal[i*3+2]) for i in range(nc)]
        qpx = rgb.load()

    data = bytearray()
    opaque = 0
    for y in range(miny, maxy+1):
        for x in range(minx, maxx+1):
            r,g,b,al = px[x,y]
            if al < a.alpha_threshold:
                data.append(0xFF)
            else:
                if palType == 0:
                    data.append(nearest(EGA, r,g,b))
                else:
                    idx = qpx[x-minx, y-miny]
                    data.append(idx if idx != 0xFF else 0xFE)  # 保留 0xFF 作透明
                opaque += 1

    with open(a.outfile, "wb") as f:
        f.write(b"CHTO")
        f.write(struct.pack("B", 1))
        f.write(struct.pack("B", palType))
        f.write(struct.pack(">HHHH", minx, miny, ow, oh))
        if palType == 1:
            f.write(struct.pack("B", len(embed_pal)))
            for (r,g,b) in embed_pal:
                f.write(struct.pack("BBB", r,g,b))
        f.write(bytes(data))

    extra = f"  內嵌色={len(embed_pal)}" if palType==1 else ""
    print(f"OK: {a.outfile}  框=({minx},{miny}) {ow}x{oh}  非透明={opaque} px  調色盤={a.palette}{extra}")

if __name__ == "__main__":
    main()
