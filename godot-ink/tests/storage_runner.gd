extends SceneTree
const Model = preload("res://scripts/ink_engine.gd")
const Legacy = preload("res://tests/migration_v1_engine.gd")
const Store = preload("res://scripts/progress_store.gd")
const TEST_PATHS = ["res://verification/test-progress.json","res://verification/test-v2-import.json","res://verification/test-v1-source.json","res://verification/test-v2-legacy-flow.json","res://verification/test-v1-legacy-flow.json"]
var checks = 0
var failures: Array = []
func _init(): call_deferred("run")
func check(value: bool, message: String):
	checks += 1
	if not value: failures.append(message); printerr("FAIL: "+message)
func write_text(path: String, value: String):
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(value); file.close()
func cleanup():
	for path in TEST_PATHS:
		for suffix in [path,path.get_basename()+".backup.json",path+".tmp"]:
			if FileAccess.file_exists(suffix): DirAccess.remove_absolute(suffix)
func run():
	cleanup()
	var model = Model.new(7654321); model.dispatch({"type":"newRun"})
	var path = TEST_PATHS[0]
	check(Store.save_state(model.state,path) == OK,"Save current native model to isolated path")
	check(Store.read_state(model,path) == model.state,"Restore exact current model")
	var original = model.state.duplicate(true)
	model.dispatch({"type":"card","uid":model.state.battle.hand[0].uid})
	check(Store.save_state(model.state,path) == OK,"Overwrite current native model")
	check(Store.read_state(model,path) == model.state,"Restore overwritten model")
	write_text(path,"{broken")
	check(Store.read_state(model,path) == original,"Recover valid backup after main corruption")
	var backup_before = FileAccess.get_file_as_string(path.get_basename()+".backup.json")
	check(Store.save_state(original,path) == OK,"Save after backup recovery")
	check(FileAccess.get_file_as_string(path.get_basename()+".backup.json") == backup_before,"Recovery preserves good backup instead of copying corrupt main")
	check(Store.read_state(model,path) == original,"Recovered main becomes readable")
	for key in ["profile","settings","battle","run"]:
		var bad = original.duplicate(true); bad[key] = "invalid"
		check(not Store.validate(bad,model),"Reject damaged core "+key)
	var bad = original.duplicate(true); bad.schema = 16; check(not Store.validate(bad,model),"Reject webpage/foreign schema")
	bad = original.duplicate(true); bad.profile.records = {}; check(not Store.validate(bad,model),"Reject incomplete records")
	bad = original.duplicate(true); bad.profile.realm = "bad"; check(not Store.validate(bad,model),"Reject noninteger realm")
	bad = original.duplicate(true); bad.settings.guide.seen = ["unknown"]; check(not Store.validate(bad,model),"Reject unknown guide checkpoint")
	bad = original.duplicate(true); bad.settings.guide.seen = ["swap","swap"]; check(not Store.validate(bad,model),"Reject duplicate guide checkpoint")
	bad = original.duplicate(true); bad.battle.links.swordReady = 1; check(not Store.validate(bad,model),"Reject nonbool link")
	bad = original.duplicate(true); bad.run.rulesVersion = 99; check(not Store.validate(bad,model),"Reject unsupported combat rules")
	bad = original.duplicate(true); bad.battle.rulesVersion = 2; check(not Store.validate(bad,model),"Reject run/battle rule mismatch")
	test_migration(model)
	test_flow1_migration(model)
	cleanup()
	var report = FileAccess.open("res://verification/storage.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"suite":"progress-v2-storage","checks":checks,"failures":failures,"nativeSave":true,"backupRecovery":true,"oneTimeV1Import":true,"corruptV2NoFallback":true,"defaultWritesProtected":true,"legacyFilesUntouched":true,"testPathsOnly":true,"userProgressUntouched":true},"\t")); report.close()
	print("Native v2 storage: ",checks," checks; failures: ",failures.size())
	quit(1 if not failures.is_empty() else 0)
func test_migration(model):
	var old_model = Model.new(89); old_model.dispatch({"type":"newRun"})
	var old = old_model.state.duplicate(true)
	old.settings.erase("guide"); old.profile.records.erase("lastSummary"); old.run.erase("summary"); old.run.erase("rulesVersion"); old.battle.erase("links"); old.battle.rulesVersion = 2
	old.battle.enemy.intentKind = ""; old.battle.enemy.nextDamage = 0; old_model.announce_intent(old.battle,old)
	var old_text = JSON.stringify(old); var destination = TEST_PATHS[1]; var source = TEST_PATHS[2]
	write_text(source,old_text)
	var imported = Store._read_state_paths(model,destination,source)
	check(not imported.blocked and imported.error.is_empty() and not imported.state.is_empty(),"First import succeeds")
	check(FileAccess.file_exists(destination) and Store.read_state(model,destination) == imported.state,"Successful first import persists new v2 file")
	check(FileAccess.get_file_as_string(source) == old_text and not FileAccess.file_exists(source.get_basename()+".backup.json"),"First import does not mutate original main/backup")
	check(imported.state.run.rulesVersion == 2 and imported.state.run.summary.coverage == "partial" and not imported.state.settings.guide.enabled,"Current v1 optional fields upgraded safely")
	old.profile.coins = 999999; write_text(source,JSON.stringify(old))
	check(Store._read_state_paths(model,destination,source).state == imported.state,"Existing v2 never reimports changed v1")
	write_text(destination,"{broken-v2-main"); write_text(destination.get_basename()+".backup.json","{broken-v2-backup")
	var broken = Store._read_state_paths(model,destination,source)
	check(broken.blocked and not broken.error.is_empty() and broken.state.is_empty(),"Corrupt v2 pair blocks with visible error")
	check(FileAccess.get_file_as_string(destination) == "{broken-v2-main" and FileAccess.get_file_as_string(destination.get_basename()+".backup.json") == "{broken-v2-backup","Corrupt v2 pair not overwritten or replaced by stale v1")
	var blocked_before = Store.writes_blocked; var error_before = Store.last_error
	check(Store.read_state(model,destination).is_empty(),"Explicit custom read sees corrupt pair")
	check(Store.writes_blocked == blocked_before and Store.last_error == error_before,"Custom paths do not mutate default-session protection")
	Store.writes_blocked = true
	check(Store.save_state(model.state) == ERR_FILE_CORRUPT,"Default save exits before filesystem access when blocked")
	Store.writes_blocked = blocked_before; Store.last_error = error_before
	DirAccess.remove_absolute(destination); DirAccess.remove_absolute(destination.get_basename()+".backup.json")
	write_text(source,"{broken-old-main"); write_text(source.get_basename()+".backup.json",old_text)
	check(not Store._read_state_paths(model,destination,source).blocked,"First import can recover original v1 backup")
	check(FileAccess.get_file_as_string(source) == "{broken-old-main" and FileAccess.get_file_as_string(source.get_basename()+".backup.json") == old_text,"Original v1 backup recovery leaves both old files intact")
func test_flow1_migration(model):
	var legacy = Legacy.new(345); legacy.dispatch({"type":"newRun"}); legacy.dispatch({"type":"enterNode","id":"f1"})
	legacy.state.battle.enemy.hp = 25
	var source = TEST_PATHS[4]; var destination = TEST_PATHS[3]; var old_text = JSON.stringify(legacy.state)
	write_text(source,old_text)
	var imported = Store._read_state_paths(model,destination,source)
	check(not imported.blocked and imported.state.run.flowVersion == 2 and imported.state.run.rulesVersion == 2,"Legacy flow1 imports to five waves with rules2")
	check(imported.state.battle.enemy.hp == maxi(1,roundi(99.0*25.0/legacy.state.battle.enemy.maxHp)),"Legacy flow1 remaining HP ratio preserved")
	check(imported.state.profile.coins == legacy.state.profile.coins and imported.state.profile.inventory == legacy.state.profile.inventory and imported.state.profile.collection == legacy.state.profile.collection,"Legacy growth, inventory and collection preserved")
	check(Store.validate(imported.state,model) and FileAccess.get_file_as_string(source) == old_text,"Legacy import validates and leaves original bytes intact")

