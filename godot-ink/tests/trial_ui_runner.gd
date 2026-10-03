extends SceneTree
const Main = preload("res://scenes/main.tscn")
var ui
var checks = 0
var failures: Array[String] = []
var replayed = 0

func _init(): call_deferred("run")
func settle(frames: int = 5):
	for i in range(frames): await process_frame
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); printerr("FAIL: "+message)
func click_named(name: String):
	var control = ui.find_child(name,true,false)
	if control == null: check(false,"Missing "+name); return
	var ancestor = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(control); await settle()
		ancestor = ancestor.get_parent()
	var at = control.get_global_rect().get_center()
	var motion = InputEventMouseMotion.new(); motion.position = at; Input.parse_input_event(motion); await process_frame
	for pressed in [true,false]:
		var event = InputEventMouseButton.new(); event.position = at; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		Input.parse_input_event(event); await process_frame
	await settle()
func text_of(control) -> String:
	var text = ""
	if control != null:
		for copy in control.find_children("*","Label",true,false): text += copy.text+"\n"
	return text
func version_label() -> String: return str(ProjectSettings.get_setting("application/config/version")).replace("godot-","")
func capture(name: String):
	await settle(); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://verification/trial-ui-"+version_label()+"-"+name+".png")
func wait_effects():
	var limit = Time.get_ticks_msec()+15000
	while ui.busy and Time.get_ticks_msec()<limit: await process_frame
	check(not ui.busy,"Trial presentation finishes")
	await settle()
func normal_core() -> Dictionary:
	var s = ui.normal_engine.state.duplicate(true); s.revision = 0
	s.profile.records.erase("trialStamps"); s.profile.records.erase("trialReceipts")
	return s
func native_action(action: Dictionary):
	if action.type == "swap":
		await click_named("Tile"+str(action.a)); await click_named("Tile"+str(action.b))
	elif action.type == "card":
		var slot = -1
		for i in range(3):
			if ui.engine.state.battle.hand[i].uid == action.uid: slot = i
		check(slot >= 0,"Trace card exists in fixed loadout")
		if slot < 0: return
		await click_named("Card"+str(slot)); await click_named("ConfirmCast")
	else: await click_named("EndTurn")
	await wait_effects()
func run():
	root.size = Vector2i(390,844); ui = Main.instantiate(); root.add_child(ui); await settle(12)
	check(not ui.persistence and not ui.trial_session.persistence and not ui.trial_session.has_session(),"No-save initialization reads no trial session")
	ui.normal_engine.state = ui.normal_engine.create(28347); ui.normal_engine.state.settings.guide.enabled = false
	ui.normal_engine.state.settings.reducedMotion = true; ui.view = "map"; ui.render(); await settle()
	await click_named("Trials")
	check(text_of(ui.modal).contains("普通四境通关"),"All trials explain the clear requirement")
	for id in ["sword","guard","spirit","break","chain","steps"]:
		await click_named("Trial_"+id)
		check(ui.find_child("StartTrial",true,false).disabled,"Trial start locked before clear: "+id)
		ui.close_modal(); ui.trials_modal(); await settle()
	await capture("locked-six-390x844"); ui.close_modal()
	ui.normal_engine.state.profile.records.clears = 1; ui.normal_engine.state.profile.coins = 777
	ui.normal_engine.state.profile.realm = 8; ui.normal_engine.state.profile.cultivationPath = "guard"
	var initial_normal = normal_core()
	ui.trials_modal(); await settle(); await click_named("Trial_steps")
	check(text_of(ui.modal).contains("固定种子") and text_of(ui.modal).contains("32"),"Trial detail shows exact loadout, seed and target")
	await capture("steps-detail-390x844"); await click_named("StartTrial")
	check(ui.trial_active and ui.engine != ui.normal_engine and ui.engine == ui.trial_session.engine,"Trial uses an independent model reference")
	check(ui.engine.state.profile.coins == 0 and ui.engine.state.profile.realm == 5 and ui.engine.state.profile.cultivationPath == "none","Trial ignores ordinary growth and preference")
	check(ui.find_child("BattleTool0",true,false).disabled,"Trial disables consumable bag")
	var board = ui.engine.state.battle.board.duplicate(true); var rng = ui.engine.state.rng
	var pair = ui.engine.possible_move(ui.engine.state.battle.board)
	await native_action({"type":"swap","a":pair[0],"b":pair[1]})
	await native_action({"type":"endTurn"})
	await click_named("Card0"); await click_named("ConfirmCast"); await wait_effects()
	check(normal_core() == initial_normal,"Physical trial swap/card/endTurn do not change normal progress")
	var paused = ui.engine.state.duplicate(true)
	await click_named("PauseTrial")
	check(not ui.trial_active and ui.engine == ui.normal_engine and ui.trial_session.engine.state == paused,"Pause saves and restores normal without abandoning trial")
	ui.trials_modal(); await settle(); await click_named("ResumeTrial")
	check(ui.trial_active and ui.engine.state == paused,"Resume retains exact trial resources and RNG")
	await click_named("PauseTrial"); ui.trials_modal(); await settle(); await click_named("Trial_steps"); await click_named("RetryTrial")
	check(ui.find_child("ReplaceTrial",true,false) != null,"Replacing unfinished trial explains reset in-game")
	await click_named("ReplaceTrial")
	check(ui.engine.state.battle.board == board and ui.engine.state.rng == rng,"Retry restores the same fixed initial board and RNG")
	var trace = ui.engine.normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/trial_replays/steps-630106.json")))
	for action in trace.actions:
		if ui.engine.state.battle == null:
			check(false,"Trace ended unexpectedly before all native actions"); break
		await native_action(action); replayed += 1
	check(replayed == trace.actions.size() and ui.engine.trial_result_info().qualified,"A full real native route reaches earned condition")
	check(ui.engine.state.run == null and ui.modal_required and ui.find_child("TrialRecap",true,false) != null,"Trial Boss directly enters result, without ordinary reward preparation")
	check(ui.trial_session.receipt_committed and ui.normal_engine.state.profile.records.trialStamps.steps.earned,"Result reconciles earned stamp in memory")
	check(normal_core() == initial_normal,"Only stamp ledger and best step records affect ordinary model")
	await capture("earned-result-390x844"); await click_named("TrialRecap")
	check(text_of(ui.modal).contains("实际伤害") and ui.modal_required,"Complete trial recap is readable through result flow")
	await capture("earned-recap-390x844"); await click_named("CloseRecap")
	var best = ui.normal_engine.state.profile.records.trialStamps.steps.bestMoves
	await click_named("TrialReturn")
	check(not ui.trial_active and ui.engine == ui.normal_engine,"Result returns safely to ordinary map")
	await click_named("Trials")
	check(ui.find_child("Trial_steps",true,false).text.contains("最佳%d步"%best),"Trial list displays earned stamp and best exchanges")
	await capture("stamp-list-390x844"); await click_named("Trial_steps"); await click_named("RetryTrial")
	check(ui.trial_active and ui.engine.state.battle.board == board,"Retry completed trial restores fixed seed through native UI")
	for dimensions in [Vector2i(320,568),Vector2i(360,640),Vector2i(390,700),Vector2i(390,844),Vector2i(430,932),Vector2i(1440,900),Vector2i(844,390),Vector2i(568,320)]:
		root.size = dimensions; await settle(10); ui.render(); await settle()
		var pause = ui.find_child("PauseTrial",true,false)
		check(pause.size.y >= 44 and root.get_visible_rect().encloses(pause.get_global_rect()),"Trial pause fits "+str(dimensions))
		if dimensions in [Vector2i(320,568),Vector2i(390,844),Vector2i(568,320)]: await capture("battle-%dx%d"%[dimensions.x,dimensions.y])
		await click_named("PauseTrial"); await click_named("Trials"); await click_named("Trial_steps")
		var retry = ui.find_child("RetryTrial",true,false)
		check(retry.size.y >= 44 and root.get_visible_rect().encloses(retry.get_global_rect()),"Trial detail footer fits "+str(dimensions))
		await click_named("ResumeTrial")
	await click_named("PauseTrial")
	ui.normal_engine.dispatch({"type":"newRun"}); ui.render(); await settle(); ui.trials_modal(); await settle()
	check(ui.find_child("ResumeTrial",true,false).disabled,"Ordinary active run locks trial resume")
	await click_named("Trial_sword")
	check(ui.find_child("StartTrial",true,false).disabled,"Ordinary active run locks another trial start")
	var file = FileAccess.open("res://verification/trial-ui-"+version_label()+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"nativeTraceActions":replayed,"earnedTrial":"steps","method":"Windows native mouse input, independent no-save TrialSession, eight window sizes; no fake winning state"},"\t")); file.close()
	print("Trial UI checks: ",checks,"; failures: ",failures.size(),"; real route actions: ",replayed)
	ui.queue_free(); await settle(); quit(1 if not failures.is_empty() else 0)
