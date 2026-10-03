extends SceneTree
## Content UI verification uses a separate --no-save process and native mouse input.
const Main = preload("res://scenes/main.tscn")
const Store = preload("res://scripts/progress_store.gd")
const Model = preload("res://scripts/ink_engine.gd")
var ui
var checks = 0
var failures: Array[String] = []

func _init(): call_deferred("run")

func settle(frames: int = 5):
	for i in range(frames): await process_frame

func check(ok: bool, description: String):
	checks += 1
	if not ok: failures.append(description); printerr("FAIL: "+description)

func click_named(name: String, post_frames: int = 5):
	var control = ui.find_child(name,true,false)
	if control == null: check(false,"Missing control "+name); return
	var parent = control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(control); await settle()
		parent = parent.get_parent()
	var at = control.get_global_rect().get_center()
	var motion = InputEventMouseMotion.new(); motion.position = at; Input.parse_input_event(motion); await process_frame
	for pressed in [true,false]:
		var event = InputEventMouseButton.new(); event.position = at; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		Input.parse_input_event(event); await process_frame
	await settle(post_frames)

func modal_text() -> String:
	var result = ""
	if ui.modal != null:
		for copy in ui.modal.find_children("*","Label",true,false): result += copy.text+"\n"
	return result

func wait_effects():
	var deadline = Time.get_ticks_msec()+12000
	while ui.busy and Time.get_ticks_msec() < deadline: await process_frame
	check(not ui.busy,"Combat effects finish without hanging")
	await settle()

func capture(name: String):
	await settle(); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://verification/content-ui-"+version_label()+"-"+name+".png")

func version_label() -> String:
	return str(ProjectSettings.get_setting("application/config/version")).replace("godot-","")

func fresh():
	ui.guide_open = false; ui.guide_checkpoint = ""; ui.guide_queue.clear(); ui.guide_replay = false; ui.guide_replay_seen.clear()
	ui.close_modal(true)
	ui.engine.state = ui.engine.create(98231); ui.engine.state.settings.guide.enabled = false
	ui.engine.state.settings.reducedMotion = true
	ui.selected_card = -1; ui.selected_tile = -1; ui.view = "deck"; ui.render()
	await settle()

func four_board():
	var b = ui.engine.state.battle; var types = ui.engine.d.types
	for i in range(36): b.board[i].type = types[(i/6+i%6)%5]
	for column in range(6): b.board[column].type = ["red","red","blue","red","yellow","purple"][column]
	b.board[8].type = "red"
	check(ui.engine.matches(b.board).is_empty(),"Tutorial fixture starts with no matched tiles")
	ui.render(); await settle()

func run():
	root.size = Vector2i(390,844); ui = Main.instantiate(); root.add_child(ui); await settle(12)
	check(not ui.persistence,"Content UI runner must use --no-save")
	await fresh()
	await click_named("DeckPresets")
	check(ui.modal != null and modal_text().contains("尚需收藏"),"Presets show explicit collection requirements")
	check(ui.find_child("Preset_sword",true,false).disabled,"Uncollected preset is disabled")
	var before = ui.engine.state.profile.deck.duplicate(); var revision = ui.engine.state.revision
	await click_named("Preset_sword")
	check(ui.engine.state.profile.deck == before and ui.engine.state.revision == revision,"Clicking unavailable preset does not change deck or submit")
	await capture("presets-390x844")
	ui.engine.state.profile.deck[0] = "step"
	await click_named("Preset_starter")
	check(ui.modal == null and ui.engine.state.profile.deck == ["sword","ward","heal"],"Starter preset equips all three slots through native click")
	check(ui.engine.state.revision == revision+1,"Preset application is one atomic action")
	for id in ui.engine.state.profile.collection: ui.engine.state.profile.collection[id] = 1
	await click_named("DeckPresets"); await click_named("Preset_sword")
	check(ui.engine.state.profile.deck == ["sword","comboOrder","step"],"Owned sword recommendation equips exactly approved cards")
	await click_named("DeckDepart"); await settle()
	check(ui.view == "battle" and ui.engine.rules_version() == Model.CURRENT_RULES,"Preset proceeds into the current rule set")
	await click_named("NextEnemyPreview")
	check(ui.modal != null and modal_text().contains("第2/5战"),"Progress hit area opens the next enemy preview")
	check(ui.find_child("NextEnemyPreview",true,false).size.y >= 44,"Progress preview hit area is at least 44px high")
	check(modal_text().contains("接战保留"),"Next preview explains real resource inheritance")
	await capture("next-preview-390x844"); await click_named("ClosePreview")
	ui.goto("deck"); await settle(); await click_named("DeckPresets")
	check(ui.find_child("Preset_starter",true,false).disabled and modal_text().contains("本轮三式已锁定"),"Presets expose whole-run lock")
	before = ui.engine.state.profile.deck.duplicate(); await click_named("Preset_starter")
	check(ui.engine.state.profile.deck == before,"Locked preset mouse click cannot alter the run")
	ui.close_modal(); ui.goto("battle"); await settle()
	await fresh(); await click_named("DeckDepart")
	if ui.engine.state.battle == null:
		printerr("New battle failed: view=",ui.view," feedback=",ui.feedback," modal=",modal_text()," deck=",ui.engine.state.profile.deck)
		check(false,"A fresh starter deck enters battle through native button")
		quit(1); return
	ui.engine.state.settings.guide.enabled = true
	await four_board()
	await click_named("Tile2"); await click_named("Tile8")
	check(ui.busy and ui.modal == null,"Tutorial waits until the real swap presentation finishes")
	revision = ui.engine.state.revision
	await click_named("ConfirmCast")
	check(ui.engine.state.revision == revision,"Busy combat cannot submit a second action")
	await wait_effects()
	check(ui.guide_open and ui.guide_checkpoint == "swap","First successful swap produces the short event-based tutorial")
	await capture("guide-390x844"); await click_named("GuideSkip")
	check(not ui.engine.state.settings.guide.enabled and ui.guide_queue.is_empty(),"Tutorial skip persists disabled state and clears pending tips")
	check(ui.engine.state.battle.links.swordReady,"Actual four-match readies the sword link")
	await click_named("PlayerPortrait")
	check(modal_text().contains("联动") and modal_text().contains("10"),"Player detail shows the pending sword link")
	await capture("link-status-390x844"); ui.close_modal()
	ui.engine.state.settings.reducedMotion = false; ui.render(); await settle()
	await click_named("Card0")
	var pre_hit = ui.find_child("EnemyHealth",true,false).value
	await click_named("ConfirmCast",0)
	check(ui.busy and ui.find_child("EnemyHealth",true,false).value == pre_hit,"Ready sword link keeps HP at pre-hit value during wind-up")
	await create_timer(0.18).timeout
	check(ui.find_child("EnemyHealth",true,false).value < pre_hit and ui.find_child("EnemyHealth",true,false).value > ui.engine.state.battle.enemy.hp,"Ready sword HP drains at impact before link feedback")
	await capture("sword-link-impact-390x844"); await wait_effects()
	ui.engine.state.settings.reducedMotion = true
	check(ui.engine.state.run.summary.links.sword == 1,"Actual sword cast consumes and records the link once")
	await click_named("BattleTool2"); await click_named("GuideReplay"); await click_named("GuideReplayStart")
	check(ui.guide_replay and not ui.engine.state.settings.guide.enabled,"Manual replay is session-only and does not reset saved preference")
	await click_named("EndTurn"); await wait_effects()
	check(ui.guide_open and ui.guide_checkpoint == "endTurn","Replay follows an actual end-turn event")
	await click_named("GuideSkip")
	check(not ui.guide_replay and not ui.engine.state.settings.guide.enabled,"Skipping manual replay preserves the saved disabled setting")
	ui.engine.state.settings.guide.enabled = true
	await click_named("EndTurn"); await wait_effects(); await click_named("GuideContinue")
	check("endTurn" in ui.engine.state.settings.guide.seen,"Acknowledging a tutorial persists its actual checkpoint")
	ui.engine.state.settings.guide.enabled = false; ui.guide_queue.clear()
	ui.perform({"type":"abandon"}); await settle()
	check(ui.modal_required and ui.find_child("ResultRecap",true,false) != null,"Result has compact summary and native recap action")
	await capture("result-390x844"); await click_named("ResultRecap")
	check(ui.modal_required and modal_text().contains("返"),"Detailed recap stays inside required result flow")
	await capture("recap-390x844"); await click_named("CloseRecap")
	check(ui.find_child("FinishResult",true,false) != null,"Recap returns to the result without clearing it")
	await click_named("FinishResult"); ui.goto("records"); await settle(); await click_named("RecentRecap")
	check(ui.modal != null and modal_text().contains("施法"),"Record page exposes the most recent summary")
	ui.close_modal()
	var summary = ui.engine.state.profile.records.lastSummary.duplicate(true)
	summary.coverage = "partial"; summary.startChapter = 1; summary.startWave = 3
	ui.recap_detail(summary,false); await settle()
	check(modal_text().contains("第2关") and modal_text().contains("第3"),"Partial old-run recap identifies tracking start")
	ui.close_modal(); ui.recap_detail({},false); await settle()
	check(modal_text().contains("没有详细") or modal_text().contains("无详细"),"Old empty recap does not fabricate zero statistics")
	ui.close_modal()
	await fresh(); await click_named("DeckDepart")
	ui.engine.state.run.rulesVersion = 2; ui.engine.state.battle.rulesVersion = 2
	ui.engine.state.battle.erase("links"); ui.render(); await settle(); await click_named("NextEnemyPreview")
	check(modal_text().contains("更新前"),"Old active run preview clearly retains old rules")
	ui.close_modal()
	for dimensions in [Vector2i(390,844),Vector2i(320,568),Vector2i(568,320)]:
		root.size = dimensions; await settle(10); ui.render(); await settle()
		var preview = ui.find_child("NextEnemyPreview",true,false)
		check(preview.size.y >= 44 and root.get_visible_rect().encloses(preview.get_global_rect()),"Preview hit area fits "+str(dimensions))
		await capture("battle-%dx%d"%[dimensions.x,dimensions.y])
		await click_named("NextEnemyPreview"); await capture("preview-%dx%d"%[dimensions.x,dimensions.y]); await click_named("ClosePreview")
	root.size = Vector2i(390,844); await settle(10)
	ui.save_blocked = true; ui.save_warning = "现有v2存档无法读取。"; Store.writes_blocked = true; Store.last_error = ui.save_warning
	ui.persistence = true
	check(not ui.save_progress(),"UI refuses automatic writes in corrupt-v2 recovery mode")
	ui.settings_modal(); await settle(); await click_named("StorageRecovery")
	check(modal_text().contains("临时试玩") and modal_text().contains("progress-v2"),"Blocked save UI gives readable recovery instructions")
	await capture("storage-warning-390x844")
	ui.persistence = false; Store.writes_blocked = false; Store.last_error = ""
	var file = FileAccess.open("res://verification/content-ui-"+version_label()+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"method":"Godot Windows native mouse input; --no-save, corrupt-store marker tested without opening real save files"},"\t")); file.close()
	print("Content UI checks: ",checks,"; failures: ",failures.size())
	ui.queue_free(); await settle(); quit(1 if not failures.is_empty() else 0)
