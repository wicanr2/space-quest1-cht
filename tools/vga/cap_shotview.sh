#!/bin/bash
# 進遊戲後放著跑，靠引擎自己在「指定 view 被畫上去的那一刻」存畫面（SCI_SHOT_ON_VIEW）。
# headless 定時連拍抓不到只閃一下的東西，這條路才抓得到。
VIEW="${1:?用法: cap_shotview.sh <viewId>}"
export HOME=/tmp XDG_RUNTIME_DIR=/tmp DISPLAY=:99 SDL_AUDIODRIVER=dummy
Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
sleep 3
mkdir -p /w/out/shot
cd /w
SCI_LOG_GFX=1 SCI_SHOT_ON_VIEW="${VIEW},/w/out/shot" timeout 200 \
  ./scummvm-src/scummvm --config=/w/out/scummvm.ini sq1-cht >/w/out/shot/shot.log 2>&1 &
sleep 30
WID=$(xdotool search --class scummvm | head -1)
xdotool windowactivate "$WID" 2>/dev/null; sleep 1
for i in 1 2 3 4 5 6; do xdotool mousemove 432 457; sleep 1; xdotool click 1; sleep 3; done
sleep 90
pkill -f scummvm 2>/dev/null || true
sleep 1
chown -R 1000:1000 /w/out
