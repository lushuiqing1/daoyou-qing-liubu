extends SceneTree
var ui
func _init(): call_deferred("run")
func frame():
	for i in range(6): await process_frame
func press(at: Vector2, down: bool):
	var motion = InputEventMouseMotion.new(); motion.position = at; motion.global_position = at; Input.parse_input_event(motion)
	await process_frame
	var e = InputEventMouseButton.new(); e.position = at; e.global_position = at; e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down; Input.parse_input_event(e)
	await process_frame
func wait_effects():
	var deadline = Time.get_ticks_msec()+10000
	while ui.busy and Time.get_ticks_msec()<deadline: await process_frame
	assert(not ui.busy,"Combat presentation must finish within ten seconds")
	for i in range(5): await process_frame

func run():
	root.size = Vector2i(390,844); ui = load("res://scenes/main.tscn").instantiate(); root.add_child(ui); await frame()
	ui.engine.state = ui.engine.create(111)
	ui.engine.state.settings.guide.enabled = false
	ui.engine.dispatch({"type":"newRun"}); ui.view = "battle"; ui.render(); await frame()
	var pair = ui.engine.possible_move(ui.engine.state.battle.board)
	var at = ui.tile_buttons[pair[0]].get_global_rect().get_center(); var to = ui.tile_buttons[pair[1]].get_global_rect().get_center()
	await press(at,true)
	var move = InputEventMouseMotion.new(); move.position = to; move.global_position = to; move.relative = to-at; move.button_mask = MOUSE_BUTTON_MASK_LEFT; Input.parse_input_event(move)
	await process_frame; await press(to,false); await wait_effects()
	assert(ui.engine.state.run.moves == 1 and not ui.busy)
	at = ui.tile_buttons[0].get_global_rect().get_center(); await press(at,true); await press(at,false); await frame()
	assert(ui.selected_tile == 0)
	ui.engine.state.battle.mana = 7; ui.render(); await frame()
	var uid = ui.engine.state.battle.hand[0].uid; ui.select_card(uid)
	assert(ui.perform({"type":"card","uid":uid}))
	var spent = ui.engine.state.battle.mana; assert(ui.busy)
	assert(not ui.perform({"type":"card","uid":uid}) and ui.engine.state.battle.mana == spent)
	await wait_effects(); assert(not ui.busy)
	ui.engine.state.settings.reducedMotion = true
	assert(ui.perform({"type":"endTurn"})); await wait_effects(); assert(not ui.busy)
	var report = FileAccess.open("res://verification/input.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"mouse_swipe":true,"tap_after_swipe":true,"duplicate_submission_blocked":true,"reduced_motion":true,"physical_touchscreen_tested":false},"\t"))
	print("Native input: drag / next tap / duplicate guard / reduced motion passed")
	ui.queue_free(); await frame(); quit()
