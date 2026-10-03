extends SceneTree
const Main = preload("res://scenes/main.tscn")
var ui
var checks = 0
var failures: Array[String] = []

func _init(): call_deferred("run")

func settle(frames: int = 5):
	for i in range(frames): await process_frame

func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message); printerr("FAIL: "+message)

func click_named(name: String):
	var control = ui.find_child(name,true,false)
	if control == null: check(false,"Missing control "+name); return
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
	var copy = ""
	if control != null:
		for label in control.find_children("*","Label",true,false): copy += label.text+"\n"
	return copy

func capture(name: String):
	await settle(); await RenderingServer.frame_post_draw
	var version = str(ProjectSettings.get_setting("application/config/version")).replace("godot-","")
	root.get_texture().get_image().save_png("res://verification/cultivation-ui-"+version+"-"+name+".png")

func wait_effects():
	var limit = Time.get_ticks_msec()+12000
	while ui.busy and Time.get_ticks_msec() < limit: await process_frame
	check(not ui.busy,"Combat sequence completes")
	await settle()

func fresh(realm: int = 0):
	ui.guide_open = false; ui.guide_queue.clear(); ui.guide_replay = false
	ui.close_modal(true); ui.engine.state = ui.engine.create(47582)
	ui.engine.state.settings.guide.enabled = false; ui.engine.state.settings.reducedMotion = true
	ui.engine.state.profile.realm = realm; ui.engine.state.profile.coins = 100000
	ui.view = "cultivation"; ui.render(); await settle()

func run():
	root.size = Vector2i(390,844); ui = Main.instantiate(); root.add_child(ui); await settle(12)
	check(not ui.persistence,"Cultivation UI verification uses --no-save")
	await fresh()
	await click_named("PathChoices")
	check(text_of(ui.modal).contains("第3层") and text_of(ui.modal).contains("第6层") and text_of(ui.modal).contains("第9层"),"Path browse explains all three unlock boundaries")
	for id in ["sword","guard","spirit"]:
		check(ui.find_child("Path_"+id,true,false).disabled,"Below third layer disables "+id)
	await click_named("Path_sword")
	check(ui.engine.state.profile.cultivationPath == "none","Locked selection cannot change the profile")
	check(not ui.find_child("Path_none",true,false).disabled,"Cancel remains available without an active run")
	await capture("unlock-preview-390x844"); await click_named("ClosePaths")
	await fresh(2)
	check(ui.engine.cultivation_info().availableTier == 1 and ui.engine.cultivation_info().nextRealm == 5,"Third layer shows first tier and next unlock at sixth")
	var coins = ui.engine.state.profile.coins; var hp = ui.engine.state.profile.hp
	for id in ["sword","guard","spirit","none"]:
		await click_named("PathChoices")
		var revision = ui.engine.state.revision
		await click_named("Path_"+id)
		check(ui.modal == null and ui.engine.state.profile.cultivationPath == id,"Native selection and cancel apply "+id)
		check(ui.engine.state.profile.coins == coins and ui.engine.state.profile.hp == hp and ui.engine.state.revision == revision+1,"Selection is one free action: "+id)
	await click_named("PathChoices"); await click_named("Path_sword")
	await capture("selected-sword-390x844")
	for realm in [5,8]:
		ui.engine.state.profile.realm = realm; ui.render(); await settle()
		check(ui.engine.cultivation_info().selectedTier == (2 if realm == 5 else 3),"Higher realm updates preferred tier "+str(realm+1))
		check(ui.engine.cultivation_info().nextRealm == (8 if realm == 5 else -1),"Next tier is accurate at layer "+str(realm+1))
	ui.goto("deck"); await settle(); await click_named("DeckDepart")
	check(ui.engine.state.battle != null and ui.engine.state.battle.cultivation.redBonus == 3,"New battle pins ninth-layer sword snapshot")
	await click_named("PlayerPortrait")
	var details = text_of(ui.modal)
	check(details.contains("战斗效果来源") and details.contains("御剑3") and details.contains("术式"),"Player details state the exact snapshot source and spell exclusion")
	await capture("battle-sources-390x844"); ui.close_modal()
	ui.goto("cultivation"); await settle(); await click_named("PathChoices")
	for id in ["sword","guard","spirit","none"]:
		check(ui.find_child("Path_"+id,true,false).disabled,"Whole-run path lock covers "+id)
	await click_named("Path_guard")
	check(ui.engine.state.profile.cultivationPath == "sword","Locked browse does not switch the pinned path")
	await capture("locked-paths-390x844"); await click_named("ClosePaths")
	for rules in [2,3]:
		ui.engine.state.run.rulesVersion = rules; ui.engine.state.battle.rulesVersion = rules
		ui.goto("battle"); await settle(); await click_named("PlayerPortrait")
		details = text_of(ui.modal)
		check(details.contains("下一轮") and details.contains("御剑0") and not details.contains("御剑3"),"Old rules "+str(rules)+" show zero actual path effect and deferred preference")
		ui.close_modal(); ui.goto("cultivation"); await settle()
		check(text_of(ui.canvas).contains("御剑") and text_of(ui.canvas).contains("下一轮"),"Old active cultivation page separates selected preference from actual effects")
	await fresh(4)
	await click_named("PathChoices"); await click_named("Path_guard")
	ui.goto("deck"); await settle(); await click_named("DeckDepart")
	check(ui.engine.state.battle.cultivation.tier == 1 and ui.engine.state.battle.shield == 4,"Fifth layer guard starts with one-tier shield plus cloth")
	for wave in range(1,6):
		ui.engine.state.battle.enemy.hp = 1; ui.engine.state.battle.mana = 7; ui.render(); await settle()
		await click_named("Card0"); await click_named("ConfirmCast"); await wait_effects()
		if wave < 5: check(ui.engine.state.run.wave == wave+1 and ui.engine.state.battle.cultivation.tier == 1,"Same-turn handoff keeps cultivation snapshot")
	await click_named("SkipReward")
	check(ui.engine.state.battle == null and ui.engine.state.run.chapter == 1,"Boss reward enters between-chapter preparation")
	ui.goto("cultivation"); await settle(); await click_named("Cultivate")
	check(ui.engine.state.profile.realm == 5,"Original breakthrough remains allowed between chapters")
	check(text_of(ui.canvas).contains("下一关"),"Between-chapter page explains next-chapter activation")
	await click_named("PathChoices")
	check(ui.find_child("Path_guard",true,false).disabled,"Path remains locked after the between-chapter breakthrough")
	await click_named("ClosePaths"); ui.goto("map"); await settle(); await click_named("ContinueStage")
	check(ui.engine.state.battle.cultivation.tier == 2 and ui.engine.state.battle.shield == 6,"Next chapter uses improved guard tier plus cloth once")
	ui.goto("cultivation"); await settle()
	for dimensions in [Vector2i(320,568),Vector2i(360,640),Vector2i(390,700),Vector2i(390,844),Vector2i(430,932),Vector2i(1440,900),Vector2i(844,390),Vector2i(568,320)]:
		root.size = dimensions; await settle(10); ui.render(); await settle()
		var breakthrough = ui.find_child("Cultivate",true,false)
		check(breakthrough.size.y >= 44 and root.get_visible_rect().encloses(breakthrough.get_global_rect()),"Breakthrough keeps native hit area at "+str(dimensions))
		await click_named("PathChoices")
		var close = ui.find_child("ClosePaths",true,false)
		check(close.size.y >= 44 and root.get_visible_rect().encloses(close.get_global_rect()),"Path modal footer fits "+str(dimensions))
		if dimensions in [Vector2i(320,568),Vector2i(390,844),Vector2i(568,320)]: await capture("paths-%dx%d"%[dimensions.x,dimensions.y])
		await click_named("ClosePaths")
	var version = str(ProjectSettings.get_setting("application/config/version")).replace("godot-","")
	var file = FileAccess.open("res://verification/cultivation-ui-"+version+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"method":"Windows native mouse input, eight window sizes, --no-save"},"\t")); file.close()
	print("Cultivation UI checks: ",checks,"; failures: ",failures.size())
	ui.queue_free(); await settle(); quit(1 if not failures.is_empty() else 0)
