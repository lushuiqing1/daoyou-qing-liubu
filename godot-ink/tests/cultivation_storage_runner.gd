extends SceneTree
const Model = preload("res://scripts/ink_engine.gd")
const Store = preload("res://scripts/progress_store.gd")
const PATH = "res://verification/test-cultivation-progress.json"
var checks = 0
var failures: Array = []
func _init(): call_deferred("run")
func check(value: bool, message: String):
	checks += 1
	if not value: failures.append(message); printerr("FAIL: "+message)
func cleanup():
	for path in [PATH, PATH.get_basename()+".backup.json", PATH+".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
func write_state(value: Dictionary):
	var file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(value)); file.close()
func run():
	cleanup()
	for path_id in ["none", "sword", "guard", "spirit"]:
		for realm in [2, 5, 8]:
			var model = Model.new(630100+realm)
			model.state.profile.realm = realm
			check(model.dispatch({"type":"cultivationPath", "id":path_id}).ok, "Select path "+path_id)
			check(model.dispatch({"type":"newRun"}).ok, "Start rule4 path")
			check(Store.validate(model.state, model), "Validate exact chapter snapshot")
			check(Store.save_state(model.state, PATH) == OK, "Save isolated rule4")
			check(Store.read_state(model, PATH) == model.state, "Rule4 continue exact RNG/resources/snapshot")
			for key in ["tier", "redBonus", "turnShield", "startMana"]:
				var bad = model.state.duplicate(true); bad.battle.cultivation[key] += 1
				check(not Store.validate(bad, model), "Reject incorrect source value "+key)
			var missing = model.state.duplicate(true); missing.battle.erase("cultivation")
			check(not Store.validate(missing, model), "Rule4 cannot omit snapshot")
			missing = model.state.duplicate(true); missing.run.erase("cultivationPath")
			check(not Store.validate(missing, model), "Rule4 cannot omit locked path")
			missing = model.state.duplicate(true); missing.profile.cultivationPath = "invalid"
			check(not Store.validate(missing, model), "Reject malformed selected path")
			cleanup()
	var model = Model.new(730001)
	model.state.profile.realm = 8
	model.dispatch({"type":"newRun"})
	var raw = model.state.duplicate(true)
	raw.profile.erase("cultivationPath"); raw.run.erase("cultivationPath"); raw.battle.erase("cultivation")
	raw.run.rulesVersion = 3; raw.battle.rulesVersion = 3
	check(Store.validate(raw, model), "Accept historical rule3 missing new fields")
	write_state(raw)
	var restored = Store.read_state(model, PATH)
	check(restored.run.rulesVersion == 3 and restored.profile.cultivationPath == "none", "Rule3 remains pinned after upgrade")
	check(restored.battle.enemy == raw.battle.enemy and restored.rng == raw.rng and restored.seq == raw.seq, "Rule3 retains telegraph/RNG/sequence")
	model.state = restored
	check(model.dispatch({"type":"endTurn"}).ok and Store.validate(model.state,model), "Rule3 continue commits valid state")
	check(Store.save_state(model.state, PATH) == OK, "Save continued rule3")
	var continued = model.state.duplicate(true)
	check(Store.read_state(model, PATH) == continued, "Rule3 save roundtrip")
	var file = FileAccess.open(PATH,FileAccess.WRITE); file.store_string("{broken"); file.close()
	check(Store.read_state(model, PATH).battle.enemy == raw.battle.enemy, "Rule3 restores backup telegraph")
	check(Store.save_state(continued, PATH) == OK, "Recovered backup preserved on new write")
	check(Store.read_state(model, PATH) == continued, "Recovered rule3 resumes exact state")
	cleanup()
	var legacy = raw.duplicate(true)
	legacy.run.rulesVersion = 2; legacy.battle.rulesVersion = 2
	model.state = legacy
	legacy.battle.enemyRound = 2; legacy.battle.round = 2
	legacy.battle.enemy.intentKind = ""; legacy.battle.enemy.nextDamage = 0
	model.announce_intent(legacy.battle, legacy)
	check(Store.validate(legacy, model), "Historical rule2 charged state accepted")
	write_state(legacy)
	restored = Store.read_state(model, PATH)
	check(restored.run.rulesVersion == 2 and restored.battle.enemy == legacy.battle.enemy, "Rule2 charged damage preserved")
	check(restored.profile.cultivationPath == "none", "Legacy user defaults unselected")
	cleanup()
	var version = str(ProjectSettings.get_setting("application/config/version")).replace("godot-", "")
	file = FileAccess.open("res://verification/cultivation-storage-"+version+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"rules3And4ExactContinue":true,"isolatedStorage":true},"\t")); file.close()
	print("Cultivation storage: ",checks," checks; failures: ",failures.size())
	quit(0 if failures.is_empty() else 1)
