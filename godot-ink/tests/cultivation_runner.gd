extends SceneTree
const Model = preload("res://scripts/ink_engine.gd")
const Store = preload("res://scripts/progress_store.gd")
class StableModel extends Model:
	var next_red_batch = false
	func collapse(_s: Dictionary, board: Array):
		for i in range(36): board[i] = {"id":i+1,"type":d.types[(i/6+2*(i%6))%5]}
		if next_red_batch:
			for i in range(3): board[i].type = "red"
			next_red_batch = false
var checks = 0
var failures: Array = []
func _init(): call_deferred("run")
func check(ok: bool, text: String):
	checks += 1
	if not ok: failures.append(text); printerr("FAIL: "+text)
func apply(model, action: Dictionary) -> Dictionary:
	var result = model.dispatch(action)
	check(result.ok, "Action accepted "+JSON.stringify(action))
	check(Store.validate(model.state,model), "Valid state after "+str(action.type))
	return result
func fresh(realm: int, path: String, jade_accessory: bool = false):
	var model = StableModel.new(402)
	model.state.profile.realm = realm
	for id in model.cards: model.state.profile.collection[id] = 1
	apply(model,{"type":"cultivationPath","id":path})
	if jade_accessory: apply(model,{"type":"equip","id":"jade"})
	apply(model,{"type":"newRun"})
	return model
func set_wave(model, chapter: int, wave: int):
	model.state.run.chapter = chapter; model.state.run.nodes = model.node_states()
	for node in model.d.nodes:
		if node.level < wave-1: model.state.run.nodes[node.id] = "passed"
	model.start_battle(model.state,model.d.nodes[wave-1])
func match_board(model) -> Array:
	var board = []
	for i in range(36): board.append({"id":i+1,"type":model.d.types[(i/6+2*(i%6))%5]})
	for i in range(3): board[i].type = "red"
	model.state.seq = maxi(model.state.seq,100)
	return board
func kill_one(model) -> Dictionary:
	model.state.battle.enemy.hp = 1; model.state.battle.mana = 7
	return apply(model,{"type":"card","uid":model.state.battle.hand[0].uid})
func complete_chapter(model):
	while model.state.battle != null: kill_one(model)
	apply(model,{"type":"reward","id":""})
func run():
	test_tiers_and_selection()
	test_sword()
	test_guard_and_chapter()
	test_spirit()
	test_legacy_and_rng()
	test_storage()
	var version = str(ProjectSettings.get_setting("application/config/version")).trim_prefix("godot-")
	var file = FileAccess.open("res://verification/cultivation-"+version+".json",FileAccess.WRITE)
	check(file != null,"Cultivation report writable")
	if file != null:
		file.store_string(JSON.stringify({"suite":"cultivation-rule4", "version":version, "rulesVersion":4, "checks":checks,"failures":failures,"playerProgressUntouched":true,"method":"Deterministic rules, isolated storage fixtures, no player save access"},"\t")); file.close()
	print("Cultivation rules4: ",checks," checks; failures: ",failures.size())
	quit(0 if failures.is_empty() else 1)
func test_tiers_and_selection():
	var model = Model.new(12)
	for realm in range(10):
		check(model.cultivation_tier(realm) == (0 if realm < 2 else 1 if realm < 5 else 2 if realm < 8 else 3),"Tier realm boundary "+str(realm))
	check(model.state.profile.cultivationPath == "none","New profile opts out")
	for realm in [0,1]:
		model.state.profile.realm = realm
		for path in ["sword","guard","spirit"]:
			var before = model.state.duplicate(true)
			check(not model.dispatch({"type":"cultivationPath","id":path}).ok and model.state == before,"Below unlock atomic "+path)
		apply(model,{"type":"cultivationPath","id":"none"})
	model.state.profile.realm = 2
	var base = model.stats(); var rng = model.state.rng; var coins = model.state.profile.coins
	for path in ["sword","guard","spirit","none"]:
		apply(model,{"type":"cultivationPath","id":path})
		check(model.state.profile.coins == coins and model.state.rng == rng and model.stats() == base,"Free selection no stat/RNG change "+path)
	var before = model.state.duplicate(true)
	check(not model.dispatch({"type":"cultivationPath","id":"unknown"}).ok and model.state == before,"Invalid path atomic")
	apply(model,{"type":"cultivationPath","id":"sword"}); apply(model,{"type":"newRun"})
	check(model.state.run.rulesVersion == 4 and model.state.run.cultivationPath == "sword","New run pins rule4/path")
	before = model.state.duplicate(true)
	for path in ["none","guard"]: check(not model.dispatch({"type":"cultivationPath","id":path}).ok and model.state == before,"Entire run selection/cancel locked")
	var info = model.cultivation_info()
	check(info.locked and info.unlocked and info.selectedId == "sword" and info.availableTier == 1 and info.nextRealm == 5,"Info locking and next tier")
	for realm in [2,5,8]:
		var none = fresh(realm,"none")
		check(none.state.battle.cultivation == {"id":"none","tier":0,"redBonus":0,"turnShield":0,"startMana":0},"None always tier0")
func test_sword():
	for realm in [2,5,8]:
		var model = fresh(realm,"sword"); set_wave(model,3,5)
		var tier = model.cultivation_tier(realm); var st = model.stats(); var value = model.card_value("sword")
		check(st.attack == st.cardPower,"Sword path does not alter base attack/cardPower")
		model.state.battle.board = match_board(model); model.next_red_batch = true
		var expected = 3*(st.attack+tier)+roundi(3*(st.attack+tier)*1.15)
		check(model.resolve(model.state),"Sword chain resolution")
		check(model.state.run.summary.damage == expected,"Per-red path before chain multiplier tier "+str(tier))
		check(model.card_value("sword") == value,"Sword path never scales card damage")
		check(Store.validate(model.state,model),"Sword fixture valid")
		check("御剑%d"%tier in model.combat_sources_text() and "不增加术式伤害" in model.combat_sources_text(),"Sword precise source explanation")
func test_guard_and_chapter():
	for realm in [2,5,8]:
		var model = fresh(realm,"guard"); var expected = 2+2*model.cultivation_tier(realm)
		check(model.state.battle.shield == expected,"Cloth and guard initial shield")
		var snapshot = model.state.battle.cultivation.duplicate(true)
		kill_one(model)
		check(model.state.run.wave == 2 and model.state.battle.shield == expected and model.state.battle.cultivation == snapshot,"Same-turn wave preserves shield without new aura")
		apply(model,{"type":"endTurn"})
		check(model.state.battle.shield == expected,"Guard refresh only next player turn")
		check(model.state.run.summary.shieldExpired == expected,"Guard unused actual shield expiration counted")
	var growth = fresh(4,"guard"); var old_snapshot = growth.state.battle.cultivation.duplicate(true)
	complete_chapter(growth)
	var before = growth.state.duplicate(true)
	check(not growth.dispatch({"type":"cultivationPath","id":"sword"}).ok and growth.state == before,"Interchapter path locked")
	growth.state.profile.coins += int(growth.d.realms[4].cost)
	apply(growth,{"type":"cultivate"})
	check(growth.state.profile.realm == 5 and old_snapshot.tier == 1,"Breakthrough does not rewrite prior snapshot")
	apply(growth,{"type":"enterNode","id":"f1"})
	check(growth.state.battle.cultivation.tier == 2 and growth.state.battle.shield == 6,"New chapter snapshots increased tier")
func test_spirit():
	for realm in [2,5,8]:
		var model = fresh(realm,"spirit"); var tier = model.cultivation_tier(realm)
		check(model.state.battle.mana == 3+tier,"Spirit chapter-only starting mana")
		kill_one(model); var after_spell = 7-model.card_cost("sword")
		check(model.state.battle.mana == after_spell,"Spirit no same-turn wave refill")
		apply(model,{"type":"endTurn"})
		check(model.state.battle.mana == after_spell,"Spirit no next-turn refill")
	var cap = fresh(8,"spirit",true)
	check(cap.state.battle.mana == 7,"Spirit plus turn accessory cap7")
	complete_chapter(cap); apply(cap,{"type":"buyTreasure","id":"jade"})
	var overflow = int(cap.state.run.summary.manaOverflow)
	apply(cap,{"type":"enterNode","id":"f1"})
	check(cap.state.battle.mana == 7 and cap.state.run.summary.manaOverflow == overflow+1,"Treasure/accessory/spirit actual capped overflow")
	check("聚灵玉佩1" in cap.combat_sources_text() and "灵术3" in cap.combat_sources_text() and "每回合+1" in cap.combat_sources_text(),"Spirit exact sources")
func test_legacy_and_rng():
	var baseline = fresh(5,"none")
	for path in ["sword","guard","spirit"]:
		var current = fresh(5,path)
		check(current.state.rng == baseline.state.rng and current.state.battle.board == baseline.state.battle.board,"Path consumes no RNG "+path)
		for version in [2,3]:
			current.state.run.rulesVersion = version; current.state.battle.rulesVersion = version
			current.start_battle(current.state,current.node_by_id("f1"))
			check(current.state.battle.cultivation.id == "none" and current.state.battle.cultivation.tier == 0,"Old rules snapshot none")
			check(current.state.battle.shield == 2 and current.state.battle.mana == 3,"Old rules no guard/spirit initial effect")
			var info = current.cultivation_info()
			check(info.id == "none" and info.selectedId == path and "下一轮" in info.text,"Old run actual none vs preference")
			set_wave(current,3,5); current.state.battle.board = match_board(current)
			var damage_before = int(current.state.run.summary.damage); var attack = current.stats().attack
			check(current.resolve(current.state),"Old-rule red resolves")
			check(current.state.run.summary.damage-damage_before == 3*attack,"Old rules no red bonus")
func test_storage():
	var model = fresh(5,"guard"); var path = "res://verification/test-cultivation-v4.json"
	check(Store.save_state(model.state,path) == OK,"Write isolated rule4 fixture")
	check(Store.read_state(model,path) == model.state,"Rule4 exact save/load continuation")
	var updated = model.state.duplicate(true); updated.revision += 1
	check(Store.save_state(updated,path) == OK,"Rule4 backup write")
	var file = FileAccess.open(path,FileAccess.WRITE); file.store_string("corrupt fixture"); file.close()
	check(Store.read_state(model,path) == model.state,"Rule4 backup recovery")
	DirAccess.remove_absolute(path); DirAccess.remove_absolute(path.get_basename()+".backup.json")
	for field in ["id","tier","redBonus","turnShield","startMana"]:
		var invalid = model.state.duplicate(true)
		invalid.battle.cultivation[field] = "invalid"
		check(not Store.validate(invalid,model),"Reject malformed snapshot "+field)
	var invalid = model.state.duplicate(true); invalid.battle.cultivation.turnShield += 1
	check(not Store.validate(invalid,model),"Reject derived snapshot mismatch")
	invalid = model.state.duplicate(true); invalid.run.cultivationPath = "sword"
	check(not Store.validate(invalid,model),"Reject pinned path/snapshot mismatch")
	invalid = model.state.duplicate(true); invalid.profile.cultivationPath = "unknown"
	check(not Store.validate(invalid,model),"Reject unknown profile path")
	var old = fresh(5,"none"); old.state.run.rulesVersion = 3; old.state.battle.rulesVersion = 3
	old.state.profile.erase("cultivationPath"); old.state.run.erase("cultivationPath"); old.state.battle.erase("cultivation")
	var original_enemy = old.state.battle.enemy.duplicate(true); var rng = old.state.rng
	check(Store.validate(old.state,old),"Rule3 lacks optional cultivation fields")
	old.state = old.upgrade_state(old.state)
	check(old.state.profile.cultivationPath == "none" and old.state.battle.cultivation.tier == 0,"Rule3 optional cultivation migration")
	check(old.state.battle.enemy == original_enemy and old.state.rng == rng and old.state.run.rulesVersion == 3,"Rule3 pinned telegraph/RNG continuation")
	var old_path = "res://verification/test-cultivation-v3.json"
	check(Store.save_state(old.state,old_path) == OK and Store.read_state(old,old_path) == old.state,"Rule3 exact continuation")
	DirAccess.remove_absolute(old_path); DirAccess.remove_absolute(old_path.get_basename()+".backup.json")
