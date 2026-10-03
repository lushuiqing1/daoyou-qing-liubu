extends SceneTree
const Main = preload("res://scenes/main.tscn")
var ui
var failures: Array = []
var checks = 0
var geometry: Array = []

func _init(): call_deferred("run")

func settle(frames: int = 5):
	for i in range(frames): await process_frame

func check(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message); printerr("FAIL: "+message)

func click_named(name: String):
	var b = ui.find_child(name,true,false)
	if b == null: check(false,"Missing button "+name); return
	var ancestor = b.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(b); await settle()
		ancestor = ancestor.get_parent()
	await click_at(b.get_global_rect().get_center())

func click_at(at: Vector2):
	var motion = InputEventMouseMotion.new(); motion.position = at; Input.parse_input_event(motion)
	await process_frame
	for pressed in [true,false]:
		var e = InputEventMouseButton.new(); e.position = at; e.button_index = MOUSE_BUTTON_LEFT; e.pressed = pressed
		Input.parse_input_event(e); await process_frame
	await settle()

func key(code: int):
	var e = InputEventKey.new(); e.keycode = code; e.pressed = true; Input.parse_input_event(e); await settle()
	e = InputEventKey.new(); e.keycode = code; e.pressed = false; Input.parse_input_event(e)

func capture(name: String):
	await settle(); await RenderingServer.frame_post_draw
	var prefix = str(ProjectSettings.get_setting("application/config/version")).replace("godot-", "content-")+"-"
	root.get_texture().get_image().save_png("res://verification/"+prefix+name+".png")

func wait_effects():
	var deadline = Time.get_ticks_msec()+10000
	while ui.busy and Time.get_ticks_msec()<deadline: await process_frame
	assert(not ui.busy,"Combat presentation must finish within ten seconds")
	for i in range(5): await process_frame

func run():
	root.size = Vector2i(390,844); ui = Main.instantiate(); root.add_child(ui); await settle(12)
	check(not ui.persistence,"Tests must disable saves")
	ui.engine.state = ui.engine.create(98765); ui.engine.state.settings.guide.enabled = false; ui.render(); await settle()
	await capture("home-390x844")
	await click_named("Nav0"); check(ui.view == "map","Stage nav")
	await capture("entry-390x844")
	await click_named("Nav1"); check(ui.view == "deck","Deck nav")
	await click_named("Skill_step"); check(ui.modal != null,"Skill detail opens")
	await click_named("EquipSkill"); check(ui.engine.state.profile.deck[0] == "step","Equip replacement via real mouse")
	check(ui.modal == null,"Equip closes detail")
	await settle(); var focus = root.gui_get_focus_owner()
	check(focus != null and focus.name == "Skill_step","Equip returns skill focus")
	await click_named("Unload0"); check(ui.engine.state.profile.deck[0] == null,"Unload slot")
	await click_named("DeckDepart"); check(ui.engine.state.run == null,"Incomplete deck cannot depart")
	await click_named("Skill_sword"); await click_named("EquipSkill")
	await click_named("Skill_thunder"); check(ui.find_child("EquipSkill",true,false).disabled,"Locked skill cannot equip")
	await key(KEY_ESCAPE); check(ui.modal == null,"Esc closes detail")
	await capture("deck-390x844")
	await click_named("DeckDepart"); check(ui.engine.state.run != null,"Full deck starts expedition")
	check(ui.view == "battle" and ui.engine.state.battle != null and ui.engine.state.run.wave == 1,"Depart immediately starts first of five enemies")
	check(ui.find_child("Node_f1",true,false) == null,"No route node buttons remain")
	var initial_deck = ui.engine.state.run.deck.duplicate()
	await click_named("PlayerPortrait"); check(ui.modal != null,"Player status opens")
	await key(KEY_ESCAPE); check(root.gui_get_focus_owner().name == "PlayerPortrait","Player focus restored")
	var health_plate = ui.find_child("PlayerPortrait",true,false).get_global_rect()
	await click_at(Vector2(health_plate.get_center().x,health_plate.end.y-10))
	check(ui.modal != null,"Health plate passes mouse clicks to player details")
	await key(KEY_ESCAPE)
	await click_named("EnemyPortrait"); check(ui.modal != null,"Enemy status opens")
	await capture("enemy-detail-390x844"); await key(KEY_ESCAPE)
	var pair = ui.engine.possible_move(ui.engine.state.battle.board); var moves = ui.engine.state.run.moves
	await click_named("Tile"+str(pair[0])); await click_named("Tile"+str(pair[1])); await wait_effects()
	check(not ui.busy and ui.engine.state.run.moves == moves+1,"Two native tile clicks resolve swap")
	check(ui.engine.matches(ui.engine.state.battle.board).is_empty(),"Resolved board has no matches")
	# Temporary durable enemy fixture isolates repeated-cast controls from victory.
	ui.engine.state.battle.enemy.hp = 500; ui.engine.state.battle.enemy.maxHp = 500
	ui.engine.state.battle.mana = 7; ui.render(); await settle()
	await click_named("Card0"); var uid = ui.selected_card; var hp = ui.engine.state.battle.enemy.hp
	var expected_sword_damage = ui.engine.card_value("sword")
	await click_named("ConfirmCast"); await wait_effects()
	check(ui.engine.state.battle.enemy.hp == hp-expected_sword_damage,"Sword damage through actual confirmation")
	check(ui.find_child("EnemyHealth",true,false).value == ui.engine.state.battle.enemy.hp and ui.find_child("EnemyHealth",true,false).max_value == ui.engine.state.battle.enemy.maxHp,"Health bar updates after real cast")
	check(ui.selected_card == uid,"Cast preserves selection")
	await click_named("ConfirmCast"); await wait_effects()
	check(ui.engine.state.battle.mana == 1,"Repeat cast charges mana twice")
	check(ui.find_child("ConfirmCast",true,false).disabled,"Insufficient mana disables confirmation")
	var round_no = ui.engine.state.battle.round
	await click_named("EndTurn"); await wait_effects()
	check(ui.engine.state.battle.round == round_no+1,"End turn acts and refreshes")
	check(str(ui.engine.state.battle.enemy.nextDamage) in ui.find_child("EnemyIntent",true,false).text,"Enemy charge telegraph updates after end turn")
	# Supply mana for an isolated shield-display check after the insufficient-mana case.
	ui.engine.state.battle.mana = 7; ui.render(); await settle()
	await click_named("Card1"); await click_named("ConfirmCast"); await wait_effects()
	check(ui.engine.state.battle.shield >= 30,"Shield spell applies through native confirmation")
	check(ui.find_child("PlayerShield",true,false).text == str(ui.engine.state.battle.shield),"Blue shield value updates after real cast")
	check(ui.find_child("PlayerAttack",true,false).text == str(ui.engine.stats().attack),"Sword shows current player attack")
	var before_heal = ui.engine.state.profile.hp
	await click_named("Card2"); await click_named("ConfirmCast"); await wait_effects()
	check(ui.engine.state.profile.hp > before_heal,"Healing spell applies through native confirmation")
	check(ui.find_child("PlayerHealth",true,false).value == ui.engine.state.profile.hp and not ui.find_child("PlayerHealth",true,false).show_percentage,"Healing updates the nonnumeric player health bar")

	await click_named("BattleTool0"); check(ui.modal != null,"Battle bag opens"); await key(KEY_ESCAPE)
	await click_named("BattleTool1"); await click_named("BattleTool2"); check(ui.modal != null,"Rules open"); await key(KEY_ESCAPE)
	await click_named("BattleTool3"); check(ui.view == "map","Pause returns stage list")
	await capture("stages-390x844")
	await click_named("Stage0"); check(ui.modal != null,"Five-enemy stage settings open")
	await capture("stage-five-enemies-390x844"); await key(KEY_ESCAPE)
	await click_named("RunDetail"); check(ui.modal != null,"Run treasure and skill details retained")
	await key(KEY_ESCAPE)
	await click_named("Nav1"); await click_named("Skill_step")
	check(ui.find_child("EquipSkill",true,false).disabled,"Full expedition locks skills even when paused")
	await key(KEY_ESCAPE); check(ui.engine.state.run.deck == initial_deck,"Paused deck remains same")
	ui.goto("battle"); await settle()
	# Screenshots and bounds across desktop, narrow portrait and short landscape.
	# Capture actual default tuning, separately from the durable spell fixture.
	ui.engine.state = ui.engine.create(345); ui.engine.state.settings.guide.enabled = false; ui.engine.dispatch({"type":"newRun"})
	ui.selected_card = -1; ui.render(); await settle()
	var battle_snapshot = ui.engine.state.duplicate(true)
	for size in [Vector2i(320,568),Vector2i(360,640),Vector2i(390,700),Vector2i(390,844),Vector2i(430,932),Vector2i(1440,900),Vector2i(844,390),Vector2i(568,320)]:
		root.size = size; await settle(10)
		ui.engine.state = battle_snapshot.duplicate(true); ui.view = "battle"; ui.render(); await settle()
		var rect = ui.board_rect; var end = ui.find_child("EndTurn",true,false).get_global_rect()
		check(absf(rect.size.x-rect.size.y)<0.01,"Square board "+str(size))
		check(end.size.y>=44 and end.end.y<=size.y,"Action remains visible "+str(size))
		check(rect.end.y<=ui.h and rect.end.x<=ui.w,"Board inside frame "+str(size))
		geometry.append({"size":[size.x,size.y],"board":[rect.position.x,rect.position.y,rect.size.x],"end_turn":[end.position.x,end.position.y,end.size.x,end.size.y]})
		await capture("battle-%dx%d"%[size.x,size.y])
		for page in ["home","map","deck","bag","shop","cultivation","tasks","records"]:
			ui.view = page; ui.render(); await settle()
			var nav = ui.find_child("Nav0",true,false).get_global_rect()
			check(nav.end.y<=size.y and nav.size.y==ui.nav_height(),page+" uniform dock "+str(size))
			if size == Vector2i(390,844) or size == Vector2i(320,568) or size == Vector2i(568,320): await capture(page+"-%dx%d"%[size.x,size.y])
	# Native inventory/shop/cultivation/task interaction.
	root.size = Vector2i(390,844); await settle()
	ui.engine.state = ui.engine.create(2); ui.engine.state.settings.guide.enabled = false; ui.view = "bag"; ui.render(); await settle()
	await click_named("Item_jade"); await click_named("ItemPrimary"); check(ui.engine.state.profile.equipment.accessory == "jade","Native equip item")
	await key(KEY_ESCAPE); await click_named("Item_golden_gourd"); await click_named("ItemPrimary")
	check(ui.engine.state.profile.coins == 60,"Native consumable updates coins"); await key(KEY_ESCAPE)
	ui.goto("shop"); await settle(); await click_named("Buy_spring_pill"); check(ui.engine.state.profile.coins == 42,"Native shop purchase")
	ui.goto("cultivation"); await settle(); await click_named("Cultivate"); check(ui.engine.state.profile.realm == 1,"Native breakthrough")
	ui.goto("tasks"); await settle(); await click_named("Claim_cultivate"); check(ui.engine.state.profile.tasks.cultivate == 2,"Native claim task")
	ui.goto("records"); await settle(); await click_named("Nav4"); check(ui.modal != null,"More menu"); await capture("more-390x844"); await key(KEY_ESCAPE)
	await click_named("Nav4"); await click_named("More_shop")
	check(ui.view == "shop" and ui.modal == null,"More merchant entry navigates and closes the menu")
	await click_named("Settings"); check(ui.modal != null,"Settings entry opens")
	await capture("settings-390x844")
	var old_motion = ui.engine.state.settings.reducedMotion
	await click_named("ReducedMotion")
	check(ui.engine.state.settings.reducedMotion != old_motion,"Reduced-motion switch updates real settings")
	var old_sound = ui.engine.state.settings.sound
	await click_named("SoundToggle")
	check(ui.engine.state.settings.sound != old_sound,"Native sound switch updates existing saved setting")
	await click_named("SoundToggle")
	check(ui.engine.state.settings.sound == old_sound,"Native sound switch restores sound")
	await click_named("ResetNative"); check(ui.modal != null,"Reset requires its confirmation dialog")
	await capture("reset-confirmation-390x844"); await key(KEY_ESCAPE)
	check(ui.engine.state.profile.coins > 0,"Cancel reset preserves current profile")
	# First victory immediately continues through the real cast button.
	ui.engine.state = battle_snapshot.duplicate(true); ui.engine.state.battle.enemy.hp = 1; ui.engine.state.battle.mana = 7
	var retained_board = ui.engine.state.battle.board.duplicate(true)
	ui.view = "battle"; ui.render(); await settle(); await click_named("Card0"); var retained_uid = ui.selected_card
	await click_named("ConfirmCast"); await wait_effects()
	check(ui.engine.state.run.wave == 2 and ui.engine.state.battle != null,"Next monster automatically appears")
	check(ui.modal == null and not ui.modal_required,"Ordinary victory has no reward interruption")
	check(ui.selected_card == retained_uid and ui.engine.state.battle.board == retained_board,"Selected skill and board survive next monster")
	await capture("continuous-second-390x844")
	# Set up the actual fifth enemy, then defeat it through the real cast button.
	ui.engine.state = battle_snapshot.duplicate(true)
	for wave in range(4):
		ui.engine.state.battle.enemy.hp = 1; ui.engine.state.battle.mana = 7
		ui.engine.dispatch({"type":"card","uid":ui.engine.state.battle.hand[0].uid})
	ui.view = "battle"; ui.selected_card = -1; ui.render(); await settle()
	check(ui.engine.state.run.wave == 5 and ui.engine.state.battle.enemy.type == "boss","Fifth enemy is Boss")
	await capture("battle-boss-390x844")
	ui.engine.state.battle.enemy.hp = 1; ui.engine.state.battle.mana = 7
	ui.view = "battle"; ui.render(); await settle(); await click_named("Card0"); await click_named("ConfirmCast"); await wait_effects()
	check(ui.modal_required,"Win opens mandatory reward")
	await key(KEY_ESCAPE); check(ui.modal != null,"Mandatory reward ignores Esc")
	await capture("reward-390x844"); await click_named("SkipReward")
	check(ui.modal == null and ui.engine.state.run.pendingReward == null,"Reward settles and closes")
	check(ui.engine.state.run.deck == initial_deck,"Reward never inserts a card into current deck")
	check(ui.engine.state.run.chapter == 1 and ui.engine.state.battle == null,"Boss reward allows interchapter preparation")
	check(ui.view == "map" and ui.find_child("ContinueStage",true,false) != null,"Next chapter uses stage button")
	await capture("stage-preparation-390x844")
	ui.goto("cultivation"); await settle(); await click_named("Cultivate")
	check(ui.engine.state.profile.realm == 1,"Can cultivate between chapters")
	ui.goto("shop"); await settle(); await click_named("Buy_qingming")
	check(ui.engine.has(ui.engine.state,"qingming"),"Merchant treasure can be purchased through the scrolling catalog between chapters")
	await capture("shop-owned-390x844")
	ui.goto("map"); await settle(); await click_named("ContinueStage")
	check(ui.view == "battle" and ui.engine.state.run.chapter == 1 and ui.engine.state.run.wave == 1,"Next chapter starts first enemy")
	var file = FileAccess.open("res://verification/ui.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"geometry":geometry,"method":"Godot native window with injected mouse/key events; no physical phone tested"},"\t")); file.close()
	print("Native UI checks: ",checks,"; failures: ",failures.size())
	ui.queue_free(); await settle(); quit(1 if failures.size() else 0)
