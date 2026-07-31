#!/bin/bash
# 跳到指定 room 截圖（找／驗證烘進美術的字用）。
#
# [HARD] 換場要用 `send ?sq1 newRoom <n>`，**不要用 `room <n>`**。
#   console 的 `room` 只是把全域變數 g13（目前房號）改掉，並不觸發換場；房間腳本
#   下一輪又把它蓋回去，結果是「console 印了 Room number changed，畫面卻沒動」，
#   很容易誤判成「debugger 換場不穩」。`newRoom` 是 Game 物件的方法，才是真的換場。
#   物件怎麼找：console 打 `vmvars g 1` → SQ1 VGA 是 `object 'sq1'`
#   （g0 是 ego、g2 是目前房間物件）。換別款遊戲先用這招問一次。
#
# [HARD] 開 console 之前先把畫面上的訊息框點掉。框開著的時候遊戲主迴圈是停的，
#   換場不會發生（CLAUDE.md ⑩「每個 UI 動作前先把框清乾淨」）。
#
# 其他踩過的雷：
#   ① Xvfb 要暖機；② root 開 1024x768（640x480 收不到鍵盤）；③ 換完場先 `exit`
#   再截圖；④ `xdotool key --window <id>` 走 XSendEvent，**SDL2 預設忽略合成事件**
#   → 要 windowactivate 後送不帶 --window 的 XTEST 事件；⑤ `xdotool type` 太快
#   SDL 會漏字元，要 --delay。
ROOM="${1:?用法: cap_room.sh <room>}"
GAMEOBJ="${GAMEOBJ:-?sq1}"
TAG="${TAG:-}"
export HOME=/tmp XDG_RUNTIME_DIR=/tmp DISPLAY=:99 SDL_AUDIODRIVER=dummy
Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
sleep 3
mkdir -p /w/out/room /w/out/shot
cd /w
[ -n "${SHOTVIEW:-}" ] && export SCI_SHOT_ON_VIEW="$SHOTVIEW,/w/out/shot"
SCI_LOG_GFX=1 SCI_LOG_VIEWS=1 timeout 240 ./scummvm-src/scummvm --config=/w/out/scummvm.ini sq1-cht \
  >/w/out/room/room${ROOM}${TAG}.log 2>&1 &
sleep 30
WID=$(xdotool search --class scummvm | head -1)
xdotool windowactivate "$WID" 2>/dev/null; sleep 1
# 開場「要跳過片頭嗎」對話框出現的時間會飄，單次點擊常 miss → 連點。
for i in 1 2 3 4 5 6; do
  xdotool mousemove 432 457; sleep 1; xdotool click 1; sleep 3
done
# [注意] 這裡**不要**再多點幾下想「先清訊息框」。`send ... newRoom` 是直接執行的，
# 不像 `room` 要等主迴圈讀變數，所以框開著也換得過去；多點反而會讓角色走動、
# 觸發新的動作，實測會讓換場失敗。
sleep 6
xdotool key --clearmodifiers ctrl+alt+d ; sleep 3
xdotool type --clearmodifiers --delay 120 "send ${GAMEOBJ} newRoom ${ROOM}"
xdotool key --clearmodifiers Return ; sleep 3
xdotool type --clearmodifiers --delay 120 "exit"
xdotool key --clearmodifiers Return ; sleep 8
import -window root /w/out/room/room${ROOM}${TAG}_a.png
sleep 5
import -window root /w/out/room/room${ROOM}${TAG}_b.png
# 到站後常會有一個「進場敘述」訊息框擋住畫面 → 點掉再補一張乾淨的。
for i in 1 2 3; do xdotool mousemove 512 200; xdotool click 1; sleep 2; done
sleep 4
import -window root /w/out/room/room${ROOM}${TAG}_clean.png
pkill -f scummvm 2>/dev/null || true
sleep 1
chown -R 1000:1000 /w/out
