#!/usr/bin/env bash
# 交叉編譯 Windows 版 ScummVM（mingw-w64），產出 scummvm-win/scummvm.exe。
#
# 用法: tools/build_windows.sh
#
# 兩個踩過的雷：
# 1. 複製 source 樹時**不可排除 config.guess / config.sub**，否則 configure 判不出
#    endianness，會停在 "unknown endianness"。
# 2. 啟用先前停用過的子系統（這裡是 mt32emu）時，其 vendor 靜態標頭可能在複製時缺席，
#    mingw 編譯會報 MT32EMU_VERSION_* 未宣告。複製完先比對 audio/softsynth/mt32 補齊。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/scummvm-src"
WIN="$ROOT/scummvm-win"

if [ ! -d "$WIN" ]; then
  echo ">> 建立 scummvm-win source 樹（自 scummvm-src，排除 .git 與 build 產物）"
  mkdir -p "$WIN"
  tar -C "$SRC" --exclude=.git --exclude='*.o' --exclude='*.dwo' --exclude='*.d' \
      --exclude='.deps' --exclude=scummvm --exclude=config.log --exclude=config.mk \
      -cf - . | tar -C "$WIN" -xf -
else
  echo ">> scummvm-win 已存在，同步 engines/agi 的原始碼（**只同步原始碼**）"
  # [雷 3] 不可以 `cp -a engines/agi/.`：scummvm-src 是本機 Linux 編過的樹，裡面有 ELF 的
  # .o/.d/.dwo。整個目錄複製會用 ELF 物件檔蓋掉 mingw 的同名物件檔，且時間戳較新，
  # make 判定不用重編 → 直接拿 ELF .o 去連結 → 幾百條
  # "undefined reference to Agi::GfxMgr::..."，看起來像原始碼壞掉，其實是物件檔架構不符。
  find "$SRC/engines/agi" -name '*.cpp' -o -name '*.h' | while read -r f; do
    rel="${f#$SRC/}"
    mkdir -p "$WIN/$(dirname "$rel")"
    cp "$f" "$WIN/$rel"
  done
fi

# 雷 1：確認 endianness 探測所需檔案在
for f in config.guess config.sub; do
  [ -f "$WIN/$f" ] || cp "$SRC/$f" "$WIN/$f"
done
# 雷 2：mt32emu vendor 標頭
if [ -d "$SRC/audio/softsynth/mt32" ]; then
  mkdir -p "$WIN/audio/softsynth/mt32"
  cp -an "$SRC/audio/softsynth/mt32/." "$WIN/audio/softsynth/mt32/" 2>/dev/null || true
fi

echo ">> configure + make（mingw，AGI-only，保留 mt32emu）"
docker run --rm --name sq1-mingw-build -v "$WIN":/src -w /src sq1-mingw bash -c '
  set -e
  ./configure --host=x86_64-w64-mingw32 \
      --disable-all-engines --enable-engine=agi --disable-detection-full \
      > /src/configure-win.log 2>&1
  grep -E "MT32|Backend|WARNING" /src/configure-win.log | head -5 || true
  grep -q "^#define USE_MT32EMU" config.h && echo "   USE_MT32EMU 已啟用" || { echo "!! mt32emu 未啟用"; exit 1; }
  make -j8 > /src/make-win.log 2>&1
  ls -la scummvm.exe
'
echo ">> 完成: $WIN/scummvm.exe"
