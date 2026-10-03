extends RefCounted
## Native progress only; imports original native v1 read-only on first v2 load.
## Browser localStorage and trial saves are never imported here.
const SAVE = "user://progress-v2.json"
const BACKUP = "user://progress-v2.backup.json"
const LEGACY_SAVE = "user://progress-v1.json"
static var last_error: String = ""
static var writes_blocked: bool = false
static var _recovered_backups: Dictionary = {}

static func save_state(state: Dictionary, save_path: String = SAVE) -> Error:
	if state.has("trial"): return ERR_INVALID_DATA
	if save_path == SAVE and writes_blocked:
		return ERR_FILE_CORRUPT
	var backup_path = save_path.get_basename()+".backup.json"
	var temp = FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if temp == null: return _save_error(FileAccess.get_open_error(), save_path)
	temp.store_string(JSON.stringify(state)); temp.flush()
	var write_error = temp.get_error(); temp.close()
	if write_error != OK: return _save_error(write_error, save_path)
	# Preserve the valid backup after recovering from a corrupt main file.
	if FileAccess.file_exists(save_path) and not _recovered_backups.has(save_path):
		var backup_error = DirAccess.copy_absolute(save_path, backup_path)
		if backup_error != OK: return _save_error(backup_error, save_path)
	var replace_error = DirAccess.rename_absolute(save_path + ".tmp", save_path)
	if replace_error == OK: _recovered_backups.erase(save_path)
	return _save_error(replace_error, save_path)

static func _save_error(error: Error, save_path: String) -> Error:
	if save_path == SAVE:
		last_error = "" if error == OK else "进度保存失败（%d）：%s"%[error, ProjectSettings.globalize_path(save_path)]
	return error

static func read_state(engine: InkEngine, save_path: String = SAVE) -> Dictionary:
	if save_path == SAVE:
		last_error = ""; writes_blocked = false
	var result = _read_state_paths(engine, save_path, LEGACY_SAVE if save_path == SAVE else "")
	if save_path == SAVE:
		last_error = result.error
		writes_blocked = result.blocked
	return result.state

# Path-injected core permits isolated migration tests without accessing player files.
static func _read_state_paths(engine: InkEngine, save_path: String, legacy_path: String = "") -> Dictionary:
	var backup_path = save_path.get_basename()+".backup.json"
	var found_current = FileAccess.file_exists(save_path) or FileAccess.file_exists(backup_path)
	var restored = _read_pair(engine, save_path)
	if not restored.is_empty(): return {"state": restored, "error": "", "blocked": false}
	if found_current:
		return {"state": {}, "error": "新进度主文件和备份均无法读取，已停止自动保存。请保留文件并从有效备份恢复："+ProjectSettings.globalize_path(save_path), "blocked": true}
	if legacy_path.is_empty(): return {"state": {}, "error": "", "blocked": false}
	var old_backup = legacy_path.get_basename()+".backup.json"
	if not FileAccess.file_exists(legacy_path) and not FileAccess.file_exists(old_backup):
		return {"state": {}, "error": "", "blocked": false}
	restored = _read_pair(engine, legacy_path)
	if restored.is_empty():
		return {"state": {}, "error": "原生旧进度和备份均无法读取，未建立新进度。请保留文件："+ProjectSettings.globalize_path(legacy_path), "blocked": true}
	var save_error = save_state(restored, save_path)
	if save_error != OK:
		return {"state": restored, "error": "旧进度已读取，但迁移保存失败（%d），已停止自动保存：%s"%[save_error, ProjectSettings.globalize_path(save_path)], "blocked": true}
	return {"state": restored, "error": "", "blocked": false}

static func _read_pair(engine: InkEngine, save_path: String) -> Dictionary:
	for path in [save_path, save_path.get_basename()+".backup.json"]:
		if not FileAccess.file_exists(path): continue
		var parser = JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK: continue
		var v = InkEngine.normalize_numbers(parser.data)
		if validate(v, engine):
			var upgraded = engine.upgrade_state(v)
			if validate(upgraded, engine):
				if path != save_path: _recovered_backups[save_path] = true
				return upgraded
	return {}

static func validate(v: Variant, engine: InkEngine, allow_trial: bool = false) -> bool:
	v = InkEngine.normalize_numbers(v)
	if not v is Dictionary or not v.get("schema") is String: return false
	if v.has("trial") and not allow_trial: return false
	if v.schema != InkEngine.FORMAT: return false
	if not v.get("profile") is Dictionary or not v.get("settings") is Dictionary: return false
	var p = v.profile
	for k in ["name", "realm", "hp", "coins", "inventory", "equipment", "collection", "deck", "tasks", "records", "legacy"]:
		if not p.has(k): return false
	if not p.name is String or p.name.length() > 50: return false
	if not integer(p.realm,0,9) or not integer(p.hp,1) or not integer(p.coins): return false
	if p.has("cultivationPath"):
		if not p.cultivationPath is String or p.cultivationPath not in ["none", "sword", "guard", "spirit"]: return false
		if p.cultivationPath != "none" and p.realm < 2: return false
	for k in ["inventory", "equipment", "collection", "tasks", "records", "legacy"]:
		if not p[k] is Dictionary: return false
	for k in ["hp", "attack", "armor"]:
		if not integer(p.legacy.get(k)): return false
	for k in ["wins", "clears", "highestChapter", "maxCombo"]:
		if not integer(p.records.get(k)): return false
	if not p.records.has("bestMoves") or (p.records.bestMoves != null and not integer(p.records.bestMoves)): return false
	if p.records.has("lastSummary") and not summary_valid(p.records.lastSummary, engine): return false
	if p.records.has("trialStamps"):
		if not p.records.trialStamps is Dictionary: return false
		for id in p.records.trialStamps:
			if not id is String or engine.trial_definition(id).is_empty(): return false
			var stamp = p.records.trialStamps[id]
			if not stamp is Dictionary or stamp.get("earned") != true or not stamp.get("earned") is bool or not integer(stamp.get("bestMoves"),1): return false
	if p.records.has("trialReceipts"):
		if not p.records.trialReceipts is Dictionary: return false
		for token in p.records.trialReceipts:
			if not token is String or token.strip_edges().is_empty() or token.length() > 128 or p.records.trialReceipts[token] != true or not p.records.trialReceipts[token] is bool: return false
	for k in ["sound", "reducedMotion"]:
		if not v.settings.get(k) is bool: return false
	if v.settings.has("guide"):
		var guide = v.settings.guide
		if not guide is Dictionary or not integer(guide.get("version"),1,1) or not guide.get("enabled") is bool or not guide.get("seen") is Array: return false
		var checkpoints = []
		for checkpoint in guide.seen:
			if not checkpoint is String or checkpoint not in InkEngine.GUIDE_CHECKPOINTS or checkpoint in checkpoints: return false
			checkpoints.append(checkpoint)
	if not p.deck is Array or p.deck.size() != 3: return false
	var equipped_cards = []
	for id in p.deck:
		if id != null:
			if not id is String or not engine.cards.has(id) or p.collection.get(id) != 1 or id in equipped_cards: return false
			equipped_cards.append(id)
	for i in engine.d.items:
		if not integer(p.inventory.get(i.id),0,100000): return false
	for c in engine.d.cards:
		if p.collection.get(c.id) not in [0, 1]: return false
	for t in engine.d.tasks:
		if p.tasks.get(t.id) not in [0, 1, 2]: return false
	for slot in ["weapon", "armor", "accessory"]:
		if not p.equipment.has(slot): return false
		var id = p.equipment[slot]
		if id != null and (not engine.items.has(id) or engine.items[id].get("slot") != slot or p.inventory[id] <= 0): return false
	for key in ["seq", "rng", "revision", "run", "battle", "lastResult"]:
		if not v.has(key): return false
	if not integer(v.rng,1,4294967295) or not integer(v.seq) or not integer(v.revision): return false
	if v.lastResult != null:
		if not v.lastResult is Dictionary: return false
		if v.lastResult.get("kind") not in ["clear","defeat","abandon"] or not integer(v.lastResult.get("moves")) or not integer(v.lastResult.get("chapter"),0,3): return false
		if v.lastResult.has("summary") and not summary_valid(v.lastResult.summary, engine): return false
	if v.run != null:
		if not v.run is Dictionary: return false
		for k in ["chapter", "nodes", "deck", "treasures", "settled", "pendingReward", "moves", "reviveUsed", "id"]:
			if not v.run.has(k): return false
		if v.run.pendingReward != null and not v.run.pendingReward is Dictionary: return false
		if not integer(v.run.chapter,0,3) or not integer(v.run.moves) or not v.run.reviveUsed is bool: return false
		if not v.run.id is String or not v.run.nodes is Dictionary or not v.run.deck is Array: return false
		if not v.run.treasures is Array or not v.run.settled is Array: return false
		if v.run.has("rulesVersion") and not integer(v.run.rulesVersion,2,4): return false
		if v.run.has("cultivationPath") and (not v.run.cultivationPath is String or v.run.cultivationPath not in ["none", "sword", "guard", "spirit"]): return false
		if v.run.get("rulesVersion", 2) >= 4:
			if not v.run.has("cultivationPath") or not p.has("cultivationPath") or v.run.cultivationPath != p.cultivationPath: return false
		if v.run.has("summary"):
			if not summary_valid(v.run.summary, engine) or v.run.summary.is_empty(): return false
			if v.run.summary.moves > v.run.moves or v.run.summary.deck != v.run.deck or v.run.summary.startChapter > v.run.chapter: return false
			if v.run.summary.coverage == "full" and v.run.summary.moves != v.run.moves: return false
		if engine.deck_error(v): return false
		if v.run.deck != p.deck: return false
		var held = []
		for id in v.run.treasures:
			if not id is String or not engine.treasures.has(id) or id in held: return false
			held.append(id)
		for id in v.run.settled:
			if not id is String: return false
		for n in engine.d.nodes:
			if v.run.nodes.get(n.id) not in ["locked", "available", "passed", "closed", "current"]: return false
		if v.run.has("flowVersion"):
			if not integer(v.run.flowVersion,2,2) or not integer(v.run.get("wave"),1,5) or not integer(v.run.get("chapterCoins")): return false
			if v.battle != null and (not v.battle is Dictionary or engine.wave_number(v.battle.get("node", "")) != v.run.wave): return false
			if v.run.nodes.size() != 5: return false
			for n in engine.d.nodes:
				var expected = "passed" if n.level < v.run.wave-1 else "locked"
				if n.level == v.run.wave-1:
					expected = "current" if v.battle != null else "passed" if v.run.pendingReward != null and v.run.pendingReward.get("chapterComplete",false) else "available"
				if v.run.nodes[n.id] != expected: return false
		if v.run.pendingReward != null:
			var q = v.run.pendingReward
			if not q is Dictionary or v.battle != null: return false
			for k in ["coins", "choices", "chapterComplete", "enemy", "node", "battleId"]:
				if not q.has(k): return false
			if not integer(q.coins) or not q.choices is Array or q.choices.size() > 3 or not q.chapterComplete is bool or not q.enemy is String: return false
			if not q.node is String or not q.battleId is String: return false
			if q.battleId not in v.run.settled or engine.node_by_id(q.node).is_empty(): return false
			var choices = []
			for id in q.choices:
				if not id is String or not engine.cards.has(id) or p.collection[id] != 0 or id in choices: return false
				choices.append(id)
			if q.has("fixedCard"):
				if not q.fixedCard is String or not engine.cards.has(q.fixedCard) or p.collection[q.fixedCard] != 1: return false
				if not q.get("fixedNew") is bool or not integer(q.get("chapterCoins")): return false
	else:
		if v.battle != null: return false
	if v.battle != null:
		var b = v.battle
		if not b is Dictionary: return false
		for k in ["board", "hand", "enemy", "round", "steps", "mana", "shield", "node", "id", "comboRemain", "comboAtk"]:
			if not b.has(k): return false
		if not integer(b.mana,0,7) or not integer(b.round,1) or not integer(b.steps) or not integer(b.shield) or not integer(b.comboRemain) or not integer(b.comboAtk): return false
		if not b.node is String: return false
		if not b.id is String or b.id in v.run.settled or v.run.nodes.get(b.node) != "current": return false
		if not b.board is Array or b.board.size() != 36 or not b.hand is Array or b.hand.size() != 3: return false
		var tile_ids = []
		for t in b.board:
			if not t is Dictionary or t.get("type") not in engine.d.types or not integer(t.get("id"),1,v.seq) or t.id in tile_ids: return false
			tile_ids.append(t.id)
		if not engine.matches(b.board).is_empty(): return false
		for i in range(3):
			if not b.hand[i] is Dictionary or b.hand[i].get("cardId") != v.run.deck[i] or not integer(b.hand[i].get("uid"),1,v.seq): return false
		if not b.enemy is Dictionary: return false
		for k in ["hp", "maxHp", "shield", "damage", "intent", "intentKind", "intentShield", "nextDamage", "phase", "type", "reward", "elite", "name"]:
			if not b.enemy.has(k): return false
		for k in ["hp", "maxHp", "shield", "damage", "intent", "intentShield", "nextDamage", "reward"]:
			if not integer(b.enemy[k]): return false
		if not b.enemy.name is String or not b.enemy.elite is bool: return false
		if b.enemy.hp <= 0 or b.enemy.hp > b.enemy.maxHp: return false
		if not engine.d.combat.patterns.has(b.enemy.type): return false
		if b.enemy.phase not in ["calm","enraged"] or b.enemy.intentKind not in ["attack","heavy","guard","charge"]: return false
		var is_v2 = v.run.get("flowVersion") == 2
		var pattern = engine.intent_pattern(v) if is_v2 else engine.d.combat.patterns[b.enemy.type]
		if is_v2 and (not integer(b.get("bonusSteps"),0,2) or not integer(b.get("enemyRound"),1,b.round)): return false
		var intent_round = b.enemyRound if is_v2 else b.round
		var expected_rules = v.run.get("rulesVersion", 2) if is_v2 else 1
		if b.enemy.intentKind != pattern[(intent_round-1)%pattern.size()] or b.get("rulesVersion") != expected_rules: return false
		if b.has("links"):
			if not b.links is Dictionary: return false
			for key in ["swordReady", "wardArmed", "wardRefunded", "purpleReady"]:
				if not b.links.get(key) is bool: return false
		elif expected_rules >= 3: return false
		if expected_rules >= 4:
			if not cultivation_valid(b.get("cultivation"), v.run.cultivationPath, int(p.realm)): return false
		elif b.has("cultivation") and not cultivation_valid(b.cultivation, "none", int(p.realm)): return false
	if p.hp > engine.stats(v).maxHp: return false
	return true

static func integer(value: Variant, minimum: int = 0, maximum: int = 1000000000) -> bool:
	return value is int and value >= minimum and value <= maximum

static func cultivation_valid(value: Variant, path: String, realm: int) -> bool:
	if not value is Dictionary or not value.get("id") is String or value.id != path: return false
	var available_tier = 3 if realm >= 8 else 2 if realm >= 5 else 1 if realm >= 2 else 0
	var tier = available_tier if path != "none" else 0
	if not integer(value.get("tier"), 0, 3) or value.tier != tier: return false
	for key in ["redBonus", "turnShield", "startMana"]:
		if not integer(value.get(key), 0, 6): return false
	return value.redBonus == (tier if path == "sword" else 0) and value.turnShield == (2*tier if path == "guard" else 0) and value.startMana == (tier if path == "spirit" else 0)

static func summary_valid(value: Variant, engine: InkEngine) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true # Historical completed runs have no fabricated detail.
	if value.get("coverage") not in ["full", "partial"] or not integer(value.get("startChapter"),0,3) or not integer(value.get("startWave"),1,5): return false
	for key in ["moves", "maxChain", "refundSteps", "damage", "enemyShieldRemoved", "hpLost", "blocked", "healed", "manaOverflow", "shieldExpired"]:
		if not integer(value.get(key)): return false
	if value.get("kind") not in ["", "active", "clear", "defeat", "abandon"]: return false
	if not value.get("casts") is Dictionary or not value.get("links") is Dictionary or not value.get("fatal") is Dictionary: return false
	for id in value.casts:
		if not id is String or not engine.cards.has(id) or not integer(value.casts[id]): return false
	for key in ["sword", "ward", "purple"]:
		if not integer(value.links.get(key)): return false
	if not value.get("deck") is Array or value.deck.size() != 3: return false
	var seen = []
	for id in value.deck:
		if not id is String or not engine.cards.has(id) or id in seen: return false
		seen.append(id)
	if not value.fatal.is_empty():
		if value.fatal.get("intentKind") not in ["attack", "heavy", "guard", "charge"] or not integer(value.fatal.get("loss")) or not integer(value.fatal.get("mana"),0,7): return false
		for key in ["defensiveCard", "healCard"]:
			if not value.fatal.has(key): return false
			var id = value.fatal[key]
			if id != null and (not id is String or not engine.cards.has(id)): return false
		if not integer(value.fatal.get("chapter"),0,3) or not integer(value.fatal.get("wave"),1,5): return false
	return true
