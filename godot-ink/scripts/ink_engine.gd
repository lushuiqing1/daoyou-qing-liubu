class_name InkEngine
extends RefCounted
## Deterministic, transactional gameplay model. UI never mutates this state.
## Versioned deterministic rules; existing runs keep their original rule set.

const FORMAT = "daoyou-godot-1"
const CURRENT_RULES = 4
const CULTIVATION_PATHS = ["none", "sword", "guard", "spirit"]
const GUIDE_CHECKPOINTS = ["swap", "cast", "endTurn", "fourMatch", "wave", "links"]
var d: Dictionary
var cards: Dictionary = {}
var items: Dictionary = {}
var treasures: Dictionary = {}
var state: Dictionary
var events: Array = []

func _init(seed_value: int = 1234567):
	d = normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://data/game.json")))
	for c in d.cards: cards[c.id] = c
	for i in d.items: items[i.id] = i
	for t in d.treasures: treasures[t.id] = t
	state = create(seed_value)

static func normalize_numbers(value: Variant) -> Variant:
	# JSON's parser represents all numbers as doubles; game counters are integers.
	if value is float and value == floor(value): return int(value)
	if value is Dictionary:
		for key in value: value[key] = normalize_numbers(value[key])
	elif value is Array:
		for i in range(value.size()): value[i] = normalize_numbers(value[i])
	return value

func create(seed_value: int) -> Dictionary:
	var inventory = {}; var collection = {}; var tasks = {}
	for i in d.items: inventory[i.id] = i.count
	for c in d.cards: collection[c.id] = int(c.id in d.initialCollection)
	for t in d.tasks: tasks[t.id] = 0
	return {"schema": FORMAT, "rng": (seed_value & 0xffffffff) if seed_value else 1234567,
		"seq": 0, "revision": 0, "settings": {"sound": true, "reducedMotion": false,
			"guide": {"version": 1, "enabled": true, "seen": []}}, "lastResult": null,
		"profile": {"name": "沈砚", "realm": 0, "hp": 100, "coins": 0, "cultivationPath": "none",
			"legacy": {"hp": 0, "attack": 0, "armor": 0}, "inventory": inventory,
			"equipment": {"weapon": "wood_sword", "armor": "cloth", "accessory": null},
			"collection": collection, "deck": d.initialDeck.duplicate(), "tasks": tasks,
			"records": {"wins": 0, "clears": 0, "highestChapter": 0, "maxCombo": 0, "bestMoves": null,
				"lastSummary": {}, "trialStamps": {}, "trialReceipts": {}}},
		"run": null, "battle": null}

func random_value(s: Dictionary) -> float:
	var n = int(s.rng)
	n = (n ^ ((n << 13) & 0xffffffff)) & 0xffffffff
	n = (n ^ (n >> 17)) & 0xffffffff
	n = (n ^ ((n << 5) & 0xffffffff)) & 0xffffffff
	s.rng = n
	return n / 4294967296.0

func shuffled(s: Dictionary, values: Array) -> Array:
	var a = values.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j = int(floor(random_value(s) * (i + 1)))
		var v = a[i]; a[i] = a[j]; a[j] = v
	return a

func has(s: Dictionary, id: String) -> bool:
	return s.run != null and id in s.run.treasures

func rules_version(s: Dictionary = state) -> int:
	return int(s.run.get("rulesVersion", 2)) if s.run != null else CURRENT_RULES

func cultivation_tier(realm: int) -> int:
	return 3 if realm >= 8 else 2 if realm >= 5 else 1 if realm >= 2 else 0

func cultivation_name(id: String) -> String:
	return {"none": "未选倾向", "sword": "御剑", "guard": "守阵", "spirit": "灵术"}.get(id, "未选倾向")

func cultivation_snapshot(s: Dictionary = state) -> Dictionary:
	var id = str(s.profile.get("cultivationPath", "none"))
	if s.run != null: id = str(s.run.get("cultivationPath", "none"))
	if rules_version(s) < 4: id = "none"
	var tier = cultivation_tier(int(s.profile.realm)) if id != "none" else 0
	return {"id": id, "tier": tier, "redBonus": tier if id == "sword" else 0,
		"turnShield": 2*tier if id == "guard" else 0, "startMana": tier if id == "spirit" else 0}

func cultivation_info(s: Dictionary = state) -> Dictionary:
	var info = s.battle.get("cultivation", cultivation_snapshot(s)).duplicate(true) if s.battle != null else cultivation_snapshot(s)
	# Old battles can contain a compatibility snapshot but always have zero path effects.
	if rules_version(s) < 4: info = {"id":"none", "tier":0, "redBonus":0, "turnShield":0, "startMana":0}
	var available_tier = cultivation_tier(int(s.profile.realm))
	var selected_id = str(s.profile.get("cultivationPath", "none"))
	info.name = cultivation_name(info.id); info.selectedId = selected_id; info.selectedName = cultivation_name(selected_id)
	info.selectedTier = available_tier if selected_id != "none" else 0; info.availableTier = available_tier
	info.locked = s.run != null; info.unlocked = int(s.profile.realm) >= 2
	info.nextRealm = 2 if available_tier == 0 else 5 if available_tier == 1 else 8 if available_tier == 2 else -1
	info.text = "未选择修炼倾向；基础境界成长照常生效。"
	if info.id == "sword": info.text = "御剑第%d档：每枚赤刃额外伤害+%d，在连锁倍率之前计算；不增加术式伤害。" % [info.tier, info.redBonus]
	if info.id == "guard": info.text = "守阵第%d档：每个玩家回合开始时额外获得%d点护盾，同回合接战不重复。" % [info.tier, info.turnShield]
	if info.id == "spirit": info.text = "灵术第%d档：每关开始时额外获得%d点灵墨，上限7；回合与接战不补充。" % [info.tier, info.startMana]
	if rules_version(s) < 4: info.text = "本轮沿用旧规则，修炼倾向从下一轮开始生效。"
	return info

func combat_sources_text(s: Dictionary = state) -> String:
	var st = stats(s); var cultivation = cultivation_info(s)
	var qingming = 3 if has(s, "qingming") else 0
	var cloth = 2 if s.profile.equipment.armor == "cloth" else 0
	var jade_initial = 1 if has(s, "jade") else 0
	var jade_turn = 1 if s.profile.equipment.accessory == "jade" else 0
	return "每赤刃：基础攻击%d + 青冥剑%d + 御剑%d，之后计算连锁倍率。\n术式成长攻击%d；御剑不增加术式伤害。\n每回合起始护盾：粗布衣%d + 守阵%d。\n关初灵墨：基础3 + 聚灵玉佩%d + 灵术%d；古玉佩每回合+%d，上限7。\n%s" % [
		int(st.cardPower), qingming, int(cultivation.redBonus), int(st.cardPower), cloth, int(cultivation.turnShield),
		jade_initial, int(cultivation.startMana), jade_turn, cultivation.text]

func empty_links() -> Dictionary:
	return {"swordReady": false, "wardArmed": false, "wardRefunded": false, "purpleReady": false}

func new_summary(s: Dictionary, coverage: String = "full") -> Dictionary:
	return {"coverage": coverage, "startChapter": int(s.run.chapter), "startWave": int(s.run.get("wave", 1)),
		"moves": 0, "maxChain": 0, "refundSteps": 0, "casts": {}, "damage": 0,
		"enemyShieldRemoved": 0, "hpLost": 0, "blocked": 0, "healed": 0, "manaOverflow": 0,
		"shieldExpired": 0, "links": {"sword": 0, "ward": 0, "purple": 0}, "fatal": {},
		"deck": s.run.deck.duplicate(), "kind": "active"}

func add_summary(s: Dictionary, key: String, amount: int):
	if s.run != null and s.run.has("summary"):
		s.run.summary[key] = int(s.run.summary.get(key, 0)) + maxi(0, amount)

func gain_mana(s: Dictionary, amount: int) -> int:
	var actual = mini(maxi(0, 7-s.battle.mana), maxi(0, amount))
	add_summary(s, "manaOverflow", maxi(0, amount)-actual)
	s.battle.mana += actual
	return actual

func emit_link(s: Dictionary, kind: String):
	events.append({"type": "link", "kind": kind, "state": s.duplicate(true)})

func record_link(s: Dictionary, kind: String, emit_event: bool = true):
	if s.run.has("summary"): s.run.summary.links[kind] += 1
	if emit_event: emit_link(s, kind)

func preset_list() -> Array:
	return [
		{"id": "starter", "name": "初行三式", "deck": ["sword", "ward", "heal"], "description": "剑气、护盾、恢复兼顾，适合初次历练。"},
		{"id": "sword", "name": "剑气连消", "deck": ["sword", "comboOrder", "step"], "description": "连击令配合四连消，强化下一次剑气；神行步补充防护。"},
		{"id": "guard", "name": "护盾守势", "deck": ["ward", "ironwall", "golden"], "description": "多种护盾交替使用，金刚符护盾被打破时返还灵墨。"},
		{"id": "spirit", "name": "灵墨循环", "deck": ["spiritArray", "flame", "heal"], "description": "聚灵阵配合紫灵消除，积累灵墨后攻守交替。"}]

func preset_by_id(id: String) -> Dictionary:
	for preset in preset_list():
		if preset.id == id: return preset
	return {}

func trial_definitions() -> Array:
	return d.get("trials", []).duplicate(true)

func trial_definition(id: String) -> Dictionary:
	for definition in d.get("trials", []):
		if definition.id == id: return definition.duplicate(true)
	return {}

func trials_unlocked(s: Dictionary = state) -> bool:
	return int(s.profile.records.clears) > 0

func trial_metric(definition: Dictionary, summary: Dictionary) -> int:
	var target = str(definition.get("target", ""))
	if target in ["sword", "ward", "purple"]: return int(summary.get("links", {}).get(target, 0))
	return int(summary.get(target, 0))

func trial_goal_met(definition: Dictionary, metric: int) -> bool:
	return metric <= int(definition.maximum) if definition.has("maximum") else metric >= int(definition.get("minimum", 0))

func start_trial(id: String, session_id: String) -> Dictionary:
	var definition = trial_definition(id)
	if definition.is_empty(): return {"ok":false, "notice":"未知试炼", "events":[]}
	if session_id.strip_edges().is_empty() or session_id.length() > 128: return {"ok":false, "notice":"试炼会话标识无效", "events":[]}
	if state.seq != 0 or state.run != null or state.lastResult != null or int(state.profile.records.wins) != 0 or int(state.profile.records.clears) != 0:
		return {"ok":false, "notice":"请使用独立的新试炼角色", "events":[]}
	var s = create(int(definition.seed)); var p = s.profile
	p.realm = int(definition.realm); p.coins = 0; p.legacy = {"hp":0, "attack":0, "armor":0}; p.cultivationPath = "none"
	p.equipment = {"weapon":"wood_sword", "armor":"cloth", "accessory":"jade"}
	for item_id in p.inventory: p.inventory[item_id] = 1 if item_id in ["wood_sword", "cloth", "jade"] else 0
	for card_id in p.collection: p.collection[card_id] = 1
	p.deck = definition.deck.duplicate(); s.settings.guide.enabled = false
	s.seq += 1
	s.run = {"id":"r"+str(s.seq), "chapter":int(definition.chapter), "nodes":node_states(), "deck":p.deck.duplicate(),
		"treasures":definition.treasures.duplicate(), "reviveUsed":false, "moves":0, "settled":[], "pendingReward":null,
		"flowVersion":2, "rulesVersion":4, "cultivationPath":"none", "wave":1, "chapterCoins":0}
	s.run.summary = new_summary(s); p.hp = stats(s).maxHp
	s.trial = {"id":id, "seed":int(definition.seed), "sessionId":session_id, "result":{}}
	events = []; start_battle(s, node_by_id("f1")); state = s
	return {"ok":true, "notice":"试炼已开始", "events":[]}

func trial_result_info(s: Dictionary = state) -> Dictionary:
	if not s.has("trial") or s.run != null or s.lastResult == null: return {}
	var definition = trial_definition(str(s.trial.id))
	if definition.is_empty(): return {}
	var summary = s.lastResult.get("summary", {}); var metric = trial_metric(definition, summary)
	var kind = str(s.lastResult.kind)
	return {"id":str(s.trial.id), "seed":int(s.trial.seed), "sessionId":str(s.trial.sessionId), "kind":kind,
		"qualified":kind == "clear" and trial_goal_met(definition, metric), "metric":metric,
		"moves":int(summary.get("moves", 0)), "requirement":str(definition.requirement)}

func trial_receipt_error(receipt: Variant) -> String:
	if not receipt is Dictionary: return "试炼回执无效"
	if not receipt.get("id") is String or not receipt.get("sessionId") is String: return "试炼回执标识无效"
	var definition = trial_definition(receipt.id)
	if definition.is_empty(): return "未知试炼回执"
	if not receipt.get("seed") is int or receipt.seed != definition.seed: return "试炼种子不符"
	if receipt.sessionId.strip_edges().is_empty() or receipt.sessionId.length() > 128: return "试炼会话标识无效"
	if receipt.get("kind") != "clear" or not receipt.get("qualified") is bool or not receipt.qualified: return "此试炼尚未达成获章条件"
	if not receipt.get("metric") is int or receipt.metric < 0 or not receipt.get("moves") is int or receipt.moves <= 0: return "试炼成绩无效"
	if not trial_goal_met(definition, int(receipt.metric)): return "试炼目标数值不符"
	if definition.target == "moves" and receipt.metric != receipt.moves: return "试炼交换记录不符"
	if receipt.get("requirement") != definition.requirement: return "试炼目标描述不符"
	return ""

func card_description(id: String, s: Dictionary = state) -> String:
	if not cards.has(id): return "未知术式"
	var description = str(cards[id].text)
	if rules_version(s) < 3: return description
	if id == "sword": description += " 装备时，任意颜色直线四连及以上消除使下一次剑气伤害+10；不叠加，施放后消耗。"
	if id == "ironwall": description += " 施放后，本回合护盾被敌方伤害打破时返还1点灵墨；每回合最多一次，自然消失不触发。"
	if id == "spiritArray": description += " 施放后，下一个含紫灵的消除批次额外获得1点灵墨；不叠加，达到上限也消耗。"
	return description

func link_state_text(s: Dictionary = state) -> String:
	if rules_version(s) < 3: return "本轮沿用原规则，术式联动从新历练开始。"
	if s.battle == null: return "四连蓄剑气、破盾返灵墨、聚灵助紫消；联动每回合刷新。"
	var links = s.battle.get("links", empty_links())
	var lines = []
	if links.swordReady: lines.append("剑气就绪：下次剑气伤害+10")
	if links.wardArmed and not links.wardRefunded: lines.append("金刚符就绪：护盾被打破返1灵墨")
	if links.wardRefunded: lines.append("本回合破盾返灵墨已触发")
	if links.purpleReady: lines.append("聚灵就绪：下个紫灵消除批次额外+1灵墨")
	return "\n".join(lines) if not lines.is_empty() else "当前没有已蓄好的联动。"

func summary_text(summary: Dictionary) -> String:
	if summary.is_empty(): return "此记录没有详细复盘数据。"
	var heading = "本轮完整记录" if summary.get("coverage") == "full" else "接续后的部分记录：从第%d关第%d只开始" % [int(summary.get("startChapter", 0))+1, int(summary.get("startWave", 1))]
	var cast_lines = []
	for card in d.cards:
		var count = int(summary.get("casts", {}).get(card.id, 0))
		if count > 0: cast_lines.append("%s %d次" % [card.name, count])
	var link_counts = summary.get("links", {})
	return "%s\n有效交换 %d步 · 最高 %d连锁 · 返步 %d\n实际伤害 %d · 移除敌盾 %d\n气血损失 %d · 护盾格挡 %d · 恢复 %d\n灵墨溢出 %d · 自然消失护盾 %d\n施法：%s\n联动：剑气 %d次 · 破盾 %d次 · 紫灵 %d次" % [heading,
		int(summary.get("moves", 0)), int(summary.get("maxChain", 0)), int(summary.get("refundSteps", 0)),
		int(summary.get("damage", 0)), int(summary.get("enemyShieldRemoved", 0)), int(summary.get("hpLost", 0)),
		int(summary.get("blocked", 0)), int(summary.get("healed", 0)), int(summary.get("manaOverflow", 0)),
		int(summary.get("shieldExpired", 0)), "、".join(cast_lines) if not cast_lines.is_empty() else "未施放",
		int(link_counts.get("sword", 0)), int(link_counts.get("ward", 0)), int(link_counts.get("purple", 0))]

func recap_advice(summary: Dictionary) -> String:
	if summary.is_empty(): return "此记录没有详细数据，无法复盘。"
	var suffix = "\n以上仅依据接续后的记录。" if summary.get("coverage") == "partial" else ""
	var fatal = summary.get("fatal", {})
	if not fatal.is_empty():
		var action_name = {"attack": "普攻", "heavy": "重击", "charge": "蓄力", "guard": "守势"}.get(fatal.get("intentKind"), "敌方行动")
		var fact = "最后一次%s实际损失%d点气血，行动前剩余%d点灵墨。" % [action_name, int(fatal.get("loss", 0)), int(fatal.get("mana", 0))]
		if fatal.get("defensiveCard") != null:
			return fact+" 当时可施放%s增加护盾；下次可先检查已预告伤害。" % cards[fatal.defensiveCard].name+suffix
		if fatal.get("healCard") != null:
			return fact+" 当时可施放%s恢复气血；下次可在结束回合前检查恢复机会。" % cards[fatal.healCard].name+suffix
		return fact+suffix
	if int(summary.get("manaOverflow", 0)) > 0:
		return "本轮有%d点灵墨达到上限后溢出，可在紫消前考虑施法。" % summary.manaOverflow+suffix
	if int(summary.get("shieldExpired", 0)) > 0:
		return "本轮有%d点护盾在回合结束后自然消失，可按敌方预告决定何时补盾。" % summary.shieldExpired+suffix
	for card_id in summary.get("deck", []):
		if cards.has(card_id) and int(summary.get("casts", {}).get(card_id, 0)) == 0:
			return "本轮已装备%s，尚未施放；下次可结合敌方预告尝试它的作用。" % cards[card_id].name+suffix
	if int(summary.get("maxChain", 0)) > 0:
		return "本轮最高%d连锁，通过长消除返还%d步，可继续尝试安排连锁与返步。" % [int(summary.maxChain), int(summary.get("refundSteps", 0))]+suffix
	return "本轮完成%d次有效交换，累计返还%d步。" % [int(summary.get("moves", 0)), int(summary.get("refundSteps", 0))]+suffix

func fatal_snapshot(s: Dictionary, loss: int) -> Dictionary:
	var b = s.battle
	var snapshot = {"intentKind": b.enemy.intentKind, "loss": loss, "mana": int(b.mana),
		"defensiveCard": null, "healCard": null, "chapter": int(s.run.chapter), "wave": wave_number(b.node)}
	for instance in b.hand:
		if card_reason(instance.uid, s) != "": continue
		var card = cards[instance.cardId]
		if snapshot.defensiveCard == null and (card.has("shield") or card.has("shieldRatio")): snapshot.defensiveCard = card.id
		if snapshot.healCard == null and s.profile.hp < stats(s).maxHp and (card.has("heal") or card.has("healRatio")): snapshot.healCard = card.id
	return snapshot

func stats(s: Dictionary = state) -> Dictionary:
	var p = s.profile
	var st = {"maxHp": 100, "attack": 3, "armor": 0}
	for n in range(int(p.realm)):
		st.maxHp += d.realms[n].hp; st.attack += d.realms[n].attack; st.armor += d.realms[n].armor
	st.maxHp += p.legacy.hp + (50 if has(s, "ice") else 0)
	st.attack += p.legacy.attack + (1 if p.equipment.weapon == "wood_sword" else 0)
	st.cardPower = st.attack
	st.attack += 3 if has(s, "qingming") else 0
	st.armor += p.legacy.armor + (3 if has(s, "robe") else 0)
	st.heal = 2; st.shield = 2; st.steps = 4 + (1 if has(s, "swordArt") else 0)
	return st

func tile(s: Dictionary, kind: String = "") -> Dictionary:
	s.seq += 1
	return {"id": s.seq, "type": kind if kind else d.types[int(floor(random_value(s) * 5))]}

func matches(board: Array) -> Array:
	var found = {}
	for row in range(6):
		for col in range(6):
			var i = row * 6 + col
			if board[i] == null: continue
			var kind = board[i].type
			if col < 4 and board[i+1] != null and board[i+2] != null and board[i+1].type == kind and board[i+2].type == kind:
				var x = col
				while x < 6 and board[row*6+x] != null and board[row*6+x].type == kind:
					found[row*6+x] = true; x += 1
			if row < 4 and board[i+6] != null and board[i+12] != null and board[i+6].type == kind and board[i+12].type == kind:
				var y = row
				while y < 6 and board[y*6+col] != null and board[y*6+col].type == kind:
					found[y*6+col] = true; y += 1
	return found.keys()

func has_long_match(board: Array) -> bool:
	for i in range(36):
		if board[i] == null: continue
		var kind = board[i].type
		if i%6 <= 2 and board[i+1] != null and board[i+2] != null and board[i+3] != null:
			if board[i+1].type == kind and board[i+2].type == kind and board[i+3].type == kind: return true
		if i < 18 and board[i+6] != null and board[i+12] != null and board[i+18] != null:
			if board[i+6].type == kind and board[i+12].type == kind and board[i+18].type == kind: return true
	return false

func adjacent(a: int, b: int) -> bool:
	return a >= 0 and b >= 0 and a < 36 and b < 36 and (absi(a-b) == 6 or (a/6 == b/6 and absi(a-b) == 1))

func possible_move(board: Array) -> Array:
	var copy = board.duplicate()
	for a in range(36):
		for b in [a+1 if a%6 < 5 else -1, a+6 if a < 30 else -1]:
			if b < 0: continue
			var v = copy[a]; copy[a] = copy[b]; copy[b] = v
			var ok = not matches(copy).is_empty()
			v = copy[a]; copy[a] = copy[b]; copy[b] = v
			if ok: return [a, b]
	return []

func make_board(s: Dictionary) -> Array:
	for attempt in range(100):
		var board = []
		for i in range(36):
			var allowed = []
			for kind in d.types:
				if i%6 >= 2 and board[i-1].type == kind and board[i-2].type == kind: continue
				if i >= 12 and board[i-6].type == kind and board[i-12].type == kind: continue
				allowed.append(kind)
			board.append(tile(s, allowed[int(floor(random_value(s) * allowed.size()))]))
		if not possible_move(board).is_empty(): return board
	return []

func collapse(s: Dictionary, board: Array):
	for col in range(6):
		var values = []
		for row in range(5, -1, -1):
			if board[row*6+col] != null: values.append(board[row*6+col])
		for row in range(5, -1, -1):
			board[row*6+col] = values[5-row] if 5-row < values.size() else tile(s)

func node_states() -> Dictionary:
	var result = {}
	for n in d.nodes: result[n.id] = "available" if n.id == "f1" else "locked"
	return result

func deck_error(s: Dictionary = state) -> String:
	if s.profile.deck.size() != 3: return "请装备齐3张不同术式后启程"
	var seen = []
	for id in s.profile.deck:
		if id == null or id == "": return "请装备齐3张不同术式后启程"
		if id in seen: return "不能重复装备同一种术式"
		if not cards.has(id) or s.profile.collection[id] != 1: return "只能装备已解锁的术式"
		seen.append(id)
	return ""

func node_by_id(id: String) -> Dictionary:
	for n in d.nodes:
		if n.id == id: return n
	return {}

func complete_node(s: Dictionary, id: String):
	var node = node_by_id(id)
	s.run.nodes[id] = "passed"
	for other in d.nodes:
		if other.level == node.level and other.id != id: s.run.nodes[other.id] = "closed"
	for next in node.edges: s.run.nodes[next] = "available"

func wave_number(id: String) -> int:
	return int(node_by_id(id).get("level", 0)) + 1

func available_node(s: Dictionary = state) -> String:
	if s.run == null: return ""
	for n in d.nodes:
		if s.run.nodes.get(n.id) == "available": return n.id
	return ""

func intent_pattern(s: Dictionary = state) -> Array:
	return pattern_for(int(s.run.chapter), s.battle.node, s.battle.enemy.type, rules_version(s))

func wave_tuning(chapter: int, node: String, version: int) -> Dictionary:
	if version < 3: return {}
	return d.combat.chapters[chapter].get("waves", {}).get(node, {})

func pattern_for(chapter: int, node: String, enemy_type: String, version: int) -> Array:
	var tuning = d.combat.chapters[chapter]
	return wave_tuning(chapter, node, version).get("pattern", tuning.patterns[enemy_type])

func next_enemy_preview(s: Dictionary = state) -> Dictionary:
	var preview = {"available": false, "wave": 0, "role": "", "text": "开始历练后可查看下一位敌人的行动特点。", "firstIntent": "", "firstValue": 0}
	if s.run == null or s.battle == null: return preview
	var next_wave = wave_number(s.battle.node)+1
	if next_wave > 5:
		preview.text = "这是本关最后一位首领。击败后领取奖励，随后可整备。"
		return preview
	var node = d.nodes[next_wave-1]; var chapter = int(s.run.chapter)
	var tuning = d.combat.chapters[chapter]; var enemy_type = str(node.type)
	var details = wave_tuning(chapter, node.id, rules_version(s))
	var pattern = pattern_for(chapter, node.id, enemy_type, rules_version(s))
	var first = str(pattern[0]); var attack = roundi(tuning.attack*d.combat.waveAttackScale[node.id])
	var value = attack if first == "attack" else roundi(attack*d.combat.heavyRatio) if first in ["charge", "heavy"] else roundi(tuning.hp*d.combat.healthScale[node.id]*float(details.get("guardRatio", tuning.guardRatio)))
	preview.available = true; preview.wave = next_wave
	preview.role = "首领" if enemy_type == "boss" else "精英" if enemy_type == "elite" else "普通怪"
	preview.text = str(details.get("description", d.chapters[chapter].theme))
	preview.firstIntent = {"attack": "攻击", "guard": "守势", "charge": "蓄力", "heavy": "重击"}[first]
	preview.firstValue = value
	return preview

func turn_auras(s: Dictionary):
	if s.profile.equipment.armor == "cloth": s.battle.shield += 2
	if rules_version(s) >= 4: s.battle.shield += int(s.battle.cultivation.turnShield)
	if s.profile.equipment.accessory == "jade": gain_mana(s, 1)

func announce_intent(b: Dictionary, s: Dictionary = state):
	var e = b.enemy
	var previous = e.get("intentKind", ""); var locked = e.get("nextDamage", 0)
	var tuning = d.combat.chapters[int(s.run.chapter)]
	var details = wave_tuning(int(s.run.chapter), b.node, rules_version(s))
	var pattern = pattern_for(int(s.run.chapter), b.node, e.type, rules_version(s))
	e.intentKind = pattern[(int(b.get("enemyRound", b.round))-1)%pattern.size()]
	var heavy = roundi(e.damage * (d.combat.enragedRatio if e.phase == "enraged" else d.combat.heavyRatio))
	e.intent = e.damage if e.intentKind == "attack" else (locked if previous == "charge" else heavy) if e.intentKind == "heavy" else 0
	e.intentShield = roundi(e.maxHp * float(details.get("guardRatio", tuning.guardRatio))) if e.intentKind == "guard" else 0
	e.nextDamage = heavy if e.intentKind == "charge" else 0

func check_enrage(s: Dictionary):
	var e = s.battle.enemy
	if e.type == "boss" and e.phase == "calm" and e.hp > 0 and e.hp*2 <= e.maxHp:
		e.phase = "enraged"; events.append({"type": "enrage", "state": s.duplicate(true)})

func enemy_name(s: Dictionary, id: String) -> String:
	var ch = d.chapters[int(s.run.chapter)]
	return ch.waves[wave_number(id)-1]

func enemy_art(s: Dictionary = state) -> String:
	return d.enemyArt[int(s.run.chapter)*2 + (1 if s.battle.node == "boss" else 0)].file

func start_battle(s: Dictionary, node: Dictionary, previous: Dictionary = {}):
	var ch = d.chapters[int(s.run.chapter)]; var tuning = d.combat.chapters[int(s.run.chapter)]
	var hp = roundi(tuning.hp * d.combat.healthScale[node.id]); var elite = node.type == "elite"
	var hand = []
	var cultivation = previous.get("cultivation", cultivation_snapshot(s)).duplicate(true)
	# IDs must be assigned after board generation to retain deterministic parity.
	s.seq += 1
	var battle_id = s.run.id + "-b" + str(int(s.seq))
	var board = make_board(s) if previous.is_empty() else previous.board
	if previous.is_empty():
		for id in s.run.deck:
			s.seq += 1; hand.append({"uid": s.seq, "cardId": id})
	else: hand = previous.hand
	s.run.wave = wave_number(node.id)
	s.battle = {"id": battle_id, "rulesVersion": rules_version(s), "node": node.id, "round": previous.get("round", 1), "enemyRound": 1,
		"steps": stats(s).steps if previous.is_empty() else previous.steps, "shield": previous.get("shield", 0), "mana": 3 + (1 if has(s, "jade") else 0) if previous.is_empty() else previous.mana,
		"bonusSteps": previous.get("bonusSteps", 0), "comboRemain": previous.get("comboRemain", 0), "comboAtk": previous.get("comboAtk", 0),
		"links": previous.get("links", empty_links()).duplicate(true), "cultivation": cultivation, "board": board, "hand": hand,
		"enemy": {"name": enemy_name(s, node.id), "hp": hp, "maxHp": hp,
			"damage": roundi(tuning.attack * d.combat.waveAttackScale[node.id]), "intent": 0,
			"shield": 0, "phase": "calm", "elite": elite, "type": node.type,
			"reward": roundi(ch.reward * node.scale * (1.3 if elite else 1.0))}}
	announce_intent(s.battle, s)
	if previous.is_empty():
		if rules_version(s) >= 4: gain_mana(s, int(cultivation.startMana))
		turn_auras(s)
	s.run.nodes[node.id] = "current"; s.lastResult = null

func upgrade_state(value: Dictionary) -> Dictionary:
	# Only called after structural validation; profile/inventory never reset.
	var s = value.duplicate(true)
	if not s.profile.has("cultivationPath"): s.profile.cultivationPath = "none"
	if not s.settings.has("guide"): s.settings.guide = {"version": 1, "enabled": false, "seen": []}
	if not s.profile.records.has("lastSummary"): s.profile.records.lastSummary = {}
	if not s.profile.records.has("trialStamps"): s.profile.records.trialStamps = {}
	if not s.profile.records.has("trialReceipts"): s.profile.records.trialReceipts = {}
	if s.run != null:
		if not s.run.has("rulesVersion"): s.run.rulesVersion = 2
		if not s.run.has("summary"):
			s.run.summary = new_summary(s, "partial")
			if s.battle != null: s.run.summary.startWave = wave_number(s.battle.node)
			elif s.run.pendingReward != null: s.run.summary.startWave = wave_number(s.run.pendingReward.node)
	if s.battle != null and not s.battle.has("links"): s.battle.links = empty_links()
	if s.battle != null and not s.battle.has("cultivation"): s.battle.cultivation = cultivation_snapshot(s)
	if s.run == null or s.run.get("flowVersion") == 2: return s
	var r = s.run; var current_id = ""
	if s.battle != null: current_id = s.battle.node
	elif r.pendingReward != null:
		current_id = r.pendingReward.node
		if not r.pendingReward.chapterComplete:
			r.pendingReward.legacyReward = true
			current_id = node_by_id(current_id).edges[0]
	else:
		for n in d.nodes:
			if r.nodes.get(n.id) not in ["passed", "closed"]:
				current_id = n.id; break
		if current_id == "": current_id = "boss"
	r.flowVersion = 2; r.wave = wave_number(current_id); r.chapterCoins = 0
	r.summary.startWave = r.wave
	r.nodes = node_states()
	for n in d.nodes:
		r.nodes[n.id] = "passed" if n.level < r.wave-1 else "locked"
	r.nodes[current_id] = "current" if s.battle != null else "available"
	if r.pendingReward != null and r.pendingReward.chapterComplete: r.nodes.boss = "passed"
	if s.battle != null:
		var b = s.battle; var e = b.enemy; var tuning = d.combat.chapters[int(r.chapter)]
		var hp_ratio = float(e.hp)/e.maxHp
		e.maxHp = roundi(tuning.hp*d.combat.healthScale[current_id]); e.hp = maxi(1, roundi(e.maxHp*hp_ratio))
		e.damage = roundi(tuning.attack*d.combat.waveAttackScale[current_id]); e.name = enemy_name(s, current_id)
		e.intentKind = ""; e.nextDamage = 0; b.rulesVersion = 2; b.bonusSteps = 0; b.enemyRound = b.round
		announce_intent(b, s)
	elif r.pendingReward == null: start_battle(s, node_by_id(current_id))
	return s

func damage_enemy(s: Dictionary, amount: int, true_damage: bool = false) -> int:
	var e = s.battle.enemy
	var before_hp = int(e.hp)
	var blocked = 0 if true_damage else mini(e.shield, amount)
	e.shield -= blocked; e.hp = maxi(0, e.hp - amount + blocked)
	add_summary(s, "damage", before_hp-e.hp)
	add_summary(s, "enemyShieldRemoved", blocked)
	return amount - blocked

func card_cost(id: String, s: Dictionary = state) -> int:
	return maxi(1, cards[id].cost - (1 if has(s, "aura") else 0))

func card_value(id: String, s: Dictionary = state) -> int:
	var c = cards[id]
	var linked = id == "sword" and rules_version(s) >= 3 and s.battle != null and s.battle.get("links", {}).get("swordReady", false)
	return c.get("damage", 0) + (maxi(0, stats(s).cardPower - 2)*3 if c.get("scale", false) else 0) + (5 if id == "sword" and s.battle != null and s.battle.enemy.elite else 0) + (10 if linked else 0)

func card_reason(uid: int, s: Dictionary = state) -> String:
	if s.battle == null: return "当前没有进行中的战斗"
	if s.run.pendingReward != null: return "请先领取战斗奖励"
	for c in s.battle.hand:
		if c.uid != uid: continue
		if s.battle.mana < card_cost(c.cardId, s): return "灵墨不足"
		if c.cardId == "heal" and s.profile.hp >= stats(s).maxHp: return "气血已满"
		return ""
	return "此术式未装备"

func win(s: Dictionary):
	var b = s.battle; var r = s.run
	if b.id in r.settled: return
	r.settled.append(b.id); s.profile.coins += b.enemy.reward; r.chapterCoins += b.enemy.reward
	s.profile.records.wins += 1; s.profile.tasks.win = maxi(1, s.profile.tasks.win)
	complete_node(s, b.node)
	var healed = mini(stats(s).maxHp-s.profile.hp, roundi(stats(s).maxHp*d.combat.victoryHealRatio))
	s.profile.hp += healed
	add_summary(s, "healed", healed)
	events.append({"type": "win", "wave": wave_number(b.node), "enemy": b.enemy.name, "heal": healed, "state": s.duplicate(true)})
	if b.node != "boss":
		start_battle(s, node_by_id(available_node(s)), b)
		events.append({"type": "wave", "wave": r.wave, "enemy": s.battle.enemy.name, "state": s.duplicate(true)})
		return
	if s.has("trial"):
		end_run(s, "clear")
		return
	var fixed_id = d.chapters[int(r.chapter)].fixedUnlock
	var fixed_new = s.profile.collection[fixed_id] == 0
	s.profile.collection[fixed_id] = 1
	var fixed_bonus = 0 if fixed_new else 20
	s.profile.coins += fixed_bonus; r.chapterCoins += fixed_bonus
	var candidates = []
	for c in d.cards:
		if s.profile.collection[c.id] == 0: candidates.append(c.id)
	var choices = shuffled(s, candidates).slice(0, 3); var bonus = 20 if choices.is_empty() else 0
	s.profile.coins += bonus; r.chapterCoins += bonus
	var chapter_complete = b.node == "boss"
	if chapter_complete:
		s.profile.tasks.chapter = maxi(1, s.profile.tasks.chapter)
		s.profile.records.highestChapter = maxi(s.profile.records.highestChapter, r.chapter+1)
	r.pendingReward = {"battleId": b.id, "node": b.node, "enemy": b.enemy.name,
		"coins": b.enemy.reward+bonus+fixed_bonus, "chapterCoins": r.chapterCoins,
		"fixedCard": fixed_id, "fixedNew": fixed_new, "choices": choices, "chapterComplete": chapter_complete}
	s.battle = null

func end_run(s: Dictionary, kind: String):
	if kind == "clear":
		s.profile.records.clears += 1
		s.profile.records.bestMoves = s.run.moves if s.profile.records.bestMoves == null else mini(s.run.moves, s.profile.records.bestMoves)
	var summary = s.run.get("summary", {}).duplicate(true)
	if not summary.is_empty(): summary.kind = kind
	s.lastResult = {"kind": kind, "moves": s.run.moves, "chapter": s.run.chapter, "summary": summary}
	s.profile.records.lastSummary = summary.duplicate(true)
	s.run = null; s.battle = null; s.profile.hp = stats(s).maxHp
	if s.has("trial"): s.trial.result = trial_result_info(s)

func resolve(s: Dictionary) -> bool:
	var found = matches(s.battle.board); var chain = 1
	while not found.is_empty():
		if chain > 100: return false
		var b = s.battle; var st = stats(s); var counts = {}
		for kind in d.types: counts[kind] = 0
		for i in found: counts[b.board[i].type] += 1
		var multi = 1 + (chain-1)*0.15; var bonus = 0
		var returned_step = 0
		var long_match = has_long_match(b.board)
		if long_match and b.bonusSteps < d.combat.matchBonusStepsLimit:
			b.steps += 1; b.bonusSteps += 1; returned_step = 1
		add_summary(s, "refundSteps", returned_step)
		if s.run.has("summary"): s.run.summary.maxChain = maxi(s.run.summary.maxChain, chain)
		if long_match and rules_version(s) >= 3 and "sword" in s.run.deck: b.links.swordReady = true
		if b.comboRemain > 0:
			bonus = b.comboAtk; b.comboRemain -= 1
			if b.comboRemain == 0: b.comboAtk = 0
		var enemy_shield_before = b.enemy.shield
		var red_bonus = int(b.cultivation.redBonus) if rules_version(s) >= 4 else 0
		var dealt = damage_enemy(s, roundi(counts.red*(st.attack+red_bonus)*multi)+bonus) if counts.red else 0
		var heal = mini(st.maxHp-s.profile.hp, roundi(counts.green*st.heal*multi)+(counts.green*2 if has(s, "incense") else 0))
		s.profile.hp += heal
		add_summary(s, "healed", heal)
		var shield = roundi(counts.blue*st.shield*multi); b.shield += shield
		var coins = counts.yellow*(7 if has(s, "map") else 4); s.profile.coins += coins
		var purple_linked = counts.purple > 0 and rules_version(s) >= 3 and b.links.purpleReady
		if purple_linked: b.links.purpleReady = false
		var mana = gain_mana(s, counts.purple+(1 if purple_linked else 0))
		if purple_linked: record_link(s, "purple", false)
		s.profile.records.maxCombo = maxi(s.profile.records.maxCombo, chain)
		events.append({"type": "match", "indices": found.duplicate(), "board": b.board.duplicate(true),
			"chain": chain, "dealt": dealt, "heal": heal, "shield": shield, "coins": coins, "mana": mana, "bonusStep": returned_step,
			"attack": counts.red > 0, "blocked": enemy_shield_before-b.enemy.shield, "state": s.duplicate(true)})
		if purple_linked: emit_link(s, "purple")
		check_enrage(s)
		for i in found: b.board[i] = null
		collapse(s, b.board); events.append({"type": "board", "board": b.board.duplicate(true)})
		if b.enemy.hp <= 0:
			win(s)
			if s.battle == null: return true
		found = matches(s.battle.board); chain += 1
	if possible_move(s.battle.board).is_empty():
		s.battle.board = make_board(s); events.append({"type": "reshuffle", "board": s.battle.board.duplicate(true)})
	return true

func preflight(a: Dictionary) -> String:
	var s = state; var p = s.profile; var id = a.get("id", ""); var kind = a.get("type", "")
	if s.has("trial") and kind not in ["swap", "card", "endTurn", "abandon", "settings", "guideProgress", "guideSkip", "clearResult"]:
		return "试炼角色与配置固定，此操作不可用"
	if s.run != null and s.run.pendingReward != null and kind not in ["reward", "settings", "guideProgress", "guideSkip", "awardTrial"]: return "请先领取或跳过战斗奖励"
	if kind in ["swap", "card", "endTurn"] and (s.battle == null or s.run == null): return "当前没有进行中的战斗"
	match kind:
		"newRun":
			if s.run != null: return "本轮历练尚未结束"
			return deck_error(s)
		"enterNode":
			if s.run == null or s.battle != null: return "请先完成或继续当前战斗"
			if id != available_node(s) or node_by_id(id).is_empty(): return "此怪物尚未登场"
		"swap":
			if s.battle.steps <= 0: return "步数已用尽，可使用术式或结束回合"
			if not adjacent(int(a.get("a", -1)), int(a.get("b", -1))): return "只能交换相邻方块"
		"card": return card_reason(int(a.get("uid", -1)), s)
		"reward":
			if s.run == null or s.run.pendingReward == null: return "没有待领取奖励"
			if id and (id not in s.run.pendingReward.choices or p.collection.get(id, 1) != 0): return "此术式已解锁或不可领取"
		"abandon":
			if s.run == null: return "没有进行中的历练"
		"equip", "unequip", "sell", "buyItem", "cultivate":
			if s.battle != null: return "战斗尚未结束，暂不可更换、出售、购买或突破"
			if kind == "equip" and (not items.has(id) or not items[id].has("slot") or p.inventory[id] <= 0): return "没有这件装备"
			if kind == "unequip" and id not in ["weapon", "armor", "accessory"]: return "装备槽不存在"
			if kind == "sell":
				if not items.has(id) or p.inventory[id] <= 0: return "没有这件物品"
				if id in p.equipment.values(): return "请先卸下装备"
			if kind == "buyItem":
				if not items.has(id) or not items[id].has("price"): return "此物品不在售"
				if p.coins < items[id].price: return "铜钱不足"
			if kind == "cultivate":
				if d.realms[int(p.realm)].cost == null: return "已达筑基初期"
				if p.coins < d.realms[int(p.realm)].cost: return "铜钱不足"
		"use":
			if not items.has(id) or items[id].kind != "consumable" or p.inventory[id] <= 0: return "没有可用的消耗品"
			if id == "spring_pill" and p.hp >= stats(s).maxHp: return "气血已满，无需使用"
			if id == "cloud_talisman" and s.battle == null: return "此物品需在战斗中使用"
		"buyTreasure":
			if s.run == null or s.battle != null: return "开始历练后，可在战斗之外购买法宝"
			if not treasures.has(id) or has(s, id): return "本轮已拥有此法宝"
			if p.coins < treasures[id].price: return "铜钱不足"
		"deckEquip", "deckRemove":
			if s.run != null: return "本轮术式已锁定，整轮历练结束后可更换"
			var slot = int(a.get("slot", -1))
			if slot < 0 or slot > 2: return "装备槽不存在"
			if kind == "deckRemove" and p.deck[slot] == null: return "此槽位尚未装备"
			if kind == "deckEquip":
				if not cards.has(id) or p.collection[id] != 1: return "此术式尚未解锁"
				for i in range(3):
					if i != slot and p.deck[i] == id: return "不能重复装备同一种术式"
		"deckPreset":
			if s.run != null: return "本轮术式已锁定，整轮历练结束后可更换"
			var preset = preset_by_id(id)
			if preset.is_empty(): return "未知推荐组合"
			var missing = []
			for card_id in preset.deck:
				if p.collection.get(card_id, 0) != 1: missing.append(cards[card_id].name)
			if not missing.is_empty(): return "尚未收藏："+"、".join(missing)
		"guideProgress":
			if id not in GUIDE_CHECKPOINTS: return "未知引导步骤"
		"cultivationPath":
			if s.run != null: return "本轮修炼倾向已锁定，历练结束后可更换"
			if id not in CULTIVATION_PATHS: return "未知修炼倾向"
			if id != "none" and int(p.realm) < 2: return "达到炼气三层后可选择修炼倾向"
		"claimTask":
			if p.tasks.get(id) != 1: return "任务尚未完成或已领取"
		"settings":
			if id not in ["sound", "reducedMotion"]: return "未知设置"
		"awardTrial":
			return trial_receipt_error(a.get("receipt"))
		"endTurn", "clearResult", "guideSkip": pass
		_: return "未知操作"
	return ""

func dispatch(a: Dictionary) -> Dictionary:
	var error = preflight(a)
	if error: return {"ok": false, "notice": error, "events": []}
	if a.type == "awardTrial" and state.profile.records.get("trialReceipts", {}).get(a.receipt.sessionId, false):
		return {"ok":true, "notice":"此试炼印章已领取", "events":[]}
	var s = state.duplicate(true); var p = s.profile; events = []
	var profile_before_hp = int(p.hp)
	var id = a.get("id", ""); var notice = ""
	match a.type:
		"newRun":
			s.seq += 1
			s.run = {"id": "r"+str(int(s.seq)), "chapter": 0, "nodes": node_states(), "deck": p.deck.duplicate(),
				"treasures": [], "reviveUsed": false, "moves": 0, "settled": [], "pendingReward": null,
				"flowVersion": 2, "rulesVersion": CURRENT_RULES, "cultivationPath": p.get("cultivationPath", "none"), "wave": 1, "chapterCoins": 0}
			s.run.summary = new_summary(s)
			p.hp = stats(s).maxHp; s.lastResult = null
			start_battle(s, node_by_id("f1"))
		"enterNode":
			var n = node_by_id(id)
			start_battle(s, n)
		"swap":
			var b = s.battle; var left = int(a.a); var right = int(a.b); var v = b.board[left]
			b.board[left] = b.board[right]; b.board[right] = v
			events.append({"type": "swap", "board": b.board.duplicate(true), "a": left, "b": right})
			if matches(b.board).is_empty():
				v = b.board[left]; b.board[left] = b.board[right]; b.board[right] = v
				events.append({"type": "swap", "board": b.board.duplicate(true), "a": left, "b": right}); notice = "未形成消除，不扣步数"
			else:
				b.steps -= 1; s.run.moves += 1
				add_summary(s, "moves", 1)
				if not resolve(s): return {"ok": false, "notice": "连锁过长，本次操作已撤回", "events": []}
		"card":
			var b = s.battle; var instance = {}
			for c in b.hand:
				if c.uid == a.uid: instance = c
			var c = cards[instance.cardId]; var st = stats(s); var before_hp = p.hp; var before_shield = b.shield
			var enemy_shield_before = b.enemy.shield
			var sword_linked = rules_version(s) >= 3 and c.id == "sword" and b.links.swordReady
			if s.run.has("summary"): s.run.summary.casts[c.id] = int(s.run.summary.casts.get(c.id, 0))+1
			b.mana -= card_cost(c.id, s); var dealt = 0
			if c.has("damage"):
				dealt = damage_enemy(s, card_value(c.id, s), c.id == "armorBreak")
				if c.id == "armorBreak":
					var removed = mini(6, b.enemy.shield); b.enemy.shield -= removed
					add_summary(s, "enemyShieldRemoved", removed)
			if rules_version(s) >= 3:
				if sword_linked:
					b.links.swordReady = false; record_link(s, "sword", false)
				if c.id == "ironwall": b.links.wardArmed = true
				if c.id == "spiritArray": b.links.purpleReady = true
			if c.has("shieldRatio"): b.shield += roundi(st.maxHp*c.shieldRatio)
			if c.has("shield"): b.shield += c.shield
			if c.has("healRatio"): p.hp = mini(st.maxHp, p.hp+roundi(st.maxHp*c.healRatio))
			if c.has("heal"): p.hp = mini(st.maxHp, p.hp+c.heal)
			if c.id == "comboOrder": b.comboRemain += 2; b.comboAtk += 10
			add_summary(s, "healed", p.hp-before_hp)
			events.append({"type": "card", "cardId": c.id, "dealt": dealt, "heal": p.hp-before_hp, "shield": b.shield-before_shield,
				"attack": c.has("damage"), "blocked": enemy_shield_before-b.enemy.shield, "state": s.duplicate(true)})
			if sword_linked: emit_link(s, "sword")
			notice = c.name+"已施放"; check_enrage(s)
			if b.enemy.hp <= 0: win(s)
		"endTurn":
			var b = s.battle; var st = stats(s); var e = b.enemy
			var raw = maxi(0, e.intent-st.armor); var blocked = mini(raw, b.shield); var damage = raw-blocked
			var shield_before = int(b.shield); var actual_loss = mini(int(p.hp), damage)
			var fatal = fatal_snapshot(s, actual_loss)
			add_summary(s, "hpLost", actual_loss); add_summary(s, "blocked", blocked)
			e.shield = 0; b.shield -= blocked; p.hp = maxi(0, p.hp-damage)
			if e.intentKind == "guard": e.shield = e.intentShield
			var ward_triggered = rules_version(s) >= 3 and b.links.wardArmed and not b.links.wardRefunded and shield_before > 0 and blocked == shield_before
			if ward_triggered:
				b.links.wardRefunded = true; b.links.wardArmed = false; gain_mana(s, 1)
			events.append({"type": "enemy", "kind": e.intentKind, "damage": damage, "blocked": blocked,
				"guard": e.intentShield, "nextDamage": e.nextDamage, "state": s.duplicate(true)})
			if ward_triggered: record_link(s, "ward")
			add_summary(s, "shieldExpired", b.shield)
			b.shield = 0
			if p.hp <= 0:
				if has(s, "revive") and not s.run.reviveUsed:
					s.run.reviveUsed = true; p.hp = maxi(1, roundi(st.maxHp*0.5)); add_summary(s, "healed", p.hp)
					events.append({"type": "revive", "state": s.duplicate(true)})
				else:
					if s.run.has("summary"): s.run.summary.fatal = fatal
					end_run(s, "defeat")
			if s.battle != null:
				b.round += 1; b.enemyRound += 1; b.steps = stats(s).steps; b.bonusSteps = 0; b.links = empty_links()
				turn_auras(s); announce_intent(b, s)
				if possible_move(b.board).is_empty(): b.board = make_board(s)
		"reward":
			var reward = s.run.pendingReward
			if id: p.collection[id] = 1; notice = cards[id].name+"已收藏，下轮可装备"
			s.run.pendingReward = null
			if reward.chapterComplete:
				if s.run.chapter == 3: end_run(s, "clear")
				else:
					s.run.chapter += 1; s.run.nodes = node_states(); s.run.chapterCoins = 0; s.run.wave = 1
					notice = "关卡奖励已领取，可整备后开始下一关"
			elif reward.get("legacyReward", false): start_battle(s, node_by_id(available_node(s)))
		"abandon": end_run(s, "abandon")
		"equip": p.equipment[items[id].slot] = id; p.tasks.equip = maxi(1, p.tasks.equip)
		"unequip": p.equipment[id] = null
		"sell": p.inventory[id] -= 1; p.coins += d.sellPrices[items[id].quality]
		"use":
			if id == "spring_pill": p.hp = mini(stats(s).maxHp, p.hp+24)
			if id == "cloud_talisman": s.battle.steps += 2
			if id == "golden_gourd": p.coins += 60
			p.inventory[id] -= 1
		"buyItem": p.coins -= items[id].price; p.inventory[id] += 1
		"buyTreasure":
			p.coins -= treasures[id].price; s.run.treasures.append(id)
			if id == "ice": p.hp += 50
			if id == "aura": p.hp = stats(s).maxHp
		"cultivate":
			var realm = d.realms[int(p.realm)]; p.coins -= realm.cost; p.realm += 1
			p.hp = mini(stats(s).maxHp, p.hp+realm.hp); p.tasks.cultivate = maxi(1, p.tasks.cultivate)
		"deckEquip": p.deck[int(a.slot)] = id
		"deckRemove": p.deck[int(a.slot)] = null
		"deckPreset":
			var preset = preset_by_id(id); p.deck = preset.deck.duplicate()
			notice = "%s已装备" % preset.name
		"cultivationPath":
			p.cultivationPath = id
			notice = "已选择%s" % cultivation_name(id) if id != "none" else "已取消修炼倾向"
		"claimTask":
			p.tasks[id] = 2
			for task in d.tasks:
				if task.id == id: p.coins += task.reward
		"settings": s.settings[id] = bool(a.value)
		"guideProgress":
			if not s.settings.has("guide"): s.settings.guide = {"version": 1, "enabled": false, "seen": []}
			if id not in s.settings.guide.seen: s.settings.guide.seen.append(id)
		"guideSkip":
			if not s.settings.has("guide"): s.settings.guide = {"version": 1, "enabled": false, "seen": []}
			s.settings.guide.enabled = false
		"awardTrial":
			if not p.records.has("trialStamps"): p.records.trialStamps = {}
			if not p.records.has("trialReceipts"): p.records.trialReceipts = {}
			var receipt = a.receipt; var previous = p.records.trialStamps.get(receipt.id, {})
			var best_moves = mini(int(previous.get("bestMoves", receipt.moves)), int(receipt.moves))
			p.records.trialStamps[receipt.id] = {"earned":true, "bestMoves":best_moves}
			p.records.trialReceipts[receipt.sessionId] = true
			notice = "已获得%s印章" % trial_definition(receipt.id).name
		"clearResult":
			if not s.has("trial"): s.lastResult = null
	if a.type in ["use", "buyTreasure", "cultivate"]: add_summary(s, "healed", p.hp-profile_before_hp)
	p.hp = clampi(p.hp, 1, stats(s).maxHp); s.revision += 1; state = s
	return {"ok": true, "notice": notice, "events": events.duplicate(true)}
