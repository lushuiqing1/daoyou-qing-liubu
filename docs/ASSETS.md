# 网页轻体验美术来源

本页复用《道友请留步》水墨版已有独立生产素材。人物、棋子、术式与场景分层呈现；数值、血条、卡名和操作均由真实 DOM 渲染。未将战斗截图铺为背景或设置透明热点。

全部素材均来自本项目 `道友请留步-Godot-水墨版/assets/`。背景、人物和术式原作及生成说明已随完整源码保留。本次仅缩小或切分原有图集后压缩为 WebP，保留人物和术式透明通道，没有下载外部图片、字体或库。原素材文件不作修改。

| 网页文件 | 原素材 | 处理 |
| --- | --- | --- |
| `background.webp` | `battle-bamboo-background.png` | 900px 宽，WebP 78 |
| `scene.webp` | `battle-bamboo-background.png` | 截取上部无字竹林环境，1000px 内，WebP 82 |
| `player.webp` | `player-portrait.png` | 360 × 700 内，透明 WebP 87 |
| `enemy.webp` | `enemies/bamboo-puppet.png` | 640px 内，透明 WebP 84 |
| `boss.webp` | `enemy-portrait.png` | 640px 内，透明 WebP 84 |
| `tile-*.webp` | 五张 `tile-*-watercolor.jpg` | 160px，WebP 89 |
| `skill-*.webp` | `skill-ink-atlas.png` | 4 × 3 图集切为11张透明术式图，160px，WebP 87 |
| `status-*.svg` | `ui/status-*.svg` | 原始矢量图直接复制 |

术式图顺序：`sword`、`armorBreak`、`ward`、`heal`、`step`、`comboOrder`、`thunder`、`spiritArray`、`flame`、`golden`、`ironwall`。棋子图名：`sword`、`shield`、`heart`、`scroll`、`coin`。

压缩过程使用本地 Pillow；转换脚本与各图尺寸、字节记录位于项目交付目录之外的 `outputs/web-demo-qa/`，不参与网页运行。
