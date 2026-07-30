#!/usr/bin/env python3
"""從 SCI_DUMP_RES dump 出的(未壓縮)message.* / text.* patch 檔抽「精確」可翻譯字串,
產生 translation.tsv 骨架(英文原文 <TAB> 英文原文,待翻)+ 出處 sidecar。

message 版本(照 ScummVM engines/sci/engine/message.cpp):
  V2  headerSize=6  recordSize=4   stringOffset @ rec+2
  V3  headerSize=8  recordSize=10  stringOffset @ rec+5
  V4  headerSize=10 recordSize=11  stringOffset @ rec+5, talker @ rec+4  ← SQ4 CD talkie
text.*(SCI text 資源:單純 null 結尾字串表):直接 null 切。

key 一律過 norm_key(),與引擎 sci.cpp sciChtNormKey() 逐字一致
(前導空白忽略、連續空白收斂成一個、去尾)——否則多行硬換行的敘事段會比對 MISS。

dump 檔開頭 2 bytes 為 patch header(type, headerSkip);resource data 從 offset 2 起。

用法:extract_strings.py <dump_dir> <out_tsv> [--sidecar out.jsonl]
純 stdlib。
"""
import sys, os, re, json, struct, glob, argparse

PATCH_HEADER = 2  # dump 檔前 2 bytes:resource type + headerSkip

# version -> (headerSize, recordSize, stringOffsetField, talkerField|None)
MSG_FMT = {
    2: (6, 4, 2, None),
    3: (8, 10, 5, None),
    4: (10, 11, 5, 4),
}

def norm_key(s):
    """與引擎 sciChtNormKey 等價:空白(space/\\r/\\n/\\t)收斂成單一空格 + 去前後。"""
    return " ".join(s.split())

def is_translatable(s):
    s2 = s.strip()
    if len(s2) < 2:
        return False
    # 去掉 printf spec 後仍要有兩個以上連續英文字母
    if not re.search(r"[A-Za-z]{2,}", re.sub(r"%[-0-9.]*[a-zA-Z]", "", s2)):
        return False
    return True

def parse_message(path):
    """回傳 [(tuple_str, talker, text)]。"""
    raw = open(path, "rb").read()
    d = raw[PATCH_HEADER:]
    if len(d) < 10:
        return []
    version = struct.unpack_from("<I", d, 0)[0] // 1000
    fmt = MSG_FMT.get(version)
    if fmt is None:
        return [("", None, s) for s in null_split(raw)]
    header_size, record_size, str_field, talker_field = fmt
    count = struct.unpack_from("<H", d, header_size - 2)[0]
    out = []
    for i in range(count):
        rec = header_size + i * record_size
        if rec + record_size > len(d):
            break
        noun, verb, cond, seq = d[rec], d[rec + 1], d[rec + 2], d[rec + 3]
        string_off = struct.unpack_from("<H", d, rec + str_field)[0]
        if string_off >= len(d):
            continue
        end = d.find(b"\x00", string_off)
        if end < 0:
            end = len(d)
        talker = d[rec + talker_field] if talker_field is not None else None
        out.append((f"{noun}.{verb}.{cond}.{seq}", talker,
                    d[string_off:end].decode("latin1")))
    return out

def null_split(raw):
    out = []
    for chunk in raw.split(b"\x00"):
        s = chunk.decode("latin1", "replace")
        printable = sum(1 for c in s if 32 <= ord(c) < 127 or c in "\r\n\t")
        if not s or printable / max(1, len(s)) < 0.95:
            continue
        out.append(s)
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump_dir")
    ap.add_argument("out_tsv")
    ap.add_argument("--sidecar", default=None, help="出處 jsonl(給翻譯 subagent 當上下文)")
    a = ap.parse_args()

    seen = set()
    rows = []

    def add(res, tup, talker, s):
        key = norm_key(s)
        if not is_translatable(key) or key in seen:
            return
        seen.add(key)
        rows.append({"res": res, "tuple": tup, "talker": talker, "en": key,
                     "multiline": "\n" in s or "\r" in s})

    for f in sorted(glob.glob(os.path.join(a.dump_dir, "message.*")),
                    key=lambda p: int(p.rsplit(".", 1)[1])):
        for tup, talker, s in parse_message(f):
            add(os.path.basename(f), tup, talker, s)
    for f in sorted(glob.glob(os.path.join(a.dump_dir, "text.*")),
                    key=lambda p: int(p.rsplit(".", 1)[1])):
        for s in null_split(open(f, "rb").read()):
            add(os.path.basename(f), "", None, s)

    with open(a.out_tsv, "w", encoding="utf-8") as out:
        for r in rows:
            out.write(f"{r['en']}\t{r['en']}\n")
    if a.sidecar:
        with open(a.sidecar, "w", encoding="utf-8") as out:
            for r in rows:
                out.write(json.dumps(r, ensure_ascii=False) + "\n")

    total = sum(len(r["en"]) for r in rows)
    ml = sum(1 for r in rows if r["multiline"])
    print(f"抽出 {len(rows)} 則(精確 key,含多行敘事 {ml} 則),共 {total} 英文字元 → {a.out_tsv}")

if __name__ == "__main__":
    main()
