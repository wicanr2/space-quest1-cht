#!/usr/bin/env bash
# 打包 Linux AppImage **patch 版**：只有中文化後的 ScummVM 引擎 + 中文資料，不含遊戲本體。
#
# 這是要上 GitHub Release 的公開版本，[HARD] 絕不能混入任何遊戲資源或 MT-32 ROM。
# full 完整版是另一支 package_appimage_full.sh，產物只留本機 dist-all/。
#
# 中文如何啟用：AGI 軌靠「搜尋路徑裡有 sq1_big5.fnt」，不是 --language（帶了會讓遊戲退回啟動器）。
# 引擎用 Common::File::open() 開字型，走 SearchMan，因此 --extrapath 指向包內 cht-data 即可，
# 玩家不需要把中文檔案複製進自己的遊戲資料夾。
#
# 用法: tools/package_appimage_patch.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# [HARD] Release 資產檔名只能用 ASCII——GitHub 上傳時會把中文字整段剝掉
# （實測「宇宙傳奇I EGA-繁中-patch版-win64.zip」上去變成「II-.-patch.-win64.zip」）。
LABEL="SQ1-EGA-CHT-patch"
STAGE="$ROOT/build/appimage"; DIST="$ROOT/dist-patch"
APPDIR="$STAGE/AppDir-patch"
rm -rf "$APPDIR"; mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" "$APPDIR/usr/share/cht-data" "$DIST"

echo ">> 複製 scummvm + strip"
cp "$ROOT/scummvm-src/scummvm" "$APPDIR/usr/bin/scummvm"
chmod u+w "$APPDIR/usr/bin/scummvm"
docker run --rm --name sq1-pkg-strip -v "$APPDIR/usr/bin:/b" sq1-build strip /b/scummvm 2>/dev/null || true

echo ">> 收集共享庫（容器內 ldd，排除 glibc 核心）"
docker run --rm --name sq1-pkg-libs \
  -v "$APPDIR/usr/bin/scummvm:/collect/bin:ro" \
  -v "$APPDIR/usr/lib:/collect/out" \
  -v "$ROOT/tools/pkg_collect_libs.py:/collect/collect.py:ro" \
  -w /collect sq1-build python3 collect.py bin out
echo "   $(ls "$APPDIR/usr/lib" | wc -l) 個 .so"

echo ">> 放入中文資料（只有這三個檔，不含遊戲資源、不含 ROM）"
for f in translation.tsv sq1_big5.fnt sq1_title.ovl; do
  cp "$ROOT/dist-cht/$f" "$APPDIR/usr/share/cht-data/"
done

# AppRun：預設開啟 ScummVM 啟動器讓玩家 Add Game；
# 若玩家把遊戲夾放在 AppImage 旁邊並命名為 game，就自動帶入直接開玩。
# [HARD] 不帶 --language（AGI 遇非英文語言會進不去遊戲）、不預設 mt32（本包無 ROM，會彈阻擋框）。
cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/bash
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/lib:${LD_LIBRARY_PATH:-}"
CHT="$HERE/usr/share/cht-data"
SCUMMVM="$HERE/usr/bin/scummvm"
BASE="$(dirname "$(readlink -f "${APPIMAGE:-$0}")")"
if [ -f "$BASE/game/LOGDIR" ]; then
  exec "$SCUMMVM" --render-mode=ega --extrapath="$CHT" --path="$BASE/game" --auto-detect "$@"
fi
exec "$SCUMMVM" --render-mode=ega --extrapath="$CHT" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

cat > "$APPDIR/sq1-ega-cht.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=宇宙傳奇I EGA： 繁體中文化
Comment=Space Quest II: Vohaul's Revenge (宇宙傳奇I EGA：) 繁體中文化
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
   /cache/appimagetool-x86_64.AppImage --appimage-extract-and-run 'AppDir-patch' '/stage/out-patch.AppImage'"
mv "$STAGE/out-patch.AppImage" "$OUT"
chmod +x "$OUT"

echo ">> 完成: $OUT ($(du -h "$OUT" | cut -f1))"
