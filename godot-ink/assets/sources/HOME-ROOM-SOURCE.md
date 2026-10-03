# 洞府主城美术来源

2026-09-27，用户批准主界面预览并明确要求落地到 v15。

- 批准预览：`verification/room-home/approved-preview.png`。
- 运行背景：`home-room-scene.png`，由内置 imagegen 编辑批准预览生成。保留坐姿沈砚、茶盏、佩剑、洞府与山水窗景，去除界面文字、图标和面板。界面控件由真实 HTML/CSS 渲染，动态数值直接读取游戏状态。
- 源文件：`生成原图归档/01a0e1dd-eea9-7272-b0f5-6664613874a3/exec-7864bc06-456b-40d4-977b-80cb95215c7b.png`。运行时只依赖本目录内文件。
- 复用既有 `home-ink-icons.png` 图集、`home-ink-brush.png` 朱砂笔触及宣纸纹理。

## 三处 UI 保真修正（2026-09-27）

用户指出首次落地的底部导航、顶部资源条与右上境界未匹配批准预览，本轮为这三个区域独立生成组件。以下源文件均位于 `生成原图归档/01a0e1dd-eea9-7272-b0f5-6664613874a3/`；运行时只引用本 assets 目录内的副本。

| 运行素材 | 尺寸与透明性 | 源文件 | 用途 |
| --- | --- | --- | --- |
| `home-room-dock.png` | 2172×724，不透明 | `exec-98b2922e-75e6-4dc5-85c6-dd89e250fd88.png` | 暖象牙纸底及五个大导航图案；名称由真实 HTML 覆盖 |
| `home-room-resources.png` | 2172×724，透明 | `exec-a091c100-10fb-4f5c-9512-e96b52d3707e.png` | 玉葫芦、铜钱、无字撕纸横条；实时气血、铜钱及加号由 HTML 提供 |
| `home-room-realm.png` | 1536×1024，透明 | `exec-a7163c8c-a48e-407d-882c-b038af677658.png` | 木轴、绳索、流苏及留白山水卷轴；境界名称、标题与进度点由 HTML 提供 |

三幅组件由内置 imagegen 生成，方向依据同一批准预览；此处记录用途与来源，未保存的逐字生成提示词不作补写。底栏不再使用旧图集中的五个导航图案；旧图集仍用于其他既有入口，朱砂笔触继续复用。组件的标签、数值和操作均未烘焙到图像中。

## 四处 UI 继续保真修正（2026-09-27）

用户继续指出标题矩形底、左侧图案、章节矩形底及行囊重叠、方形双列人物名牌与批准预览不符。新增以下独立透明组件。源文件仍位于上述 `generated_images/01a0e1dd-eea9-7272-b0f5-6664613874a3/` 目录，运行时只引用本 assets 目录副本。

| 运行素材 | 尺寸与透明性 | 源文件 | 用途 |
| --- | --- | --- | --- |
| `home-room-title.png` | 2172×724，透明 | `exec-88d1b626-7b60-4ffc-bee0-3acfe60e586e.png` | 固定云隐山麓书法与红印，无矩形底 |
| `home-room-rail.png` | 724×2172，透明 | `exec-df6b89cc-6d5e-4698-9712-d548cfcb5883.png` | 三等格竖图集：设置齿轮、红绳任务纸笺、修炼莲花与固定中文标签 |
| `home-room-tags.png` | 1024×1536，透明 | `exec-38812611-30d0-4a77-911a-2a72e3ea5c10.png` | 两等列图集：沈砚/听雨剑客单列人物竖签、行囊签 |
| `home-room-chapter.png` | 2172×724，透明 | `exec-732f6eb3-4c3c-4814-a995-1599cbb0070c.png` | 留白毛边纸洗与菱形饰纹，承托实时章节和暂停状态 |

四幅素材由内置 imagegen 生成，方向依据同一批准预览；此处仅记录已知来源与用途，不补造未保存的逐字提示词。本轮标题、左侧入口、人物及行囊使用固定图像题字，同时保留真实 HTML 名称及无图回退。章节底不含文字，章节、暂停状态、奖励徽标与其他实时数值不烘焙进图。此前三处 UI 组件及原场景继续保留。

## 背景生成提示词

Edit target: the supplied approved Chinese watercolor game UI. Deliver a production background illustration ONLY, portrait exact 9:16 composition matching input. Remove ALL UI and ALL TEXT from this image: the two resource strips at top, upper-left 云隐山麓 calligraphy, all left-edge shortcut icons and their paper labels, the entire hanging upper-right realm scroll plaque (including progress dots), hero name label, bag text tag, chapter label, entire red CTA brush button, entire bottom navigation parchment panel including its icons. Inpaint the newly uncovered areas as continuous matching room scenery. Keep the existing seated young male hero Shen Yan's exact face, pose, clothing, red sash, tea cup, ponytail, chair, sword and full boots; keep the surrounding ancient wooden study, open right window, bamboo curtain, mountain waterfall and cliff temple, desk, incense, physical satchel and scroll props. Do not redesign the room or move the character. At the very bottom formerly occupied by dock extend the wooden floor naturally with restrained ink-wash fading, no additional props. Preserve quiet space top-left for title, top-right for a new real HTML realm panel, and lower center for a real HTML start button. Same delicate painterly semi-realistic Chinese ink and mineral watercolor on warm ivory paper, muted jade-gray and warm wood, not photorealistic or cartoon. No letters, digits, Chinese characters, seals, icons, panels, signs, labels, buttons or HUD remain anywhere. High detail illustration matching approved scene faithfully.


> 发布副本说明：本机绝对路径已替换为来源归档标识；原始工作文件未改动。游戏运行只依赖工程内素材。
