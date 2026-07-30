#!/usr/bin/env python3
"""把 AGI skeleton 切成翻譯批次（給 subagent fan-out）。

規則：
- 跳過「不含任何英文單字」的純控制碼行（如 %m8"%w1"、%v81,%v82）——這些交由引擎原樣輸出。
- 其餘全部入批（含帶 %s/%v/%m/%w 控制序列的句子，翻譯時要原樣保留控制序列）。
- 輸出 translation/batch/NN.tsv，格式 <英文原文>\t<英文原文>（subagent 只改第二欄）。

用法: prep_batches.py <skeleton.tsv> <out_dir> [--size 130]
"""
import re, sys, os, argparse

def has_english_word(s):
    # 去掉控制序列後還剩至少一個 2 字母以上的英文詞才算需要翻譯
    stripped = re.sub(r'%[a-z]\d*|%\d+', ' ', s)
    return bool(re.search(r'[A-Za-z]{2,}', stripped))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('skeleton'); ap.add_argument('out_dir')
    ap.add_argument('--size', type=int, default=130)
    a = ap.parse_args()

    rows, skipped = [], []
    for line in open(a.skeleton, encoding='utf-8'):
        parts = line.rstrip('\n').split('\t')
        if len(parts) < 2 or not parts[0]:
            continue
        (rows if has_english_word(parts[0]) else skipped).append(parts[0])

    os.makedirs(a.out_dir, exist_ok=True)
    n = 0
    for i in range(0, len(rows), a.size):
        n += 1
        with open(os.path.join(a.out_dir, f'{n:02d}.tsv'), 'w', encoding='utf-8') as f:
            for k in rows[i:i+a.size]:
                f.write(f'{k}\t{k}\n')
    with open(os.path.join(a.out_dir, '..', 'skipped_control_only.tsv'), 'w', encoding='utf-8') as f:
        for k in skipped:
            f.write(f'{k}\t{k}\n')
    print(f'待翻 {len(rows)} 則 -> {n} 批（每批 {a.size}）；純控制碼跳過 {len(skipped)} 則')

if __name__ == '__main__':
    main()
