#!/usr/bin/env python3
"""合併後的譯名一致性 / 用字掃描（獨立 subagent 翻譯必然會漂移，這是最後防線）。

檢查三類：
1. 譯名表裡的英文詞出現在原文時，譯文有沒有用約定譯名。
2. 已知的漂移別名（同一專有名詞的其他寫法）。
3. 中國大陸用語與非 Big5 字。

用法: scan_consistency.py <merged.tsv>
"""
import sys, re

# 英文詞 -> (約定譯名, [不該出現的別名])
NAMES = {
    'Vohaul':        ('沃霍爾', ['沃豪', '佛霍', '沃浩', '沃霍尔']),
    'Sludge':        ('史拉吉', ['斯拉吉', '史萊吉', '汙泥']),
    'Xenon':         ('氙星',   ['澤農', '芝諾', '贊農', '氙農']),
    'Labion':        ('拉比恩', ['拉比翁', '萊比恩', '勞比恩']),
    'Star Generator':('星辰產生器', ['造星機', '恆星產生器', '星球產生器']),
    'Terror Beast':  ('恐懼獸', ['恐怖獸', '驚懼獸']),
    'Sarien':        ('沙利安', ['薩利安', '沙里安', '賽利安']),
    'Monolith Burger':('巨石漢堡', ['莫諾利斯漢堡', '獨石漢堡']),
    'Andromeda':     ('仙女座', ['安卓美達', '仙女星座']),
    # 系列共通貨幣，SQ3/SQ4 都用「太空幣」。音譯是本專案初版的錯，列進 wrong 才掃得出來。
    'buckazoid':     ('太空幣', ['巴克佐幣', '巴克佐德', '巴克幣', '巴卡佐']),
}

# 中國大陸用語 -> 台灣用語
MAINLAND = {
    '視頻': '影片', '質量': '品質', '信息': '訊息', '軟件': '軟體', '硬件': '硬體',
    '網絡': '網路', '屏幕': '螢幕', '激光': '雷射', '默認': '預設', '菜單': '選單',
    '鼠標': '滑鼠', '智能': '智慧', '打印': '列印', '數據': '資料',
    '內存': '記憶體', '磁盤': '磁碟',
}
# 註：「程序」「一會兒」曾被列入黑名單，實測皆為誤報已移除——
# 「發射程序／上升程序」是 procedure 的正常繁中用法（非 program），
# 「過了一會兒」也是標準繁中。規則寧可漏報也別誤導後續判斷。

def main():
    path = sys.argv[1]
    issues = 0
    rows = []
    for i, line in enumerate(open(path, encoding='utf-8'), 1):
        parts = line.rstrip('\n').split('\t')
        if len(parts) >= 2:
            rows.append((i, parts[0], parts[1]))

    print('=== 1. 譯名遵循 ===')
    for en, (zh, aliases) in NAMES.items():
        miss, drift = [], []
        for i, k, v in rows:
            if re.search(re.escape(en), k, re.I) and k != v:
                if zh not in v:
                    miss.append((i, k[:60], v[:60]))
                for a in aliases:
                    if a in v:
                        drift.append((i, a, v[:60]))
        # 全表掃別名（原文沒有該英文詞也可能誤用）
        for i, k, v in rows:
            for a in aliases:
                if a in v and (i, a, v[:60]) not in drift:
                    drift.append((i, a, v[:60]))
        if miss:
            print(f'[{en} → {zh}] 原文含此詞但譯文未用約定譯名 {len(miss)} 則：')
            for i, k, v in miss[:5]:
                print(f'   L{i}: {k}\n        → {v}')
            issues += len(miss)
        if drift:
            print(f'[{en} → {zh}] 出現漂移別名 {len(drift)} 則：')
            for i, a, v in drift[:5]:
                print(f'   L{i}: 「{a}」 in {v}')
            issues += len(drift)

    print('\n=== 2. 中國大陸用語 ===')
    for bad, good in MAINLAND.items():
        hits = [(i, v) for i, k, v in rows if bad in v]
        if hits:
            print(f'「{bad}」→ 應為「{good}」，{len(hits)} 則：')
            for i, v in hits[:3]:
                print(f'   L{i}: {v[:70]}')
            issues += len(hits)

    print('\n=== 3. 非 Big5 字 ===')
    bad_chars = {}
    for i, k, v in rows:
        for ch in v:
            if ord(ch) < 128:
                continue
            try:
                ch.encode('big5')
            except UnicodeEncodeError:
                bad_chars.setdefault(ch, []).append((i, v[:60]))
    for ch, hits in bad_chars.items():
        print(f'「{ch}」×{len(hits)}：')
        for i, v in hits[:3]:
            print(f'   L{i}: {v}')
        issues += len(hits)

    print(f'\n--- 共 {len(rows)} 則，發現 {issues} 個待處理項')

if __name__ == '__main__':
    main()
