#!/usr/bin/env python3
"""把烘進 SCI view 美術裡的英文招牌重畫成中文，輸出 dist-cht/sq1_cels.dat。

**只輸出我們自己畫的那幾張點陣**，不重編整支 view——原因是交付政策：patch 版不得含
任何遊戲資源，而「解碼原 view → 換 cel → 重編成 N.v56」會把沒改到的其他 cel 一起複製
出來。引擎端在 GfxView::getBitmap() 把這些點陣蓋回去（見 view.cpp chtReplaceCel）。

字用倚天中文系統 16×15 原生點陣（跟對白同一套來源），顏色從**原 cel 自己的調色盤**取，
所以換上去的中文在色調上跟原畫一致，也不必在執行期做最近色對應。

用法:
  bake_cels_cn.py <res_dir> <out.dat> [--preview <dir>]
    res_dir  = SCI_DUMP_RES 出來的資源夾（要有 view.NNN）

新增一個招牌就在 JOBS 裡加一筆；每筆自己描述版面（文字、色、上下留白、閃爍變體）。
"""
import os
import sys
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from sci1_view import SCI1View                      # noqa: E402
from build_eten_font import EtenFont                # noqa: E402

ETEN = os.path.join(HERE, "assets", "eten")


# --- 招牌清單 --------------------------------------------------------------
#
# text      要畫的中文（Big5 全形，一字 16×15）
# loop/cels 要換掉哪些 cel（同一個招牌常有好幾張閃爍變體）
# fg        文字色：('idx', N) 直接指定 view 調色盤 index
# bg        底色 index
# frame     (色 index, 上下各幾列) → 在文字上下畫橫條，模仿原招牌的紅色飾帶
# glitch    每個 cel 的破圖手法，對齊原版的霓虹閃爍：
#             None      完整
#             ('shift', dx)      整段左右位移（字被邊緣切掉）
#             ('gap', x0, x1)    中間挖掉一段直條
#             ('tear', y0, y1)   挖掉幾列
# slant     每個字往上抬幾列（招牌本身是斜的，橫排中文貼上去會很出戲）
# neon      每個 cel 指定「哪一個字最亮」，模仿原版霓虹燈依序點亮；其餘字用 fg_dim
JOBS = [
    dict(
        view=104, loop=3, cels=[0, 1, 2, 3, 4, 5],
        text="警報",
        fg=13, bg=0, frame=(12, 2),
        # 原版這六格是「字母缺角、位移」的破圖式閃爍。中文只有兩個字，照抄破圖會讓單張
        # 畫面看起來像字型壞掉（實測截圖確認），所以改成**明暗脈動**：同樣是閃，但每一格
        # 單獨看都是完整的字。
        cel_fg=[12, 13, 13, 13, 11, 12],
        note="阿寇達號走廊牆上的 RED ALERT 閃爍警示牌",
    ),
    dict(
        view=141, loop=0, cels=[0, 1, 2, 3],
        text="火箭酒吧",
        fg=35, fg_dim=180, bg=15, slant=2,
        neon=[None, 0, 1, 2],
        note="尤倫斯荒原「火箭酒吧」的霓虹招牌（原文 ROCKET，字母是斜著往右上排的）",
    ),
]


def load_font():
    return EtenFont(os.path.join(ETEN, "STDFONT.15"),
                    os.path.join(ETEN, "SPCFONT.15"), 16, 15)


def glyph_rows(font, ch):
    """回傳 16×15 的 bool 列表（[y][x]）。"""
    b = ch.encode("big5")
    if len(b) != 2:
        raise SystemExit(f"非 Big5 全形字: {ch!r}")
    g = font.glyph(b[0], b[1])
    if g is None:
        raise SystemExit(f"倚天字型沒有這個字: {ch}")
    rb = (font.w + 7) // 8
    return [[bool(g[y * rb + (x >> 3)] & (0x80 >> (x & 7))) for x in range(font.w)]
            for y in range(font.h)]


def render(job, w, h, font, bright=None):
    """畫出一張 w×h 的 index bitmap（不含 glitch）。bright = 哪一個字用亮色。"""
    bmp = bytearray([job['bg']]) * (w * h)
    chars = list(job['text'])
    gw, gh = font.w, font.h
    total = gw * len(chars)
    slant = job.get('slant', 0)
    rise = slant * (len(chars) - 1)
    if total > w or gh + abs(rise) > h:
        raise SystemExit(f"view {job['view']}: {job['text']} 需要 {total}x{gh + abs(rise)}，cel 只有 {w}x{h}")
    x0 = (w - total) // 2
    y0 = (h - gh - abs(rise)) // 2 + (abs(rise) if rise > 0 else 0)
    fg_dim = job.get('fg_dim', job['fg'])
    for ci, ch in enumerate(chars):
        col = job['fg'] if (bright is None or bright == ci) else fg_dim
        rows = glyph_rows(font, ch)
        yy0 = y0 - slant * ci
        for y in range(gh):
            for x in range(gw):
                if rows[y][x] and 0 <= yy0 + y < h:
                    bmp[(yy0 + y) * w + x0 + ci * gw + x] = col
    if job.get('frame'):
        col, n = job['frame']
        for k in range(n):
            for band in (k, h - 1 - k):
                if 0 <= band < h and (band < y0 or band >= y0 + gh):
                    for x in range(1, w - 1):
                        bmp[band * w + x] = col
    return bmp


def apply_glitch(bmp, w, h, bg, spec):
    if spec is None:
        return bmp
    kind = spec[0]
    out = bytearray(bmp)
    if kind == 'shift':
        dx = spec[1]
        out = bytearray([bg]) * (w * h)
        for y in range(h):
            for x in range(w):
                sx = x - dx
                if 0 <= sx < w:
                    out[y * w + x] = bmp[y * w + sx]
    elif kind == 'gap':
        x0, x1 = spec[1], spec[2]
        for y in range(h):
            for x in range(max(0, x0), min(w, x1)):
                out[y * w + x] = bg
    elif kind == 'tear':
        y0, y1 = spec[1], spec[2]
        for y in range(max(0, y0), min(h, y1)):
            for x in range(w):
                out[y * w + x] = bg
    else:
        raise SystemExit(f"不認得的 glitch: {spec}")
    return out


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    res_dir, out_path = sys.argv[1], sys.argv[2]
    preview = None
    if "--preview" in sys.argv:
        preview = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(preview, exist_ok=True)

    font = load_font()
    entries = []
    for job in JOBS:
        vp = os.path.join(res_dir, f"view.{job['view']:03d}")
        v = SCI1View(open(vp, 'rb').read())
        cels = v.loops[job['loop']]
        neon = job.get('neon')
        cel_fg = job.get('cel_fg')
        for n, ci in enumerate(job['cels']):
            c = cels[ci]
            j = dict(job)
            if cel_fg and n < len(cel_fg):
                j['fg'] = cel_fg[n]
            base = render(j, c.w, c.h, font, neon[n] if neon and n < len(neon) else None)
            g = job.get('glitch') or [None] * len(job['cels'])
            bmp = apply_glitch(base, c.w, c.h, j["bg"], g[n] if n < len(g) else None)
            entries.append((job['view'], job['loop'], ci, c.w, c.h, bytes(bmp)))
            if preview:
                from PIL import Image
                pal = v.palette or [(i, i, i) for i in range(256)]
                im = Image.new('RGB', (c.w, c.h))
                im.putdata([pal[b] for b in bmp])
                im = im.resize((c.w * 6, c.h * 6), Image.NEAREST)
                im.save(os.path.join(preview, f"v{job['view']}_l{job['loop']}_c{ci}.png"))
        print(f"  view {job['view']} loop {job['loop']} cels {job['cels']} "
              f"→ 「{job['text']}」  ({job['note']})")

    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, 'wb') as fh:
        fh.write(b"CHTC")
        fh.write(struct.pack("<HH", 1, len(entries)))
        for vid, lo, ce, w, h, data in entries:
            fh.write(struct.pack("<HHHHH", vid, lo, ce, w, h))
            fh.write(data)
    print(f"→ {out_path}（{len(entries)} 張 cel，{os.path.getsize(out_path)} bytes）")


if __name__ == "__main__":
    main()
