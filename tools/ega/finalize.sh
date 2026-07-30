#!/usr/bin/env bash
# 合併翻譯批次 → 驗證 → 用字掃描 → 烘 Big5 字型 + runtime translation.tsv → 部署到 game/
#
# 用法: tools/finalize.sh [譯文目錄]     （在 workplace/ 下執行）
#   預設 translation/done2（重審後的版本）；沒有就退回 translation/done。
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-}"
if [ -z "$SRC" ]; then
  if [ -d translation/done2 ] && [ -n "$(ls translation/done2/*.tsv 2>/dev/null)" ]; then
    SRC=translation/done2
  else
    SRC=translation/done
  fi
fi
echo ">> 譯文來源：$SRC"

echo ">> 1. 逐批驗證（行數、key 逐 byte、控制序列、長度比）"
fail=0
for b in translation/batch/*.tsv; do
  n="$(basename "$b")"
  d="$SRC/$n"
  if [ ! -f "$d" ]; then echo "   缺 $d"; fail=1; continue; fi
  python3 tools/validate_batch.py "$b" "$d" || fail=1
done
[ "$fail" -eq 0 ] || { echo "!! 驗證未過，先修批次再跑"; exit 1; }

echo ">> 2. 用字掃描（簡體字／中國用語／非 Big5）"
python3 tools/scan_zh.py "$SRC" || echo "   （上列項目請確認過再繼續）"

echo ">> 3. 合併成 translation/sq2-full.tsv"
cat "$SRC"/*.tsv > translation/sq2-full.tsv
wc -l translation/sq2-full.tsv

echo ">> 4. 譯名一致性掃描"
python3 tools/scan_consistency.py translation/sq2-full.tsv | tail -20

echo ">> 5. 同步引擎硬寫 UI 用字（字型只從譯文取字，硬寫字串的字得另外餵，否則缺字）"
if [ -f scummvm-src/engines/agi/systemui.cpp ]; then
  python3 tools/extract_engine_ui_chars.py
else
  echo "   （沒有 scummvm-src，沿用版控內的 translation/engine_ui_chars.txt）"
fi

echo ">> 6. 烘字型 + runtime tsv -> dist-cht/"
mkdir -p dist-cht
python3 tools/build_cht.py translation/sq2-full.tsv dist-cht --size 16 \
  --corrections translation/corrections.tsv \
  --extra-chars translation/engine_ui_chars.txt

echo ">> 7. 部署到 game/"
cp dist-cht/translation.tsv dist-cht/sq1_big5.fnt game/
[ -f dist-cht/sq1_title.ovl ] && cp dist-cht/sq1_title.ovl game/ || true
ls -la game/translation.tsv game/sq1_big5.fnt

echo ">> 完成。接著跑 headless 驗證："
echo "   docker run --rm --name sq1-cht-capture -v \$PWD/scummvm-src:/src -v \$PWD/game:/game \\"
echo "     -v \$PWD/out:/out -v \$PWD/tools:/tools sq1-capture bash /tools/capture.sh"
