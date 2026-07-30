#!/usr/bin/env python3
"""掃描譯文用字：簡體字、中國大陸用語、非 Big5 字元。

Big5 只收繁體，所以「不在 Big5 的漢字」就是簡體字或罕用字的可靠訊號——
這比維護一份簡體字表更不會漏。注意要掃**原始譯文**，不要掃烘字型後的產物：
build_cht.py 有一張正規化表會靜默把一部分簡體字換掉，掃產物會看不到真實狀況。

用法: scan_zh.py <檔或目錄> [...]
      scan_zh.py translation/done/ comic/work/
"""
import sys, os, glob, json, collections

MAINLAND = {
    '視頻': '影片', '質量': '品質', '信息': '訊息', '軟件': '軟體', '硬件': '硬體',
    '網絡': '網路', '屏幕': '螢幕', '激光': '雷射', '默認': '預設', '菜單': '選單',
    '鼠標': '滑鼠', '打印': '列印', '內存': '記憶體', '磁盤': '磁碟',
    '牛逼': '厲害', '忽悠': '唬弄', '靠譜': '可靠', '給力': '夠力', '貓膩': '內情',
    '鋥亮': '亮晶晶', '咋': '怎麼', '瞅': '看',
}
# 註：「程序」（發射程序＝procedure）、「一會兒」都是正常繁中，實測是誤報，不列入。

def texts_of(path):
    """回傳 (行號提示, 文字) 的串列。tsv 取第二欄，json 取 boxes[].text，其餘整檔。"""
    ext = os.path.splitext(path)[1]
    out = []
    if ext == '.tsv':
        for n, line in enumerate(open(path, encoding='utf-8'), 1):
            p = line.rstrip('\n').split('\t')
            if len(p) >= 2:
                out.append((n, p[1]))
    elif ext == '.json':
        try:
            d = json.load(open(path, encoding='utf-8'))
        except Exception:
            return out
        for i, b in enumerate(d.get('boxes', []), 1):
            if b.get('text'):
                out.append((i, b['text']))
    else:
        for n, line in enumerate(open(path, encoding='utf-8'), 1):
            out.append((n, line.rstrip('\n')))
    return out

def main():
    args = sys.argv[1:] or ['translation/done/', 'comic/work/']
    files = []
    for a in args:
        if os.path.isdir(a):
            files += sorted(glob.glob(os.path.join(a, '*.tsv')) +
                            glob.glob(os.path.join(a, '*.json')))
        else:
            files.append(a)

    nonbig5 = collections.Counter()
    hits = []
    for f in files:
        for n, t in texts_of(f):
            for ch in t:
                if ord(ch) < 128:
                    continue
                try:
                    ch.encode('big5')
                except UnicodeEncodeError:
                    nonbig5[ch] += 1
                    hits.append(('非Big5', ch, f, n, t[:60]))
            for bad, good in MAINLAND.items():
                if bad in t:
                    hits.append(('中國用語', f'{bad}→{good}', f, n, t[:60]))

    print(f'掃了 {len(files)} 個檔')
    if not hits:
        print('乾淨，沒有發現問題。')
        return 0
    for kind, what, f, n, s in hits:
        print(f'[{kind}] {what}  {f}:{n}\n    {s}')
    print(f'\n共 {len(hits)} 處待處理')
    return 1

if __name__ == '__main__':
    sys.exit(main())
