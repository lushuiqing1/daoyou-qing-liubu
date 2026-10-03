extends SceneTree
## Native style catalog; this sheet demonstrates skins, not gameplay state.
var ui
func _init(): call_deferred("run")
func run():
	root.size = Vector2i(430,654)
	ui = load("res://scenes/main.tscn").instantiate(); root.add_child(ui)
	for i in range(6): await process_frame
	ui.canvas.hide()
	var sheet = Control.new(); ui.add_child(sheet); sheet.size = Vector2(430,654)
	ui.panel(sheet,Rect2(0,0,430,654),Color("f6efdf"),Color("f6efdf"))
	ui.label(sheet,"水墨按钮",Rect2(20,15,390,40),30)
	ui.label(sheet,"宣纸肌理 · 手绘墨线 · 朱砂笔触",Rect2(22,57,388,25),14,ui.MUTED)
	var states = ["normal","hover","pressed","disabled"]
	for i in range(4): ui.label(sheet,["常态","悬停","按下","不可用"][i],Rect2(18+i*100,92,94,25),14,ui.MUTED,HORIZONTAL_ALIGNMENT_CENTER)
	var rows = [["主要操作 · 朱砂","cinnabar","开始闯关"],["次要操作 · 宣纸","paper","整理术式"],["辅助操作 · 青墨","jade","结束回合"],["选中术式 · 印记","selected","剑气诀"]]
	for row in range(rows.size()):
		var entry = rows[row]; var y = 125+row*93
		ui.label(sheet,entry[0],Rect2(22,y,388,25),16)
		for column in range(4):
			var control = ui.button(sheet,entry[2],Rect2(18+column*100,y+29,94,47),func(): pass,"red" if row == 0 else "paper","不可用" if column == 3 else "",14)
			ui.apply_ink_button(control,entry[1])
			if column < 3:
				# Display each real theme state side by side for visual comparison.
				control.add_theme_stylebox_override("normal",control.get_theme_stylebox(states[column]))
				control.add_theme_stylebox_override("hover",control.get_theme_stylebox(states[column]))
	ui.label(sheet,"键盘焦点与设置开关",Rect2(22,502,388,25),16)
	var focus = ui.button(sheet,"确认施放",Rect2(20,534,180,46),func(): pass,"red","",18)
	focus.grab_focus()
	var toggle = CheckButton.new(); sheet.add_child(toggle); toggle.text = "战斗音效"
	toggle.position = Vector2(215,534); toggle.size = Vector2(195,46); toggle.button_pressed = true
	ui.refine_ink_toggle(toggle)
	ui.label(sheet,"原生控件样式预览，按钮文案可实时替换",Rect2(22,604,386,24),12,ui.MUTED)
	for i in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://verification/ink-buttons-style-sheet.png")
	ui.queue_free(); await process_frame; quit()
