extends SceneTree
const Main = preload("res://scenes/main.tscn")
var ui
var failures: Array = []
var checks = 0
var samples: Array = []
var recording = false
var frames = 0
var audio_observed = false

func _init(): call_deferred("run")
func settle(count: int = 5):
	for i in range(count): await process_frame
func check(value: bool, message: String):
	checks += 1
	if not value: failures.append(message); printerr("FAIL: "+message)
func click(name: String):
	var control = ui.find_child(name,true,false); check(control != null,"Native control exists: "+name)
	if control == null: return
	var at = control.get_global_rect().get_center()
	var motion = InputEventMouseMotion.new(); motion.position = at; Input.parse_input_event(motion); await process_frame
	for down in [true,false]:
		var input = InputEventMouseButton.new(); input.position = at; input.button_index = MOUSE_BUTTON_LEFT; input.pressed = down
		Input.parse_input_event(input); await process_frame
func snapshot(name: String):
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://verification/"+str(ProjectSettings.get_setting("application/config/version")).replace("godot-", "content-")+"-feedback-"+name+".png")
func capture_movie():
	while recording:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://verification/combat-frames/%04d.png"%frames); frames += 1
func wait_until_idle():
	var deadline = Time.get_ticks_msec()+10000
	while ui.busy and Time.get_ticks_msec()<deadline:
		audio_observed = audio_observed or ui.find_child("CombatAudio",true,false) != null
		await process_frame
	check(not ui.busy,"Presentation finishes and releases input")
	await settle()
func wait_for_wave(number: int):
	var deadline = Time.get_ticks_msec()+4000
	while ui.busy and ui.presentation_state.run.wave < number and Time.get_ticks_msec()<deadline: await process_frame
	await create_timer(0.10).timeout
func fixture(wave_number: int = 1):
	ui.engine.state = ui.engine.create(9921); ui.engine.state.settings.guide.enabled = false; ui.engine.dispatch({"type":"newRun"})
	for i in range(wave_number-1):
		ui.engine.state.battle.enemy.hp = 1; ui.engine.state.battle.mana = 7
		ui.engine.dispatch({"type":"card","uid":ui.engine.state.battle.hand[0].uid})
	ui.presentation_state = {}; ui.selected_card = -1; ui.view = "battle"; ui.render()
	await settle()
func run():
	root.size = Vector2i(390,844); ui = Main.instantiate(); root.add_child(ui); await settle(10)
	check(not ui.persistence,"Animation fixtures do not write player progress")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://verification/combat-frames"))
	await fixture(); recording = true; capture_movie()
	await settle(12); await click("Card0"); await settle(4)
	var before = ui.engine.state.battle.enemy.hp
	await click("ConfirmCast")
	check(ui.busy,"Real cast locks combat input during animation")
	var committed = ui.engine.state.duplicate(true)
	check(not ui.perform({"type":"endTurn"}) and ui.engine.state == committed,"Extra action cannot spend resources while animation runs")
	check(ui.find_child("EnemyHealth",true,false).value == before,"Health stays at pre-hit value during wind-up")
	await create_timer(0.18).timeout
	var bar = ui.find_child("EnemyHealth",true,false)
	check(bar.value < before and bar.value > ui.engine.state.battle.enemy.hp,"Health visibly drains at impact before final render")
	check(ui.find_child("DamagePopup",true,false) != null,"Damage popup is visible at impact")
	check(ui.find_child("CombatStrike",true,false) != null,"Layered sword stroke exists at impact")
	check(ui.find_child("EnemyArt",true,false).self_modulate != Color.WHITE,"Target flashes at impact")
	await snapshot("sword-impact"); await wait_until_idle()
	check(ui.find_child("EnemyHealth",true,false).value == ui.engine.state.battle.enemy.hp,"Displayed health finishes at committed damage")
	await settle(10)
	ui.engine.state.battle.enemy.hp = 1; ui.engine.state.battle.mana = 7; ui.render(); await settle()
	var kept_board = ui.engine.state.battle.board.duplicate(true)
	await click("Card0"); await settle(2); await click("ConfirmCast")
	await create_timer(0.61).timeout
	check(ui.busy and ui.presentation_state.run.wave == 1 and ui.presentation_state.battle.enemy.hp == 0,"Defeated first foe remains visible before incoming foe")
	check(ui.find_child("EnemyArt",true,false).modulate.a < 1,"Defeated monster visibly fades out")
	await snapshot("monster-defeat")
	await wait_for_wave(2)
	check(ui.presentation_state.run.wave == 2,"Incoming event displays the second foe snapshot")
	check(ui.find_child("EnemyHealth",true,false).value == ui.presentation_state.battle.enemy.maxHp,"New foe enters with its own full health")
	check(ui.find_child("BattleBanner",true,false) != null,"Next-wave announcement remains visible")
	await snapshot("monster-entry"); await wait_until_idle()
	check(ui.engine.state.battle.board == kept_board and ui.selected_card >= 0,"Wave animation preserves board and selected spell")
	await fixture(4); ui.engine.state.battle.enemy.hp = 1; ui.engine.state.battle.mana = 7; ui.render(); await settle()
	await click("Card0"); await settle(2); await click("ConfirmCast"); await wait_for_wave(5)
	check(ui.presentation_state.run.wave == 5 and ui.presentation_state.battle.enemy.type == "boss","Fifth entry uses the actual Boss snapshot")
	check(ui.find_child("EnemyArt",true,false).texture == ui.tex(ui.engine.enemy_art(ui.presentation_state)),"Boss art changes at incoming event")
	await snapshot("boss-entry"); await wait_until_idle(); await settle(15)
	recording = false; await settle(2)
	# Shield absorb and reduced-motion cues remain clear, without recoil or flights.
	await fixture(); ui.engine.state.battle.enemy.shield = 100; ui.engine.state.battle.mana = 7; ui.render(); await settle()
	await click("Card0"); await settle(2); await click("ConfirmCast"); await create_timer(0.18).timeout
	check(ui.engine.state.battle.enemy.hp == 99 and ui.find_child("EnemyShield",true,false).text == "64","Fully absorbed strike changes shield, not health")
	check(ui.find_child("CombatPopup",true,false) != null,"Full block has visible text feedback")
	await snapshot("shield-block"); await wait_until_idle()
	ui.engine.state.battle.enemy.intentKind = "heavy"; ui.engine.state.battle.enemy.intent = 31
	ui.engine.state.battle.shield = 8; ui.render(); await settle()
	var hp_before = ui.engine.state.profile.hp
	await click("EndTurn"); await create_timer(0.18).timeout
	check(ui.engine.state.profile.hp < hp_before and ui.find_child("DamagePopup",true,false) != null,"Enemy heavy hit gives player damage feedback")
	await snapshot("enemy-hit"); await wait_until_idle()
	ui.engine.state.battle.mana = 7; ui.render(); await settle(); await click("Card2"); await settle(2); await click("ConfirmCast")
	await create_timer(0.13).timeout
	check(ui.find_child("CombatPulse",true,false) != null and ui.find_child("PlayerHealth",true,false).value > hp_before-30,"Heal has pulse and rising health")
	await snapshot("heal"); await wait_until_idle()
	check(audio_observed,"Enabled sound produces native audio playback")
	await fixture(); ui.engine.state.settings.reducedMotion = true; ui.engine.state.settings.sound = false; ui.render(); await settle()
	await click("Card0"); await settle(2); await click("ConfirmCast"); await create_timer(0.08).timeout
	check(ui.find_child("EnemyArt",true,false).position == Vector2.ZERO and ui.find_child("PlayerArt",true,false).position == Vector2.ZERO,"Reduced motion disables both recoil and attacker lunge")
	check(ui.find_child("CombatStrike",true,false).still,"Reduced motion replaces moving stroke with static hit mark")
	check(ui.find_child("EnemyHealth",true,false).value == ui.engine.state.battle.enemy.hp,"Reduced motion still updates hit health immediately")
	check(ui.find_child("CombatAudio",true,false) == null,"Sound off suppresses audio players")
	await snapshot("reduced-motion"); await wait_until_idle()
	# One swap can kill several foes. Every wave event must retain its own state.
	await fixture()
	var found_sequence = false
	for seed_value in range(1,180):
		var model = ui.engine.get_script().new(seed_value); model.dispatch({"type":"newRun"})
		# Large legacy attack fixture forces a red cascade to advance several foes.
		model.state.profile.legacy.attack = 200; model.state.battle.enemy.hp = 1
		model.state.settings.reducedMotion = true; model.state.settings.sound = false
		model.state.settings.guide.enabled = false
		var pair = model.possible_move(model.state.battle.board)
		var initial = model.state.duplicate(true)
		var result = model.dispatch({"type":"swap","a":pair[0],"b":pair[1]})
		var wave_events = result.events.filter(func(event): return event.type == "wave")
		if wave_events.size() < 2: continue
		found_sequence = true
		for i in range(wave_events.size()):
			check(wave_events[i].state.run.wave == wave_events[i].wave,"Cascade wave snapshot matches its event")
			check(wave_events[i].state.battle.enemy.hp == wave_events[i].state.battle.enemy.maxHp,"Each cascade arrival snapshot has fresh health")
		check(wave_events[0].state != model.state,"Earlier arrival is preserved independently of final state")
		ui.engine.state = initial; ui.view = "battle"; ui.render(); await settle()
		ui.perform({"type":"swap","a":pair[0],"b":pair[1]})
		var seen: Array = []; var deadline = Time.get_ticks_msec()+10000
		while ui.busy and Time.get_ticks_msec()<deadline:
			var displayed = ui.presentation_state.run.wave
			if displayed > 1 and displayed not in seen:
				seen.append(displayed)
				check(ui.presentation_state.battle.enemy.hp == ui.presentation_state.battle.enemy.maxHp,"Live cascade enters each foe before next damage")
			await process_frame
		check(seen.size() == wave_events.size() and not ui.busy,"Every cascade foe is presented in order without skipping")
		break
	check(found_sequence,"Multi-foe cascade scenario exercised")
	# Resizing during impact must retain the presentation and unlock afterward.
	await fixture(); ui.engine.state.battle.mana = 7; ui.render(); await settle()
	await click("Card0"); await settle(2); await click("ConfirmCast")
	await create_timer(0.17).timeout; root.size = Vector2i(320,568); await settle(3)
	check(ui.busy and ui.find_child("EnemyHealth",true,false) != null,"Resizing at impact rebuilds the native combat controls")
	await wait_until_idle()
	check(ui.find_child("EnemyHealth",true,false).value == ui.engine.state.battle.enemy.hp,"Resize finishes with the correct health")
	await click("Card1"); await settle(2); await click("ConfirmCast"); await create_timer(0.12).timeout
	var popup = ui.find_child("CombatPopup",true,false)
	check(popup != null and popup.get_rect().position.x >= 0 and popup.get_rect().end.x <= ui.w,"Feedback remains within the narrow viewport")
	await snapshot("shield-320x568"); await wait_until_idle()
	var report = FileAccess.open("res://verification/feedback.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"version":ProjectSettings.get_setting("application/config/version"),"checks":checks,"failures":failures,"captured_frames":frames,"capture_fps":30,"native_viewport":true,"physical_phone_tested":false},"\t"))
	print("Combat feedback: %d checks; failures: %d; recorded frames: %d"%[checks,failures.size(),frames])
	ui.queue_free(); await settle(); quit(0 if failures.is_empty() else 1)
