#!/usr/bin/env bash
# 打包 Windows full 完整版：scummvm.exe + DLL + 內嵌 game/ + MT-32 ROM + 啟動 .bat。
# 產物放 dist-all/（gitignore），**不上 GitHub**——內含遊戲本體與有版權的 MT-32 ROM。
#
# 用法: tools/package_windows_full.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MT32_ROM_SRC="${MT32_ROM_SRC:-/home/anr2/cht/mt32}"
WIN="$ROOT/scummvm-win"
STAGE="$ROOT/build/win64-full"; DIST="$ROOT/dist-all"
NAME="宇宙傳奇I EGA-繁中-完整版-win64"

[ -f "$WIN/scummvm.exe" ] || { echo "!! 找不到 $WIN/scummvm.exe，先跑 tools/build_windows.sh"; exit 1; }

rm -rf "$STAGE"; mkdir -p "$STAGE/game" "$DIST"
cp "$WIN/scummvm.exe" "$STAGE/"
echo ">> strip scummvm.exe（未 strip 約 63MB，含大量除錯符號）"
docker run --rm --name sq1-pkg-winstrip -v "$STAGE":/out sq1-mingw \
  bash -c 'x86_64-w64-mingw32-strip /out/scummvm.exe && ls -la /out/scummvm.exe'

echo ">> 取 mingw runtime DLL"
docker run --rm --name sq1-pkg-dll -v "$STAGE":/out sq1-mingw bash -c '
  for d in SDL2.dll libwinpthread-1.dll; do
    p=$(find /usr/x86_64-w64-mingw32 -name "$d" 2>/dev/null | head -1)
    [ -n "$p" ] && cp "$p" /out/ && echo "   $d"
  done'
docker run --rm --name sq1-pkg-dllown -v "$STAGE":/out sq1-mingw chown -R 1000:1000 /out

echo ">> 放入遊戲資料 + 中文字型/翻譯/標題疊圖"
cp -r "$ROOT/game/." "$STAGE/game/"
for f in translation.tsv sq1_big5.fnt sq1_title.ovl; do
  [ -f "$ROOT/dist-cht/$f" ] && cp "$ROOT/dist-cht/$f" "$STAGE/game/"
done

# MT-32 ROM（完整包才附）。逐一試檔名，不用 `ls a b | head -1`——
# 檔名不存在時 ls 回非零，在 set -o pipefail 下會讓腳本靜默中止。
MT32ARGS=""
CTRL=""
for c in "$MT32_ROM_SRC"/MT32_CONTROL.1987*.ROM "$MT32_ROM_SRC"/MT32_CONTROL.ROM; do
  if [ -f "$c" ]; then CTRL="$c"; break; fi
done
if [ -n "$CTRL" ] && [ -f "$MT32_ROM_SRC/MT32_PCM.ROM" ]; then
  cp "$CTRL" "$STAGE/game/MT32_CONTROL.ROM"
  cp "$MT32_ROM_SRC/MT32_PCM.ROM" "$STAGE/game/MT32_PCM.ROM"
  MT32ARGS=' --music-driver=mt32 --extrapath="%~dp0game"'
  echo "   MT-32 ROM 已放入（$(basename "$CTRL") → MT32_CONTROL.ROM）"
fi

# 啟動器：直指內嵌遊戲，不需要玩家輸入路徑。
# AGI 軌中文靠「遊戲目錄有 sq1_big5.fnt」啟用，**不可帶 --language**（會讓遊戲進不去）。
cat > "$STAGE/宇宙傳奇I EGA-繁中版.bat" <<'BAT'
@echo off
chcp 950 >nul
cd /d "%~dp0"
start "" "%~dp0scummvm.exe" --render-mode=ega __MT32__ --path="%~dp0game" --auto-detect
BAT
sed -i "s|__MT32__|${MT32ARGS}|" "$STAGE/宇宙傳奇I EGA-繁中版.bat"

cat > "$STAGE/讀我.txt" <<'TXT'
宇宙傳奇I EGA： — 繁體中文化（完整版）

雙擊「宇宙傳奇I EGA-繁中版.bat」即可遊玩，不需要另外安裝或指定路徑。

音樂預設使用 Roland MT-32（本包已內附 ROM）。這款遊戲當年就是為 MT-32 譜寫的，
音色遠優於 AdLib。若要改用其他音效驅動，可於 ScummVM 的遊戲設定中變更。

操作沿用原版：方向鍵移動，直接鍵入英文指令（LOOK、GET、USE…），
F1 說明、F5 存檔、F7 讀檔、Esc 開選單。

本中文化不修改遊戲原始資源，是在 ScummVM 引擎層做內容比對替換。
TXT

OUT="$DIST/$NAME.zip"; rm -f "$OUT"
( cd "$STAGE" && zip -qr "$OUT" . )
echo ">> 完成: $OUT ($(du -h "$OUT" | cut -f1))"
