#!/bin/bash
# 跳到指定 room 截圖（找 baked-art 用）。
# [HARD] 四個雷：① Xvfb 要暖機、② root 用 1024x768、③ 換場後先 exit 再截圖、
#        ④ **一個行程只能跳一次房**（第二次會 invalid port id 然後黑屏）。
# 另外：一開場是片頭動畫，直接跳房會被片頭腳本蓋回去 → 先按 Return 跳過片頭再跳房。
ROOM="${1:?用法: cap_room.sh <room>}"
export HOME=/tmp XDG_RUNTIME_DIR=/tmp DISPLAY=:99 SDL_AUDIODRIVER=dummy
Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
sleep 3
mkdir -p /w/out/room
cd /w
[ -n "${SHOTVIEW:-}" ] && export SCI_SHOT_ON_VIEW="$SHOTVIEW,/w/out/shot"
mkdir -p /w/out/shot
SCI_LOG_GFX=1 SCI_LOG_VIEWS=1 timeout 240 ./scummvm-src/scummvm --config=/w/out/scummvm.ini sq1-cht \
  >/w/out/room/room${ROOM}.log 2>&1 &
sleep 30                       # Sierra logo + 標題 + 「要不要跳過片頭」對話框
WID=$(xdotool search --class scummvm | head -1)
# [HARD雷] `xdotool key --window <id>` 走 XSendEvent，**SDL2 預設忽略合成事件** →
# 按鍵看似送出卻毫無反應（會誤以為是時序或視窗尺寸問題）。要先 windowactivate 讓它
# 取得焦點，再送**不帶 --window** 的 XTEST 事件。滑鼠同理。
xdotool windowactivate "$WID" 2>/dev/null; sleep 1
# [雷] 對話框出現的時刻會飄，**單次點擊常常 miss**；miss 掉的話後面整段都停在對話框，
# 而截圖看起來只是「畫面沒動」，很容易誤判成引擎壞掉。所以連點。
for i in 1 2 3 4 5 6; do
  xdotool mousemove 432 457; sleep 1; xdotool click 1; sleep 3
done
sleep 8
import -window root /w/out/room/room${ROOM}_pre.png
xdotool key --clearmodifiers ctrl+alt+d ; sleep 3
# [雷] type 太快 SDL 會漏字元 → 打成 `rom 41` 之類，console 靜靜地不換場。放慢。
xdotool type --clearmodifiers --delay 120 "room ${ROOM}"
xdotool key --clearmodifiers Return ; sleep 4
xdotool type --clearmodifiers --delay 120 "exit"
xdotool key --clearmodifiers Return ; sleep 5
import -window root /w/out/room/room${ROOM}_a.png
sleep 4
import -window root /w/out/room/room${ROOM}_b.png
pkill -f scummvm 2>/dev/null || true
sleep 1
chown -R 1000:1000 /w/out
