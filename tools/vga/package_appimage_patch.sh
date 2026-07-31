#!/usr/bin/env bash
# 打包 Linux AppImage **patch 版**（VGA / SCI1 軌）：只有中文化後的 ScummVM 引擎 + 中文資料，
# 不含遊戲本體。這是要上 GitHub Release 的公開版本，
# [HARD] 絕不能混入任何遊戲資源或 MT-32 ROM。
# full 完整版是另一支 package_appimage_full.sh，產物只留本機 dist-all/。
#
# 中文如何啟用：SCI 軌是 `--language=tw`（跟 AGI 軌相反，AGI 帶了會進不去遊戲）。
# 引擎用 Common::File::open() 開字型與譯文表，走 SearchMan，所以 --extrapath 指向包內
# cht-data 就夠，玩家不必把中文檔案複製進自己的遊戲資料夾。
#
# 用法: tools/package_appimage_patch.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# [HARD] Release 資產檔名只能用 ASCII——GitHub 上傳會把中文字整段剝掉。
LABEL="SQ1-VGA-CHT-patch"
STAGE="$ROOT/build/appimage"; DIST="$ROOT/dist-patch"
APPDIR="$STAGE/AppDir-patch"
rm -rf "$APPDIR"; mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" "$APPDIR/usr/share/cht-data" "$DIST"

echo ">> 複製 scummvm + strip"
cp "$ROOT/scummvm-src/scummvm" "$APPDIR/usr/bin/scummvm"
chmod u+w "$APPDIR/usr/bin/scummvm"
docker run --rm --name sq1-vgapkg-strip -v "$APPDIR/usr/bin:/b" sq1-build strip /b/scummvm 2>/dev/null || true

echo ">> 收集共享庫（容器內 ldd，排除 glibc 核心）"
docker run --rm --name sq1-vgapkg-libs \
  -v "$APPDIR/usr/bin/scummvm:/collect/bin:ro" \
  -v "$APPDIR/usr/lib:/collect/out" \
  -v "$ROOT/tools/pkg_collect_libs.py:/collect/collect.py:ro" \
  -w /collect sq1-build python3 collect.py bin out
echo "   $(ls "$APPDIR/usr/lib" | wc -l) 個 .so"

echo ">> 放入中文資料（只有這些檔，不含遊戲資源、不含 ROM）"
for f in translation.tsv sq1_big5.fnt sq1_big5_hi.fnt sq1_title.ovl sq1_cels.dat; do
  cp "$ROOT/dist-cht/$f" "$APPDIR/usr/share/cht-data/"
done

# AppRun：預設開啟 ScummVM 啟動器讓玩家 Add Game；
# 若玩家把遊戲夾放在 AppImage 旁邊並命名為 game，就自動帶入直接開玩（跟 README 寫的一致）。
# [HARD] 不預設 mt32（本包無 ROM，設了會先彈一次阻擋框再退回 AdLib）。
cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/bash
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/lib:${LD_LIBRARY_PATH:-}"
CHT="$HERE/usr/share/cht-data"
SCUMMVM="$HERE/usr/bin/scummvm"
BASE="$(dirname "$(readlink -f "${APPIMAGE:-$0}")")"
if [ -f "$BASE/game/RESOURCE.MAP" ] || [ -f "$BASE/game/resource.map" ]; then
  exec "$SCUMMVM" --language=tw --extrapath="$CHT" --path="$BASE/game" --auto-detect "$@"
fi
exec "$SCUMMVM" --language=tw --extrapath="$CHT" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

cat > "$APPDIR/sq1-vga-cht.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=新宇宙傳奇I（VGA）繁體中文化
Comment=Space Quest I: The Sarien Encounter (1991 VGA remake) 繁體中文化
Exec=AppRun
Icon=sq1-vga-cht
Categories=Game;
Terminal=false
DESK
cp "$ROOT/tools/assets/icon.png" "$APPDIR/sq1-vga-cht.png" 2>/dev/null || \
  cp "$ROOT/../ega/tools/assets/icon.png" "$APPDIR/sq1-vga-cht.png"
ln -sf sq1-vga-cht.png "$APPDIR/.DirIcon"

OUT="$DIST/${LABEL}-x86_64.AppImage"; rm -f "$OUT"
echo ">> appimagetool 打包（--appimage-extract-and-run 免 FUSE）"
docker run --rm --name sq1-vgapkg-appimg -v "$STAGE:/stage" -v "$ROOT/tools/.cache:/cache:ro" \
  -e ARCH=x86_64 -w /stage sq1-build bash -c \
  "apt-get update -qq >/dev/null && apt-get install -y -qq file >/dev/null && \
   /cache/appimagetool-x86_64.AppImage --appimage-extract-and-run 'AppDir-patch' '/stage/out-patch.AppImage'"
mv "$STAGE/out-patch.AppImage" "$OUT"
chmod +x "$OUT"

echo ">> 完成: $OUT ($(du -h "$OUT" | cut -f1))"
