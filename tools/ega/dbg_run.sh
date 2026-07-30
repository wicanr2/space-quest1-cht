#!/bin/bash
export HOME=/tmp XDG_RUNTIME_DIR=/tmp DISPLAY=:99 SDL_AUDIODRIVER=dummy
Xvfb :99 -screen 0 1024x768x24 >/tmp/xvfb.log 2>&1 &
sleep 2
cd /w
AGI_CHT_DEBUG=1 timeout 45 ./scummvm-src/scummvm --config=/w/out/scummvm.ini sq1-ega-cht >/w/out/dbg.log 2>&1
pkill -f scummvm 2>/dev/null || true
chown -R 1000:1000 /w/out
