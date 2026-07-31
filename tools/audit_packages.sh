#!/usr/bin/env bash
# [HARD] 收尾稽核：full 包**必含**遊戲資源（與 ROM）；patch 包**必不含**任何遊戲資源或 ROM。
# 這條跟 verify_packages.sh 是兩件事——那支比 md5（資料有沒有過期），這支比「有沒有裝錯東西」。
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fail=0
for track in ega vga; do
  echo "=== $track ==="
  for pkg in "$track"/dist-patch/* "$track"/dist-all/*; do
    [ -f "$pkg" ] || continue
    tmp=$(mktemp -d)
    case "$pkg" in
      *.AppImage) (cd "$tmp" && "$OLDPWD/$pkg" --appimage-extract >/dev/null 2>&1) ;;
      *.zip)      unzip -qo "$pkg" -d "$tmp" 2>/dev/null ;;
      *.tar.gz)   tar -xzf "$pkg" -C "$tmp" 2>/dev/null ;;
      *) rm -rf "$tmp"; continue ;;
    esac
    # 遊戲資源：AGI 是 LOGDIR/VOL.*/WORDS.TOK，SCI 是 RESOURCE.*
    game=$(find "$tmp" \( -iname 'resource.0*' -o -iname 'logdir' -o -iname 'vol.*' -o -iname 'words.tok' \) | wc -l)
    rom=$(find "$tmp" -iname '*.ROM' | wc -l)
    case "$pkg" in
      */dist-all/*)   # full：必須有遊戲；ROM 有無都可（macOS/Windows/Linux 完整版都放）
        if [ "$game" -gt 0 ]; then echo "  ✓ $(basename "$pkg")  遊戲資源 $game 個、ROM $rom 個"
        else echo "  ✗ $(basename "$pkg")  完整版卻沒有遊戲資源"; fail=1; fi ;;
      */dist-patch/*) # patch：一個都不能有
        if [ "$game" -eq 0 ] && [ "$rom" -eq 0 ]; then echo "  ✓ $(basename "$pkg")  乾淨（無遊戲資源、無 ROM）"
        else echo "  ✗ $(basename "$pkg")  patch 版混入 遊戲資源 $game 個 / ROM $rom 個"; fail=1; fi ;;
    esac
    rm -rf "$tmp"
  done
done
exit $fail
