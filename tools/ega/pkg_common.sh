#!/usr/bin/env bash
# 共用函式:中文資料 staging + 玩家 README 生成。
# 供 tools/package.sh(本機 Linux/Windows/dev-setup)與 tools/package_macos_data.sh(macOS CI 後製)共用,
# 確保三平台的中文資料內容與說明文字一致、不因各自維護一份而drift。
#
# 用法:source tools/pkg_common.sh   (呼叫端須先定義 ROOT 變數,指向 repo 根目錄)

# 中文資料包 staging:$1=vga|ega  $2=輸出目錄
# LSL1 是「內容比對替換」中文化:只需 translation.tsv + Big5 字型,無 view/pic 美術 patch。
# 來源用版控內的 runtime 快照(fonts/=EGA、fonts_vga/=VGA;build_cht.py 也是輸出到這兩處),
# CI checkout 直接可用。字型檔須改名成引擎實際 open 的檔名(EGA lsl_big5.fnt / VGA lsl1_big5.fnt)。
stage_cht_data() {
  local edition="$1" out="$2" base fnt_dst
  rm -rf "$out"; mkdir -p "$out"
  if [ "$edition" = vga ]; then
    base="$ROOT/fonts_vga"; fnt_dst="lsl1_big5.fnt"   # SCI 引擎 open lsl1_big5.fnt
  else
    base="$ROOT/fonts";     fnt_dst="lsl_big5.fnt"    # AGI 引擎 open lsl_big5.fnt(靠檔存在啟用中文)
  fi
  [ -f "$base/translation.tsv" ] || { echo "!! 找不到 $base/translation.tsv(先跑 build_cht.py 或確認 checkout 含 runtime 快照)" >&2; return 1; }
  cp "$base/translation.tsv" "$out/translation.tsv"
  cp "$base/qfg1_big5.fnt"   "$out/$fnt_dst"          # build_cht 固定輸出 qfg1_big5.fnt,依版改名
  # 標題疊圖(EGA「幻想空間」中文標題)—有才複製,引擎缺檔自動略過
  [ -f "$base/lsl_title.ovl" ] && cp "$base/lsl_title.ovl" "$out/lsl_title.ovl"
  echo ">>    staged $(ls "$out" | wc -l) 個中文資料檔 → $out"
}

# MT-32 ROM staging(僅完整包 dist-all;[HARD] 絕不入 GitHub release/patch 包)。
# 把 Roland MT-32 ROM 改名成 ScummVM Munt 認的檔名放進 $1;有放成功回 0、無回 1(呼叫端據此決定要不要設 music_driver=mt32)。
# 來源 MT32_ROM_SRC 預設本機 /home/anr2/cht/mt32(ROM 有版權,不散布、不入版控)。優先 1987 v1.07 老 MT-32(合 LSL1 年代)。
MT32_ROM_SRC="${MT32_ROM_SRC:-/home/anr2/cht/mt32}"
stage_mt32_rom() {
  local out="$1" ctrl
  ctrl=$(ls "$MT32_ROM_SRC"/MT32_CONTROL.1987*.ROM "$MT32_ROM_SRC"/MT32_CONTROL*.ROM "$MT32_ROM_SRC"/MT32_CONTROL.ROM 2>/dev/null | head -1)
  if [ -z "$ctrl" ] || [ ! -f "$MT32_ROM_SRC/MT32_PCM.ROM" ]; then
    echo ">>    (無 MT-32 ROM @ $MT32_ROM_SRC → 略過,完整包退回預設音效驅動)" >&2
    return 1
  fi
  cp "$ctrl" "$out/MT32_CONTROL.ROM"
  cp "$MT32_ROM_SRC/MT32_PCM.ROM" "$out/MT32_PCM.ROM"
  echo ">>    MT-32 ROM 已放入 $out（完整包專用，$(basename "$ctrl")→MT32_CONTROL.ROM）" >&2
  return 0
}

# 中文資料包玩家 README(繁中,說明部署方式):$1=vga|ega  $2=linux|windows|macos
gen_readme() {
  local edition="$1" platform="$2"
  local edition_zh fnt_name target lang_hint launch_zh
  if [ "$edition" = vga ]; then
    edition_zh="VGA(1991 重製版,SCI1,256 色)"
    fnt_name="lsl1_big5.fnt"; target="lsl1sci"
    lang_hint="把 Language 設為 Chinese(Taiwan)(或啟動時帶 --language=tw)"
    launch_zh="--language=tw"
  else
    edition_zh="EGA(1987 原版,AGI,16 色)"
    fnt_name="lsl_big5.fnt"; target="lsl1"
    # AGI 版中文靠「字型檔存在」啟用,不能帶 --language(非英文會使遊戲無法啟動);EGA 用 --render-mode=ega
    lang_hint="不需設定語言——只要 lsl_big5.fnt 在遊戲資料夾內,中文自動啟用"
    launch_zh="--render-mode=ega"
  fi
  cat <<EOF
幻想空間(Leisure Suit Larry in the Land of the Lounge Lizards)繁體中文化 — $edition_zh

本包內容
--------
- patched ScummVM 執行檔(含 Big5 繪字引擎改動:AGI 逐字繪字 / SCI 內容比對替換)
- cht-data-${edition}/:中文資料(translation.tsv 對白/訊息、$fnt_name Big5 點陣字型)
- 本說明檔

本包【不含】原遊戲資源。請自備合法取得的《幻想空間》${edition} 版遊戲檔。

安裝步驟
--------
1. 準備好你自己的《幻想空間》${edition} 版遊戲資料夾($([ "$edition" = vga ] && echo 'RESOURCE.MAP / RESOURCE.00x' || echo 'LOGDIR / PICDIR / VIEWDIR / VOL.* / WORDS.TOK') 等,檔名請一律小寫)。
2. 把 cht-data-${edition}/ 資料夾內的所有檔案,複製進上述遊戲資料夾(與遊戲資源同一層)。
3. 執行本包的 ScummVM 執行檔(見下方「執行方式」)。
4. 在 ScummVM 啟動器按「Add Game...」,選剛才那個遊戲資料夾加入。
5. ${lang_hint}。
EOF
  echo
  echo "執行方式"
  echo "--------"
  case "$platform" in
    linux)
      cat <<EOF
./幻想空間-$( [ "$edition" = vga ] && echo VGA || echo EGA )-x86_64.AppImage
（AppImage 已內含執行必需的共享庫,免安裝系統套件；若系統禁用 FUSE,
 可改用 --appimage-extract-and-run,或直接執行展開後的 AppRun。）
啟動器內請選 ${target} target$( [ "$edition" = ega ] && echo '(EGA 版以 --render-mode=ega 執行)')。
EOF
      ;;
    windows)
      cat <<EOF
雙擊「玩-幻想空間-繁中.bat」即可(會自動 --add 遊戲並以中文 target 啟動)。
也可手動執行:scummvm.exe $launch_zh --path="你的遊戲資料夾路徑" ${target}
EOF
      ;;
    macos)
      cat <<EOF
把 ScummVM.app 拖進「應用程式」,第一次執行前先解除 Gatekeeper 隔離(未簽署 app):
  xattr -dr com.apple.quarantine /Applications/ScummVM.app
中文資料已預先放進 .app/Contents/Resources/cht-data-${edition}/,
仍需依「安裝步驟」複製到你自己的遊戲資料夾(.app 本身不含遊戲資源)。
啟動:開啟 ScummVM.app 後在啟動器 Add Game,或終端機:
  ScummVM.app/Contents/MacOS/scummvm $launch_zh --path="你的遊戲資料夾路徑" ${target}
EOF
      ;;
  esac
  cat <<'EOF'

交付原則
--------
中文化僅以 ScummVM patch 形式交付(引擎改動 + 中文資料),原遊戲資源不入包、不散布。
repo:https://github.com/wicanr2/Leisure_Suit_Larry1-cht
EOF
}
