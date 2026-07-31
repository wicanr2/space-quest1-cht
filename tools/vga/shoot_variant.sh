#!/usr/bin/env bash
# 烘一個設計版本 → 部署 → 跳房實機截圖。用來給人看「真的長這樣」，不是合成預覽。
# 用法: shoot_variant.sh <rocket|alert> <vN>
set -euo pipefail
KIND="${1:?rocket|alert}"; VER="${2:?v1|v2|v3}"
WP="$(cd "$(dirname "$0")/.." && pwd)"; cd "$WP"
case "$KIND" in
  rocket) VIEW=141; ROOM=41 ;;
  alert)  VIEW=104; ROOM=4  ;;
  *) echo "!! 只認 rocket / alert"; exit 1 ;;
esac
docker run --rm --name sq1-bake-$KIND-$VER -v "$WP":/w -w /w python:3.12-slim bash -c "
  pip install -q --root-user-action=ignore pillow >/dev/null 2>&1
  python tools/bake_cels_cn.py extract/res dist-cht/sq1_cels.dat --png ${VIEW}:out/design/${KIND}_${VER}.png
  chown -R 1000:1000 /w/dist-cht" | tail -2
cp dist-cht/sq1_cels.dat game/
TAG="_${KIND}_${VER}" docker run --rm --name sq1-shoot-$KIND-$VER -e TAG="_${KIND}_${VER}" \
  -v "$WP":/w -w /w sq1-capture bash /w/tools/cap_room.sh "$ROOM" >/dev/null 2>&1 || true
echo ">> out/room/room${ROOM}_${KIND}_${VER}_clean.png"
