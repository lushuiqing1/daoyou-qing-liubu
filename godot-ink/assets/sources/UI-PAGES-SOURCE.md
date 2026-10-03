# 水墨全界面主题点景素材来源

生成日期：2026-09-29。

- 生成方式：Codex 内置 `image_gen.imagegen`；每个素材独立调用一次，`transparent_background: true`。未使用外部素材网站或 CLI 图像 API。
- 风格参考：本项目 `assets/map-entry-scroll.png`（先查看，作为风格参考传入；不是编辑目标）。
- 使用位置：普通页面头部右侧约 110 × 80 CSS px；莲台也可用于修炼页主题背景。文字、数值、按钮均由页面独立渲染。
- 原图均为 1536 × 1024、RGBA PNG；从生成目录原样复制，未缩放、重编码或编辑 alpha。
- 四张图均检查了真实透明通道，alpha 范围为 0–254。全透明像素占比：书卷 52.41%、器物 56.88%、莲台 44.64%、摊铺 51.84%。
- 已查看生成结果：主题物件完整，无文字、数值、按钮与界面面板；墨绿、米白与旧金风格统一。

生成原图目录：`生成原图归档/01a0eccc-c9ce-7620-a455-6fcb1a0bb1d3/`。以下四张原图均保留。

## 藏经阁书卷

项目文件：`assets/ui-library-vignette.png`。

生成原图：`exec-004bbb9d-a71f-4ef7-a3ef-5988fde6bb2b.png`。

最终提示词：

```text
Use case: stylized-concept. Production raster illustration for a Chinese xianxia mobile game, displayed as one compact decorative vignette in a page header about 110 x 80 CSS pixels. Reference image supplies ONLY the artistic style: sophisticated traditional Chinese watercolor, delicate dark ink outlines, subdued sage and deep ink-green, warm ivory paper materials, restrained aged-gold details. Generate a NEW independent subject, not the reference scroll. Landscape approximately 3:2 canvas. One bold readable compact object group, complete silhouette with clear edges and small transparent margin. True transparent background and transparent negative space. No scenic background, no rectangular paper rectangle, no frame, no words, no Chinese characters, no numerals, no pseudo-lettering, no seals or logos, no UI, no buttons. All objects fully inside canvas. Calm, refined, lightly weathered textures; not glossy 3D, not cartoon, not photorealistic. Subject: a small collection of two closed traditional thread-bound books with completely blank pale ivory covers and ink-green cloth spines, beside a partly unfurled blank paper scroll with dark wood rollers. A slender small bamboo sprig rests behind the books. Library and collected knowledge motif. Wide low arrangement, three-quarter view. The books and scroll dominate; do not add elaborate furniture.
```

## 行囊器物

项目文件：`assets/ui-bag-vignette.png`。

生成原图：`exec-6d3de19b-c0dc-45ab-9956-70871c759a7c.png`。

最终提示词：

```text
Use case: stylized-concept. Production raster illustration for a Chinese xianxia mobile game, displayed as one compact decorative vignette in a page header about 110 x 80 CSS pixels. Reference image supplies ONLY the artistic style: sophisticated traditional Chinese watercolor, delicate dark ink outlines, subdued sage and deep ink-green, warm ivory paper materials, restrained aged-gold details. Generate a NEW independent subject, not the reference scroll. Landscape approximately 3:2 canvas. One bold readable compact object group, complete silhouette with clear edges and small transparent margin. True transparent background and transparent negative space. No scenic background, no rectangular paper rectangle, no frame, no words, no Chinese characters, no numerals, no pseudo-lettering, no seals or logos, no UI, no buttons. All objects fully inside canvas. Calm, refined, lightly weathered textures; not glossy 3D, not cartoon, not photorealistic. Subject: a compact sage-green traveling cloth pouch with a simple dark drawstring, accompanied by a small pale celadon medicine flask and a sheathed short Chinese sword with aged brass fittings lying diagonally. Travel equipment and personal inventory motif. Compact wide low arrangement, three-quarter view. Limit to these three legible objects; no weapons held by a character, no person.
```

## 修炼莲台

项目文件：`assets/ui-cultivation-vignette.png`。

生成原图：`exec-6ae44fa3-611e-41ba-8497-f145a690556b.png`。

最终提示词：

```text
Use case: stylized-concept. Production raster illustration for a Chinese xianxia mobile game, displayed as one compact decorative vignette in a page header about 110 x 80 CSS pixels. Reference image supplies ONLY the artistic style: sophisticated traditional Chinese watercolor, delicate dark ink outlines, subdued sage and deep ink-green, warm ivory paper materials, restrained aged-gold details. Generate a NEW independent subject, not the reference scroll. Landscape approximately 3:2 canvas. One bold readable compact object group, complete silhouette with clear edges and small transparent margin. True transparent background and transparent negative space. No scenic background, no rectangular paper rectangle, no frame, no words, no Chinese characters, no numerals, no pseudo-lettering, no seals or logos, no UI, no buttons. All objects fully inside canvas. Calm, refined, lightly weathered textures; not glossy 3D, not cartoon, not photorealistic. Subject: a carved pale stone lotus meditation pedestal with an open ivory lotus blossom at its center, two muted green lotus leaves at its base and a very faint small curl of ink mist. Cultivation and quiet spiritual refinement motif. Wide low symmetrical three-quarter view, lotus and petal-shaped platform visually dominant. No human figures, no Buddha, no deity, no glyphs, no magical rings, no full landscape.
```

## 云游摊铺

项目文件：`assets/ui-shop-vignette.png`。

生成原图：`exec-931681a7-6f83-4d7d-ae18-b90509ed88a8.png`。

最终提示词：

```text
Use case: stylized-concept. Production raster illustration for a Chinese xianxia mobile game, displayed as one compact decorative vignette in a page header about 110 x 80 CSS pixels. Reference image supplies ONLY the artistic style: sophisticated traditional Chinese watercolor, delicate dark ink outlines, subdued sage and deep ink-green, warm ivory paper materials, restrained aged-gold details. Generate a NEW independent subject, not the reference scroll. Landscape approximately 3:2 canvas. One bold readable compact object group, complete silhouette with clear edges and small transparent margin. True transparent background and transparent negative space. No scenic background, no rectangular paper rectangle, no frame, no words, no Chinese characters, no numerals, no pseudo-lettering, no seals or logos, no UI, no buttons. All objects fully inside canvas. Calm, refined, lightly weathered textures; not glossy 3D, not cartoon, not photorealistic. Subject: a tiny traditional traveling merchant stall, empty of people, low wooden counter holding two simple ceramic jars and a folded cloth bundle, with a small sage-green cloth awning on two slender bamboo poles. Old gold wooden accents. Compact readable silhouette in three-quarter view. Street market motif with complete canopy and legs visible. No signboard, no writing, no hanging labels, no background buildings or street.
```



## 水墨路线版复用（2026-09-29）

进行中的历练路线复用本页行商/莲台点景、map-entry-background.png及GameData.enemyPortrait返回的章节敌人PNG；未生成新图片。名称、章签、当前标记、进度与状态独立渲染。连接线为程序读取已有节点边生成的SVG，不包含或替代场景插画。


> 发布副本说明：本机绝对路径已替换为来源归档标识；原始工作文件未改动。游戏运行只依赖工程内素材。
