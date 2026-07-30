#!/usr/bin/env python3
"""Jones (SCI1 VGA) pic 內嵌 cel 編解碼器。

SCI1 VGA pic = vector opcode 流，內含 PIC_OP_OPX(0xfe)+VGA_EMBEDDED_VIEW(0x01) 嵌入 cel
(棋盤背景 + 各建築 sprite,招牌文字烘在其中)。cel 格式同 view cel(8-byte header + 單流 RLE)。

嵌入 cel opcode 佈局(picture.cpp PIC_OPX_VGA_EMBEDDED_VIEW):
  fe 01 [coordPrefix][xlo][ylo](3 bytes abs coords) [size:WORD] [cel:size bytes]
  cel: [w:WORD][h:WORD][dx:s8][dy][clearKey][unk] [RLE...]  (RLE 起於 header+8)
SET_PALETTE(fe 02): skip 256+4,之後 256 色 * 4 bytes(used,r,g,b)。

用法:
  sci1_pic.py info    <pic_file>
  sci1_pic.py extract <pic_file> <out_dir>              # 每嵌入 cel 一 PNG(套 pic palette)
  sci1_pic.py roundtrip <pic_file>                      # 每 cel decode→RLE encode→decode 一致性
  sci1_pic.py replace <pic_file> <out.p56> cel_idx,png [cel_idx,png ...]
純 stdlib + Pillow(extract/replace 用)。
"""
import sys, os, struct

def u16(d, o): return d[o] | (d[o+1] << 8)
def p16(v): return bytes((v & 0xFF, (v >> 8) & 0xFF))


def decode_rle(d, pos, w, h, clear):
    n = w * h
    out = bytearray([clear]) * n
    i = 0
    p = pos
    while i < n:
        cb = d[p]; p += 1
        ln = cb & 0x3F
        op = cb & 0xC0
        if op == 0x40:
            ln += 64; op = 0x00
        if op == 0x00:
            m = min(ln, n - i)
            out[i:i+m] = d[p:p+m]; p += ln; i += ln
        elif op == 0x80:
            col = d[p]; p += 1
            for k in range(min(ln, n - i)):
                out[i+k] = col
            i += ln
        else:
            i += ln
    return out


def encode_rle(bmp, n, clear):
    """簡單但正確的 SCI1 VGA 單流 RLE:fill(0x80)/literal(0x00)/skip(0xC0),run<=63。"""
    out = bytearray()
    i = 0
    while i < n:
        px = bmp[i]
        r = 1
        while i + r < n and bmp[i+r] == px and r < 63:
            r += 1
        if px == clear:
            out.append(0xC0 | r); i += r
        elif r >= 2:
            out.append(0x80 | r); out.append(px); i += r
        else:
            lit = bytearray([px]); i += 1
            while i < n and len(lit) < 63:
                p2 = bmp[i]
                if p2 == clear:
                    break
                r2 = 1
                while i + r2 < n and bmp[i+r2] == p2 and r2 < 3:
                    r2 += 1
                if r2 >= 2:
                    break
                lit.append(p2); i += 1
            out.append(0x00 | len(lit)); out.extend(lit)
    return bytes(out)


class SCI1Pic:
    def __init__(self, raw):
        self.body = raw[2:] if raw[:1] in (b'\x81', b'\x80') else raw
        self.palette = self._find_palette()
        self.cels = self._find_cels()

    def _find_palette(self):
        d = self.body
        for i in range(len(d) - 3):
            if d[i] == 0xfe and d[i+1] == 0x02:
                base = i + 2 + 256 + 4
                pal = [(0, 0, 0)] * 256
                ok = True
                for c in range(256):
                    o = base + c * 4
                    if o + 4 > len(d):
                        ok = False; break
                    pal[c] = (d[o+1], d[o+2], d[o+3])
                if ok:
                    return pal
        return None

    def _find_cels(self):
        d = self.body
        cels = []
        i = 0
        while i < len(d) - 12:
            if d[i] == 0xfe and d[i+1] == 0x01:
                p = i + 2
                # abs coords NoMirror: prefix, xlo, ylo
                pref = d[p]; x = d[p+1] + ((pref & 0xF0) << 4); y = d[p+2] + ((pref & 0x0F) << 8)
                p += 3
                size = u16(d, p); p += 2
                w = u16(d, p); h = u16(d, p+2); clear = d[p+6]
                if 1 <= w <= 320 and 1 <= h <= 200 and 8 < size < 70000 and p + size <= len(d):
                    cels.append({'op': i, 'x': x, 'y': y, 'size': size,
                                 'w': w, 'h': h, 'clear': clear,
                                 'hdr': p, 'data': p + 8, 'end': p + size})
                    i = p + size
                    continue
            i += 1
        return cels

    def decode(self, idx):
        c = self.cels[idx]
        return decode_rle(self.body, c['data'], c['w'], c['h'], c['clear'])

    def replace(self, reps):
        """reps: {idx: index_bitmap}. 回傳新 body bytes(以 RLE 重編,更新 size,splice)。"""
        d = self.body
        # 依 op 位置由後往前 splice,避免位移影響
        out = bytearray(d)
        for idx in sorted(reps, key=lambda k: self.cels[k]['op'], reverse=True):
            c = self.cels[idx]
            rle = encode_rle(reps[idx], c['w'] * c['h'], c['clear'])
            hdr = bytes((c['w'] & 0xFF, c['w'] >> 8, c['h'] & 0xFF, c['h'] >> 8,
                         d[c['hdr']+4], d[c['hdr']+5], c['clear'], d[c['hdr']+7]))
            new_cel = hdr + rle
            new_size = len(new_cel)
            # [op..coords][size field @ hdr-2][cel @ hdr..end]
            size_pos = c['hdr'] - 2
            out[size_pos:c['end']] = p16(new_size) + new_cel
        return bytes(out)


def _save_png(bmp, w, h, pal, path):
    from PIL import Image
    img = Image.new('RGB', (w, h))
    p = pal or [(i, i, i) for i in range(256)]
    img.putdata([p[b] for b in bmp[:w*h]])
    img.save(path)


def cmd_info(f):
    pic = SCI1Pic(open(f, 'rb').read())
    print(f"palette={'yes' if pic.palette else 'no'}  嵌入 cel {len(pic.cels)} 個:")
    for i, c in enumerate(pic.cels):
        print(f"  cel {i}: pos({c['x']},{c['y']}) {c['w']}x{c['h']} size={c['size']} clear={c['clear']}")


def cmd_extract(f, outdir):
    os.makedirs(outdir, exist_ok=True)
    pic = SCI1Pic(open(f, 'rb').read())
    for i, c in enumerate(pic.cels):
        bmp = pic.decode(i)
        _save_png(bmp, c['w'], c['h'], pic.palette,
                  os.path.join(outdir, f"cel{i}_x{c['x']}y{c['y']}_{c['w']}x{c['h']}.png"))
    print(f"extracted {len(pic.cels)} cel(s) → {outdir}")


def cmd_roundtrip(f):
    pic = SCI1Pic(open(f, 'rb').read())
    ok = 0
    for i, c in enumerate(pic.cels):
        orig = pic.decode(i)
        rle = encode_rle(orig, c['w']*c['h'], c['clear'])
        re = decode_rle(rle, 0, c['w'], c['h'], c['clear'])
        if bytes(re) == bytes(orig):
            ok += 1
        else:
            print(f"  cel {i}: RLE roundtrip 不符")
    print(f"roundtrip: {ok}/{len(pic.cels)} cel RLE identity")


def cmd_replace(f, outp, specs):
    from PIL import Image
    pic = SCI1Pic(open(f, 'rb').read())
    pal = pic.palette or [(i, i, i) for i in range(256)]
    # RGB→index 查表
    reps = {}
    for spec in specs:
        idx, png = spec.split(',', 1)
        idx = int(idx)
        c = pic.cels[idx]
        img = Image.open(png).convert('RGB').resize((c['w'], c['h']))
        px = img.load()
        bmp = bytearray(c['w'] * c['h'])
        cache = {}
        for y in range(c['h']):
            for x in range(c['w']):
                rgb = px[x, y]
                v = cache.get(rgb)
                if v is None:
                    best = 0; bd = 1 << 30
                    for k, (r, g, b) in enumerate(pal):
                        dd = (r-rgb[0])**2 + (g-rgb[1])**2 + (b-rgb[2])**2
                        if dd < bd:
                            bd = dd; best = k
                    cache[rgb] = v = best
                bmp[y*c['w']+x] = v
        reps[idx] = bmp
    new_body = pic.replace(reps)
    with open(outp, 'wb') as fh:
        fh.write(b'\x81\x00')
        fh.write(new_body)
    print(f"replaced {len(reps)} cel(s) → {outp} ({len(new_body)+2} bytes)")


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'info':
        cmd_info(sys.argv[2])
    elif cmd == 'extract':
        cmd_extract(sys.argv[2], sys.argv[3])
    elif cmd == 'roundtrip':
        cmd_roundtrip(sys.argv[2])
    elif cmd == 'replace':
        cmd_replace(sys.argv[2], sys.argv[3], sys.argv[4:])
    else:
        print(__doc__); sys.exit(1)
