# 十一术式水墨图集

2026-09-29 · Codex 内置 image_gen.imagegen 生成，transparent_background=true。

生产文件：skill-ink-atlas.png。4列×3行，按 js/data.js 的卡牌顺序排列，末格透明。直接从生成目录复制，保留原图与透明通道；未通过其他工具裁切或重绘。CSS背景位置显示各格，名称、费用与状态均为实时DOM。用于藏经阁装备槽、三列收藏、技能详情。短横屏槽位优先显示名称和卸下操作，收藏与详情仍显示图案。

顺序：剑气诀、破甲符、金刚罩、回春丹；神行步、连击令、天雷引、聚灵阵；焚风诀、金蝉脱壳、金刚符、透明空格。

原图：exec-ebe5af7b-6ba1-45a0-8484-65beea6e8d30.png。独立候选剑气诀、破甲符原图另保留于 verification/skill-art/alternates/，游戏使用统一图集。符箓上的装饰笔画不作为名称或规则文字。

总览：verification/skill-art/catalog.html 与 skill-patterns.png。总览通过浏览器排版生成，包含真实PNG图案与独立中文标签，不是另一张AI概念图。

## 最终图集提示词

Create ONE production-ready UI sprite atlas for a Chinese ink-watercolor xianxia game. Transparent background. EXACTLY 4 equal columns by 3 equal rows, landscape canvas 4:3. Each cell square, one isolated emblem fully contained within the central 72% of its cell, with ample clear margin, no overlaps or off-grid decorative elements. Same fine ink contour and muted watercolor style throughout, rich dark outlines readable at 44px. NO labels, names, letters, numbers, card frames, borders, background scenery or UI. Top row, left to right: (1) jade-green straight sword surrounded by a pale cyan crescent of sword energy; (2) red paper talisman piercing a visibly split dark bronze armor plate; (3) antique golden bell inside a translucent amber protective dome; (4) green medicinal pearl cradled by pale lotus petals and green leaves. Middle row, left to right: (5) dark teal cloth boot riding a cloud inside a protective wind ring; (6) red wooden command token with TWO crossed crimson sword-energy arcs; (7) bold jagged violet lightning bolt beneath a dark indigo thundercloud; (8) five jade stones forming a circular magic formation around a glowing teal orb. Bottom row, left to right: (9) elegant orange-cinnabar flame shaped like a twisting gust of wind; (10) golden cicada shell with translucent wings and a small jade life-energy wisp; (11) ochre paper talisman in front of a sturdy angular bronze-gold shield; (12) EMPTY TRANSPARENT CELL. Distinguish round protective bell from angular shield; healing pearl from magic formation. All 11 emblems consistent size and painting style, maximum legibility on pale rice-paper UI. Absolutely no words or numbers anywhere. Genuinely transparent RGBA background.

