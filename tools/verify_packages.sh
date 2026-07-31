#!/usr/bin/env bash
# [HARD] 收工驗收：逐包比對「包內中文資料」與 dist-cht/ 的 md5。
# 包是快照、不會回溯——改了 dist-cht 沒重打包時，檔案「存在」看不出這件事（SQ2 踩過）。
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fail=0
for track in ega vga; do
  echo "=== $track ==="
  # 有些檔案在 dist-cht 裡但該軌其實用不到，別當成缺件。
  #   EGA(AGI) 只讀 sq1_big5.fnt（graphics.cpp 寫死 16×15，沒有 hi-res 路徑），
  #   sq1_big5_hi.fnt 是烘字型時順手產的，patch 包刻意不放。
  case "$track" in
    ega) skip=" sq1_big5_hi.fnt " ;;
    *)   skip=" " ;;
  esac
  declare -A want=()
  for f in "$track"/dist-cht/*; do
    b="$(basename "$f")"
    case "$skip" in *" $b "*) continue ;; esac
    want["$b"]="$(md5sum "$f" | cut -d' ' -f1)"
  done
  for pkg in "$track"/dist-patch/* "$track"/dist-all/* "$track"/release-staging/*; do
    [ -f "$pkg" ] || continue
    tmp=$(mktemp -d)
    case "$pkg" in
      *.AppImage) (cd "$tmp" && "$OLDPWD/$pkg" --appimage-extract >/dev/null 2>&1) ;;
      *.zip)      unzip -qo "$pkg" -d "$tmp" 2>/dev/null ;;
      *.tar.gz)   tar -xzf "$pkg" -C "$tmp" 2>/dev/null ;;
      *) rm -rf "$tmp"; continue ;;
    esac
    bad=0; n=0; seen=" "
    while IFS= read -r got; do
      base="$(basename "$got")"
      [ -n "${want[$base]:-}" ] || continue
      n=$((n+1)); seen="$seen$base "
      [ "$(md5sum "$got" | cut -d' ' -f1)" = "${want[$base]}" ] || { echo "  ✗ $(basename "$pkg"): $base md5 不符"; bad=1; fail=1; }
    done < <(find "$tmp" -type f \( -name 'translation.tsv' -o -name 'sq1_*' \))
    # [HARD] 只比對「包裡找到的檔案」會漏掉最惡劣的一種情況：**檔案根本沒被放進去**。
    # 新增一種中文資料（例如 sq1_cels.dat）而打包腳本忘了加，上面的迴圈會照樣印 ✓。
    # 所以這裡反過來，用 dist-cht 的清單當基準檢查有沒有缺件。
    for base in "${!want[@]}"; do
      case "$seen" in *" $base "*) ;; *) echo "  ✗ $(basename "$pkg"): 缺少 $base"; bad=1; fail=1 ;; esac
    done
    [ "$bad" = 0 ] && echo "  ✓ $(basename "$pkg")  （$n 個中文資料檔 md5 全符）"
    rm -rf "$tmp"
  done
done
exit $fail
