#!/usr/bin/env python3
"""從 scummvm-src 的 systemui.cpp 抽出「引擎硬寫的中文系統 UI 字串」，產生 translation/engine_ui_chars.txt。

為什麼需要這支：
    build_cht.py 烘 Big5 字型時，字集是從**譯文**取的。但道具欄標題、暫停、存讀檔提示這些
    是引擎裡硬寫的 Big5 字面值，不走 translation 表——它們用到的字如果剛好沒在任何一則譯文
    出現過，字型裡就沒有那個字，實機會顯示成空白，而且不會有任何警告。

    實際踩到：「ScummVM 存檔目錄中」的「錄」、「用方向鍵選擇…」的「擇」、「描述為：」的
    「描」「述」、「載入存檔時發生錯誤」的「誤」，五個字全部缺字，畫面上就是幾個洞。

用法（workplace/ 下）：
    python3 tools/extract_engine_ui_chars.py            # 寫入 translation/engine_ui_chars.txt
    python3 tools/extract_engine_ui_chars.py --check    # 只檢查檔案是否過期（CI/收尾用）

改了 systemui.cpp 的中文字串之後要重跑這支，再重跑 finalize.sh 烘字型。
"""
import argparse
import re
import sys

SRC = "scummvm-src/engines/agi/systemui.cpp"
OUT = "translation/engine_ui_chars.txt"
MARKER = "if (_gfx->chtEnabled()) {"


def unescape(lit: str) -> bytes:
    """把 C 字面值內容還原成 bytes（處理 \\xNN 與常見跳脫）。"""
    out = bytearray()
    i = 0
    simple = {"n": b"\n", "t": b"\t", "r": b"\r", "\\": b"\\", '"': b'"', "0": b"\0"}
    while i < len(lit):
        if lit[i] == "\\" and i + 1 < len(lit):
            c = lit[i + 1]
            if c == "x":
                out += bytes([int(lit[i + 2:i + 4], 16)])
                i += 4
                continue
            out += simple.get(c, c.encode())
            i += 2
            continue
        out += lit[i].encode("latin-1")
        i += 1
    return bytes(out)


def extract(path: str) -> str:
    src = open(path, encoding="latin-1").read()
    if MARKER not in src:
        sys.exit(f"!! {path} 裡找不到中文區塊標記 {MARKER!r}")
    # 取 chtEnabled 區塊：從標記到該區塊結尾的 "\n\t}\n"
    block = src.split(MARKER, 1)[1].split("\n\t}\n", 1)[0]
    raw = b"".join(unescape(m) for m in re.findall(r'"((?:[^"\\]|\\.)*)"', block))
    return raw.decode("big5", errors="replace")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=SRC)
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--check", action="store_true", help="只比對，不寫檔；過期則以非 0 結束")
    a = ap.parse_args()

    text = extract(a.src)
    chars = sorted({ch for ch in text if ord(ch) > 127 and not ch.isspace()})
    body = ("# 引擎硬寫的系統 UI 中文用字（tools/extract_engine_ui_chars.py 自動產生，勿手改）\n"
            "# 來源：" + a.src + " 的 chtEnabled 區塊\n"
            "# build_cht.py 會把這些字一併烘進 Big5 字型，避免硬寫字串缺字。\n"
            + "".join(chars) + "\n")

    if a.check:
        try:
            cur = open(a.out, encoding="utf-8").read()
        except FileNotFoundError:
            sys.exit(f"!! 缺 {a.out}，請跑 tools/extract_engine_ui_chars.py")
        if cur != body:
            sys.exit(f"!! {a.out} 與 {a.src} 不同步，請重跑 tools/extract_engine_ui_chars.py 再烘字型")
        print(f"{a.out} 與引擎同步（{len(chars)} 字）")
        return

    open(a.out, "w", encoding="utf-8").write(body)
    print(f"{len(chars)} 個引擎 UI 用字 → {a.out}")


if __name__ == "__main__":
    main()
