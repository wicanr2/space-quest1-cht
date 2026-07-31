#!/bin/bash
# 進遊戲後連拍，用來抓「只出現一下子」的畫面（例如倒數計時面板）。
export HOME=/tmp XDG_RUNTIME_DIR=/tmp DISPLAY=:99 SDL_AUDIODRIVER=dummy
Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
sleep 3
mkdir -p /w/out/burst
cd /w
SCI_LOG_GFX=1 timeout 200 ./scummvm-src/scummvm --config=/w/out/scummvm.ini sq1-cht \
  >/w/out/burst/burst.log 2>&1 &
sleep 30
WID=$(xdotool search --class scummvm | head -1)
xdotool windowactivate "$WID" 2>/dev/null; sleep 1
for i in 1 2 3 4 5 6; do xdotool mousemove 432 457; sleep 1; xdotool click 1; sleep 3; done
for i in $(seq -w 1 30); do
  import -window root /w/out/burst/b_${i}.png
  sleep 2
done
pkill -f scummvm 2>/dev/null || true
sleep 1
chown -R 1000:1000 /w/out
