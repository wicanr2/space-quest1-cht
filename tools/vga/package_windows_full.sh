#!/usr/bin/env bash
# 《宇宙傳奇 IV》繁中化 Windows x86_64 打包(mingw 交叉編譯產物)。
#
#   patch → 引擎 + 中文資料,玩家自備遊戲,上 GitHub Release
#   full  → 內嵌整個 game\ 與 MT-32 ROM,雙擊即玩,只放本機 dist-all/
#
# 用法:package_windows_full.sh patch|full
# 前置:先跑 mingw configure+make 產出 scummvm-win/scummvm.exe
#
# 啟動器用 .bat 寫一份 scummvm.ini 再指定 target,理由同 AppImage:
# SCI1.1 的偵測器會在偵測階段用語言過濾條目,且 SQ4 CD 同時符合 DOS/Windows 兩個條目,
# `--auto-detect` 只會列出候選不會啟動。
set -euo pipefail
MODE="${1:?用法: package_windows_full.sh patch|full}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tools/pkg_common.sh"

MINGW_IMG="${MINGW_IMG:-sq1-mingw}"
EXE="$ROOT/scummvm-win/scummvm.exe"
[ -f "$EXE" ] || { echo "!! 找不到 $EXE(先跑 mingw build)"; exit 1; }

case "$MODE" in
  patch) STAGE="$ROOT/build/win64-patch"; DIST="$ROOT/release-staging"; OUT="$DIST/SQ1-VGA-CHT-patch-win64.zip" ;;
  full)  STAGE="$ROOT/build/win64-full";  DIST="$ROOT/dist-all";        OUT="$DIST/SQ1-VGA-CHT-full-win64.zip" ;;
  *) echo "MODE 只能是 patch 或 full"; exit 1 ;;
esac

mkdir -p "$DIST"; rm -rf "$STAGE"; mkdir -p "$STAGE"

echo ">> 複製 scummvm.exe + strip"
cp "$EXE" "$STAGE/scummvm.exe"
docker run --rm --name sq1-winpkg-strip -v "$STAGE:/s" "$MINGW_IMG" x86_64-w64-mingw32-strip /s/scummvm.exe

echo ">> 收集 mingw runtime DLL"
docker run --rm --name sq1-winpkg-sdl2 "$MINGW_IMG" cat /usr/x86_64-w64-mingw32/bin/SDL2.dll > "$STAGE/SDL2.dll"
docker run --rm --name sq1-winpkg-pthread "$MINGW_IMG" cat /usr/x86_64-w64-mingw32/lib/libwinpthread-1.dll > "$STAGE/libwinpthread-1.dll"

MT32LINE=""
if [ "$MODE" = patch ]; then
  echo ">> 放入中文資料(patch-only,不含遊戲)"
  mkdir -p "$STAGE/scummvm-cht"
  cp "$ROOT/dist-cht/translation.tsv" "$ROOT/dist-cht/sq1_big5.fnt" \
     "$ROOT/dist-cht/sq1_big5_hi.fnt" "$ROOT/dist-cht/sq1_title.ovl" \
     "$STAGE/scummvm-cht/"
else
  echo ">> 放入遊戲資料(game/ 已含中文資料)"
  mkdir -p "$STAGE/game"
  cp -r "$ROOT/game/." "$STAGE/game/"
  if stage_mt32_rom "$STAGE/game"; then
    MT32LINE='music_driver=mt32'
  fi
fi

# --- 啟動器 .bat（CRLF 換行，Windows 記事本／cmd 才不會亂）--------------------
if [ "$MODE" = patch ]; then
cat > "$STAGE/新宇宙傳奇1-中文版.bat" <<'BAT'
@echo off
rem ini 內容一律 ASCII:cmd 在不同 codepage 下用 echo 寫中文會變亂碼,
rem 而 description 只是啟動器清單上的名字,不影響遊戲內的中文。
chcp 65001 >nul
setlocal
cd /d "%~dp0"
set GAME=%~1
if "%GAME%"=="" (
  echo.
  echo   用法: 把你的「宇宙傳奇 IV」遊戲資料夾拖到這個 .bat 上,或
  echo         新宇宙傳奇1-中文版.bat D:\games\sq1vga
  echo.
  echo   遊戲夾內要有 resource.000 / resource.aud / resource.map（自備正版）。
  echo.
  pause
  exit /b 1
)
set "INI=%~dp0scummvm.ini"
rem 逐行 append 而不是用括號區塊重導向:區塊重導向在部分 cmd 實作(含 wine)不生效,
rem 結果只有第一行進檔案、其餘噴到畫面,遊戲就會說找不到 target。
> "%INI%"  echo [scummvm]
>>"%INI%"  echo.
>>"%INI%"  echo [sq1-cht]
>>"%INI%"  echo engineid=sci
>>"%INI%"  echo gameid=sq1sci
>>"%INI%"  echo description=Space Quest IV CHT
>>"%INI%"  echo path=%GAME%
>>"%INI%"  echo extrapath=%~dp0scummvm-cht
>>"%INI%"  echo language=tw
>>"%INI%"  echo subtitles=true
>>"%INI%"  echo speech_mute=false
>>"%INI%"  echo aspect_ratio=false
"%~dp0scummvm.exe" --config="%~dp0scummvm.ini" sq1-cht
BAT
else
cat > "$STAGE/新宇宙傳奇1-中文版.bat" <<BAT
@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
set "INI=%~dp0scummvm.ini"
> "%INI%"  echo [scummvm]
>>"%INI%"  echo.
>>"%INI%"  echo [sq1-cht]
>>"%INI%"  echo engineid=sci
>>"%INI%"  echo gameid=sq1sci
>>"%INI%"  echo description=Space Quest IV CHT (full)
>>"%INI%"  echo path=%~dp0game
>>"%INI%"  echo extrapath=%~dp0game
>>"%INI%"  echo language=tw
>>"%INI%"  echo subtitles=true
>>"%INI%"  echo speech_mute=false
>>"%INI%"  echo aspect_ratio=false
$( [ -n "$MT32LINE" ] && echo ">>\"%INI%\"  echo $MT32LINE" )
"%~dp0scummvm.exe" --config="%~dp0scummvm.ini" sq1-cht %*
BAT
fi
# .bat 要 CRLF
sed -i 's/$/\r/' "$STAGE/新宇宙傳奇1-中文版.bat"

cat > "$STAGE/讀我.txt" <<'TXT'
新宇宙傳奇I — 沙利安人的遭遇　繁體中文化（Windows x86_64）

怎麼玩
------
  patch 版：把你的遊戲資料夾拖到「新宇宙傳奇1-中文版.bat」上（或在命令列把路徑當參數帶進去）。
  完整版：直接雙擊「新宇宙傳奇1-中文版.bat」，遊戲已內嵌在 game\ 裡。

.bat 會自動產生一份 scummvm.ini 並指定中文 target。
不要改用 --language=tw 這種命令列參數：SCI1.1 的偵測器在偵測階段就會用語言過濾條目，
帶了反而會讓遊戲認不出來。

語音與字幕
------
CD 版有全套英文語音。中文化保留原配音、字幕顯示繁中，兩者預設同時開啟。

MT-32 音效
------
引擎已編入 MT-32 模擬（Munt），音色遠勝 AdLib。
完整版已附 ROM 並預設啟用；patch 版請自備 MT32_CONTROL.ROM 與 MT32_PCM.ROM
放進遊戲資料夾，再到音效選項選 Roland MT-32。

repo：https://github.com/wicanr2/space-quest4-cht
TXT
sed -i 's/$/\r/' "$STAGE/讀我.txt"

rm -f "$OUT"
echo ">> zip 打包"
( cd "$STAGE" && zip -qr "$OUT" . )
echo ">> 完成: $OUT ($(du -h "$OUT" | cut -f1))"
