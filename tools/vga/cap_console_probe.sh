#!/bin/bash
# 在 console 裡打一串指令，每打一條就截一張，用來確認語法對不對。
export HOME=/tmp XDG_RUNTIME_DIR=/tmp DISPLAY=:99 SDL_AUDIODRIVER=dummy
Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
sleep 3
mkdir -p /w/out/probe
cd /w
timeout 200 ./scummvm-src/scummvm --config=/w/out/scummvm.ini sq1-cht >/w/out/probe/probe.log 2>&1 &
sleep 30
WID=$(xdotool search --class scummvm | head -1)
xdotool windowactivate "$WID" 2>/dev/null; sleep 1
for i in 1 2 3 4 5 6; do xdotool mousemove 432 457; sleep 1; xdotool click 1; sleep 3; done
sleep 6
xdotool key --clearmodifiers ctrl+alt+d ; sleep 3
n=0
while IFS= read -r cmd; do
  n=$((n+1))
  xdotool type --clearmodifiers --delay 100 "$cmd"
  xdotool key --clearmodifiers Return
  sleep 2
  import -window root "/w/out/probe/p$(printf %02d $n).png"
done <<'CMDS'
send ?sq1 newRoom 41
exit
vmvars g 13
CMDS
pkill -f scummvm 2>/dev/null || true
sleep 1
chown -R 1000:1000 /w/out
