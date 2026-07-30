#!/bin/bash
export HOME=/tmp XDG_RUNTIME_DIR=/tmp DISPLAY=:99 SDL_AUDIODRIVER=dummy
Xvfb :99 -screen 0 1024x768x24 >/tmp/xvfb.log 2>&1 &
sleep 2
mkdir -p /w/out/intro
cd /w
timeout 100 ./scummvm-src/scummvm --config=/w/out/scummvm.ini sq1-ega-cht >/w/out/intro.log 2>&1 &
sleep 5
for s in $(seq 0 17); do
  import -window root /w/out/intro/in_$(printf %02d $s).png 2>/dev/null || true
  sleep 5
done
pkill -f scummvm 2>/dev/null || true
sleep 1
chown -R 1000:1000 /w/out
