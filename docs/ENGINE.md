# 浏览器轻体验战斗引擎

`engine.js` 是无依赖 UMD 模块。浏览器使用 `window.BattleDemo`，Node 使用 `require('./engine.js')`。规则以桌面版 1.5.0 的 `scripts/ink_engine.gd` 与 `data/game.json` 为依据；原工程和历史发布包没有修改。

## 试玩范围

直接进入竹林道的连续五战，击败山魈后结束。角色固定为炼气六层、桃木剑、粗布衣、古玉佩，提供青冥剑和灵气丹以降低初次试玩的难度。没有修炼倾向、养成、购物、物品消耗、领奖页或普通进度写入。金铢保留消除效果和本局铜钱计数，不兑换奖励。

角色为 170 气血、每枚赤刃 16 点基础伤害（成长攻击 13 + 青冥剑 3）、护甲 5。每个玩家回合开始有粗布衣护盾 2、古玉佩灵墨 1；首次进入时合计灵墨 4。每回合 4 步，灵墨上限 7。灵气丹使术式墨耗减 1，最低 1；卡牌说明已经显示这份固定配置下的实际数值。

五怪气血/攻击为 99/14、110/15、132/16、165/18、231/22，行动序列与规则 4 的竹林五怪相同。每层连锁增加 15% 效果；任意颜色直线四枚以上消除返 1 步，每回合最多 2 步。击败每怪恢复最大气血的 10%，只统计实际恢复量。接战保留棋盘、玩家回合、剩余步数、灵墨、护盾、连击令和待用联动，新怪从自己首次预告开始且不立刻攻击。

首领半血激怒保留当前行动位置和已预告伤害。冷静蓄力锁定重击倍率 1.8，激怒后的新蓄力为 2.2。护盾在敌方行动结算后自然消散；敌方护盾持续到下一次敌方行动。

## API

```js
const { create, act, hint, DATA, PRESETS, CARDS } = BattleDemo;
let state = create({ seed: 630101, preset: 'starter' });
const result = act(state, { type: 'swap', a: 18, b: 19 });
if (result.ok) state = result.state;
```

- `create({ seed?, preset? })`：新的独立会话。默认种子 `630101`，默认搭配 `starter`。四组搭配 id 为 `starter`、`sword`、`guard`、`spirit`。无效搭配回退起始组，种子转换为非零无符号 32 位数。
- `act(state, action)`：支持 `{type:'swap',a,b}`、`{type:'cast',cardId}`、`{type:'endTurn'}`。交换索引为 0–35，逐行从左到右。返回 `{ok,state,events,error}`。成功克隆提交，输入状态不被修改；失败返回输入状态的同一个引用、空事件和中文原因。无消除交换也按失败事务处理，不扣资源，不推进随机数，不增加统计。
- `hint(state)`：返回第一个有效相邻交换 `[a,b]`；无合法交换或已经结束时返回 `null`。提示本身不修改状态或消耗资源。
- `DATA`：章名、固定角色、配装、格子定义和五怪行动表。`CARDS` 为 cardId → 卡牌定义字典（含实际 cost、damage、text）；`PRESETS` 为搭配数组，卡牌列表字段是 `deck`。以上定义递归冻结。

状态主要字段：

| 字段 | 含义 |
|---|---|
| `player` | `{hp,maxHp,attack,cardPower,armor,shield}` |
| `enemy` | `{name,hp,maxHp,attack,damage,shield,type,phase,round,intentKind,intent,intentShield,nextDamage}`；phase 为 calm/enraged，type 为 battle/elite/boss |
| `board` | 36 项 `{id,type}`，颜色是 red/green/blue/yellow/purple；每颗 id 唯一，掉落保持原 id，新生颗粒新分配 id |
| `wave / round` | 波次 1–5 / 玩家回合数；`enemy.round` 独立记录当前敌人的行动位置 |
| `mana / steps / maxSteps / bonusSteps` | 当前灵墨 / 剩余步数 / 每回合基础步数 / 本回合已返步数 |
| `cards / preset` | 三个 cardId 字符串 / 本局搭配 id |
| `links` | `{swordBoost,talismanRefund,spiritBonus}`，布尔值；分别代表强化剑气、金刚符返墨资格、聚灵阵紫消增益 |
| `comboRemain / comboAtk` | 连击令剩余消除批次 / 赤刃额外伤害；沿用原版重复施放的累加规则 |
| `status` | playing / won / lost |
| `rng / seq / seed` | 本局确定性随机数、颗粒序号、初始种子 |

三个联动都是待用资格，重复触发只刷新、不叠加，同回合接战延续，结束回合清除。剑气联动只在装备剑气诀时，由任何颜色的直线四连触发；金刚符只在敌方伤害实际击破全部现有护盾时返 1 灵墨，自然消散不触发；聚灵阵在下一个含紫灵的消除批次额外 +1 灵墨，满墨时也消耗资格。

## 动画事件

事件按提交后的发生顺序返回。每个事件包含 `state` 快照（HUD、棋盘、统计和联动），不含随机数和内部标志。界面应锁住输入、依次播放事件，最后显示完整提交状态。

| type | 额外字段 |
|---|---|
| swap | `a,b,board`，交换后的棋盘 |
| match | `indices,board,chain,counts,dealt,damage,blocked,heal,shield,coins,mana,bonusStep`，board 是本批消除前的棋盘 |
| board / reshuffle | `board`，掉落补充后的棋盘 / 无有效交换时重新生成的棋盘 |
| card | `cardId,dealt,damage,blocked,heal,shield,swordBoost` |
| damage | `target:'enemy'/'player',damage,blocked,raw`，damage 是实际气血变化 |
| enemy | `kind,damage,blocked,guard,nextDamage` |
| intent | `kind,damage,shield?,nextDamage`，下一次敌方行动预告 |
| enrage | 首领激怒，当前预告数值不变 |
| link | `kind:'sword'/'ward'/'purple'`，实际消耗/触发联动 |
| win / wave | `wave,enemy,heal?` |
| result | `status:'won'/'lost'` |

`damage` 同时出现在 match/card/enemy 的汇总字段和独立反馈事件中，UI 只计一次动画数字；复盘应直接读状态内统计。

## 实际复盘统计

`stats.swaps` 仅有效交换；`maxChain` 为最高连锁层数；`fourReturns` 为实际返步数量；`casts` 按 cardId 记录成功施法次数；`damage` 为实际敌方失血，不包括过杀；`enemyShieldRemoved` 为伤害实际移除敌方护盾；`hpLost` 为实际我方失血；`blocked` 为护盾实际挡住的伤害；`healed` 为实际回复，包含击败恢复；`shieldExpired` 为自然消散的剩余我方护盾；`manaOverflow` 记录紫灵消除（含聚灵阵额外墨）的溢出，回合恢复触顶不混入紫消统计；`armorPrevented` 为护甲实际减伤；`enemiesDefeated` 为击败数。`links` 记录三项实际联动次数。

败局 `fatal` 保留波次、末次行动与已预告伤害、行动前灵墨/步数/护盾，以及当时墨耗足够的防护/回复术式。它是事实记录，不推断使用后必然获胜。引擎不写 localStorage、cookie 或存档文件。

## 验证与完整复放记录

运行 `node --test web-demo/tests/engine.test.cjs`。10 项测试覆盖无效操作事务、棋盘与随机数确定性、四连返步上限、接战资源延续、五怪各两完整周期、首领蓄力前后激怒/锁定重击、联动刷新与清除、灵墨上限、实际统计与失败资源快照，以及四套搭配合法通关和完整重放一致性。

固定种子 `630101`：起始、御剑各 10 次有效交换 / 2 回合 / 170 气血通关；守阵 26 次 / 5 回合 / 170 气血；灵术 10 次 / 2 回合 / 170 气血。记录由验证脚本的确定性合法操作模拟产生，未经修改状态。它们证明搭配可以通关，并非最短解或平衡难度承诺。

以下每组都从 `create({seed:630101,preset})` 开始。`["s",a,b]` 表示交换，`["c",id]` 表示施法，`["e"]` 表示结束回合。

```json
{
  "starter": [["s",18,19],["c","sword"],["s",10,11],["s",20,21],["c","sword"],["s",18,24],["s",26,27],["c","sword"],["s",31,32],["e"],["c","sword"],["c","sword"],["s",13,19],["s",7,8],["c","sword"],["s",18,19],["s",32,33],["c","sword"]],
  "sword": [["s",18,19],["c","sword"],["s",10,11],["s",20,21],["c","sword"],["s",18,24],["s",26,27],["c","sword"],["s",31,32],["e"],["c","sword"],["c","sword"],["s",13,19],["s",7,8],["c","sword"],["s",18,19],["s",32,33],["c","sword"]],
  "guard": [["s",18,19],["s",10,11],["s",18,24],["s",7,8],["s",10,11],["s",24,25],["e"],["s",3,9],["s",19,20],["s",25,26],["s",0,1],["s",1,7],["s",8,14],["e"],["s",14,15],["s",2,3],["s",10,16],["s",14,15],["s",32,33],["s",16,17],["e"],["s",15,16],["s",7,13],["s",0,6],["s",10,16],["s",4,5],["s",29,35],["e"],["s",11,17],["s",4,5]],
  "spirit": [["s",18,19],["c","flame"],["s",10,11],["c","spiritArray"],["s",20,21],["c","flame"],["s",18,24],["s",20,21],["c","spiritArray"],["c","spiritArray"],["c","flame"],["s",14,20],["c","spiritArray"],["c","spiritArray"],["c","flame"],["e"],["s",21,22],["c","spiritArray"],["c","spiritArray"],["s",8,14],["s",9,15],["s",4,10],["c","spiritArray"],["c","spiritArray"],["c","flame"]]
}
```
