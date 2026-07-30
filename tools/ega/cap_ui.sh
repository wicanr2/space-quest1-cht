#!/bin/bash
# UI 巡查：每個動作前先把訊息框清乾淨，否則功能鍵會被當成「關掉框」吃掉，
# 截到的全是訊息框（SQ2 踩過，看起來巡查過了其實一個 UI 都沒進到）。
export HOME=/tmp XDG_RUNTIME_DIR=/tmp DISPLAY=:99 SDL_AUDIODRIVER=dummy
Xvfb :99 -screen 0 1024x768x24 >/tmp/xvfb.log 2>&1 &
sleep 2
mkdir -p /w/out/ui
cd /w
timeout 150 ./scummvm-src/scummvm --config=/w/out/scummvm.ini sq1-ega-cht >/w/out/ui.log 2>&1 &
sleep 8
WID=$(xdotool search --class scummvm | head -1)
k(){ xdotool key --clearmodifiers --window "$WID" "$1"; sleep 1.5; }
clear_box(){ k Return; k Return; k Escape; sleep 1; }
# 先推進過開場字幕（每次 Return 推一段）
for i in $(seq 1 14); do k Return; done
sleep 3
import -window root /w/out/ui/00_after_intro.png
clear_box
import -window root /w/out/ui/01_game.png
k Tab                       # 道具欄
sleep 2; import -window root /w/out/ui/02_inventory.png
k Escape; sleep 1; clear_box
k Escape                    # 選單列
sleep 2; import -window root /w/out/ui/03_menu.png
k Right; sleep 1; import -window root /w/out/ui/04_menu2.png
k Escape; sleep 1; clear_box
k F5                        # 存檔
sleep 2; import -window root /w/out/ui/05_save.png
k Escape; sleep 1; clear_box
k F7                        # 讀檔
sleep 2; import -window root /w/out/ui/06_restore.png
k Escape; sleep 1
pkill -f scummvm 2>/dev/null || true
chown -R 1000:1000 /w/out
