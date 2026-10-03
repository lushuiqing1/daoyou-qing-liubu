extends SceneTree
## Deterministic strategy regression. Never reads/writes player progress.
const Model = preload("res://scripts/ink_engine.gd")
const Store = preload("res://scripts/progress_store.gd")
const SEEDS = [91001, 91098, 91195, 91292, 91389, 91486, 91583, 91680]
const PRESETS = ["starter", "sword", "guard", "spirit"]
const ACTION_LIMIT = 4500
const START_REALM = 5
var checks = 0
var failures: Array = []

func _init(): call_deferred("run")

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: "+message)

func initialized(seed_value: int):
	var model = Model.new(seed_value)
	# Same complete collection and growth for every preset. Base data remains untouched.
	model.state.profile.realm = START_REALM
	for id in model.cards: model.state.profile.collection[id] = 1
	return model

func apply_action(model, action: Dictionary, trace: Array) -> bool:
	var result = model.dispatch(action)
	check(result.ok, "Accepted legal action "+JSON.stringify(action))
	if not result.ok: return false
	trace.append(action.duplicate(true))
	check(Store.validate(model.state, model), "Valid simulated state after "+str(action.type))
	return true

func uid_for(model, id: String) -> int:
	for instance in model.state.battle.hand:
		if instance.cardId == id: return int(instance.uid)
	return -1

func ready(model, id: String) -> bool:
	var uid = uid_for(model, id)
	return uid >= 0 and model.card_reason(uid) == ""

func cast_action(model, id: String) -> Dictionary:
	return {"type": "card", "uid": uid_for(model, id)}

func best_swap(model) -> Dictionary:
	var b = model.state.battle; var st = model.stats(); var hp = int(model.state.profile.hp)
	var best = {"pair": [], "counts": {}, "score": -INF}
	var danger = maxi(0, int(b.enemy.intent)-int(st.armor)-int(b.shield))
	for left in range(36):
		for right in [left+1 if left%6 < 5 else -1, left+6 if left < 30 else -1]:
			if right < 0: continue
			var copy = b.board.duplicate(); var temp = copy[left]; copy[left] = copy[right]; copy[right] = temp
			var indices = model.matches(copy)
			if indices.is_empty(): continue
			var counts = {"red":0,"green":0,"blue":0,"yellow":0,"purple":0}
			for index in indices: counts[copy[index].type] += 1
			var score = 0.0
			score += counts.red*st.attack*(0.6 if b.enemy.shield > 0 else 1.25)
			score += counts.green*st.heal*(1.7 if hp < st.maxHp*0.6 else 0.7 if hp < st.maxHp*0.9 else 0.02)
			score += counts.blue*st.shield*(1.45 if danger > 0 else 0.03)
			score += counts.yellow*0.35
			var spell_power = 0.0
			for id in model.state.run.deck:
				if model.cards[id].has("damage"):
					spell_power = maxf(spell_power, float(model.card_value(id))/model.card_cost(id))
			score += counts.purple*maxf(4.0, spell_power)*(1.1 if b.mana < 5 else 0.55 if b.mana < 7 else 0.01)
			if model.has_long_match(copy): score += 15.0
			if model.has_long_match(copy) and "sword" in model.state.run.deck and not b.links.swordReady: score += 10.0
			if b.links.purpleReady and counts.purple > 0: score += 5.0
			if counts.red > 0 and b.comboRemain > 0: score += b.comboAtk
			if score > best.score: best = {"pair": [left, right], "counts": counts, "score": score}
	return best

func choose_action(model) -> Dictionary:
	var s = model.state; var b = s.battle; var st = model.stats(); var hp = int(s.profile.hp)
	var danger = maxi(0, int(b.enemy.intent)-int(st.armor)-int(b.shield))
	var missing_hp = int(st.maxHp)-hp
	# The same policy serves every deck, using only visible state and legal equipped cards.
	if ready(model, "heal") and (hp < st.maxHp*0.6 or (danger >= hp and missing_hp > 0)):
		return cast_action(model, "heal")
	if ready(model, "golden") and (missing_hp >= 15 and hp < st.maxHp*0.8):
		return cast_action(model, "golden")
	# Take a guaranteed lethal spell before spending swaps or adding unnecessary shield.
	for id in s.run.deck:
		if ready(model, id) and model.cards[id].has("damage"):
			var shield = 0 if id == "armorBreak" else int(b.enemy.shield)
			if model.card_value(id)-shield >= b.enemy.hp: return cast_action(model, id)
	var swap = best_swap(model) if b.steps > 0 else {"pair": [], "counts": {}}
	if ready(model, "spiritArray") and not b.links.purpleReady:
		if (not swap.pair.is_empty() and swap.counts.get("purple", 0) > 0) or (missing_hp >= 12 and hp < st.maxHp*0.8):
			return cast_action(model, "spiritArray")
	if ready(model, "comboOrder") and b.comboRemain == 0 and b.enemy.shield == 0 and not swap.pair.is_empty() and swap.counts.get("red", 0) >= 3:
		return cast_action(model, "comboOrder")
	# Use prepared sword and capped spirit before it expires/overflows, retaining emergency mana.
	for id in s.run.deck:
		if not ready(model, id) or not model.cards[id].has("damage"): continue
		if id == "spiritArray" and b.links.purpleReady and b.steps > 0: continue
		var reserve = 1 if danger >= hp*0.5 and "heal" in s.run.deck else 0
		if b.mana-model.card_cost(id) < reserve: continue
		if b.mana >= 6 or (id == "sword" and b.links.swordReady): return cast_action(model, id)
	if b.steps > 0:
		if not swap.pair.is_empty(): return {"type": "swap", "a": swap.pair[0], "b": swap.pair[1]}
	# A prepared ironwall may accept a small visible hit to let its shield break/refund.
	if b.links.wardArmed and not b.links.wardRefunded and b.shield > 0 and danger > 0 and danger < hp*0.25:
		return {"type": "endTurn"}
	# No swaps remain: cover the previewed attack with an available shield card.
	if danger > 0:
		var defense_id = ""; var best_value = -INF
		for id in s.run.deck:
			if not ready(model, id): continue
			var card = model.cards[id]
			if not card.has("shield") and not card.has("shieldRatio"): continue
			var value = float(card.get("shield", 0))+st.maxHp*float(card.get("shieldRatio", 0))
			var healing = mini(missing_hp, int(card.get("heal", 0)))
			var expected_refund = 1 if id == "ironwall" and danger >= value and not b.links.wardRefunded else 0
			var utility = (minf(value, danger)+healing)/maxi(1, model.card_cost(id)-expected_refund)
			if utility > best_value: best_value = utility; defense_id = id
		if defense_id != "": return cast_action(model, defense_id)
	# Spend remaining offense when it cannot remove an affordable necessary defense.
	var attack_id = ""; var efficiency = -INF
	for id in s.run.deck:
		if not ready(model, id) or not model.cards[id].has("damage"): continue
		if danger >= hp and b.mana-model.card_cost(id) < 2: continue
		var value = float(model.card_value(id))/model.card_cost(id)
		if value > efficiency: efficiency = value; attack_id = id
	if attack_id != "": return cast_action(model, attack_id)
	return {"type": "endTurn"}

func simulate(preset_id: String, seed_value: int, keep_trace: bool) -> Dictionary:
	var model = initialized(seed_value); var trace: Array = []
	var initial = model.state.duplicate(true)
	apply_action(model, {"type": "deckPreset", "id": preset_id}, trace)
	apply_action(model, {"type": "equip", "id": "jade"}, trace)
	apply_action(model, {"type": "newRun"}, trace)
	var enemy_turns = 0
	while model.state.run != null and trace.size() < ACTION_LIMIT:
		var action: Dictionary
		if model.state.run.pendingReward != null: action = {"type": "reward", "id": ""}
		elif model.state.battle == null: action = {"type": "enterNode", "id": "f1"}
		else: action = choose_action(model)
		if action.type == "endTurn": enemy_turns += 1
		if not apply_action(model, action, trace): break
	var result_kind = str(model.state.lastResult.kind) if model.state.lastResult != null else "timeout"
	check(result_kind != "timeout", "Strategy terminates "+preset_id+" seed "+str(seed_value))
	var summary = model.state.lastResult.get("summary", {}) if model.state.lastResult != null else model.state.run.get("summary", {})
	var result = {"preset": preset_id, "seed": seed_value, "result": result_kind,
		"chapterReached": int(model.state.lastResult.chapter)+1 if model.state.lastResult != null else int(model.state.run.chapter)+1,
		"wins": int(model.state.profile.records.wins), "actions": trace.size(), "enemyTurns": enemy_turns,
		"swaps": int(summary.get("moves", 0)), "damage": int(summary.get("damage", 0)),
		"links": summary.get("links", {}).duplicate(true), "summary": summary.duplicate(true)}
	if keep_trace:
		result.initialState = initial; result.replayActions = trace.duplicate(true)
		var replay = Model.new(seed_value); replay.state = initial.duplicate(true)
		var replay_trace: Array = []
		for action in trace:
			if not apply_action(replay, action, replay_trace): break
		result.replayVerified = replay.state == model.state
		check(result.replayVerified, "Exact trace replay "+preset_id)
	return result

func run():
	var runs: Array = []; var groups: Array = []
	for preset_id in PRESETS:
		var group = {"preset": preset_id, "runs": 0, "clears": 0, "defeats": 0, "timeouts": 0, "swaps": 0, "damage": 0, "links": {"sword":0,"ward":0,"purple":0}}
		for seed_index in range(SEEDS.size()):
			var result = simulate(preset_id, SEEDS[seed_index], seed_index == 0)
			runs.append(result); group.runs += 1
			group.clears += int(result.result == "clear"); group.defeats += int(result.result == "defeat"); group.timeouts += int(result.result == "timeout")
			group.swaps += result.swaps; group.damage += result.damage
			for kind in group.links: group.links[kind] += int(result.links.get(kind, 0))
		groups.append(group)
		print("Build simulation ", preset_id, ": ", group.clears, " clear / ", group.defeats, " defeat / ", group.timeouts, " timeout")
	var configuration = {"realmIndex": START_REALM, "realmName": "炼气六层", "equipment": {"weapon":"wood_sword","armor":"cloth","accessory":"jade"}, "allCardsCollected":true, "startingCoins":0, "treasures":[], "consumablesUsed":false, "cultivationDuringRun":false}
	var version = str(ProjectSettings.get_setting("application/config/version")).trim_prefix("godot-")
	configuration.cultivationPath = "none"
	var file = FileAccess.open("res://verification/build-simulation-"+version+".json", FileAccess.WRITE)
	check(file != null, "Simulation report writable")
	var report = {"suite":"four-build-strategy-simulation", "version":version, "rulesVersion":Model.CURRENT_RULES, "checks":checks, "failures":failures,
		"method":"One visible-state heuristic with eight identical fixed seeds per preset; legal dispatch only after shared setup. These results are strategy regression evidence, not human win rates or human playtests.",
		"playerProgressUntouched":true, "baseDataUnchanged":true, "configuration":configuration,
		"seeds":SEEDS, "groups":groups, "runs":runs, "traceCoverage":"First seed per preset has full initialState, replayActions and exact replay verification."}
	if file != null: file.store_string(JSON.stringify(report,"\t")); file.close()
	print("Build simulation checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
