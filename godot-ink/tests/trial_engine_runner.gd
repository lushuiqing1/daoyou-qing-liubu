extends SceneTree
const Model = preload("res://scripts/ink_engine.gd")
const Store = preload("res://scripts/progress_store.gd")
var checks = 0
var failures: Array = []
var replays: Array = []
func _init(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); printerr("FAIL: "+message)
func new_trial(id: String, token: String):
	var model = Model.new()
	check(model.start_trial(id,token).ok,"Start exact trial "+id)
	check(Store.validate(model.state,model,true),"Core allows trial only explicit context")
	check(not Store.validate(model.state,model),"Ordinary progress rejects trial state")
	return model
func run():
	var normal = Model.new(932)
	normal.state.profile.records.clears = 1
	check(normal.trials_unlocked(),"Ordinary four-chapter clear unlocks trials")
	check(normal.trial_definitions().size() == 6,"Six exact trial definitions")
	for definition in normal.trial_definitions():
		var model = new_trial(definition.id,"engine-replay-"+definition.id)
		check(model.state.run.chapter == definition.chapter and model.state.run.rulesVersion == 4,"Direct target chapter rule4")
		check(model.state.profile.realm == definition.realm and model.state.profile.deck == definition.deck and model.state.run.treasures == definition.treasures,"Fixed trial configuration")
		check(model.state.profile.cultivationPath == "none" and model.state.battle.cultivation.tier == 0,"Trial has no cultivation")
		check(model.trial_result_info().is_empty(),"Active trial no complete receipt")
		var retry = new_trial(definition.id,"engine-retry-"+definition.id)
		var first = model.state.duplicate(true); var second = retry.state.duplicate(true)
		first.trial.sessionId = "same"; second.trial.sessionId = "same"
		check(first == second,"Same seed retry exact state/RNG independent token")
		test_prohibitions(model)
		var path = "res://tests/trial_replays/%s-%d.json"%[definition.id,definition.seed]
		var trace = Model.normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string(path)))
		for action in trace.actions:
			var result = model.dispatch(action)
			check(result.ok,"Real earned trace legal "+definition.id+" "+str(action.type))
			check(Store.validate(model.state,model,true),"Real earned trace valid "+definition.id)
		var result = model.trial_result_info()
		check(model.state.run == null and model.state.battle == null and model.state.lastResult.kind == "clear","Boss directly ends trial "+definition.id)
		check(result.qualified and result.kind == "clear" and result.metric == model.trial_metric(definition,model.state.lastResult.summary),"Genuine goal earned "+definition.id)
		var expected = trace.expectedSummary.duplicate(true); expected.kind = "clear"
		check(model.state.lastResult.summary == expected,"Entire genuine summary preserved except result kind "+definition.id)
		check(model.state.rng == trace.finalRng and model.state.seq == trace.finalSeq,"Original genuine trace exact final RNG/seq "+definition.id)
		check(model.state.trial.result == result,"Durable result matches actual summary")
		var completed = model.state.duplicate(true)
		check(model.dispatch({"type":"clearResult"}).ok and model.state.lastResult == completed.lastResult and model.state.trial.result == completed.trial.result,"Closing retains pending trial result")
		var ordinary_before = normal.state.duplicate(true)
		check(normal.dispatch({"type":"awardTrial","receipt":result}).ok,"Award earned receipt "+definition.id)
		check(normal.state.profile.records.trialStamps[definition.id] == {"earned":true,"bestMoves":result.moves},"Stamp only and best moves")
		check(normal.state.profile.records.trialReceipts[result.sessionId],"Receipt ledger durable")
		var ordinary_after = normal.state.duplicate(true)
		ordinary_after.profile.records.trialStamps = ordinary_before.profile.records.trialStamps
		ordinary_after.profile.records.trialReceipts = ordinary_before.profile.records.trialReceipts
		ordinary_after.revision = ordinary_before.revision
		check(ordinary_after == ordinary_before,"Award changes only ledger/stamps/revision all ordinary profile/run/battle untouched")
		ordinary_before = normal.state.duplicate(true)
		check(normal.dispatch({"type":"awardTrial","receipt":result}).ok and normal.state == ordinary_before,"Repeated receipt fully idempotent including revision")
		check(Store.validate(normal.state,normal),"Awarded normal progress validates")
		test_receipt_rejections(normal,result)
		replays.append({"id":definition.id,"seed":definition.seed,"qualified":result.qualified,"metric":result.metric,"moves":result.moves,"actions":trace.actions.size(),"originalRngMatched":true})
	test_terminal_failure()
	test_award_during_normal_battle(normal)
	var version = str(ProjectSettings.get_setting("application/config/version")).trim_prefix("godot-")
	var file = FileAccess.open("res://verification/trial-engine-"+version+".json",FileAccess.WRITE)
	check(file != null,"Trial engine report writable")
	if file != null:
		file.store_string(JSON.stringify({"suite":"six-genuine-trial-engine", "version":version, "checks":checks,"failures":failures,"replays":replays,"onlyLegalEarnedReplays":true,"playerProgressUntouched":true},"\t")); file.close()
	print("Trial engine: ",checks," checks; failures: ",failures.size())
	quit(0 if failures.is_empty() else 1)
func test_prohibitions(model):
	var actions = ["newRun","enterNode","reward","cultivate","equip","unequip","deckEquip","deckRemove","deckPreset","use","buyItem","sell","buyTreasure","claimTask","cultivationPath","awardTrial","useItem","sellItem","deckSet"]
	for action_type in actions:
		var before = model.state.duplicate(true)
		check(not model.dispatch({"type":action_type,"id":"spring_pill","slot":0}).ok and model.state == before,"Fixed character prohibits atomic "+action_type)
func test_receipt_rejections(normal, receipt: Dictionary):
	var edits = {"id":"unknown","seed":receipt.seed+1,"kind":"defeat","qualified":false,"metric":-1,"moves":0,"requirement":"fake goal","sessionId":""}
	for field in edits:
		var invalid = receipt.duplicate(true); invalid[field] = edits[field]; var before = normal.state.duplicate(true)
		check(not normal.dispatch({"type":"awardTrial","receipt":invalid}).ok and normal.state == before,"Invalid receipt atomic "+field)
	if receipt.id == "steps":
		var invalid = receipt.duplicate(true); invalid.moves += 1; var before = normal.state.duplicate(true)
		check(not normal.dispatch({"type":"awardTrial","receipt":invalid}).ok and normal.state == before,"Steps metric agrees with move count")
func test_terminal_failure():
	var abandon = new_trial("sword","engine-abandon")
	check(abandon.dispatch({"type":"abandon"}).ok,"Trial abandon legal")
	var result = abandon.trial_result_info()
	check(result.kind == "abandon" and not result.qualified and abandon.state.lastResult.summary.kind == "abandon","Abandon complete recap without stamp")
	check(not abandon.dispatch({"type":"newRun"}).ok,"Completed trial cannot become ordinary run")
	var defeat = new_trial("sword","engine-genuine-defeat")
	for turn in range(100):
		if defeat.state.run == null: break
		check(defeat.dispatch({"type":"endTurn"}).ok and Store.validate(defeat.state,defeat,true),"Defeat route only legal endTurn")
	result = defeat.trial_result_info()
	check(result.kind == "defeat" and not result.qualified and result.moves == 0,"Actual defeat complete recap without qualification")
	check(defeat.state.lastResult.summary.hpLost == defeat.stats().maxHp and not defeat.state.lastResult.summary.fatal.is_empty(),"Actual defeat records complete HP loss and fatal facts")
	var unknown = Model.new(); var before = unknown.state.duplicate(true)
	check(not unknown.start_trial("unknown","id").ok and unknown.state == before,"Unknown trial initialization atomic")
	check(not unknown.start_trial("sword","").ok and unknown.state == before,"Empty token initialization atomic")
	unknown.dispatch({"type":"newRun"}); before = unknown.state.duplicate(true)
	check(not unknown.start_trial("sword","id").ok and unknown.state == before,"Trial cannot overwrite ordinary in-memory run")
func test_award_during_normal_battle(normal):
	check(normal.dispatch({"type":"newRun"}).ok,"Ordinary run still works after stamps")
	var receipt = {"id":"sword","seed":630101,"sessionId":"unit-worse-score","kind":"clear","qualified":true,"metric":2,"moves":1000,"requirement":normal.trial_definition("sword").requirement}
	var before = normal.state.duplicate(true); var best_before = normal.state.profile.records.trialStamps.sword.bestMoves
	check(normal.dispatch({"type":"awardTrial","receipt":receipt}).ok,"Receipt operation permitted while independent ordinary battle active")
	check(normal.state.profile.records.trialStamps.sword.bestMoves == best_before,"Worse eligible unit receipt never worsens best moves")
	var after = normal.state.duplicate(true); after.profile.records.trialStamps = before.profile.records.trialStamps; after.profile.records.trialReceipts = before.profile.records.trialReceipts; after.revision = before.revision
	check(after == before,"Active ordinary battle/RNG/resources/profile unchanged by receipt")
