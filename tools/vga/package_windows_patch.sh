#!/usr/bin/env bash
# 把 mingw 交叉編譯出的 scummvm.exe + 中文化資料打包成 **patch 版** Windows x86_64 zip。
# 不含遊戲資源(玩家自備),上 GitHub Release。前置：先跑 mingw build 產出 scummvm-win/scummvm.exe。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"          # /home/anr2/scummvm/conquest_of_longbow/workplace
REPO_ROOT="$(cd "$ROOT/.." && pwd)"                # /home/anr2/scummvm/conquest_of_longbow

MINGW_IMG="${MINGW_IMG:-qfg1-mingw}"
EXE="$ROOT/scummvm-win/scummvm.exe"
STAGE="$ROOT/build/win64-patch"
DIST="$ROOT/release-staging"
OUT="$DIST/Longbow-CHT-patch-win64.zip"

[ -f "$EXE" ] || { echo "!! 找不到 $EXE（先跑 mingw build）"; exit 1; }

mkdir -p "$DIST"
rm -rf "$STAGE"; mkdir -p "$STAGE/scummvm-cht" "$STAGE/game"

echo ">> 複製 scummvm.exe + strip"
cp "$EXE" "$STAGE/scummvm.exe"
docker run --rm --name longbow-winpkg-patch-strip -v "$STAGE:/s" "$MINGW_IMG" x86_64-w64-mingw32-strip /s/scummvm.exe

echo ">> 收集 mingw runtime DLL"
docker run --rm --name longbow-winpkg-patch-sdl2dll "$MINGW_IMG" cat /usr/x86_64-w64-mingw32/bin/SDL2.dll > "$STAGE/SDL2.dll"
docker run --rm --name longbow-winpkg-patch-pthreaddll "$MINGW_IMG" cat /usr/x86_64-w64-mingw32/lib/libwinpthread-1.dll > "$STAGE/libwinpthread-1.dll"

echo ">> 放入中文化資料(patch-only,不含遊戲)"
cp "$ROOT/dist-cht/translation.tsv" "$STAGE/scummvm-cht/"
cp "$ROOT/dist-cht/longbow_big5.fnt" "$STAGE/scummvm-cht/"
cp "$ROOT/dist-cht/longbow_big5_hi.fnt" "$STAGE/scummvm-cht/"
cp "$ROOT/dist-cht/longbow_title.ovl" "$STAGE/scummvm-cht/"

# game/ 只留一個提示檔,不放遊戲資源——玩家把自備的遊戲檔複製進這個資料夾。
cat > "$STAGE/game/把遊戲檔放這裡.txt" <<'TXT'
把你自己合法擁有的《羅賓漢傳奇 Conquests of the Longbow》遊戲檔
(resource.000~005、resource.map、resource.cfg 等)複製到這個 game 資料夾裡,
再雙擊上一層的「執行.bat」開始遊戲。
TXT

cat > "$STAGE/執行.bat" <<'BAT'
@echo off
chcp 950 >nul
cd /d "%~dp0"
scummvm.exe --path="%~dp0game" --extrapath="%~dp0scummvm-cht" --language=tw --auto-detect
BAT

cat > "$STAGE/玩法說明.txt" <<'TXT'
羅賓漢傳奇（Conquests of the Longbow: The Legend of Robin Hood）繁體中文化 — Windows x86_64 patch 版

本包只含 patched ScummVM 引擎 + 中文化資料,不含遊戲本體(需玩家自備正版遊戲檔)。

使用方式：
  1. 把你自己合法擁有的羅賓漢傳奇遊戲檔(resource.000~005、resource.map 等 DOS 版遊戲檔)
     複製到本資料夾內的 game\ 子資料夾。
  2. 雙擊「執行.bat」開始遊戲。
     （或自行編輯 .bat / 手動執行 scummvm.exe --path="<你的遊戲路徑>" --extrapath="scummvm-cht" --language=tw --auto-detect）

內容物：
  scummvm.exe                        patched ScummVM（含 Big5 中文繪字引擎改動 + MT-32 音源模擬）
  SDL2.dll / libwinpthread-1.dll     執行所需 runtime
  scummvm-cht\                       中文化資料（translation.tsv、Big5 字型 ×2、標題疊圖 .ovl）
  game\                              空資料夾,放你自備的遊戲檔

若要用 Roland MT-32 音源（推薦，音色遠優於 AdLib）：
  請自備 MT32_CONTROL.ROM + MT32_PCM.ROM 放進 game\,再執行：
  scummvm.exe --path="game" --extrapath="scummvm-cht" --language=tw --auto-detect --music-driver=mt32

repo：https://github.com/wicanr2/conquests_of_longbow_cht
TXT

rm -f "$OUT"
echo ">> zip 打包"
( cd "$STAGE" && zip -qr "$OUT" . )
echo ">> 完成: $OUT ($(du -h "$OUT" | cut -f1))"
