# 招牌點陣原稿（VGA）

這裡放的是**我們自己畫的**中文招牌點陣圖，不是遊戲資源。

| 檔案 | 尺寸 | 用途 |
|---|---|---|
| `alert_v3.png` | 33 × 19 | 阿寇達號走廊的警示牌，`RED ALERT` → 警報 |
| `rocket_v3.png` | 95 × 23 | 尤倫斯荒原的酒吧霓虹招牌，`ROCKET` → 火箭酒吧 |

`rocket_v3.png` 裡的**洋紅 `(255,0,255)` 代表透明**（哨兵色，不在遊戲調色盤內）。
只有原本是綠色燈管的 958 個像素是不透明的，其餘讓真正的旗面透出來。

改圖之後跑 `tools/vga/design_signs.py` 重新產生，再用 `tools/vga/bake_cels_cn.py`
烘成 `dist-cht/vga/sq1_cels.dat`。要看實機效果用 `tools/vga/shoot_variant.sh`。
