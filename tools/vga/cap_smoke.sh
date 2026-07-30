#!/bin/bash
# VGA(SCI1) 軌 headless 煙霧測試：開場跑一段、每 3 秒截一張。
# [HARD] 容器內執行；呼叫端一律用 timeout 包，收尾 pkill 掉遊戲行程
#        （引擎的 dump/env hook 跑完不會自己退出，不 kill 會永久卡住）。
export HOME=/tmp XDG_RUNTIME_DIR=/tmp DISPLAY=:99 SDL_AUDIODRIVER=dummy
Xvfb :99 -screen 0 1024x768x24 >/tmp/xvfb.log 2>&1 &
sleep 2
mkdir -p /w/out/shots
cd /w
timeout 80 ./scummvm-src/scummvm --config=/w/out/scummvm.ini sq1-cht >/w/out/smoke.log 2>&1 &
sleep 6
for s in $(seq 0 15); do
  import -window root /w/out/shots/sm_$(printf %02d $s).png 2>/dev/null || true
  xdotool key --clearmodifiers Escape 2>/dev/null || true
  sleep 3
done
pkill -f scummvm 2>/dev/null || true
sleep 1
chown -R 1000:1000 /w/out
