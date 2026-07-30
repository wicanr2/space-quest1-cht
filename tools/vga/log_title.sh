#!/bin/bash
export HOME=/tmp XDG_RUNTIME_DIR=/tmp DISPLAY=:99 SDL_AUDIODRIVER=dummy
Xvfb :99 -screen 0 1024x768x24 >/tmp/xvfb.log 2>&1 &
sleep 2
cd /w
SCI_LOG_GFX=1 timeout 45 ./scummvm-src/scummvm --config=/w/out/scummvm.ini sq1-cht >/w/out/gfx.log 2>&1 &
sleep 40
pkill -f scummvm 2>/dev/null || true
sleep 1
chown -R 1000:1000 /w/out
