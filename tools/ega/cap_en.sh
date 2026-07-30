#!/bin/bash
export HOME=/tmp XDG_RUNTIME_DIR=/tmp DISPLAY=:99 SDL_AUDIODRIVER=dummy
Xvfb :99 -screen 0 1024x768x24 >/tmp/xvfb.log 2>&1 &
sleep 2
mkdir -p /w/out/shots_en
cd /w
timeout 80 ./scummvm-src/scummvm --config=/w/out/scummvm_en.ini sq1-en >/w/out/smoke_en.log 2>&1 &
sleep 6
for s in $(seq 0 15); do
  import -window root /w/out/shots_en/en_$(printf %02d $s).png 2>/dev/null || true
  xdotool key --clearmodifiers Escape 2>/dev/null || true
  sleep 3
done
pkill -f scummvm 2>/dev/null || true
sleep 1
chown -R 1000:1000 /w/out
