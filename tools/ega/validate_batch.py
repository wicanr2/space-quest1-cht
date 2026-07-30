#!/usr/bin/env python3
"""驗證翻譯批次：行數、key 逐 byte 一致、控制序列數量、長度比、非 Big5 字。

用法: validate_batch.py <batch/NN.tsv> <done/NN.tsv>
退出碼非 0 表示有 FATAL 級問題（key 或控制序列不符）。
"""
import sys, re, unicodedata

CTRL = re.compile(r'%[a-zA-Z]\d*|\\n|\\t')

def ctrl_ok(src, dst):
    """AGI 軌的控制序列規則：**逐一嚴格相符**（與 SCI 軌不同）。

    SCI 的 kFormat 有子序列對應可以少用規格；AGI 的 stringPrintf 沒有這種機制，
    %s1/%v81/%m23/%w1/%g/%d 少一個或多一個都會讓那一則顯示錯亂。
    """
    if sorted(src) == sorted(dst):
        return True, ''
    return False, 'AGI 控制序列必須與原文完全相同（不可增刪）'


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
