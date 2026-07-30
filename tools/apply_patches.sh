#!/usr/bin/env bash
# 把本專案的中文化引擎 patch 套到一棵 ScummVM 原始碼樹上。
#
# 用法: tools/apply_patches.sh <scummvm-src 路徑> <ega|vga>
#
# 兩條軌是獨立的：ega 改 engines/agi（AGI 引擎）、vga 改 engines/sci（SCI 引擎）。
# 一棵樹只套一條軌——它們對應不同的 configure（--enable-engine=agi vs sci）。
set -euo pipefail
SRC="${1:?用法: apply_patches.sh <scummvm-src> <ega|vga>}"
TRACK="${2:?用法: apply_patches.sh <scummvm-src> <ega|vga>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
P="$HERE/patches/$TRACK/0001-cht.patch"

[ -f "$P" ] || { echo "!! 找不到 $P"; exit 1; }
echo ">> 套用 $TRACK 軌 patch 到 $SRC"
git -C "$SRC" apply --check "$P" || { echo "!! patch 套不上（upstream commit 對不上？）"; exit 1; }
git -C "$SRC" apply "$P"
echo ">> 完成。configure 請帶 --enable-engine=$([ "$TRACK" = ega ] && echo agi || echo sci)"
