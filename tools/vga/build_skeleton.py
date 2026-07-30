#!/usr/bin/env python3
"""把 text.* 抽出的 skeleton 與 script.* 內嵌字串合成單一 translation skeleton。

為什麼要兩個來源:extract_strings.py 只看 message/text 資源,SCI 的 script 內
還嵌著 Print 字串、道具描述、kFormat 模板;只抽前者會在實機露出整批英文,而
覆蓋率數字完全看不出來(見 kb scummvm-sci-cht-localization)。

key 一律過 norm_key()(與引擎 sciChtNormKey 等價),多行 crawl 的硬換行在
skeleton 裡以 \\n 跳脫保存,build_cht.py 端還原。

用法:build_skeleton.py <text_skeleton.tsv> <script_strings.json> <out.tsv> [--sidecar out.tsv]
"""
import sys, json, argparse


def norm_key(s):
    return " ".join(s.split())


def esc(s):
    return s.replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("text_tsv")
    ap.add_argument("script_json")
    ap.add_argument("out_tsv")
    ap.add_argument("--origin", default=None, help="輸出 key<TAB>來源 的 sidecar")
    a = ap.parse_args()

    rows = []          # (key_norm, raw_string, origin)
    seen = set()

    for line in open(a.text_tsv, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line:
            continue
        eng = line.split("\t", 1)[0]
        k = norm_key(eng.replace("\\n", " "))
        if k in seen:
            continue
        seen.add(k)
        rows.append((k, eng, "text"))

    for s in json.load(open(a.script_json, encoding="utf-8")):
        k = norm_key(s)
        if not k or k in seen:
            continue
        seen.add(k)
        rows.append((k, esc(s), "script"))

    with open(a.out_tsv, "w", encoding="utf-8") as f:
        for _, eng, _o in rows:
            f.write(f"{eng}\t{eng}\n")

    if a.origin:
        with open(a.origin, "w", encoding="utf-8") as f:
            for k, _e, o in rows:
                f.write(f"{k}\t{o}\n")

    n_text = sum(1 for r in rows if r[2] == "text")
    n_script = len(rows) - n_text
    chars = sum(len(r[1]) for r in rows)
    print(f"skeleton:{len(rows)} 則(text {n_text} + script {n_script}),{chars} 英文字元 → {a.out_tsv}")


if __name__ == "__main__":
    main()
