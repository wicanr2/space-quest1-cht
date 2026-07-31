#!/usr/bin/env bash
# 《宇宙傳奇 IV》繁中化 AppImage 打包(Linux x86_64)。
#
#   patch  → 只有引擎 + 中文資料,玩家自備遊戲,上 GitHub Release
#   full   → 內嵌整個 game/ 與 MT-32 ROM,雙擊即玩,只放本機 dist-all/(不上傳)
#
# 用法:package_appimage_full.sh patch|full
#
# 為什麼啟動器要自己寫 config 而不是用 --language=tw:
#   SCI1.1 的 advancedDetector 在偵測階段就會用語言過濾條目,而且 SQ4 CD 同時符合
#   DOS 與 Windows 兩個條目 → `--auto-detect` 只會列出候選、不會啟動。寫一個帶
#   language=tw 的 target 進 config 再指定它,兩個問題一起解決。
set -euo pipefail
MODE="${1:?用法: package_appimage_full.sh patch|full}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tools/pkg_common.sh"                 # stage_mt32_rom

case "$MODE" in
  patch) STAGE="$ROOT/build/appimg-patch"; DIST="$ROOT/release-staging"
         OUT="$DIST/SQ1-VGA-CHT-patch-x86_64.AppImage" ;;
  full)  STAGE="$ROOT/build/appimg-full";  DIST="$ROOT/dist-all"
         OUT="$DIST/SQ1-VGA-CHT-full-x86_64.AppImage" ;;
  *) echo "MODE 只能是 patch 或 full"; exit 1 ;;
esac
APPDIR="$STAGE/AppDir"

mkdir -p "$DIST"
rm -rf "$APPDIR"; mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib"

echo ">> 複製 scummvm + strip"
cp "$ROOT/scummvm-src/scummvm" "$APPDIR/usr/bin/scummvm"
docker run --rm --name sq1-pkg-strip -v "$APPDIR/usr/bin:/b" sq1-build:latest strip /b/scummvm 2>/dev/null || true

echo ">> 收集共享庫"
docker run --rm --name sq1-pkg-libs \
  -v "$APPDIR/usr/bin/scummvm:/collect/bin:ro" \
  -v "$APPDIR/usr/lib:/collect/out" \
  -v "$ROOT/tools/pkg_collect_libs.py:/collect/collect.py:ro" \
  -w /collect sq1-build:latest python3 collect.py bin out
echo "   $(ls "$APPDIR/usr/lib" | wc -l) 個 .so"

MT32LINE=""
if [ "$MODE" = patch ]; then
  echo ">> 放入中文資料(patch-only,不含遊戲)"
  mkdir -p "$APPDIR/usr/share/scummvm-cht"
  cp "$ROOT/dist-cht/translation.tsv" "$ROOT/dist-cht/sq1_big5.fnt" \
     "$ROOT/dist-cht/sq1_big5_hi.fnt" "$ROOT/dist-cht/sq1_title.ovl" "$ROOT/dist-cht/sq1_cels.dat" \
     "$APPDIR/usr/share/scummvm-cht/"
else
  echo ">> 放入遊戲資料(game/ 已含中文資料)"
  mkdir -p "$APPDIR/usr/share/game"
  cp -r "$ROOT/game/." "$APPDIR/usr/share/game/"
  # MT-32 ROM 只放進完整包;有 ROM 才把音效驅動預設成 mt32
  # (沒 ROM 卻設 mt32 會先彈一次阻擋框才回退 AdLib)
  if stage_mt32_rom "$APPDIR/usr/share/game"; then
    MT32LINE='music_driver=mt32'
  fi
fi

cp "$ROOT/tools/assets/sq1-cht.png" "$APPDIR/sq1-cht.png"
ln -sf sq1-cht.png "$APPDIR/.DirIcon"
cat > "$APPDIR/sq1-cht.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=宇宙傳奇 IV 時空穿越者（繁體中文版）
Comment=Space Quest IV: Roger Wilco and the Time Rippers 繁體中文化 — ScummVM
Exec=AppRun
Icon=sq1-cht
Categories=Game;
Terminal=false
DESK

# --- AppRun ------------------------------------------------------------------
if [ "$MODE" = patch ]; then
cat > "$APPDIR/AppRun" <<APPRUN
#!/bin/bash
set -e
HERE="\$(dirname "\$(readlink -f "\$0")")"
export LD_LIBRARY_PATH="\$HERE/usr/lib:\${LD_LIBRARY_PATH:-}"
if [ -z "\${1:-}" ]; then
  echo "用法: \$(basename "\$0") <宇宙傳奇 IV 遊戲資料夾> [其他 scummvm 參數...]"
  echo "  範例: ./SQ1-VGA-CHT-patch-x86_64.AppImage ~/games/sq4"
  echo "  遊戲夾內要有 resource.000 / resource.aud / resource.map(自備正版)。"
  exit 1
fi
GAME="\$(readlink -f "\$1")"; shift
CFGDIR="\${XDG_CONFIG_HOME:-\$HOME/.config}/sq1-cht"
CFG="\$CFGDIR/scummvm.ini"
mkdir -p "\$CFGDIR"
if [ ! -f "\$CFG" ] || ! grep -qxF "path=\$GAME" "\$CFG"; then
  cat > "\$CFG" <<CFGEOF
[scummvm]

[sq1-cht]
engineid=sci
gameid=sq1sci
description=宇宙傳奇 IV 時空穿越者（繁體中文）
path=\$GAME
extrapath=\$HERE/usr/share/scummvm-cht
language=tw
subtitles=true
speech_mute=false
aspect_ratio=false
CFGEOF
fi
exec "\$HERE/usr/bin/scummvm" --config="\$CFG" sq1-cht "\$@"
APPRUN
else
cat > "$APPDIR/AppRun" <<APPRUN
#!/bin/bash
set -e
HERE="\$(dirname "\$(readlink -f "\$0")")"
export LD_LIBRARY_PATH="\$HERE/usr/lib:\${LD_LIBRARY_PATH:-}"
GAME="\$HERE/usr/share/game"
CFGDIR="\${XDG_CONFIG_HOME:-\$HOME/.config}/sq1-cht-full"
CFG="\$CFGDIR/scummvm.ini"
mkdir -p "\$CFGDIR"
cat > "\$CFG" <<CFGEOF
[scummvm]

[sq1-cht]
engineid=sci
gameid=sq1sci
description=宇宙傳奇 IV 時空穿越者（繁體中文・完整版）
path=\$GAME
extrapath=\$GAME
language=tw
subtitles=true
speech_mute=false
aspect_ratio=false
$MT32LINE
CFGEOF
exec "\$HERE/usr/bin/scummvm" --config="\$CFG" sq1-cht "\$@"
APPRUN
fi
chmod +x "$APPDIR/AppRun"

rm -f "$OUT"
echo ">> appimagetool 打包"
docker run --rm --name sq1-pkg-appimagetool -v "$STAGE:/stage" -v "$ROOT/tools/.cache:/cache:ro" \
  -e ARCH=x86_64 -w /stage sq1-build:latest bash -c \
  "apt-get update -qq >/dev/null && apt-get install -y -qq file >/dev/null && \
   /cache/appimagetool-x86_64.AppImage --appimage-extract-and-run 'AppDir' '/stage/$(basename "$OUT")'"
mv "$STAGE/$(basename "$OUT")" "$OUT"
chmod +x "$OUT"
echo ">> 完成: $OUT ($(du -h "$OUT" | cut -f1))"
