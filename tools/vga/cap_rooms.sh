#!/bin/bash
# 一次跑多個 room：每個 room 開一個新的 scummvm 行程（同一行程只能跳一次房）。
export HOME=/tmp XDG_RUNTIME_DIR=/tmp DISPLAY=:99 SDL_AUDIODRIVER=dummy
Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
sleep 3
mkdir -p /w/out/room
cd /w
for ROOM in "$@"; do
  timeout 150 ./scummvm-src/scummvm --config=/w/out/scummvm.ini sq1-cht \
    >/w/out/room/room${ROOM}.log 2>&1 &
  sleep 34
  WID=$(xdotool search --class scummvm | head -1)
  xdotool windowactivate "$WID" 2>/dev/null; sleep 1
  xdotool mousemove 432 457; sleep 1; xdotool click 1
  sleep 14
  xdotool key --clearmodifiers ctrl+alt+d ; sleep 3
  xdotool type --clearmodifiers "room ${ROOM}"
  xdotool key --clearmodifiers Return ; sleep 4
  xdotool type --clearmodifiers "exit"
  xdotool key --clearmodifiers Return ; sleep 5
  import -window root /w/out/room/room${ROOM}_a.png
  sleep 4
  import -window root /w/out/room/room${ROOM}_b.png
  pkill -f scummvm 2>/dev/null || true
  sleep 3
done
chown -R 1000:1000 /w/out
