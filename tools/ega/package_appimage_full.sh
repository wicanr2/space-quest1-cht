#!/usr/bin/env bash
# 把 patched ScummVM + 遊戲資料 + 中文字型/翻譯 + MT-32 ROM 打包成雙擊即玩的 AppImage。
#
# 這是 **full 完整版**：內嵌整個 game/，啟動器直指內嵌遊戲、玩家不必輸入路徑。
# 產物放 dist-all/（gitignore），**不上 GitHub**——內含遊戲本體與有版權的 MT-32 ROM。
#
# 用法: tools/package_appimage_full.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MT32_ROM_SRC="${MT32_ROM_SRC:-/home/anr2/cht/mt32}"

LABEL="宇宙傳奇I EGA-繁中-完整版"
TARGET="sq1"
STAGE="$ROOT/build/appimage"; DIST="$ROOT/dist-all"
APPDIR="$STAGE/AppDir-full"
rm -rf "$APPDIR"; mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" "$APPDIR/usr/share/game" "$DIST"

echo ">> 複製 scummvm + strip"
cp "$ROOT/scummvm-src/scummvm" "$APPDIR/usr/bin/scummvm"
docker run --rm --name sq1-pkg-strip -v "$APPDIR/usr/bin:/b" sq1-build strip /b/scummvm 2>/dev/null || true

echo ">> 收集共享庫（容器內 ldd，排除 glibc 核心）"
docker run --rm --name sq1-pkg-libs \
  -v "$APPDIR/usr/bin/scummvm:/collect/bin:ro" \
  -v "$APPDIR/usr/lib:/collect/out" \
  -v "$ROOT/tools/pkg_collect_libs.py:/collect/collect.py:ro" \
  -w /collect sq1-build python3 collect.py bin out
echo "   $(ls "$APPDIR/usr/lib" | wc -l) 個 .so"

echo ">> 放入遊戲資料 + 中文字型/翻譯/標題疊圖"
cp -r "$ROOT/game/." "$APPDIR/usr/share/game/"
for f in translation.tsv sq1_big5.fnt sq1_title.ovl; do
  [ -f "$ROOT/dist-cht/$f" ] && cp "$ROOT/dist-cht/$f" "$APPDIR/usr/share/game/"
done

# MT-32 ROM：完整包才附。有 ROM 才把音效預設成 mt32，
# 否則無 ROM 會彈一次「MT-32 emulator cannot be used」阻擋框再回退 AdLib。
MT32ARGS=""
# 用迴圈逐一試檔名，不要用 `ls a b 2>/dev/null | head -1`：
# 其中一個檔名不存在時 ls 會回非零，在 `set -o pipefail` 下傳出去，
# 配上 `set -e` 會讓整個腳本靜默中止（沒有任何錯誤訊息，只是停住）。
CTRL=""
for c in "$MT32_ROM_SRC"/MT32_CONTROL.1987*.ROM "$MT32_ROM_SRC"/MT32_CONTROL.ROM; do
  if [ -f "$c" ]; then CTRL="$c"; break; fi
done
if [ -n "$CTRL" ] && [ -f "$MT32_ROM_SRC/MT32_PCM.ROM" ]; then
  cp "$CTRL" "$APPDIR/usr/share/game/MT32_CONTROL.ROM"
  cp "$MT32_ROM_SRC/MT32_PCM.ROM" "$APPDIR/usr/share/game/MT32_PCM.ROM"
  MT32ARGS='--music-driver=mt32 --extrapath="$GAME"'
  echo "   MT-32 ROM 已放入（$(basename "$CTRL") → MT32_CONTROL.ROM）"
else
  echo "   (無 MT-32 ROM @ $MT32_ROM_SRC → 略過，回退預設音效驅動)"
fi

# AppRun：把內嵌遊戲加進設定後直接啟動。
# 注意 AGI 軌中文是靠「遊戲目錄有 sq1_big5.fnt」啟用，**不能帶 --language**（會讓遊戲進不去）。
cat > "$APPDIR/AppRun" <<APPRUN
#!/bin/bash
HERE="\$(dirname "\$(readlink -f "\$0")")"
export LD_LIBRARY_PATH="\$HERE/usr/lib:\${LD_LIBRARY_PATH:-}"
GAME="\$HERE/usr/share/game"
SCUMMVM="\$HERE/usr/bin/scummvm"
"\$SCUMMVM" --add --path="\$GAME" >/dev/null 2>&1 || true
exec "\$SCUMMVM" --render-mode=ega $MT32ARGS "$TARGET" "\$@"
APPRUN
chmod +x "$APPDIR/AppRun"

cat > "$APPDIR/sq1-ega-cht.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=$LABEL
Comment=Space Quest: The Sarien Encounter (1986 EGA 原版) 繁體中文化
Exec=AppRun
Icon=sq1-ega-cht
Categories=Game;
Terminal=false
DESK
cp "$ROOT/tools/assets/icon.png" "$APPDIR/sq1-ega-cht.png"
ln -sf sq1-ega-cht.png "$APPDIR/.DirIcon"

OUT="$DIST/${LABEL}-x86_64.AppImage"; rm -f "$OUT"
echo ">> appimagetool 打包（--appimage-extract-and-run 免 FUSE）"
docker run --rm --name sq1-pkg-appimg -v "$STAGE:/stage" -v "$ROOT/tools/.cache:/cache:ro" \
  -e ARCH=x86_64 -w /stage sq1-build bash -c \
  "apt-get update -qq >/dev/null && apt-get install -y -qq file >/dev/null && \
   /cache/appimagetool-x86_64.AppImage --appimage-extract-and-run 'AppDir-full' '/stage/out.AppImage'"
mv "$STAGE/out.AppImage" "$OUT"
chmod +x "$OUT"
echo ">> 完成: $OUT ($(du -h "$OUT" | cut -f1))"
