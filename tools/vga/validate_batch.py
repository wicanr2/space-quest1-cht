#!/usr/bin/env python3
"""驗證翻譯批次：行數、key 逐 byte 一致、控制序列數量、長度比、非 Big5 字。

用法: validate_batch.py <batch/NN.tsv> <done/NN.tsv>
退出碼非 0 表示有 FATAL 級問題（key 或控制序列不符）。
"""
import sys, re, unicodedata

CTRL = re.compile(r'%[a-zA-Z]\d*|\\n|\\t')

def ctrl_ok(src, dst):
    """SCI 軌的控制序列規則，對齊引擎 kstring.cpp 的 sciChtMapFormatSpecs()。

    引擎允許譯文「少用」原文的規格（英文複數標記 %s 中文沒有對應語法），做法是把
    譯文的規格序列當成原文的**有序子序列**去對應參數。但 %s 是直接讀 argv 的，
    位移了會崩 → 引擎只在「譯文完全不含 %s」時才接受非等同的子序列。
    這裡把同一條規則搬過來，否則驗證器會比引擎嚴，把合法的刪 %s 誤報成 FATAL。

    回傳 (是否合法, 說明字串)；說明非空但合法時只印 INFO。
    """
    if src == dst:
        return True, ''
    # 譯文規格必須是原文規格的有序子序列
    it = iter(src)
    if not all(any(s == d for s in it) for d in dst):
        return False, '譯文用了原文沒有的規格或順序錯亂'
    if '%s' in dst:
        return False, '刪規格後仍殘留 %s，引擎會退回英文'
    return True, '譯文少用了規格（引擎會重映射參數，合法）'


def big5_ok(s):
    bad = []
    for ch in s:
        if ord(ch) < 128:
            continue
        try:
            ch.encode('big5')
        except UnicodeEncodeError:
            bad.append(ch)
    return bad

def main():
    src, dst = sys.argv[1], sys.argv[2]
    a = [l.rstrip('\n') for l in open(src, encoding='utf-8')]
    b = [l.rstrip('\n') for l in open(dst, encoding='utf-8')]
    fatal = warn = 0
    if len(a) != len(b):
        print(f'FATAL 行數不符: 輸入 {len(a)} vs 輸出 {len(b)}'); sys.exit(1)
    for i, (la, lb) in enumerate(zip(a, b), 1):
        ka = la.split('\t')[0]
        parts = lb.split('\t')
        if len(parts) < 2:
            print(f'FATAL {i}: 缺 TAB 或譯文欄'); fatal += 1; continue
        kb, vb = parts[0], parts[1]
        if ka != kb:
            print(f'FATAL {i}: key 被改動\n  期望: {ka!r}\n  實得: {kb!r}'); fatal += 1; continue
        ca, cb = CTRL.findall(ka), CTRL.findall(vb)
        ok, why = ctrl_ok(ca, cb)
        if not ok:
            print(f'FATAL {i}: 控制序列不符（{why}）{sorted(ca)} -> {sorted(cb)}\n  {ka[:70]!r}'); fatal += 1
        elif why:
            print(f'INFO  {i}: {why} {sorted(ca)} -> {sorted(cb)}\n  {ka[:70]!r}')
        bad = big5_ok(vb)
        if bad:
            print(f'WARN  {i}: 非 Big5 字 {bad} -> {vb[:50]!r}'); warn += 1
        # 長度比：以顯示欄計（中文 2 欄）
        cols = sum(2 if unicodedata.east_asian_width(c) in 'WF' else 1 for c in vb)
        if len(ka) >= 20 and (cols > len(ka) * 1.35 or cols < len(ka) * 0.35):
            print(f'WARN  {i}: 長度比異常 原文 {len(ka)} 欄 -> 譯文 {cols} 欄\n  EN: {ka[:70]!r}\n  ZH: {vb[:50]!r}'); warn += 1
        if ka.endswith(' ') and not vb.endswith(' '):
            print(f'WARN  {i}: 尾端空白遺失 {ka!r}'); warn += 1
    print(f'--- {dst}: {len(b)} 行, FATAL {fatal}, WARN {warn}')
    sys.exit(1 if fatal else 0)

if __name__ == '__main__':
    main()
