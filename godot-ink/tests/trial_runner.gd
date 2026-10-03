extends SceneTree
const Model = preload("res://scripts/ink_engine.gd")
const Session = preload("res://scripts/trial_session.gd")
const CommitFailure = preload("res://tests/trial_commit_failure_session.gd")
const TrialStore = preload("res://scripts/trial_store.gd")
const Progress = preload("res://scripts/progress_store.gd")
const IDS = ["sword","guard","spirit","break","chain","steps"]
const ROOT_PATH = "res://verification/test-trial-"
var checks = 0
var failures = []
var traces = {}
var outcomes = []
var negative_cases = []
var paths = []
func _init(): call_deferred("run")
func check(value: bool, message: String):
	checks += 1
	if not value: failures.append(message); printerr("FAIL: "+message)
func normal_model():
	var model = Model.new(8899)
	model.state.profile.records.clears = 1; model.state.profile.coins = 137
	model.state.profile.realm = 2; model.state.profile.hp = 96
	return model
func ordinary_scope(s: Dictionary) -> Dictionary:
	var result = s.duplicate(true); result.revision = 0
	result.profile.records.erase("trialStamps"); result.profile.records.erase("trialReceipts")
	return result
func fixture_path(name: String) -> String:
	var path = ROOT_PATH+name+".json"
	if path not in paths: paths.append(path)
	return path
func write_text(path: String, data: String):
	var file = FileAccess.open(path,FileAccess.WRITE); file.store_string(data); file.close()
func clean_path(path: String):
	for target in [path,path.get_basename()+".backup.json",path+".tmp"]:
		if FileAccess.file_exists(target): DirAccess.remove_absolute(target)
func isolated_session(name: String):
	var session = Session.new()
	session.save_path = fixture_path(name+"-session"); session.normal_save_path = fixture_path(name+"-normal")
	clean_path(session.save_path); clean_path(session.normal_save_path)
	return session
func play(session, id: String, validate_each: bool = true):
	for action in traces[id].actions:
		var response = session.engine.dispatch(action)
		check(response.ok,"Legal original trace "+id+" "+JSON.stringify(action))
		if not response.ok: break
		if validate_each: check(TrialStore.validate(session.envelope(),session.engine),"Fixed trial/core validation after "+id+" "+str(action.type))
func run():
	for index in range(6):
		traces[IDS[index]] = Model.normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/trial_replays/"+IDS[index]+"-"+str(630101+index)+".json")))
	test_unlock_and_prohibitions()
	test_six_replays()
	test_actual_unqualified_and_defeat()
	test_save_resume_retry_and_validation()
	test_receipt_before_normal()
	test_receipt_after_normal()
	test_normal_backup_missing_receipt()
	test_write_failures()
	test_backup_and_corruption()
	for path in paths: clean_path(path)
	var file = FileAccess.open("res://verification/trials-1.5.0.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"suite":"isolated-trial-session-and-receipts","checks":checks,"failures":failures,"sixRealReplays":outcomes,"realNegativeCases":negative_cases,"onlyLegalTraceActions":true,"noInjectedTrialInit":true,"userProgressUntouched":true,"ordinaryAndTrialFilesSeparate":true},"\t")); file.close()
	print("Trial session/store: ",checks," checks; failures ",failures.size()," / ",JSON.stringify(outcomes))
	quit(0 if failures.is_empty() else 1)
func test_unlock_and_prohibitions():
	var session = Session.new(); session.persistence = false; var normal = Model.new()
	check(not session.can_start(normal) and not session.start("steps",normal) and not session.has_session(),"Trial locked before ordinary clear")
	normal.state.profile.records.clears = 1; normal.dispatch({"type":"newRun"})
	check(not session.can_start(normal) and not session.start("steps",normal),"Normal active run prevents trial start")
	normal.dispatch({"type":"abandon"}); check(session.start("steps",normal),"Finished normal run permits trial")
	check(session.engine.state.run.rulesVersion == 4 and session.engine.state.profile.cultivationPath == "none" and session.engine.state.battle.cultivation.redBonus == 0,"Fixed rules4 character has no cultivation")
	for type in ["newRun","enterNode","reward","cultivate","equip","unequip","deckEquip","deckRemove","deckPreset","use","buyItem","sell","buyTreasure","claimTask","cultivationPath","awardTrial"]:
		var before = session.engine.state.duplicate(true)
		check(not session.engine.dispatch({"type":type,"id":"spring_pill","slot":0}).ok and session.engine.state == before,"Trial rejects actual operation "+type+" atomically")
	var before = normal.state.duplicate(true)
	check(session.engine.dispatch({"type":"settings","id":"sound","value":false}).ok and normal.state == before,"Trial setting affects only trial model")
	check(session.engine.dispatch({"type":"abandon"}).ok and not session.engine.trial_result_info().qualified,"Real abandonment never earns stamp")
	check(session.save() and session.reconcile(normal) and normal.state == before,"Unqualified completed trial leaves ordinary state untouched")
func test_six_replays():
	var normal = normal_model(); var baseline = ordinary_scope(normal.state)
	for id in IDS:
		var session = Session.new(); session.persistence = false
		check(session.start(id,normal),"Start product session "+id)
		var initial = session.engine.state.duplicate(true)
		var definition = session.engine.trial_definition(id)
		check(initial.run.chapter == definition.chapter and initial.profile.realm == definition.realm and initial.profile.deck == definition.deck,"Exact fixed setup "+id)
		play(session,id)
		var receipt = session.engine.trial_result_info()
		check(session.engine.state.run == null and session.engine.state.lastResult.kind == "clear" and receipt.qualified,"True single-chapter clear and stamp "+id)
		var expected = traces[id].expectedSummary.duplicate(true); expected.kind = "clear"
		check(session.engine.state.lastResult.summary == expected,"Original rules3 gameplay summary equals rules4 none "+id)
		check(session.engine.state.rng == traces[id].finalRng and session.engine.state.seq == traces[id].finalSeq,"Identical real RNG/sequence from direct initialization "+id)
		check(ordinary_scope(normal.state) == baseline,"Playing trial never alters ordinary profile/run/RNG "+id)
		check(session.reconcile(normal) and session.receipt_committed,"Receipt committed in no-save mode "+id)
		check(normal.state.profile.records.trialStamps[id].earned and normal.state.profile.records.trialStamps[id].bestMoves == receipt.moves,"Only stamp and best swaps awarded "+id)
		var after = normal.state.duplicate(true)
		check(session.reconcile(normal) and normal.state == after,"Repeated receipt is whole-state idempotent "+id)
		check(ordinary_scope(normal.state) == baseline,"Award preserves ordinary progression and run/RNG "+id)
		outcomes.append({"id":id,"seed":receipt.seed,"moves":receipt.moves,"metric":receipt.metric,"qualified":receipt.qualified,"actions":traces[id].actions.size()})
	check(normal.state.profile.records.trialStamps.size() == 6 and normal.state.profile.records.trialReceipts.size() == 6,"Six independent stamped receipts")
func available_uid(model, id: String) -> int:
	for card in model.state.battle.hand:
		if card.cardId == id and model.card_reason(card.uid).is_empty(): return card.uid
	return -1
func inefficient_move(model) -> Array:
	var board = model.state.battle.board
	for a in range(36):
		for b in [a+1 if a%6 < 5 else -1,a+6 if a < 30 else -1]:
			if b < 0: continue
			var copy = board.duplicate(); var old = copy[a]; copy[a] = copy[b]; copy[b] = old
			var found = model.matches(copy)
			if found.is_empty(): continue
			var red = false
			for index in found:
				if copy[index].type == "red": red = true
			if not red: return [a,b]
	return model.possible_move(board)
func test_actual_unqualified_and_defeat():
	var normal = normal_model(); var original = normal.state.duplicate(true)
	var failed = Session.new(); failed.persistence = false; check(failed.start("steps",normal),"Start real defeat scenario")
	for turn in range(100):
		if failed.engine.state.run == null: break
		check(failed.engine.dispatch({"type":"endTurn"}).ok,"Actual enemy action in defeat scenario")
	check(failed.engine.state.lastResult != null and failed.engine.state.lastResult.kind == "defeat" and not failed.engine.trial_result_info().qualified,"EndTurn-only play yields actual defeat without stamp")
	check(TrialStore.validate(failed.envelope(),failed.engine) and failed.save() and failed.reconcile(normal) and normal.state == original,"Defeat journal/recap valid and ordinary progress untouched")
	negative_cases.append(failed.engine.trial_result_info())
	var slow = Session.new(); slow.persistence = false; check(slow.start("steps",normal),"Start genuine over-budget clear scenario")
	for turn in range(1800):
		if slow.engine.state.run == null: break
		var model = slow.engine; var b = model.state.battle; var st = model.stats(); var action: Dictionary
		var heal = available_uid(model,"heal"); var sword = available_uid(model,"sword"); var ward = available_uid(model,"ward")
		if heal >= 0 and model.state.profile.hp < st.maxHp*0.65: action = {"type":"card","uid":heal}
		elif model.state.run.moves > 32 and sword >= 0 and (b.steps == 0 or b.mana >= 6 or b.enemy.hp <= model.card_value("sword")): action = {"type":"card","uid":sword}
		elif b.steps > 0:
			var pair = inefficient_move(model) if model.state.run.moves <= 32 else model.possible_move(b.board)
			action = {"type":"swap","a":pair[0],"b":pair[1]}
		elif ward >= 0 and b.enemy.intent > st.armor+b.shield: action = {"type":"card","uid":ward}
		else: action = {"type":"endTurn"}
		check(model.dispatch(action).ok,"Over-budget attempt uses only legitimate dispatch")
	var result = slow.engine.trial_result_info()
	check(not result.is_empty() and result.kind == "clear" and not result.qualified and result.moves > 32,"Actual single-chapter victory can fail the exchange goal")
	check(TrialStore.validate(slow.envelope(),slow.engine) and slow.save() and slow.reconcile(normal) and normal.state == original,"Unqualified clear retains full recap and awards nothing")
	negative_cases.append(result)
func test_save_resume_retry_and_validation():
	var normal = normal_model(); var session = isolated_session("resume")
	check(session.start("steps",normal),"Persist fresh trial to isolated path")
	var initial = session.engine.state.duplicate(true)
	for action in traces.steps.actions.slice(0,6): check(session.engine.dispatch(action).ok,"Resume fixture uses legitimate actions")
	check(session.save(),"Persist midbattle")
	var saved = session.engine.state.duplicate(true)
	var resumed = Session.new(); resumed.save_path = session.save_path; resumed.normal_save_path = session.normal_save_path
	check(resumed.load() and resumed.engine.state == saved and not resumed.receipt_committed,"Resume exact RNG/resources/board/links")
	check(resumed.start("steps",normal),"Retry reconstructs fixed seed")
	var retry = resumed.engine.state.duplicate(true); retry.trial.sessionId = initial.trial.sessionId
	check(retry == initial,"Retry deterministic except independent session token")
	var envelope = resumed.envelope()
	check(not Progress.validate(resumed.engine.state,resumed.engine) and Progress.validate(resumed.engine.state,resumed.engine,true),"Ordinary validation refuses trial without explicit context")
	var guarded = fixture_path("ordinary-guard"); clean_path(guarded)
	check(Progress.save_state(resumed.engine.state,guarded) == ERR_INVALID_DATA and not FileAccess.file_exists(guarded),"Ordinary save refuses creating a trial payload")
	check(Progress.save_state(normal.state,guarded) == OK,"Create legitimate ordinary guarded fixture")
	var bytes = FileAccess.get_file_as_string(guarded)
	check(Progress.save_state(resumed.engine.state,guarded) == ERR_INVALID_DATA and FileAccess.get_file_as_string(guarded) == bytes,"Ordinary save refuses overwriting with trial payload")
	for key in ["seed","sessionId","result"]:
		var bad = envelope.duplicate(true); bad.engineState.trial[key] = 0 if key == "sessionId" else "invalid"
		check(not TrialStore.validate(bad,resumed.engine),"Reject malformed trial metadata "+key)
	for key in ["realm","equipment","legacy","inventory","deck","cultivationPath"]:
		var bad = envelope.duplicate(true); bad.engineState.profile[key] = 0
		check(not TrialStore.validate(bad,resumed.engine),"Reject altered fixed profile "+key)
	var bad = envelope.duplicate(true); bad.engineState.run.treasures = []
	check(not TrialStore.validate(bad,resumed.engine),"Reject altered fixed treasures")
	bad = envelope.duplicate(true); bad.receiptCommitted = true; check(not TrialStore.validate(bad,resumed.engine),"Active battle cannot claim committed receipt")
	bad = normal.state.duplicate(true); bad.profile.records.trialStamps = {"unknown":{"earned":true,"bestMoves":1}}; check(not Progress.validate(bad,normal),"Reject unknown normal stamp ID")
	bad = normal.state.duplicate(true); bad.profile.records.trialReceipts = {" ":true}; check(not Progress.validate(bad,normal),"Reject empty normal receipt token")
	bad = normal.state.duplicate(true); bad.profile.records.trialStamps = {"steps":{"earned":true,"bestMoves":0}}; check(not Progress.validate(bad,normal),"Reject nonpositive best exchanges")
func completed_fixture(name: String, normal):
	var session = isolated_session(name)
	check(Progress.save_state(normal.state,session.normal_save_path) == OK,"Persist ordinary fixture "+name)
	check(session.start("steps",normal),"Create receipt fixture "+name)
	play(session,"steps",false)
	check(session.save(),"Completed result journaled before receipt "+name)
	return session
func reload(session):
	var next = Session.new(); next.save_path = session.save_path; next.normal_save_path = session.normal_save_path
	check(next.load(),"Reload valid isolated trial journal")
	return next
func test_receipt_before_normal():
	var normal = normal_model(); var baseline = ordinary_scope(normal.state)
	var session = completed_fixture("before-normal",normal)
	var resumed = reload(session)
	check(not resumed.receipt_committed and normal.state.profile.records.trialStamps.is_empty(),"Crash before ordinary commit remains pending")
	check(resumed.reconcile(normal) and resumed.receipt_committed,"Recover pending result into ordinary ledger")
	check(ordinary_scope(normal.state) == baseline and Progress.read_state(normal,resumed.normal_save_path) == normal.state,"Recovered stamp is durably saved without ordinary changes")
	var after = normal.state.duplicate(true); check(reload(resumed).reconcile(normal) and normal.state == after,"Reloaded committed receipt cannot duplicate")
func test_receipt_after_normal():
	var normal = normal_model(); var session = completed_fixture("after-normal",normal)
	check(normal.dispatch({"type":"awardTrial","receipt":session.engine.trial_result_info()}).ok,"Apply ordinary receipt without journal flag")
	check(Progress.save_state(normal.state,session.normal_save_path) == OK,"Persist ordinary commit before trial flag")
	var before = normal.state.duplicate(true); var resumed = reload(session)
	check(not resumed.receipt_committed and resumed.reconcile(normal) and resumed.receipt_committed,"Crash after ordinary commit repairs trial flag")
	check(normal.state == before,"Flag repair never rewrites ordinary model/revision")
	var bad = resumed.envelope().duplicate(true); bad.engineState.trial.result.metric += 1
	check(not TrialStore.validate(bad,resumed.engine),"Completed receipt metric must match real recap")
	bad = resumed.envelope().duplicate(true); bad.engineState.trial.result.qualified = false
	check(not TrialStore.validate(bad,resumed.engine),"Completed qualification must match real goal")
func test_normal_backup_missing_receipt():
	var normal = normal_model(); var session = completed_fixture("normal-backup",normal)
	check(session.reconcile(normal) and session.receipt_committed,"Commit both stores before backup-loss scenario")
	write_text(session.normal_save_path,"{corrupt-main")
	var backup_state = Progress.read_state(normal,session.normal_save_path)
	check(not backup_state.is_empty() and backup_state.profile.records.trialReceipts.is_empty(),"Valid ordinary backup predates receipt")
	normal.state = backup_state; var baseline = ordinary_scope(normal.state); var resumed = reload(session)
	check(resumed.receipt_committed and resumed.reconcile(normal),"Committed trial flag still repairs missing ordinary ledger token")
	check(normal.state.profile.records.trialStamps.steps.earned and ordinary_scope(normal.state) == baseline,"Backup recovery reawards only stamp fields")
	# Same independent journal also survives an intentional ordinary-profile reset.
	normal.state = normal.create(707); baseline = ordinary_scope(normal.state)
	check(resumed.reconcile(normal) and normal.state.profile.records.trialStamps.steps.earned and ordinary_scope(normal.state) == baseline,"Ordinary reset preserves and can recover latest trial stamp without restoring progression")
func test_write_failures():
	var normal = normal_model(); var session = completed_fixture("normal-writefail",normal)
	var correct_path = session.normal_save_path; var before = normal.state.duplicate(true)
	session.normal_save_path = "res://verification/nonexistent-trial-directory-"+str(Time.get_ticks_msec())+"/progress.json"
	check(not session.reconcile(normal) and not session.last_error.is_empty() and normal.state == before,"Failed ordinary save rolls back in-memory receipt exactly")
	var pending = session.engine.state.duplicate(true)
	check(not session.start("sword",normal) and session.engine.state == pending and normal.state == before,"Pending qualifying result cannot be discarded when replacement reconciliation fails")
	check(not session.receipt_committed and reload(session).engine.trial_result_info().qualified,"Failed ordinary save leaves qualifying result recoverable")
	session.normal_save_path = correct_path; check(session.start("sword",normal) and normal.state.profile.records.trialStamps.steps.earned and session.engine.state.trial.id == "sword","New trial starts only after prior qualifying receipt is durably committed")
	var blocked = Progress.writes_blocked; var prior_error = Progress.last_error
	var other = completed_fixture("blocked-normal",normal_model()); var untouched = normal_model(); before = untouched.state.duplicate(true)
	other.normal_save_path = Progress.SAVE; Progress.writes_blocked = true; Progress.last_error = "Injected protected ordinary store"
	check(not other.reconcile(untouched) and untouched.state == before and not other.receipt_committed,"Protected default ordinary store prevents award before file access")
	Progress.writes_blocked = blocked; Progress.last_error = prior_error
	var original = normal_model(); var final_fail = CommitFailure.new()
	final_fail.save_path = fixture_path("final-writefail-session"); final_fail.normal_save_path = fixture_path("final-writefail-normal")
	clean_path(final_fail.save_path); clean_path(final_fail.normal_save_path)
	check(Progress.save_state(original.state,final_fail.normal_save_path) == OK and final_fail.start("steps",original),"Set up final journal failure")
	play(final_fail,"steps",false)
	check(not final_fail.reconcile(original) and original.state.profile.records.trialStamps.steps.earned and not final_fail.receipt_committed,"Last journal write can fail after normal commit with pending flag retained")
	before = original.state.duplicate(true); var recovered = reload(final_fail)
	check(recovered.reconcile(original) and recovered.receipt_committed and original.state == before,"Final journal failure recovery commits flag without duplicate award")
func test_backup_and_corruption():
	var normal = normal_model(); var session = isolated_session("trial-corruption")
	check(session.start("steps",normal),"Create trial corruption fixture")
	var first = session.engine.state.duplicate(true)
	check(session.engine.dispatch(traces.steps.actions[0]).ok and session.save(),"Create valid trial backup through legal action")
	write_text(session.save_path,"{corrupt-trial-main")
	var recovered = reload(session)
	check(recovered.engine.state == first,"Trial backup restores exact earlier resources/RNG")
	var backup = FileAccess.get_file_as_string(session.save_path.get_basename()+".backup.json")
	check(recovered.save() and FileAccess.get_file_as_string(session.save_path.get_basename()+".backup.json") == backup,"Trial backup preserved on first recovery save")
	write_text(session.save_path,"{bad-main"); write_text(session.save_path.get_basename()+".backup.json","{bad-backup")
	var locked = Session.new(); locked.save_path = session.save_path; locked.normal_save_path = session.normal_save_path
	check(not locked.load() and locked.writes_blocked and not locked.last_error.is_empty(),"Trial pair double corruption blocks with a clear error")
	check(not locked.start("steps",normal) and FileAccess.get_file_as_string(session.save_path) == "{bad-main" and FileAccess.get_file_as_string(session.save_path.get_basename()+".backup.json") == "{bad-backup","Double corruption cannot be overwritten by retry/start")
