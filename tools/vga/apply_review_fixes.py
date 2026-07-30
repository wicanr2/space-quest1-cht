#!/usr/bin/env python3
"""把 translation/review/g*.tsv 的譯文修正套回對應 batch/*.tsv。

review 格式(5 欄 TAB):批次檔名 | 英文原文 | 現譯 | 建議譯文 | 理由
- 以「英文原文(strip 後)」為 key 定位 batch 行,只替換第二欄(譯文),第一欄(英文 key)原樣不動。
- 建議欄保留前後空白(padding/置中),不 strip。
- 跳過:註解行(#開頭)、建議欄非實際譯文的 baseline 註記(以「(」或「（」開頭)。
純 stdlib。用法:apply_review_fixes.py
"""
import glob, os

ROOT = "/home/anr2/scummvm/conquest_of_longbow/workplace"
BATCH = os.path.join(ROOT, "translation/batch")

# 1) 收集修正:batch檔名 -> { 英文strip -> 新譯文 }
fixes = {}
n_rows = 0
for rf in sorted(glob.glob(os.path.join(ROOT, "translation/review/g*.tsv"))):
    for line in open(rf, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line or line.lstrip().startswith("#"):
            continue
        cols = line.split("\t")
        if len(cols) < 4:
            continue
        batch, eng, cur, sug = cols[0], cols[1], cols[2], cols[3]
        if sug.strip().startswith("(") or sug.strip().startswith("（"):
            continue  # baseline 註記,非實際譯文
        if not sug.strip():
            continue
        fixes.setdefault(batch.strip(), {})[eng.strip()] = sug
        n_rows += 1

print(f"讀入 {n_rows} 筆修正,分佈於 {len(fixes)} 個批次")

# 2) 套回 batch
applied = 0
missed = []
for batch, m in fixes.items():
    path = os.path.join(BATCH, batch)
    if not os.path.exists(path):
        missed += [f"{batch}(檔不存在):{k[:40]}" for k in m]
        continue
    lines = open(path, encoding="utf-8").read().split("\n")
    out = []
    hit = set()
    for line in lines:
        if "\t" in line:
            en, zh = line.split("\t", 1)
            key = en.strip()
            if key in m:
                out.append(f"{en}\t{m[key]}")
                hit.add(key)
                continue
        out.append(line)
    open(path, "w", encoding="utf-8").write("\n".join(out))
    applied += len(hit)
    for k in m:
        if k not in hit:
            missed.append(f"{batch}: {k[:50]}")

print(f"✓ 已套用 {applied} 筆")
if missed:
    print(f"⚠ {len(missed)} 筆未命中(英文 key 對不上):")
    for x in missed:
        print("   ", x)
