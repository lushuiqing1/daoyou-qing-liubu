extends SceneTree
const Model = preload("res://tests/migration_v1_engine.gd")
const Store = preload("res://scripts/progress_store.gd")
var checked = 0
var failed = 0

func _init(): call_deferred("run")

func mismatch(a: Variant, b: Variant, path: String = "") -> String:
	if a is Dictionary and b is Dictionary:
		for k in a:
			if k == "schema": continue
			if not b.has(k): return path+"/"+k+" missing"
			var diff = mismatch(a[k],b[k],path+"/"+k)
			if diff: return diff
		for k in b:
			if not a.has(k): return path+"/"+k+" unexpected"
	elif a is Array and b is Array:
		if a.size() != b.size(): return path+" array length"
		for i in range(a.size()):
			var diff = mismatch(a[i],b[i],path+"/"+str(i))
			if diff: return diff
	elif a != b: return path+": "+str(a)+" != "+str(b)
	return ""

func run():
	var suites = JSON.parse_string(FileAccess.get_file_as_string("res://tests/oracle.json"))
	for suite in suites:
		var model = Model.new(); model.state = Model.normalize_numbers(suite.initial); model.state.schema = Model.FORMAT
		for i in range(suite.steps.size()):
			var step = suite.steps[i]; var result = model.dispatch(step.action); checked += 1
			var diff = mismatch(model.state,step.state)
			if result.ok != step.ok or diff:
				failed += 1; printerr(suite.name+" step "+str(i)+" "+JSON.stringify(step.action)+" "+diff); break
	var native = preload("res://scripts/ink_engine.gd").new(88)
	assert(Store.validate(native.state,native))
	native.dispatch({"type":"newRun"}); native.dispatch({"type":"enterNode","id":"f1"})
	assert(Store.validate(JSON.parse_string(JSON.stringify(native.state)),native))
	var legacy = native.state.duplicate(true); legacy.schema = 16
	assert(not Store.validate(legacy,native))
	print("Historical v1 migration parity: ",checked," checkpoints, ",failed," failed suites. Native round-trip / legacy rejection passed.")
	var report = {"suites":suites.size(),"checkpoints":checked,"failed":failed,"native_round_trip":true,"legacy_rejected":true}
	var file = FileAccess.open("res://verification/migration-v1.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t"))
	quit(1 if failed else 0)
