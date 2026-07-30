#!/usr/bin/env python3
"""譯名漂移稽核：對每個英文專有名詞，撈出所有含該詞的譯句，數各種中文寫法出現次數。

**只數不猜**——輸出是「這個詞在譯文裡出現過哪些中文寫法、各幾次」，
由人判斷哪個才對，然後補進 converge.tsv。

用法: nameaudit.py <done_dir_or_tsv> [...]
"""
import sys, os, glob, re, collections

# 英文詞 → 該詞的正確譯名（其餘寫法即漂移）。只列會出現在譯句裡的專有名詞。
TERMS = {
    "Sarien":       "沙利安",
    "Arcada":       "阿寇達",
    "Deltaur":      "代爾它",
    "Kerona":       "柯羅娜",
    "Orat":         "歐拉特",
    "Ulence Flats": "尤倫斯荒原",
    "Star Generator": "星辰產生器",
    "Xenon":        "氙星",
    "Roger":        "羅傑",
    "Buckazoid":    "太空幣",
    "Tiny":         "小不點",
    "Droids-B-Us":  "機器人量販店",
    "Vohaul":       "沃霍爾",
    "jetpack":      "噴射背包",
    "keycard":      "磁卡",
    "cartridge":    "資料匣",
}

# 中文詞邊界：抓譯句裡連續的中文片段，找出「疑似該詞的譯法」
CJK = re.compile(r'[一-鿿]+')


def rows(paths):
    for p in paths:
        files = sorted(glob.glob(os.path.join(p, '*.tsv'))) if os.path.isdir(p) else [p]
        for f in files:
            for line in open(f, encoding='utf-8'):
                line = line.rstrip('\n')
                if '\t' not in line:
                    continue
                en, zh = line.split('\t', 1)
                if en != zh:
                    yield f, en, zh


def main():
    data = list(rows(sys.argv[1:]))
    print(f"掃了 {len(data)} 則譯句\n")
    bad = 0
    for term, want in TERMS.items():
        hits = [(f, en, zh) for f, en, zh in data if re.search(r"\b" + re.escape(term) + r"\b", en, re.I)]
        if not hits:
            continue
        ok = sum(1 for _, _, zh in hits if want in zh)
        miss = [(f, en, zh) for f, en, zh in hits if want not in zh]
        flag = '' if not miss else '  ← 有未使用約定譯名的句子'
        print(f"{term:16s} 約定「{want}」  出現 {len(hits)} 則，命中 {ok}，未命中 {len(miss)}{flag}")
        if miss:
            bad += 1
            # 列出未命中句子裡的中文片段，方便看出用了什麼別的寫法
            frags = collections.Counter()
            for _, _, zh in miss:
                for m in CJK.findall(zh):
                    if 2 <= len(m) <= 6:
                        frags[m] += 1
            for frag, n in frags.most_common(6):
                print(f"      候選寫法「{frag}」×{n}")
            for f, en, zh in miss[:2]:
                print(f"      {os.path.basename(f)}: {en[:60]}")
                print(f"        → {zh[:60]}")
    print(f"\n{bad} 個詞有未命中的句子（未命中不一定是錯——英文詞可能出現在不需重述該詞的句子裡，需人工判讀）")


if __name__ == '__main__':
    main()
