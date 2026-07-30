# 建置與重現

全程走 docker，不污染系統環境。

## 需要的東西

- docker
- 正版遊戲（EGA 版與 VGA 版各一份）
- 倚天中文系統 3.53 的點陣字檔（`STDFONT.15` / `SPCFONT.15` / `SPCFONT.24` / `STD.24M`）——**有版權，不入庫**，請自備並放到 `tools/<track>/assets/eten/`。`STD.24M` 要先用 `tools/<track>/etunpack.py` 解壓成 `stdfont.24`。
- MT-32 ROM（選用，只有完整包會用到；**有版權，不入庫**）

## 兩條軌

本作 EGA 與 VGA 是兩個不同的引擎，各自獨立：

| | 目錄 | 引擎 | configure |
|---|---|---|---|
| EGA 1986 | `patches/ega/` `dist-cht/ega/` | AGI | `--enable-engine=agi` |
| VGA 1991 | `patches/vga/` `dist-cht/vga/` | SCI | `--enable-engine=sci` |

一棵原始碼樹只套一條軌的 patch。

## 步驟

```bash
# 1. 取 pinned 的 ScummVM 原始碼並套 patch
git clone https://github.com/scummvm/scummvm.git scummvm-src
git -C scummvm-src checkout "$(cat patches/vga/UPSTREAM_COMMIT.txt)"
bash tools/apply_patches.sh scummvm-src vga

# 2. configure + make（docker 內）
#    [HARD] --disable-all-engines 要排在 --enable-engine 之前
#    [HARD] 不可帶 --disable-mt32emu；本專案一律啟用 MT-32
docker run --rm --name sq1-build -v "$PWD/scummvm-src":/src -w /src <build-image> bash -c \
  './configure --disable-all-engines --enable-engine=sci --disable-detection-full && make -j$(nproc)'

# 3. 烘中文資料（譯文 → Big5 runtime 表 + 倚天字型）
bash tools/vga/build_and_deploy.sh
```

`build_and_deploy.sh` 會做：合併批次譯文 → 依英文 key 圈定的修正 → 譯名收斂 → 烘倚天字型 → 部署到 `game/`。

## 檢查工具

```bash
python3 tools/<track>/validate_batch.py <batch> <done>   # 行數、key、控制序列、長度比
python3 tools/<track>/scan_zh.py <檔或目錄>               # 簡體字、中國用語、非 Big5
python3 tools/nameaudit.py <譯文檔或目錄>                 # 譯名漂移（只數不猜）
bash tools/verify_packages.sh                             # 逐包比對中文資料 md5
```

三支前面的工具都測不到語意層面的錯（因果講反、指涉不明、梗沒翻出來）。那些只能靠人工抽樣與實機 playtest。

## 幾個會咬人的地方

- **字型每字步幅要跟引擎宣告的高度一致。** AGI 端寫死 `loadPrefixedRaw(fnt, 16)`，倚天 16×15 每字只有 15 列，不補到 16 列的話畫面上會「有些字對、有些變成別的字、有些消失」，而字型檢查工具會回報零缺字。烘字時帶 `--lo-pad-height 16`。
- **收斂表要按錯誤寫法長度遞減排序再套用**，否則短規則會先吃掉長規則的目標。`build_and_deploy.sh` 已內建排序。
- **`patches/*/UPSTREAM_COMMIT.txt` 只能放裸的 commit hash**，CI 會直接拿它當 git ref。
- **docker 產出的檔案 owner 是 root**，每個 docker 步驟收尾要補 `chown -R 1000:1000`。
- macOS 的 `.app` / `.dmg` 只能在 macOS host 上做（codesign / hdiutil / iconutil 都是 macOS 限定），走 `.github/workflows/build-macos.yml`。
