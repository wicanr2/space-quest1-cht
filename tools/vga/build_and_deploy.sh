#!/usr/bin/env bash
# VGA(SCI1) 軌一鍵：合併批次譯文 → 收斂譯名 → 烘倚天 Big5 字型 + Big5 runtime tsv → 部署到 game/ 與 dist-cht/。
#
# 字形走**倚天中文系統原生點陣字**(ETEN 3.53)，不是 TTF rasterize：
#   sq1_big5.fnt     16×15  低解析路徑
#   sq1_big5_hi.fnt  24×24  hi-res(640×400 display 直繪)
# 引擎端常數見 engines/sci/graphics/fontchinese.cpp(kBig5Width=12 排版格 / kHiW=kHiH=24)。
#
# [HARD] Python 一律走 docker，不污染系統環境；容器一律 --name sq1-* 且用完即拋。
set -euo pipefail
WP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$WP"

echo ">> 1) 合併批次 → translation/translation.tsv"
python3 tools/merge_translations.py \
  translation/skeleton.tsv \
  translation/translation.tsv \
  translation/done/*.tsv

echo ">> 1b) 依英文 key 圈定的修正（converge 看不到英文，修不了「兩個道具撞同一個中文名」）"
python3 tools/apply_key_scoped_fixes.py translation/key_scoped_fixes.tsv \
  translation/translation.tsv translation/_keyfixed.tsv
mv translation/_keyfixed.tsv translation/translation.tsv

echo ">> 2) 合併收斂表與非 Big5 修正 → 建構期單一 corrections"
#   converge.tsv = 譯名漂移收斂(錯寫法→正寫法)；corrections.tsv = 非 Big5 字替換。
#   兩者機制相同(子字串替換)，但來源與維護理由不同，所以分開存、建構時才併。
#   [HARD] 要按「錯誤寫法長度遞減」排序再套用。子字串替換是循序的，短規則先命中會把
#   長規則的目標吃掉：例如 `老虎機→吃角子老虎` 若先跑，`死亡吃角子老虎機` 會變成
#   `死亡吃角子吃角子老虎`。排序後長的先替換，短的就再也命中不到。
cat translation/converge.tsv translation/corrections.tsv 2>/dev/null \
  | grep -v '^#' | grep -P '\t' \
  | awk -F'\t' '{print length($1)"\t"$0}' | sort -rn -k1,1 | cut -f2- \
  > translation/_merged_corrections.tsv || true

echo ">> 3) docker 內烘字型 + Big5 runtime tsv"
docker run --rm --name sq1-vga-fontbuild -v "$WP":/w -w /w python:3.12-slim bash -c '
  set -e
  pip install -q --root-user-action=ignore pillow >/dev/null 2>&1 || true
  mkdir -p dist-cht
  python tools/build_cht.py translation/translation.tsv dist-cht --no-font \
      --corrections translation/_merged_corrections.tsv
  python tools/build_eten_font.py translation/translation.tsv dist-cht --prefix sq1 \
      --corrections translation/_merged_corrections.tsv
  chown -R 1000:1000 /w/dist-cht
'

echo ">> 4) 部署到 game/"
cp dist-cht/translation.tsv dist-cht/sq1_big5.fnt dist-cht/sq1_big5_hi.fnt game/
[ -f dist-cht/sq1_title.ovl ] && cp dist-cht/sq1_title.ovl game/ || echo "   (尚無標題疊圖，略過)"

echo "== 部署完成 =="
ls -la game/translation.tsv game/sq1_big5.fnt game/sq1_big5_hi.fnt
