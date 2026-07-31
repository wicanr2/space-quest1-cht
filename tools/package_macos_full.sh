#!/bin/bash
# 把 GitHub Actions 建好的 macOS ScummVM.app（engine-only）在本機注入遊戲資源 ＋
# MT-32 ROM ＋ 啟動包裝，做成「完整包」（開箱即玩）。
#
# 為什麼 macOS full 不是 CI 產的：CI 只能產不含遊戲的引擎（遊戲資源不進 repo），
# 所以要「下載 CI artifact → 本機注入」。**這一格最常被忘記**——其他五格各是一行指令，
# 只有這格多一道手續（CLAUDE.md ⑥ 明列 SQ3/SQ4 都漏過）。
#
# 用法: package_macos_full.sh <ega|vga> <ci-tar.gz>
#
# [HARD] 產物含遊戲與 ROM → 只放本機 dist-all/，不上 Release、不進 repo。
# [HARD] 改動已簽名的 .app 會使簽章失效 → 移除 _CodeSignature（「未簽」勝過「壞簽」），
#        並附「修復-macOS.command」。Linux 端無法 codesign 也無法啟動 .app，
#        所以這個包**一定要在 Mac 上實跑過一次**才算驗收完成。
set -euo pipefail
TRACK="${1:?用法: package_macos_full.sh <ega|vga> <ci-tar.gz>}"
CI_TAR="${2:?用法: package_macos_full.sh <ega|vga> <ci-tar.gz>}"
WP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_SRC="$WP/$TRACK/game"
ROM_SRC="${ROM_SRC:-/home/anr2/cht/mt32}"
OUT="$WP/$TRACK/dist-all"
mkdir -p "$OUT"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
tar xzf "$CI_TAR" -C "$WORK"
APP="$WORK/ScummVM.app"
[ -d "$APP" ] || { echo "!! CI tar 內找不到 ScummVM.app" >&2; exit 1; }

# 1) 統一 game 夾：遊戲資源 ＋ 中文資料（cht 檔已經在 game/ 裡，一起複製）
GAME="$APP/Contents/Resources/game"; mkdir -p "$GAME"
cp -a "$GAME_SRC"/. "$GAME/"

# 2) MT-32 ROM 正名（完整包專用）
# [雷] 不要用 MT32_CONTROL.*.ROM 這種 glob——ROM 目錄裡有兩個版本（1987 v1.07 與
# 1988 patched），glob 同時命中兩個檔會讓 cp 因「多來源 + 非目錄目標」失敗。
# 依 CLAUDE.md ⑤ 指定 1987 v1.07（合本作 1986/1991 的年代）。
CTRL="$ROM_SRC/MT32_CONTROL.1987-10-07.v1.07.ROM"
if [ -f "$CTRL" ] && [ -f "$ROM_SRC/MT32_PCM.ROM" ]; then
  cp "$CTRL" "$GAME/MT32_CONTROL.ROM"
  cp "$ROM_SRC/MT32_PCM.ROM" "$GAME/MT32_PCM.ROM"
  echo ">> MT-32 ROM 已放入（$(basename "$CTRL") → MT32_CONTROL.ROM）"
else
  echo "!! 找不到 MT-32 ROM（$ROM_SRC），此包不含 ROM"
fi

# 3) 啟動包裝：binary 改名，Contents/MacOS/scummvm 改成 wrapper
#    （CFBundleExecutable 仍指 scummvm，所以檔名不能改）
#    [HARD] EGA(AGI) **絕對不能帶 --language**——AGI 的偵測遇非英文語言會讓遊戲
#    退回啟動器、根本進不去。中文靠 game/ 裡有沒有 sq1_big5.fnt 決定。
#    VGA(SCI) 反過來要 --language=tw。
mv "$APP/Contents/MacOS/scummvm" "$APP/Contents/MacOS/scummvm.bin"
if [ "$TRACK" = vga ]; then LANGOPT='--language=tw'; else LANGOPT=''; fi
cat > "$APP/Contents/MacOS/scummvm" <<WRAP
#!/bin/bash
DIR="\$(cd "\$(dirname "\$0")" && pwd)"; GAME="\$DIR/../Resources/game"
exec "\$DIR/scummvm.bin" --path="\$GAME" --auto-detect $LANGOPT \\
  --music-driver=mt32 --extrapath="\$GAME" "\$@"
WRAP
chmod +x "$APP/Contents/MacOS/scummvm" "$APP/Contents/MacOS/scummvm.bin"

# 4) 移除失效簽章
rm -rf "$APP/Contents/_CodeSignature"

# 5) 修復腳本
cat > "$WORK/修復-macOS.command" <<'FIX'
#!/bin/bash
# macOS 會給下載來的檔案加隔離屬性；本包為了注入遊戲資料而移除了原簽章，
# 直接開會被 Gatekeeper 擋。這支腳本清掉隔離屬性並重新 ad-hoc 簽章。
cd "$(dirname "$0")"
echo "處理中…"
xattr -cr ScummVM.app 2>/dev/null
codesign --force --deep --sign - ScummVM.app 2>/dev/null && echo "已重簽。" || echo "（codesign 略過）"
echo "完成，雙擊 ScummVM.app 就可以玩了。"
FIX
chmod +x "$WORK/修復-macOS.command"

cat > "$WORK/讀我.txt" <<TXT
宇宙傳奇I 繁體中文化 — $( [ "$TRACK" = ega ] && echo "EGA 1986 原版" || echo "VGA 1991 重製版" )　macOS 完整版

第一次使用：先雙擊「修復-macOS.command」跑一次，再開 ScummVM.app。
（本包為了把遊戲資料裝進去，原本的簽章失效了，這一步是處理 macOS 的 Gatekeeper。）

音樂預設走 Roland MT-32，ROM 已內附。
TXT

# [HARD] macOS 只有 bash 3.2（Apple 因 GPLv3 停在那版），沒有 ${VAR^^}；用 tr。
# 1991 VGA 重製版當年台灣代理叫「新宇宙傳奇I」，用「新」跟 1986 原版區別，這裡沿用。
TRACK_UC="$(printf "%s" "$TRACK" | tr "[:lower:]" "[:upper:]")"
if [ "$TRACK" = vga ]; then TITLE="新宇宙傳奇I"; else TITLE="宇宙傳奇I"; fi
NAME="${TITLE} ${TRACK_UC}-繁中-完整版-macos-universal.tar.gz"
( cd "$WORK" && tar czf "$OUT/$NAME" ScummVM.app 修復-macOS.command 讀我.txt )
echo ">> 完成: $OUT/$NAME ($(du -h "$OUT/$NAME" | cut -f1))"
