#!/bin/bash
export HOME=/tmp XDG_RUNTIME_DIR=/tmp DISPLAY=:99 SDL_AUDIODRIVER=dummy
Xvfb :99 -screen 0 1024x768x24 >/tmp/xvfb.log 2>&1 &
sleep 2
cd /w
SCI_DUMP_PIC=/w/out/pics timeout 45 ./scummvm-src/scummvm --config=/w/out/scummvm.ini sq1-cht >/w/out/dumppic.log 2>&1 &
sleep 40
pkill -f scummvm 2>/dev/null || true
sleep 1
cd /w/out/pics && for f in *.ppm; do convert "$f" "${f%.ppm}.png" 2>/dev/null; done
chown -R 1000:1000 /w/out
