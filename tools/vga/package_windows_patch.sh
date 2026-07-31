#!/usr/bin/env bash
# 打包 Windows **patch 版**（VGA / SCI1 軌）：scummvm.exe + DLL + 中文資料 + 啟動 .bat，
# 不含遊戲本體。這是要上 GitHub Release 的公開版本，
# [HARD] 絕不能混入任何遊戲資源或 MT-32 ROM。
#
# 用法: tools/package_windows_patch.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WIN="$ROOT/scummvm-win"
STAGE="$ROOT/build/win64-patch"; DIST="$ROOT/dist-patch"
# [HARD] Release 資產檔名只能用 ASCII（GitHub 會把中文字剝掉），包內檔名不受限。
NAME="SQ1-VGA-CHT-patch-win64"

[ -f "$WIN/scummvm.exe" ] || { echo "!! 找不到 $WIN/scummvm.exe，先跑 tools/build_windows.sh"; exit 1; }

rm -rf "$STAGE"; mkdir -p "$STAGE/cht-data" "$DIST"
cp "$WIN/scummvm.exe" "$STAGE/"
chmod u+w "$STAGE/scummvm.exe"
echo ">> strip scummvm.exe"
docker run --rm --name sq1-vgapkg-winstrip -v "$STAGE":/out sq1-mingw \
  bash -c 'x86_64-w64-mingw32-strip /out/scummvm.exe && ls -la /out/scummvm.exe'

echo ">> 取 mingw runtime DLL"
docker run --rm --name sq1-vgapkg-dll -v "$STAGE":/out sq1-mingw bash -c '
  for d in SDL2.dll libwinpthread-1.dll; do
    p=$(find /usr/x86_64-w64-mingw32 -name "$d" 2>/dev/null | head -1)
    [ -n "$p" ] && cp "$p" /out/ && echo "   $d"
  done'
docker run --rm --name sq1-vgapkg-dllown -v "$STAGE":/out sq1-mingw chown -R 1000:1000 /out

echo ">> 放入中文資料（不含遊戲資源、不含 ROM）"
for f in translation.tsv sq1_big5.fnt sq1_big5_hi.fnt sq1_title.ovl sq1_cels.dat; do
  cp "$ROOT/dist-cht/$f" "$STAGE/cht-data/"
done

# 啟動器：玩家把遊戲夾放成同層的 game\ 就自動開玩，否則開啟動器讓玩家自己 Add Game。
# 中文靠 --language=tw + --extrapath 指向包內 cht-data，玩家不必複製檔案。
# [HARD] 不預設 mt32（本包無 ROM，設了會先彈一次阻擋框再退回 AdLib）。
cat > "$STAGE/新宇宙傳奇I VGA-繁中版.bat" <<'BAT'
@echo off
chcp 950 >nul
cd /d "%~dp0"
if exist "%~dp0game\RESOURCE.MAP" (
  start "" "%~dp0scummvm.exe" --language=tw --extrapath="%~dp0cht-data" --path="%~dp0game" --auto-detect
) else (
  start "" "%~dp0scummvm.exe" --language=tw --extrapath="%~dp0cht-data"
)
BAT

cat > "$STAGE/讀我.txt" <<'TXT'
新宇宙傳奇I（1991 VGA 重製版） — 繁體中文化（Windows，patch 版）

本包只含中文化後的 ScummVM 引擎與中文資料，不含遊戲本體，請自備遊戲檔案
（1991 年 Sierra 發行的 VGA 版，資料夾內應有 RESOURCE.MAP、RESOURCE.000~003 等檔）。

兩種玩法，擇一：

【最簡單】把你的遊戲資料夾複製到本包裡、命名為 game，
          然後雙擊「新宇宙傳奇I VGA-繁中版.bat」，會直接開始遊戲。

【一般】  直接雙擊「新宇宙傳奇I VGA-繁中版.bat」開啟 ScummVM 啟動器，
          按 Add Game 選擇你的遊戲資料夾加入，再從清單啟動。

中文會自動生效——中文資料已放在本包的 cht-data 資料夾，引擎啟動時自動載入，
你不需要把任何檔案複製進遊戲資料夾。

音樂：引擎已內建 Roland MT-32 模擬器（音色遠優於 AdLib），但 MT-32 ROM 有版權、
不隨包分發。若要使用，請自備 MT32_CONTROL.ROM 與 MT32_PCM.ROM 放進 cht-data 資料夾，
再於遊戲設定的音效選項選擇 Roland MT-32。

操作沿用原版：滑鼠點畫面上方的圖示列切換動作（走路／看／拿／用／說話），再點畫面互動。
F5 存檔、F7 讀檔。

本中文化不修改遊戲原始資源，是在 ScummVM 引擎層做內容比對替換。
TXT

OUT="$DIST/$NAME.zip"; rm -f "$OUT"
( cd "$STAGE" && zip -qr "$OUT" . )
echo ">> 完成: $OUT ($(du -h "$OUT" | cut -f1))"
