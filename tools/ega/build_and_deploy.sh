#!/usr/bin/env bash
# EGA(AGI) 軌一鍵：合併批次譯文 → 重算置中 → 收斂譯名 → 烘倚天 Big5 字型 + Big5 runtime tsv → 部署。
#
# 與 VGA 軌的三個差別：
#   1. 多一道 recenter_cjk：AGI 用行首空白手動置中，中文寬度不同要重算。
#   2. 多一道 engine_ui_chars：systemui.cpp 裡硬寫的中文不走 translation 表，
#      字集若沒涵蓋就**缺字且無警告**（畫面上是空白洞）。必須另外餵進字型。
#   3. 合併順序：pretranslated.tsv（從 VGA 複用的權威譯文）放最後，覆蓋同 key 的批次譯文。
#
# [HARD] Python 一律走 docker；容器一律 --name sq1-* 用完即拋。
set -euo pipefail
WP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$WP"

echo ">> 1) 抽引擎硬寫中文字（缺這步會缺字且沒有任何警告）"
python3 tools/extract_engine_ui_chars.py || echo "   (systemui.cpp 尚無中文分支，略過)"

echo ">> 2) 合併批次 → translation/translation.tsv"
python3 tools/merge_translations.py \
  translation/skeleton.tsv \
  translation/_merged.tsv \
  translation/done/*.tsv \
  translation/pretranslated.tsv

echo ">> 3) 重算行首置中空白（AGI 手動置中，中文 2 欄）"
python3 tools/recenter_cjk.py translation/_merged.tsv translation/translation.tsv

echo ">> 4) 收斂表 + 非 Big5 修正（按錯誤寫法長度遞減排序，避免短規則先吃掉長規則）"
cat translation/converge.tsv translation/corrections.tsv 2>/dev/null \
  | grep -v '^#' | grep -P '\t' \
  | awk -F'\t' '{print length($1)"\t"$0}' | sort -rn -k1,1 | cut -f2- \
  > translation/_merged_corrections.tsv || true

echo ">> 5) 字型字集 = 譯文用字 ∪ 引擎硬寫 UI 用字"
cp translation/translation.tsv translation/_fontsrc.tsv
if [ -s translation/engine_ui_chars.txt ]; then
  printf "__ENGINE_UI_CHARS__\t%s\n" "$(grep -v "^#" translation/engine_ui_chars.txt | tr -d "\n")" \
    >> translation/_fontsrc.tsv
fi

echo ">> 6) docker 內烘字型 + Big5 runtime tsv"
docker run --rm --name sq1-ega-fontbuild -v "$WP":/w -w /w python:3.12-slim bash -c '
  set -e
  pip install -q --root-user-action=ignore pillow >/dev/null 2>&1 || true
  mkdir -p dist-cht
  python tools/build_cht.py translation/translation.tsv dist-cht --no-font \
      --corrections translation/_merged_corrections.tsv
  python tools/build_eten_font.py translation/_fontsrc.tsv dist-cht --prefix sq1 --lo-pad-height 16 \
      --corrections translation/_merged_corrections.tsv
  chown -R 1000:1000 /w/dist-cht
'

echo ">> 7) 部署到 game/"
cp dist-cht/translation.tsv dist-cht/sq1_big5.fnt game/
[ -f dist-cht/sq1_big5_hi.fnt ] && cp dist-cht/sq1_big5_hi.fnt game/ || true
[ -f dist-cht/sq1_title.ovl ] && cp dist-cht/sq1_title.ovl game/ || echo "   (尚無標題疊圖，略過)"

echo "== 部署完成 =="
ls -la game/translation.tsv game/sq1_big5.fnt
