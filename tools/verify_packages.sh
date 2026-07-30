#!/usr/bin/env bash
# [HARD] 收工驗收：逐包比對「包內中文資料」與 dist-cht/ 的 md5。
# 包是快照、不會回溯——改了 dist-cht 沒重打包時，檔案「存在」看不出這件事（SQ2 踩過）。
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fail=0
for track in ega vga; do
  echo "=== $track ==="
  declare -A want=()
  for f in "$track"/dist-cht/*; do want["$(basename "$f")"]="$(md5sum "$f" | cut -d' ' -f1)"; done
  for pkg in "$track"/dist-patch/* "$track"/dist-all/* "$track"/release-staging/*; do
    [ -f "$pkg" ] || continue
    tmp=$(mktemp -d)
    case "$pkg" in
      *.AppImage) (cd "$tmp" && "$OLDPWD/$pkg" --appimage-extract >/dev/null 2>&1) ;;
      *.zip)      unzip -qo "$pkg" -d "$tmp" 2>/dev/null ;;
      *.tar.gz)   tar -xzf "$pkg" -C "$tmp" 2>/dev/null ;;
      *) rm -rf "$tmp"; continue ;;
    esac
    bad=0; n=0
    while IFS= read -r got; do
      base="$(basename "$got")"
      [ -n "${want[$base]:-}" ] || continue
      n=$((n+1))
      [ "$(md5sum "$got" | cut -d' ' -f1)" = "${want[$base]}" ] || { echo "  ✗ $(basename "$pkg"): $base md5 不符"; bad=1; fail=1; }
    done < <(find "$tmp" -type f \( -name 'translation.tsv' -o -name 'sq1_*' \))
    [ "$bad" = 0 ] && echo "  ✓ $(basename "$pkg")  （$n 個中文資料檔 md5 全符）"
    rm -rf "$tmp"
  done
done
exit $fail
