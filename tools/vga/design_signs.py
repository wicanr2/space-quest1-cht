#!/usr/bin/env python3
"""重畫兩塊招牌的點陣圖（火箭酒吧 95×23、警報 33×19）。

## 火箭酒吧為什麼要「透明底 + 最小補丁」

招牌本體（綠色的 ROCKET）畫在背景 pic 裡，是向量指令流，改不掉。我們能換的只有疊在
上面那層霓虹發光動畫（view 141 loop 0）。所以中文必須自己把底下的英文蓋掉。

第一版做法是整片不透明黑底 → 實機看起來像一塊硬貼上去的方塊。這一版改成：

  1. 只有「原本是綠色燈管」的像素才不透明，其餘一律透明（讓真正的旗面透出來）。
  2. 那些非蓋不可的像素，用**鄰近的旗面顏色補回去**（inpaint），而不是填死一個色。
     實測 view 141 的內嵌調色盤裡就有旗幟藍的近乎完全對應（色差 3~5），補得回去。
  3. 中文筆劃畫在最上層——凡是被筆劃蓋到的英文像素，本來就不必補。

結果是招牌邊界消失，看起來像「英文本來就不在那裡」。

## 警報為什麼要重畫字

33×19 放兩個中文字，一個字最多 16px 寬。「警」19 劃，用 16×15 字模會糊成一團。
這裡改用 24×24 字模按面積覆蓋率縮到 15×17（門檻壓低保住細筆劃），再用四階紅做
筆劃層次（頂緣高光 / 主筆劃 / 外緣暗紅），做出燈管的圓潤感而不是死板的單色字。

用法: design_signs.py            # 產生六個版本到 out/design/
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from build_eten_font import EtenFont            # noqa: E402
from PIL import Image                            # noqa: E402

ETEN = os.path.join(HERE, "assets", "eten")
OUT = "out/design"
REF = "out/design/ref/rocket_original_95x23.png"

ALPHA = (255, 0, 255)          # 哨兵色＝透明（不在遊戲調色盤內）

# 火箭酒吧：霓虹綠三階 + 旗幟色（補丁用的由 inpaint 決定，不限這幾色）
NEON_HI = (159, 239, 167)
NEON = (135, 223, 67)
NEON_MID = (35, 187, 35)
NEON_DK = (23, 119, 23)

# 警報：黑底四階紅
A_BLACK = (0, 0, 0)
A_DK = (184, 32, 32)
A_MID = (216, 38, 38)
A_MAIN = (222, 70, 70)
A_HI = (228, 103, 103)


# ---------- 字模 ----------------------------------------------------------
def glyph_bits(font, ch):
    b = ch.encode("big5")
    g = font.glyph(b[0], b[1])
    if g is None:
        raise SystemExit(f"倚天字型沒有這個字: {ch}")
    rb = (font.w + 7) // 8
    return [[bool(g[y * rb + (x >> 3)] & (0x80 >> (x & 7))) for x in range(font.w)]
            for y in range(font.h)]


def scale_bits(bits, sw, sh, tw, th, thresh=0.30):
    """按面積覆蓋率縮放字模。門檻壓低是為了保住細筆劃——用 0.5 的話「警」的言部會斷。"""
    out = [[False] * tw for _ in range(th)]
    for ty in range(th):
        y0, y1 = ty * sh / th, (ty + 1) * sh / th
        for tx in range(tw):
            x0, x1 = tx * sw / tw, (tx + 1) * sw / tw
            area = cov = 0.0
            for sy in range(int(y0), min(sh, int(y1) + 1)):
                oy = min(y1, sy + 1) - max(y0, sy)
                if oy <= 0:
                    continue
                for sx in range(int(x0), min(sw, int(x1) + 1)):
                    ox = min(x1, sx + 1) - max(x0, sx)
                    if ox <= 0:
                        continue
                    a = ox * oy
                    area += a
                    if bits[sy][sx]:
                        cov += a
            out[ty][tx] = area > 0 and cov / area >= thresh
    return out


def get_glyphs(text, w, h, use24, thresh=0.30):
    lo = EtenFont(os.path.join(ETEN, "STDFONT.15"), os.path.join(ETEN, "SPCFONT.15"), 16, 15)
    hi = EtenFont(os.path.join(ETEN, "stdfont.24"), os.path.join(ETEN, "SPCFONT.24"), 24, 24)
    out = []
    for ch in text:
        if use24:
            out.append(scale_bits(glyph_bits(hi, ch), 24, 24, w, h, thresh))
        else:
            b = glyph_bits(lo, ch)
            out.append([row[:w] for row in b[:h]])
    return out


# ---------- 火箭酒吧 ------------------------------------------------------
def neon_mask(px, w, h):
    """哪些像素是原版的綠色燈管——這些非蓋掉不可。"""
    m = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            m[y][x] = g > 90 and g > r + 40 and g > b + 40
    return m


def inpaint(px, mask, w, h):
    """把燈管像素換成周圍旗面的顏色，等於把旗子補回去。

    [雷] 第一版用「最近的非燈管像素」，結果補出一片雜訊——字母附近本來就摻著天空、
    支架、旗緣好幾種顏色，取單一最近鄰等於把那些雜色抄進補丁裡。改成**取半徑內所有
    非燈管像素的逐通道中位數**，離群色就被吃掉了，補出來是平順的旗面。
    """
    out = [[px[x, y] for x in range(w)] for y in range(h)]
    for y in range(h):
        for x in range(w):
            if not mask[y][x]:
                continue
            samples = []
            r = 1
            while r < max(w, h):
                samples = [px[nx, ny]
                           for dy in range(-r, r + 1) for dx in range(-r, r + 1)
                           for nx, ny in ((x + dx, y + dy),)
                           if 0 <= nx < w and 0 <= ny < h and not mask[ny][nx]]
                if len(samples) >= 12:
                    break
                r += 1
            if not samples:
                out[y][x] = (67, 99, 191)
                continue
            med = tuple(sorted(c[k] for c in samples)[len(samples) // 2] for k in range(3))
            out[y][x] = med
    return out


def build_rocket(variant):
    im = Image.open(REF).convert("RGB")
    px = im.load()
    W, H = im.size
    mask = neon_mask(px, W, H)
    patch = inpaint(px, mask, W, H)

    canvas = [[ALPHA] * W for _ in range(H)]
    text = "火箭酒吧"

    if variant == "v1":
        gw, gh, use24, adv, slant, thresh = 16, 15, False, 22, 2, 0.30
        core, edge = NEON, NEON_DK
        tube = False
    elif variant == "v2":
        gw, gh, use24, adv, slant, thresh = 16, 18, True, 23, 2, 0.28
        core, edge = NEON, NEON_DK
        tube = False
    else:  # v3
        gw, gh, use24, adv, slant, thresh = 16, 18, True, 23, 2, 0.28
        core, edge = NEON_HI, NEON_MID
        tube = True

    glyphs = get_glyphs(text, gw, gh, use24, thresh)
    total = adv * (len(text) - 1) + gw
    x0 = (W - total) // 2
    rise = slant * (len(text) - 1)
    y0 = (H - gh + rise) // 2

    ink = [[False] * W for _ in range(H)]
    for i, g in enumerate(glyphs):
        gx = x0 + i * adv
        gy = y0 - slant * i
        for yy in range(gh):
            for xx in range(gw):
                if g[yy][xx] and 0 <= gy + yy < H and 0 <= gx + xx < W:
                    ink[gy + yy][gx + xx] = True

    # 燈管外緣：筆劃右下 1px 的暗綠，讓字浮起來
    halo = [[False] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            if ink[y][x]:
                for dy, dx in ((1, 0), (0, 1), (1, 1)):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < H and 0 <= nx < W and not ink[ny][nx]:
                        halo[ny][nx] = True

    if tube:
        for x in range(2, W - 2):
            ty = y0 + gh + 1 - (slant * (x - x0)) // adv if adv else y0 + gh + 1
            if 0 <= ty < H and not ink[ty][x]:
                halo[ty][x] = True

    # 疊圖順序：補丁 → 外緣 → 筆劃。被筆劃蓋到的英文像素就不必補。
    for y in range(H):
        for x in range(W):
            if mask[y][x]:
                canvas[y][x] = patch[y][x]
    for y in range(H):
        for x in range(W):
            if halo[y][x]:
                canvas[y][x] = edge
    for y in range(H):
        for x in range(W):
            if ink[y][x]:
                canvas[y][x] = core

    # [HARD] 驗收：原本是燈管的像素，一個都不能留成透明
    leak = sum(1 for y in range(H) for x in range(W)
               if mask[y][x] and canvas[y][x] == ALPHA)
    opaque = sum(1 for y in range(H) for x in range(W) if canvas[y][x] != ALPHA)
    print(f"  rocket_{variant}: 英文 {sum(map(sum, mask))} px，漏蓋 {leak} px，"
          f"不透明 {opaque}/{W*H} px（{opaque*100//(W*H)}%）")
    if leak:
        raise SystemExit(f"!! rocket_{variant} 有 {leak} 個英文像素沒蓋到")
    return canvas, W, H


# ---------- 警報 ----------------------------------------------------------
#
# 33x19 放兩個中文字，一個字最多 16px 寬，而「警」有 19 劃。踩過三個雷：
#
#   [雷1] 給筆劃加 1px 外緣描邊 → 密字的筆劃間隙 <2px，描邊把縫全部填滿，
#         整個字變成一團紅色色塊。黑底對比本來就夠，**不要描邊**。
#   [雷2] 拿 24x24 字模按面積覆蓋率縮到 16x15 → 筆劃被打散、糊成雜訊。
#         **16x15 的倚天字模本來就是為這個尺寸設計的**，直接用它比任何縮放都乾淨。
#         想「更精細」不是靠更大的來源字模，是靠上色層次。
#   [雷3] 縮放門檻壓太低筆劃會變胖、跟著黏死。
#
# 所以三版都用原生 16x15 字模，差別在飾帶與燈管上色：
#   頂緣打亮 / 主體 / 底緣壓暗——燈管的圓潤感來自這個。
def build_alert(variant):
    W, H = 33, 19
    text = "警報"
    if variant == "v1":       # 忠於原版：上下各兩列飾帶，單色亮紅
        bar, shade = 2, False
    elif variant == "v2":     # 無飾帶，字置中，三階燈管上色
        bar, shade = 0, True
    else:                     # 一列飾帶 + 三階上色
        bar, shade = 1, True

    lo = EtenFont(os.path.join(ETEN, "STDFONT.15"), os.path.join(ETEN, "SPCFONT.15"), 16, 15)
    glyphs = [glyph_bits(lo, ch) for ch in text]

    gw, gh, adv = 16, 15, 16
    x0 = (W - adv * len(text)) // 2
    y0 = bar + (H - 2 * bar - gh) // 2

    canvas = [[A_BLACK] * W for _ in range(H)]
    ink = [[False] * W for _ in range(H)]
    for i, g in enumerate(glyphs):
        gx = x0 + i * adv
        for yy in range(gh):
            for xx in range(gw):
                if g[yy][xx] and 0 <= y0 + yy < H and 0 <= gx + xx < W:
                    ink[y0 + yy][gx + xx] = True

    for y in range(H):
        for x in range(W):
            if not ink[y][x]:
                continue
            if not shade:
                canvas[y][x] = A_MAIN
                continue
            above = y > 0 and ink[y - 1][x]
            below = y < H - 1 and ink[y + 1][x]
            if not above:
                canvas[y][x] = A_HI
            elif not below:
                canvas[y][x] = A_DK
            else:
                canvas[y][x] = A_MAIN

    for k in range(bar):
        for x in range(1, W - 1):
            canvas[k][x] = A_MID if k == 0 else A_DK
            canvas[H - 1 - k][x] = A_MID if k == 0 else A_DK

    filled = sum(sum(1 for x in range(W) if ink[y][x]) for y in range(H))
    print(f"  alert_{variant}: 原生 16x15 字模、飾帶 {bar} 列、"
          f"{'三階燈管' if shade else '單色'}、筆劃 {filled} px")
    return canvas, W, H


def save(canvas, w, h, name):
    im = Image.new("RGB", (w, h))
    im.putdata([canvas[y][x] for y in range(h) for x in range(w)])
    im.save(os.path.join(OUT, f"{name}.png"))
    im.resize((w * 8, h * 8), Image.NEAREST).save(os.path.join(OUT, f"{name}_x8.png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    print("火箭酒吧（透明底 + 最小補丁）：")
    for v in ("v1", "v2", "v3"):
        save(*build_rocket(v), f"rocket_{v}")
    print("警報（24×24 字模縮放 + 四階紅燈管）：")
    for v in ("v1", "v2", "v3"):
        save(*build_alert(v), f"alert_{v}")
    print("→", OUT)


if __name__ == "__main__":
    main()
