extends SceneTree
var ui
func _init(): call_deferred("run")
func settle():
	for i in range(8): await process_frame
func click(name: String):
	var button = ui.find_child(name,true,false)
	assert(button != null)
	var at = button.get_global_rect().get_center()
	var motion = InputEventMouseMotion.new(); motion.position = at; Input.parse_input_event(motion); await process_frame
	for pressed in [true,false]:
		var e = InputEventMouseButton.new(); e.position = at; e.button_index = MOUSE_BUTTON_LEFT; e.pressed = pressed
		Input.parse_input_event(e); await process_frame
	await settle()
func wait_effects():
	var deadline = Time.get_ticks_msec()+10000
	while ui.busy and Time.get_ticks_msec()<deadline: await process_frame
	assert(not ui.busy,"Combat presentation must finish within ten seconds")
	for i in range(5): await process_frame

func run():
	root.size = Vector2i(390,844)
	ui = load("res://scenes/main.tscn").instantiate(); root.add_child(ui); await settle()
	assert(not ui.persistence)
	ui.engine.state.settings.guide.enabled = false
	assert(ui.engine.state.profile.coins == 0)
	await click("Nav0"); await click("Depart")
	assert(ui.engine.state.battle != null and ui.tile_buttons.size() == 36 and ui.engine.state.run.wave == 1)
	for kind in ["heart","sword","shield"]:
		assert(ui.tex("assets/ui/status-"+kind+".svg") != null)
	for cue in ["swing","impact","defeat","entry","heal","guard"]:
		assert(load("res://assets/audio/"+cue+".wav") is AudioStreamWAV)
	for family in ["cinnabar","paper","jade","selected"]:
		for state in ["normal","hover","pressed"]:
			assert(ui.tex("assets/ui/buttons/"+family+"-"+state+".svg") != null)
	for art in ["disabled","focus","nav-active","nav-hover","nav-pressed","nav-mark","toggle-on","toggle-off"]:
		assert(ui.tex("assets/ui/buttons/"+art+".svg") != null)
	await RenderingServer.frame_post_draw
	var screenshot_path = OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--screenshot")+1]
	assert(root.get_texture().get_image().save_png(screenshot_path) == OK)
	ui.engine.state.battle.enemy.hp = 1; ui.engine.state.battle.mana = 7; ui.render(); await settle()
	await click("Card0"); await click("ConfirmCast"); await wait_effects()
	assert(ui.engine.state.run.wave == 2 and ui.engine.state.battle != null and ui.modal == null)
	for wave in range(3):
		ui.engine.state.battle.enemy.hp = 1; ui.engine.state.battle.mana = 7
		assert(ui.engine.dispatch({"type":"card","uid":ui.engine.state.battle.hand[0].uid}).ok)
	ui.render(); await settle()
	assert(ui.engine.state.run.wave == 5 and ui.engine.state.battle.enemy.type == "boss")
	assert(ui.engine.state.battle.enemy.maxHp == 231 and ui.engine.state.battle.enemy.damage == 22)
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(screenshot_path.get_basename()+"-boss.png") == OK)
	ui.engine.state.battle.enemy.hp = 1; ui.engine.state.battle.mana = 7; ui.render(); await settle()
	await click("Card0"); await click("ConfirmCast"); await wait_effects()
	assert(ui.modal_required and ui.engine.state.run.pendingReward.chapterComplete)
	await click("SkipReward")
	assert(ui.engine.state.run.chapter == 1 and ui.engine.state.battle == null)
	for page in ["home","map","deck","bag","cultivation","shop","tasks","records"]:
		ui.goto(page); await settle()
		assert(ui.view == page and ui.find_child("Nav0",true,false) != null)
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(screenshot_path.get_basename()+"-"+page+".png") == OK)
	var args = OS.get_cmdline_user_args()
	if "--report" in args:
		var report = FileAccess.open(args[args.find("--report")+1],FileAccess.WRITE)
		report.store_string(JSON.stringify({"version":ProjectSettings.get_setting("application/config/version"),"fresh_start":true,"five_wave_entry":true,"automatic_next_enemy":true,"fifth_enemy_boss":true,"boss_tuning":true,"chapter_reward":true,"between_chapter_preparation":true,"tiles":36,"status_icon_resources":true,"all_eight_menu_pages":true,"six_sound_resources":true,"user_progress_untouched":true},"\t")); report.close()
	print("Portable PCK runtime: five waves / automatic next enemy / fifth Boss / chapter reward / preparation passed")
	ui.queue_free(); await settle(); quit()
