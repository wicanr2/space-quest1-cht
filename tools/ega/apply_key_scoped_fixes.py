#!/usr/bin/env python3
"""依「英文 key 命中什麼」圈定範圍，再替換譯文中的字詞。

為什麼需要這個（converge.tsv 修不了的情況）：
    converge.tsv 是純中文的子字串替換，看不到英文原文。遇到「兩個不同的英文道具
    被譯成同一個中文詞」時它無能為力——例如本作的 `widget`(磁性小物) 與 `Gadget`
    (另一個獨立道具) 都被譯成「小裝置」，玩家對照道具欄與互動訊息時會對不起來。
    這時要能說「**只有**英文含 widget 的那些句子，才把『小裝置』換成『強力磁鐵』」。

規則檔格式（TSV，# 開頭為註解）：
    <英文 regex><TAB><錯誤中文><TAB><正確中文>

用法: apply_key_scoped_fixes.py <rules.tsv> <in.tsv> <out.tsv>
"""
import sys, re, argparse


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rules")
    ap.add_argument("src")
    ap.add_argument("dst")
    a = ap.parse_args()

    rules = []
    for line in open(a.rules, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        pat, wrong, right = parts
        rules.append((re.compile(pat, re.I), wrong, right))

    n_lines = 0
    out = []
    for line in open(a.src, encoding="utf-8"):
        line = line.rstrip("\n")
        if "\t" not in line:
            out.append(line)
            continue
        en, zh = line.split("\t", 1)
        orig = zh
        for pat, wrong, right in rules:
            if wrong in zh and pat.search(en):
                zh = zh.replace(wrong, right)
        if zh != orig:
            n_lines += 1
        out.append(f"{en}\t{zh}")

    open(a.dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(f"依 key 圈定的修正：{n_lines} 行 → {a.dst}")


if __name__ == "__main__":
    main()
