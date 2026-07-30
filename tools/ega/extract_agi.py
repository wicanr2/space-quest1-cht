#!/usr/bin/env python3
"""抽取 AGI 遊戲 LOGIC 資源內的訊息字串（供中文化建 translation.tsv 的 key）。

AGI (v2) 格式：
- LOGDIR：每個 logic 一筆 3-byte 條目 = 高 4 bit vol 號 + 20 bit 在 VOL 內的 offset。
- VOL.n：resource 在 offset 處有 5-byte header（0x12 0x34、vol、2-byte LE 長度），其後為 LOGIC 資料。
- LOGIC：前 2 byte(LE) = message section 相對 code 之後的 offset。message section：
    [0]=訊息數 numMessages, [1..2]=section 總長(LE),
    接著 numMessages 個 2-byte(LE) offset（相對 section 起點+1），
    再來是字串資料，全部與 "Avis Durgan" 循環 XOR 加密（offset 0 的字串不加密判斷用長度）。

用法: extract_agi.py <game_dir> [--tsv out.tsv]
輸出：每則訊息一行 <logic>.<msgno>\t<english>（\n/\t/\\ escape），或 --tsv 輸出 skeleton（english\tenglish）。
"""
import sys, os, struct, argparse

AVIS = b"Avis Durgan"

def find_file(game_dir, *names):
    # AGI 檔名大小寫不定
    entries = {e.lower(): e for e in os.listdir(game_dir)}
    for n in names:
        if n.lower() in entries:
            return os.path.join(game_dir, entries[n.lower()])
    return None

def read_logdir(game_dir):
    p = find_file(game_dir, "LOGDIR")
    data = open(p, "rb").read()
    out = []
    for i in range(0, len(data), 3):
        b = data[i:i+3]
        if len(b) < 3:
            break
        if b == b"\xff\xff\xff":
            out.append(None); continue
        vol = b[0] >> 4
        off = ((b[0] & 0x0F) << 16) | (b[1] << 8) | b[2]
        out.append((vol, off))
    return out

def read_resource(game_dir, vol, off):
    p = find_file(game_dir, f"VOL.{vol}")
    if not p:
        return None
    with open(p, "rb") as f:
        f.seek(off)
        hdr = f.read(5)
        if len(hdr) < 5 or hdr[0] != 0x12 or hdr[1] != 0x34:
            return None
        length = hdr[3] | (hdr[4] << 8)
        return f.read(length)

def unescape_key_for_tsv(s):
    return s.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n")

def extract_messages(logic):
    # 依 ScummVM engines/agi/logic.cpp decodeLogic：
    #   bytecodeSize = LE16(data[0..1]); messageSectionPos = 2 + bytecodeSize
    #   messageCount = data[msgPos]; messagesSize = LE16(data[msgPos+1..2])
    #   stringOffsetsPos = msgPos + 3; stringsPos = stringOffsetsPos + 2*count
    #   stringsSize = messagesSize - 2 - 2*count
    #   整塊 strings 連續 XOR "Avis Durgan"（pointer table 不加密）；offset 相對 msgPos+1
    if len(logic) < 2:
        return []
    bytecode_size = logic[0] | (logic[1] << 8)
    pos = 2 + bytecode_size
    if pos + 3 > len(logic):
        return []
    num = logic[pos]
    messages_size = logic[pos + 1] | (logic[pos + 2] << 8)
    string_offsets_pos = pos + 3
    strings_pos = string_offsets_pos + 2 * num
    strings_size = messages_size - 2 - 2 * num
    decl_start = pos + 1

    data = bytearray(logic)
    for i in range(strings_size):
        if strings_pos + i < len(data):
            data[strings_pos + i] ^= AVIS[i % len(AVIS)]

    msgs = []
    for i in range(num):
        po = string_offsets_pos + i * 2
        if po + 2 > len(logic):
            break
        rel = logic[po] | (logic[po + 1] << 8)  # pointer table 未加密
        if rel == 0:
            msgs.append(None); continue
        start = decl_start + rel
        raw = bytearray()
        j = start
        while j < len(data) and data[j] != 0:
            raw.append(data[j]); j += 1
        msgs.append(raw.decode("latin-1", "replace"))
    return msgs

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game_dir")
    ap.add_argument("--tsv")
    ap.add_argument("--min-len", type=int, default=1)
    args = ap.parse_args()

    logdir = read_logdir(args.game_dir)
    rows = []
    seen = set()
    for lidx, ent in enumerate(logdir):
        if ent is None:
            continue
        res = read_resource(args.game_dir, ent[0], ent[1])
        if not res:
            continue
        for midx, m in enumerate(extract_messages(res)):
            if not m or len(m) < args.min_len:
                continue
            key = unescape_key_for_tsv(m)
            if args.tsv:
                if key in seen:
                    continue
                seen.add(key)
                rows.append(f"{key}\t{key}")
            else:
                rows.append(f"L{lidx}.{midx}\t{key}")

    if args.tsv:
        with open(args.tsv, "w", encoding="utf-8") as f:
            f.write("\n".join(rows) + "\n")
        print(f"寫出 {len(rows)} 則唯一訊息 -> {args.tsv}", file=sys.stderr)
    else:
        print("\n".join(rows))
        print(f"# 共 {len(rows)} 則", file=sys.stderr)

if __name__ == "__main__":
    main()
