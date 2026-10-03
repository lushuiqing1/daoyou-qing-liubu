class_name InkEngineMigrationV1
extends RefCounted
## Deterministic, transactional gameplay model. UI never mutates this state.
## The web engine is the migration oracle; only persistence schema differs.

const FORMAT = "daoyou-godot-1"
var d: Dictionary
var cards: Dictionary = {}
var items: Dictionary = {}
var treasures: Dictionary = {}
var state: Dictionary
var events: Array = []

func _init(seed_value: int = 1234567):
	d = normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/migration_v1_data.json")))
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
		"seq": 0, "revision": 0, "settings": {"sound": true, "reducedMotion": false}, "lastResult": null,
		"profile": {"name": "沈砚", "realm": 0, "hp": 100, "coins": 0,
			"legacy": {"hp": 0, "attack": 0, "armor": 0}, "inventory": inventory,
			"equipment": {"weapon": "wood_sword", "armor": "cloth", "accessory": null},
			"collection": collection, "deck": d.initialDeck.duplicate(), "tasks": tasks,
			"records": {"wins": 0, "clears": 0, "highestChapter": 0, "maxCombo": 0, "bestMoves": null}},
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

func turn_auras(s: Dictionary):
	if s.profile.equipment.armor == "cloth": s.battle.shield += 2
	if s.profile.equipment.accessory == "jade": s.battle.mana = mini(7, s.battle.mana + 1)

func announce_intent(b: Dictionary):
	var e = b.enemy
	var previous = e.get("intentKind", ""); var locked = e.get("nextDamage", 0)
	var pattern = d.combat.patterns[e.type]
	e.intentKind = pattern[(int(b.round)-1)%pattern.size()]
	var heavy = roundi(e.damage * (d.combat.enragedRatio if e.phase == "enraged" else d.combat.heavyRatio))
	e.intent = e.damage if e.intentKind == "attack" else (locked if previous == "charge" else heavy) if e.intentKind == "heavy" else 0
	e.intentShield = roundi(e.maxHp * d.combat.guardRatio) if e.intentKind == "guard" else 0
	e.nextDamage = heavy if e.intentKind == "charge" else 0

func check_enrage(s: Dictionary):
	var e = s.battle.enemy
	if e.type == "boss" and e.phase == "calm" and e.hp > 0 and e.hp*2 <= e.maxHp:
		e.phase = "enraged"; events.append({"type": "enrage"})

func enemy_name(s: Dictionary, id: String) -> String:
	var ch = d.chapters[int(s.run.chapter)]
	return ch.boss if id == "boss" else ch.first if id == "f1" else ch.left if id == "f2" else ch.right if id == "f3" else ch.right + " · 精英"

func enemy_art(s: Dictionary = state) -> String:
	return d.enemyArt[int(s.run.chapter)*2 + (1 if s.battle.node == "boss" else 0)].file

func start_battle(s: Dictionary, node: Dictionary):
	var ch = d.chapters[int(s.run.chapter)]; var tuning = d.combat.chapters[int(s.run.chapter)]
	var hp = roundi(tuning.hp * d.combat.healthScale[node.id]); var elite = node.type == "elite"
	var hand = []
	# IDs must be assigned after board generation to retain deterministic parity.
	s.seq += 1
	var battle_id = s.run.id + "-b" + str(int(s.seq))
	var board = make_board(s)
	for id in s.run.deck:
		s.seq += 1; hand.append({"uid": s.seq, "cardId": id})
	s.battle = {"id": battle_id, "rulesVersion": 1, "node": node.id, "round": 1,
		"steps": stats(s).steps, "shield": 0, "mana": 3 + (1 if has(s, "jade") else 0),
		"comboRemain": 0, "comboAtk": 0, "board": board, "hand": hand,
		"enemy": {"name": enemy_name(s, node.id), "hp": hp, "maxHp": hp,
			"damage": roundi(tuning.attack * d.combat.attackScale[node.type]), "intent": 0,
			"shield": 0, "phase": "calm", "elite": elite, "type": node.type,
			"reward": roundi(ch.reward * node.scale * (1.3 if elite else 1.0))}}
	announce_intent(s.battle); turn_auras(s); s.run.nodes[node.id] = "current"; s.lastResult = null

func damage_enemy(s: Dictionary, amount: int, true_damage: bool = false) -> int:
	var e = s.battle.enemy
	var blocked = 0 if true_damage else mini(e.shield, amount)
	e.shield -= blocked; e.hp = maxi(0, e.hp - amount + blocked)
	return amount - blocked

func card_cost(id: String, s: Dictionary = state) -> int:
	return maxi(1, cards[id].cost - (1 if has(s, "aura") else 0))

func card_value(id: String, s: Dictionary = state) -> int:
	var c = cards[id]
	return c.get("damage", 0) + (maxi(0, stats(s).cardPower - 2)*3 if c.get("scale", false) else 0) + (5 if id == "sword" and s.battle != null and s.battle.enemy.elite else 0)

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
	r.settled.append(b.id); s.profile.coins += b.enemy.reward
	s.profile.records.wins += 1; s.profile.tasks.win = maxi(1, s.profile.tasks.win)
	complete_node(s, b.node)
	var candidates = []
	for c in d.cards:
		if s.profile.collection[c.id] == 0: candidates.append(c.id)
	var choices = shuffled(s, candidates).slice(0, 3); var bonus = 20 if choices.is_empty() else 0
	s.profile.coins += bonus
	var chapter_complete = b.node == "boss"
	if chapter_complete:
		s.profile.tasks.chapter = maxi(1, s.profile.tasks.chapter)
		s.profile.records.highestChapter = maxi(s.profile.records.highestChapter, r.chapter+1)
	r.pendingReward = {"battleId": b.id, "node": b.node, "enemy": b.enemy.name,
		"coins": b.enemy.reward+bonus, "choices": choices, "chapterComplete": chapter_complete}
	events.append({"type": "win"}); s.battle = null

func end_run(s: Dictionary, kind: String):
	if kind == "clear":
		s.profile.records.clears += 1
		s.profile.records.bestMoves = s.run.moves if s.profile.records.bestMoves == null else mini(s.run.moves, s.profile.records.bestMoves)
	s.lastResult = {"kind": kind, "moves": s.run.moves, "chapter": s.run.chapter}
	s.run = null; s.battle = null; s.profile.hp = stats(s).maxHp

func resolve(s: Dictionary) -> bool:
	var found = matches(s.battle.board); var chain = 1
	while not found.is_empty():
		if chain > 100: return false
		var b = s.battle; var st = stats(s); var counts = {}
		for kind in d.types: counts[kind] = 0
		for i in found: counts[b.board[i].type] += 1
		var multi = 1 + (chain-1)*0.15; var bonus = 0
		if b.comboRemain > 0:
			bonus = b.comboAtk; b.comboRemain -= 1
			if b.comboRemain == 0: b.comboAtk = 0
		var dealt = damage_enemy(s, roundi(counts.red*st.attack*multi)+bonus) if counts.red else 0
		var heal = mini(st.maxHp-s.profile.hp, roundi(counts.green*st.heal*multi)+(counts.green*2 if has(s, "incense") else 0))
		s.profile.hp += heal
		var shield = roundi(counts.blue*st.shield*multi); b.shield += shield
		var coins = counts.yellow*(7 if has(s, "map") else 4); s.profile.coins += coins
		var mana = mini(7-b.mana, counts.purple); b.mana += mana
		s.profile.records.maxCombo = maxi(s.profile.records.maxCombo, chain)
		events.append({"type": "match", "indices": found.duplicate(), "board": b.board.duplicate(true),
			"chain": chain, "dealt": dealt, "heal": heal, "shield": shield, "coins": coins, "mana": mana})
		check_enrage(s)
		for i in found: b.board[i] = null
		collapse(s, b.board); events.append({"type": "board", "board": b.board.duplicate(true)})
		if b.enemy.hp <= 0: win(s); return true
		found = matches(b.board); chain += 1
	if possible_move(s.battle.board).is_empty():
		s.battle.board = make_board(s); events.append({"type": "reshuffle", "board": s.battle.board.duplicate(true)})
	return true

func preflight(a: Dictionary) -> String:
	var s = state; var p = s.profile; var id = a.get("id", ""); var kind = a.get("type", "")
	if s.run != null and s.run.pendingReward != null and kind not in ["reward", "settings"]: return "请先领取或跳过战斗奖励"
	if kind in ["swap", "card", "endTurn"] and (s.battle == null or s.run == null): return "当前没有进行中的战斗"
	match kind:
		"newRun":
			if s.run != null: return "本轮历练尚未结束"
			return deck_error(s)
		"enterNode":
			if s.run == null or s.battle != null: return "请先完成或继续当前战斗"
			if s.run.nodes.get(id) != "available": return "此路线尚不可进入"
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
		"claimTask":
			if p.tasks.get(id) != 1: return "任务尚未完成或已领取"
		"settings":
			if id not in ["sound", "reducedMotion"]: return "未知设置"
		"endTurn", "clearResult": pass
		_: return "未知操作"
	return ""

func dispatch(a: Dictionary) -> Dictionary:
	var error = preflight(a)
	if error: return {"ok": false, "notice": error, "events": []}
	var s = state.duplicate(true); var p = s.profile; events = []
	var id = a.get("id", ""); var notice = ""
	match a.type:
		"newRun":
			s.seq += 1
			s.run = {"id": "r"+str(int(s.seq)), "chapter": 0, "nodes": node_states(), "deck": p.deck.duplicate(),
				"treasures": [], "reviveUsed": false, "moves": 0, "settled": [], "pendingReward": null}
			p.hp = stats(s).maxHp; s.lastResult = null
		"enterNode":
			var n = node_by_id(id)
			if n.type == "shop": complete_node(s, id); notice = "行商已抵达，购置完毕后选择下一条路"
			elif n.type == "event":
				complete_node(s, id); p.coins += 25; p.inventory.spring_pill += 1; notice = "山中奇遇：25铜钱与一份回春散"
			else: start_battle(s, n)
		"swap":
			var b = s.battle; var left = int(a.a); var right = int(a.b); var v = b.board[left]
			b.board[left] = b.board[right]; b.board[right] = v
			events.append({"type": "swap", "board": b.board.duplicate(true), "a": left, "b": right})
			if matches(b.board).is_empty():
				v = b.board[left]; b.board[left] = b.board[right]; b.board[right] = v
				events.append({"type": "swap", "board": b.board.duplicate(true), "a": left, "b": right}); notice = "未形成消除，不扣步数"
			else:
				b.steps -= 1; s.run.moves += 1
				if not resolve(s): return {"ok": false, "notice": "连锁过长，本次操作已撤回", "events": []}
		"card":
			var b = s.battle; var instance = {}
			for c in b.hand:
				if c.uid == a.uid: instance = c
			var c = cards[instance.cardId]; var st = stats(s); var before_hp = p.hp; var before_shield = b.shield
			b.mana -= card_cost(c.id, s); var dealt = 0
			if c.has("damage"):
				dealt = damage_enemy(s, card_value(c.id, s), c.id == "armorBreak")
				if c.id == "armorBreak": b.enemy.shield -= mini(6, b.enemy.shield)
			if c.has("shieldRatio"): b.shield += roundi(st.maxHp*c.shieldRatio)
			if c.has("shield"): b.shield += c.shield
			if c.has("healRatio"): p.hp = mini(st.maxHp, p.hp+roundi(st.maxHp*c.healRatio))
			if c.has("heal"): p.hp = mini(st.maxHp, p.hp+c.heal)
			if c.id == "comboOrder": b.comboRemain += 2; b.comboAtk += 10
			events.append({"type": "card", "cardId": c.id, "dealt": dealt, "heal": p.hp-before_hp, "shield": b.shield-before_shield})
			notice = c.name+"已施放"; check_enrage(s)
			if b.enemy.hp <= 0: win(s)
		"endTurn":
			var b = s.battle; var st = stats(s); var e = b.enemy
			var raw = maxi(0, e.intent-st.armor); var blocked = mini(raw, b.shield); var damage = raw-blocked
			e.shield = 0; b.shield -= blocked; p.hp = maxi(0, p.hp-damage)
			if e.intentKind == "guard": e.shield = e.intentShield
			events.append({"type": "enemy", "kind": e.intentKind, "damage": damage, "blocked": blocked,
				"guard": e.intentShield, "nextDamage": e.nextDamage})
			b.shield = 0
			if p.hp <= 0:
				if has(s, "revive") and not s.run.reviveUsed:
					s.run.reviveUsed = true; p.hp = maxi(1, roundi(st.maxHp*0.5)); events.append({"type": "revive"})
				else: end_run(s, "defeat")
			if s.battle != null:
				b.round += 1; b.steps = stats(s).steps; turn_auras(s); announce_intent(b)
				if possible_move(b.board).is_empty(): b.board = make_board(s)
		"reward":
			var reward = s.run.pendingReward
			if id: p.collection[id] = 1; notice = cards[id].name+"已收藏，下轮可装备"
			s.run.pendingReward = null
			if reward.chapterComplete:
				if s.run.chapter == 3: end_run(s, "clear")
				else: s.run.chapter += 1; s.run.nodes = node_states()
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
		"claimTask":
			p.tasks[id] = 2
			for task in d.tasks:
				if task.id == id: p.coins += task.reward
		"settings": s.settings[id] = bool(a.value)
		"clearResult": s.lastResult = null
	p.hp = clampi(p.hp, 1, stats(s).maxHp); s.revision += 1; state = s
	return {"ok": true, "notice": notice, "events": events.duplicate(true)}
