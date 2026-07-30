#!/usr/bin/env python3
"""修正「用行首空白做置中」的譯文行。

AGI 的訊息框沒有置中功能，原作是**手動塞行首空白**把英文推到中間（開場資料匣那 30 行
就是這樣排的）。中文一個字佔兩個顯示欄，照抄英文的空白數會整段偏左、參差不齊。

做法：偵測「原文行首有 ≥2 個空白」的行，用原文推回它想置中的欄寬，再依譯文的**顯示欄數**
（中文 2 欄、ASCII 1 欄）重算行首空白。行尾空白不補（沒有意義）。

用法：recenter_cjk.py <in.tsv> <out.tsv> [--width 40]
"""
import sys, argparse, unicodedata

def cols(s):
    return sum(2 if unicodedata.east_asian_width(c) in 'WF' else 1 for c in s)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src'); ap.add_argument('dst'); ap.add_argument('--width', type=int, default=40)
    a = ap.parse_args()
    n = 0
    out = []
    for line in open(a.src, encoding='utf-8'):
        line = line.rstrip('\n')
        if '\t' not in line:
            out.append(line); continue
        k, v = line.split('\t', 1)
        lead = len(k) - len(k.lstrip(' '))
        # 認定「這是一行排版過的顯示行」的兩個條件：
        #   行首有空白（≥1，不是 ≥2——開場字幕有整行只縮 1 格的）
        #   且整行夠寬（lead+內容 ≥ 20 欄），排除 " uniform" 這種拼接片段
        #   （那種行首空白是英文單字分隔用的，補空白會把句子推歪）。
        wide = lead + len(k.strip()) >= 20
        if lead >= 1 and wide and v.strip() and v != k:
            body = v.strip()
            # 保留**原文那一行的視覺中心軸**，而不是重新置中到畫面正中。
            # 原因：這些行是美術排版的一部分（開場字幕逐行對齊在同一條軸上，
            # 而那條軸不一定等於畫面中心）。若每行各自重算基準寬，各行會對到
            # 不同的軸，整段變成參差不齊——實測踩過。
            centre = lead + len(k.strip()) / 2.0
            newlead = max(0, int(round(centre - cols(body) / 2.0)))
            # 不讓行尾超出畫面
            if newlead + cols(body) > a.width:
                newlead = max(0, a.width - cols(body))
            nv = ' ' * newlead + body
            if nv != v:
                v = nv; n += 1
        out.append(f"{k}\t{v}")
    open(a.dst, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    print(f"重算行首置中空白：{n} 行 → {a.dst}")

if __name__ == '__main__':
    main()
