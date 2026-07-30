#!/usr/bin/env bash
# 把中文資料注入 CI 產出的 engine-only ScummVM.app，產出最終 macOS 交付物。
#
# 用法: tools/package_macos_data.sh <ega|vga> <engine.tar.gz> <輸出目錄>
#
# [HARD] 注入清單要含 dist-cht/<track>/ 底下的**全部**檔案。
#   KQ4 曾漏掉標題 .ovl，macOS 版連中文標題都不顯示。凡 dist-cht 有的都要進去。
# [HARD] 改動已簽名的 .app 會讓簽章失效 → 移除 _CodeSignature（「未簽」勝過「壞簽」），
#   並附 修復-macOS.command 讓使用者在自己的 Mac 上 xattr -cr + ad-hoc 重簽。
# [HARD] patch 版不附 MT-32 ROM、也不設 mt32 為預設驅動——無 ROM 又設 mt32 會彈一次
#   阻擋框再回退 AdLib。只開能力，讓玩家自備 ROM 後在音效選項裡選。
set -euo pipefail
TRACK="${1:?用法: package_macos_data.sh <ega|vga> <engine.tar.gz> <outdir>}"
TGZ="${2:?}"; OUT="${3:?}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DATA="$HERE/dist-cht/$TRACK"
[ -d "$DATA" ] || { echo "!! 找不到 $DATA"; exit 1; }

rm -rf "$OUT"; mkdir -p "$OUT"
tar xzf "$TGZ" -C "$OUT"
APP="$OUT/ScummVM.app"
[ -d "$APP" ] || { echo "!! tar 內沒有 ScummVM.app"; exit 1; }

RES="$APP/Contents/Resources/cht-data"
mkdir -p "$RES"
cp -v "$DATA"/* "$RES/"

# 中文靠 --extrapath 帶進搜尋路徑；EGA(AGI) 另外**不可**帶 --language（會進不去遊戲）。
cat > "$OUT/啟動-繁體中文.command" <<'LAUNCH'
#!/bin/bash
cd "$(dirname "$0")"
APP="$PWD/ScummVM.app"
open -a "$APP" --args --extrapath="$APP/Contents/Resources/cht-data"
LAUNCH
chmod +x "$OUT/啟動-繁體中文.command"

cat > "$OUT/修復-macOS.command" <<'FIX'
#!/bin/bash
# macOS 會給從網路下載的檔案加上隔離屬性，加上本包為了注入中文資料而移除了原簽章，
# 直接開啟會被 Gatekeeper 擋下。這支腳本清掉隔離屬性並重新 ad-hoc 簽章。
cd "$(dirname "$0")"
xattr -cr ScummVM.app
codesign --force --deep --sign - ScummVM.app
echo "完成，可以開啟 ScummVM.app 了。"
FIX
chmod +x "$OUT/修復-macOS.command"

# 改過內容 → 原簽章失效，移除比留著壞簽好
rm -rf "$APP/Contents/_CodeSignature"

( cd "$OUT" && tar czf "SQ1-${TRACK^^}-CHT-patch-macos-universal.tar.gz" ScummVM.app 啟動-繁體中文.command 修復-macOS.command )
echo ">> 完成: $OUT/SQ1-${TRACK^^}-CHT-patch-macos-universal.tar.gz"
ls -la "$OUT"
