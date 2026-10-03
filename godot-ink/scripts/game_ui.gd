extends Control
## Responsive native Control UI. Artwork is separate from live text and controls.
const EngineModel = preload("res://scripts/ink_engine.gd")
const Store = preload("res://scripts/progress_store.gd")
const CombatStroke = preload("res://scripts/combat_effect.gd")
const TrialSessionModel = preload("res://scripts/trial_session.gd")
const INK = Color("233f38")
const MUTED = Color("6c7b6a")
const RED = Color("a64230")
const PAPER = Color("f7f0de")
const LINE = Color("afa989")
var engine: InkEngine
var view = "home"
var selected_slot = 0
var selected_card = -1
var selected_tile = -1
var busy = false
# The model commits once; presentation follows immutable event snapshots.
var presentation_state: Dictionary = {}
var health_tweens: Dictionary = {}
var persistence = true
var canvas: Control
var modal: Control
var modal_required = false
var modal_opener: Control
var scroll: ScrollContainer
var scroll_positions = {}
var textures = {}
var button_skins = {}
var font: SystemFont
var w = 430.0
var h = 844.0
var feedback = ""
var fx: Control
var player_rect: Rect2
var enemy_rect: Rect2
var board_rect: Rect2
var tile_buttons: Array = []
var dragging = -1
var drag_start = Vector2.ZERO
var suppress_click = false
var layout_waiting = false
var opener_name = ""
var side_layout = false
var summary_width = 430.0
var save_blocked = false
var save_warning = ""
var guide_queue: Array[String] = []
var guide_checkpoint = ""
var guide_replay = false
var guide_replay_seen: Array[String] = []
var guide_open = false
var normal_engine: InkEngine
var trial_session
var trial_active = false
var trial_warning = ""

func _ready():
	persistence = "--no-save" not in OS.get_cmdline_user_args()
	engine = EngineModel.new(int(Time.get_unix_time_from_system()) & 0xffffffff)
	if persistence:
		var saved = Store.read_state(engine)
		if not saved.is_empty(): engine.state = saved
		save_blocked = Store.writes_blocked
		save_warning = Store.last_error
	normal_engine = engine
	trial_session = TrialSessionModel.new(); trial_session.persistence = persistence
	if persistence and trial_session.load():
		if not trial_session.reconcile(normal_engine): trial_warning = trial_session.last_error
	elif persistence and not trial_session.last_error.is_empty(): trial_warning = trial_session.last_error
	font = SystemFont.new(); font.font_names = PackedStringArray(["KaiTi", "楷体", "STKaiti", "Noto Serif CJK SC", "Microsoft YaHei"])
	var skin = Theme.new(); skin.default_font = font; skin.default_font_size = 17; theme = skin
	get_viewport().size_changed.connect(_resize)
	configure_mobile_scale()
	render()
	check_forced()
	if save_blocked: call_deferred("storage_warning_modal")

func _resize():
	if layout_waiting: return
	layout_waiting = true
	call_deferred("_resize_now")

func _resize_now():
	layout_waiting = false
	configure_mobile_scale()
	if guide_open:
		guide_queue.push_front(guide_checkpoint); guide_open = false; guide_checkpoint = ""
	if modal != null: close_modal(true)
	render(); check_forced()
	call_deferred("maybe_show_guide")

func configure_mobile_scale():
	if not (OS.has_feature("android") or OS.has_feature("ios")): return
	var window = get_window(); var physical = window.size
	if physical.x <= 0 or physical.y <= 0: return
	var target = Vector2i(390,roundi(physical.y*390.0/physical.x)) if physical.y >= physical.x else Vector2i(roundi(physical.x*390.0/physical.y),390)
	if window.content_scale_size == target: return
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_size = target

func screen_area() -> Rect2:
	var area = Rect2(Vector2.ZERO,get_viewport_rect().size)
	if OS.has_feature("android") or OS.has_feature("ios"):
		var safe = DisplayServer.get_display_safe_area(); var physical = DisplayServer.window_get_size()
		if safe.size.x > 0 and safe.size.y > 0 and physical.x > 0 and physical.y > 0:
			var ratio = area.size/Vector2(physical)
			area = Rect2(Vector2(safe.position)*ratio,Vector2(safe.size)*ratio)
	return area

func tex(path: String) -> Texture2D:
	if not path.begins_with("res://"): path = "res://"+path
	if not textures.has(path):
		textures[path] = load(path) if ResourceLoader.exists(path) else null
	return textures[path]

func atlas(path: String, cols: int, rows: int, index: int) -> Texture2D:
	var source = tex(path)
	if source == null: return null
	var a = AtlasTexture.new(); a.atlas = source
	var cell = source.get_size()/Vector2(cols, rows)
	a.region = Rect2(Vector2(index%cols, index/cols)*cell, cell); return a

func style(fill: Color = PAPER, border: Color = LINE, width: int = 1) -> StyleBoxFlat:
	var s = StyleBoxFlat.new(); s.bg_color = fill; s.border_color = border
	s.set_border_width_all(width); s.set_corner_radius_all(3)
	s.content_margin_left = 8; s.content_margin_right = 8; s.content_margin_top = 4; s.content_margin_bottom = 4
	return s

func panel(parent: Control, rect: Rect2, fill: Color = PAPER, edge: Color = LINE) -> Panel:
	var p = Panel.new(); parent.add_child(p); p.position = rect.position; p.size = rect.size
	p.add_theme_stylebox_override("panel", style(fill, edge)); p.mouse_filter = Control.MOUSE_FILTER_IGNORE; return p

func label(parent: Control, text: String, rect: Rect2, point: int = 17, color: Color = INK, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l = Label.new(); parent.add_child(l); l.text = text; l.position = rect.position; l.size = rect.size
	l.add_theme_font_size_override("font_size", point); l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.mouse_filter = Control.MOUSE_FILTER_IGNORE; return l

func image(parent: Control, texture: Texture2D, rect: Rect2, cover: bool = false) -> TextureRect:
	var t = TextureRect.new(); parent.add_child(t)
	# Set minimum-size policy before the texture; otherwise native pixels clamp size.
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; t.clip_contents = true
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if cover else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture = texture; t.position = rect.position; t.size = rect.size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE; return t

func button(parent: Control, text: String, rect: Rect2, callback: Callable, kind: String = "paper", disabled_reason: String = "", point: int = 18, node_name: String = "") -> Button:
	var b = Button.new(); parent.add_child(b); b.text = text; b.position = rect.position; b.size = rect.size
	if node_name: b.name = node_name
	b.add_theme_font_size_override("font_size", point)
	var color = RED if kind == "red" else INK
	var fill = RED if kind == "red" else Color("e9eddc") if kind == "green" else Color(PAPER, 0.91)
	b.add_theme_stylebox_override("normal", style(fill, color if kind != "paper" else LINE, 1))
	b.add_theme_stylebox_override("hover", style(fill.lightened(0.06), color, 2))
	b.add_theme_stylebox_override("pressed", style(fill.darkened(0.08), RED, 2))
	b.add_theme_stylebox_override("focus", style(Color(0,0,0,0), RED, 2))
	b.add_theme_stylebox_override("disabled", style(Color(PAPER,0.7), LINE))
	b.add_theme_color_override("font_color", PAPER if kind == "red" else INK)
	b.add_theme_color_override("font_hover_color", PAPER if kind == "red" else INK)
	b.add_theme_color_override("font_pressed_color", PAPER if kind == "red" else INK)
	b.add_theme_color_override("font_focus_color", PAPER if kind == "red" else INK)
	b.add_theme_color_override("font_disabled_color", MUTED)
	b.disabled = not disabled_reason.is_empty(); b.tooltip_text = disabled_reason
	if not node_name.begins_with("Tile") and node_name not in ["PlayerPortrait","EnemyPortrait"]: refine_menu_button(b,kind)
	b.pressed.connect(func():
		if not busy: callback.call())
	return b

func goto(page: String):
	if busy or modal_required: return
	if trial_active and page != "battle": pause_trial(); return
	close_modal(); view = page; selected_tile = -1; scroll_positions.erase(page); feedback = ""; render(); check_forced()
	call_deferred("maybe_show_guide")

func render(preserve_scroll: bool = false):
	if preserve_scroll and is_instance_valid(scroll): scroll_positions[view] = scroll.scroll_vertical
	scroll = null; tile_buttons.clear()
	if is_instance_valid(canvas): remove_child(canvas); canvas.queue_free()
	canvas = Control.new(); canvas.name = "GameCanvas"; add_child(canvas)
	var safe = screen_area(); var vp = safe.size
	var landscape = vp.x > vp.y * 1.25 and vp.y < 500
	w = minf(vp.x, 900 if landscape else 430); h = vp.y
	side_layout = landscape and h < 500 and view != "battle"
	summary_width = minf(w*0.43,310) if side_layout else w
	canvas.position = safe.position+Vector2((vp.x-w)/2, 0); canvas.size = Vector2(w,h); canvas.clip_contents = true
	panel(canvas, Rect2(0,0,w,h), PAPER, PAPER)
	var bg = "battle-bamboo-background.png" if view == "battle" else "home-room-scene.png" if view == "home" else "map-entry-background.png"
	image(canvas, tex("assets/"+bg), Rect2(0,0,w,h), true)
	if view == "battle": render_battle(landscape)
	else:
		render_top()
		if trial_active: render_trial_lobby()
		else:
			match view:
				"home": render_home()
				"map": render_stages()
				"deck": render_deck()
				"bag": render_bag()
				"cultivation": render_cultivation()
				"shop": render_shop()
				"tasks": render_tasks()
				"records": render_records()
			render_nav()
	fx = Control.new(); canvas.add_child(fx); fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if feedback and view != "battle":
		panel(fx, Rect2(14,h-nav_height()-98,w-28,32), Color(PAPER,0.95), LINE)
		label(fx, feedback, Rect2(20,h-nav_height()-98,w-40,32), 14, RED)

func menu_skin(fill: Color = Color("f8f1e1"), edge: Color = Color("b9ad92"), border: int = 1) -> StyleBoxFlat:
	var skin = style(fill,edge,border); skin.set_corner_radius_all(6)
	skin.content_margin_left = 10; skin.content_margin_right = 10
	skin.content_margin_top = 8; skin.content_margin_bottom = 8
	return skin

func refine_menu_button(control: Button, kind: String):
	apply_ink_button(control,"cinnabar" if kind == "red" else "jade" if kind == "green" else "paper")

func ink_button_skin(art: String, inset: float = 8.0) -> StyleBox:
	var key = art+str(inset)
	if button_skins.has(key): return button_skins[key]
	var texture = tex("assets/ui/buttons/"+art+".svg")
	if texture == null:
		if art == "focus": return style(Color(0,0,0,0),RED,2)
		return style(RED if art.begins_with("cinnabar") else PAPER,RED if art == "focus" else INK)
	var skin = StyleBoxTexture.new(); skin.texture = texture
	skin.texture_margin_left = 14; skin.texture_margin_right = 14
	skin.texture_margin_top = 12; skin.texture_margin_bottom = 12
	skin.content_margin_left = inset; skin.content_margin_right = inset
	skin.content_margin_top = 4; skin.content_margin_bottom = 4
	button_skins[key] = skin
	return skin

func apply_ink_button(control: Button, family: String, inset: float = 8.0):
	for state in ["normal","hover","pressed"]:
		control.add_theme_stylebox_override(state,ink_button_skin(family+"-"+state,inset))
	control.add_theme_stylebox_override("disabled",ink_button_skin("disabled",inset))
	control.add_theme_stylebox_override("focus",ink_button_skin("focus",0))
	var copy = PAPER if family == "cinnabar" else INK
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: control.add_theme_color_override(state,copy)
	control.add_theme_color_override("font_disabled_color",Color("7b8172"))
	control.add_theme_constant_override("outline_size",0)

func refine_ink_toggle(control: CheckButton):
	apply_ink_button(control,"paper")
	for entry in [["checked","toggle-on"],["unchecked","toggle-off"],["checked_disabled","toggle-on"],["unchecked_disabled","toggle-off"]]:
		var texture = tex("assets/ui/buttons/"+entry[1]+".svg")
		if texture != null: control.add_theme_icon_override(entry[0],texture)

func menu_card(parent: Control, active: bool = false) -> VBoxContainer:
	var shell = PanelContainer.new(); parent.add_child(shell)
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.add_theme_stylebox_override("panel",menu_skin(Color("eaf0e1") if active else Color("f8f2e4"),Color("8b9b81") if active else Color("bcb196")))
	var body = VBoxContainer.new(); shell.add_child(body); body.add_theme_constant_override("separation",6)
	return body

func menu_section(parent: Control, title: String, meta: String = ""):
	var shell = PanelContainer.new(); parent.add_child(shell)
	var skin = menu_skin(Color(PAPER,0.92),Color(0,0,0,0),0)
	skin.content_margin_top = 2; skin.content_margin_bottom = 2
	shell.add_theme_stylebox_override("panel",skin)
	var row = HBoxContainer.new(); shell.add_child(row)
	var text = list_text(row,title,20); text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if meta:
		var detail = list_text(row,meta,12,MUTED)
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		detail.autowrap_mode = TextServer.AUTOWRAP_OFF
		detail.custom_minimum_size.x = ceilf(font.get_string_size(meta,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x)+4

func menu_badge(parent: Control, text: String, rect: Rect2, accent: bool = false):
	var paper = Panel.new(); parent.add_child(paper); paper.position = rect.position; paper.size = rect.size; paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var skin = menu_skin(Color("e7ece0") if not accent else Color("f0dfd3"),Color(0,0,0,0),0); skin.set_corner_radius_all(10)
	paper.add_theme_stylebox_override("panel",skin)
	label(parent,text,rect,12,RED if accent else INK,HORIZONTAL_ALIGNMENT_CENTER)

func menu_width() -> float:
	return scroll.size.x-12 if is_instance_valid(scroll) else summary_width-24

func menu_health(parent: Control, rect: Rect2):
	image(parent,tex("assets/ui/status-heart.svg"),Rect2(rect.position,Vector2(15,15)))
	var bar = ProgressBar.new(); parent.add_child(bar); bar.show_percentage = false
	bar.min_value = 0; bar.max_value = engine.stats().maxHp; bar.value = engine.state.profile.hp
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for kind in ["background","fill"]:
		var skin = StyleBoxFlat.new(); skin.bg_color = Color("d9ceb7") if kind == "background" else Color("b44335")
		skin.set_corner_radius_all(3); bar.add_theme_stylebox_override(kind,skin)
	bar.position = rect.position+Vector2(19,4); bar.size = Vector2(rect.size.x-19,7)

func render_top():
	panel(canvas,Rect2(0,0,w,56),Color("f6efdf"),Color("b7aa8f"))
	label(canvas,"道友请留步",Rect2(15,3,w-170,29),24)
	label(canvas,"固定角色 · 通关试炼" if trial_active else "山水一程 · 问道长生",Rect2(17,31,w-172,18),11,MUTED)
	menu_badge(canvas,"",Rect2(w-131,13,75,30))
	if trial_active: label(canvas,"试炼",Rect2(w-127,13,68,30),16,RED,HORIZONTAL_ALIGNMENT_CENTER)
	else:
		image(canvas,atlas("assets/home-ink-icons.png",4,2,7),Rect2(w-127,16,24,24))
		label(canvas,str(engine.state.profile.coins),Rect2(w-104,13,44,30),16,INK,HORIZONTAL_ALIGNMENT_CENTER)
	var settings = button(canvas,"",Rect2(w-50,6,44,44),settings_modal,"paper","",24,"Settings")
	settings.tooltip_text = "设置与进度"
	var gear = Line2D.new(); settings.add_child(gear); gear.width = 1.6; gear.default_color = INK
	for i in range(33):
		var radius = 11.0 if i%4 in [1,2] else 8.8
		gear.add_point(Vector2(22,22)+Vector2.from_angle(i*TAU/32)*radius)
	var center = Line2D.new(); settings.add_child(center); center.width = 1.6; center.default_color = INK
	for i in range(25): center.add_point(Vector2(22,22)+Vector2.from_angle(i*TAU/24)*3.6)

func nav_height() -> float:
	return 58 if h < 500 and w > h else 70 if h < 650 else 82

func render_nav():
	var nh = nav_height(); var cell = w/5
	panel(canvas,Rect2(0,h-nh,w,nh),Color("f5edda"),Color("b7aa8e"))
	var names = ["历练","藏经阁","主城","行囊","更多"]
	var pages = ["map","deck","home","bag","more"]
	var icon_indices = [1,3,0,2,4]
	for i in range(5):
		var page = pages[i]; var active = page == view or (i == 4 and view in ["shop","cultivation","tasks","records"])
		var b = button(canvas,"",Rect2(i*cell,h-nh,cell,nh),more_modal if page == "more" else goto.bind(page),"paper","",17,"Nav"+str(i))
		b.add_theme_stylebox_override("normal",ink_button_skin("nav-active") if active else StyleBoxEmpty.new())
		b.add_theme_stylebox_override("hover",ink_button_skin("nav-hover"))
		b.add_theme_stylebox_override("pressed",ink_button_skin("nav-pressed"))
		var ih = 25 if nh == 58 else 32 if nh == 70 else 38
		image(b,atlas("assets/home-ink-icons.png",4,2,icon_indices[i]),Rect2((cell-ih)/2,5,ih,ih))
		label(b,names[i],Rect2(0,nh-29,cell,24),14 if nh == 58 else 16,INK,HORIZONTAL_ALIGNMENT_CENTER)
		if active: image(b,tex("assets/ui/buttons/nav-mark.svg"),Rect2(cell/2-19,nh-10,38,7))

func heading(title: String, subtitle: String, art: String = ""):
	var rect = Rect2(12,65,summary_width-24,40 if side_layout else 66)
	panel(canvas,rect,Color(PAPER,0.88),Color("bcb096"))
	panel(canvas,Rect2(20,76,3,24),RED,RED)
	label(canvas,title,Rect2(30,67,summary_width-46,32),24 if side_layout else 28)
	if not side_layout: label(canvas,subtitle,Rect2(23,102,w-100 if art else w-45,23),12,MUTED)
	if art and not side_layout: image(canvas,tex("assets/"+art),Rect2(w-81,70,63,56))

func list_area(y: float, bottom: float) -> VBoxContainer:
	var x = summary_width+8 if side_layout else 12.0
	var width = w-summary_width-20 if side_layout else w-24
	if side_layout: y = 66; bottom = h-nav_height()-8
	scroll = ScrollContainer.new(); canvas.add_child(scroll); scroll.name = "ContentScroll"
	scroll.position = Vector2(x,y); scroll.size = Vector2(width,maxf(10,bottom-y))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list = VBoxContainer.new(); scroll.add_child(list); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",10)
	scroll.set_deferred("scroll_vertical",int(scroll_positions.get(view,0))); return list

func list_text(parent: Control, text: String, point: int = 16, color: Color = INK) -> Label:
	var l = label(parent,text,Rect2(),point,color); l.custom_minimum_size.y = 30 if view == "battle" else point+7; return l

func list_button(parent: Control, text: String, callback: Callable, reason: String = "", kind: String = "paper", height: float = 48, node_name: String = "") -> Button:
	var b = button(parent,text,Rect2(),callback,kind,reason,17,node_name); b.custom_minimum_size = Vector2(0,height); return b

func action_rect() -> Rect2: return Rect2(14,h-nav_height()-53 if side_layout else h-nav_height()-57,summary_width-28,46)

func render_home():
	var st = engine.stats(); var p = engine.state.profile
	var title_w = summary_width if side_layout else w
	heading("洞府","一方清静，养剑修心。")
	var y = 149.0 if side_layout else maxf(177,h-nav_height()-229)
	var summary_h = 84.0
	panel(canvas,Rect2(18,y,title_w-36,summary_h),Color(PAPER,0.95),Color("b6a98d"))
	label(canvas,"当前境界",Rect2(29,y+6,title_w-58,19),11,MUTED)
	label(canvas,engine.d.realms[int(p.realm)].name,Rect2(29,y+23,title_w-58,29),21 if side_layout else 25)
	menu_health(canvas,Rect2(title_w-117,y+35,87,15))
	label(canvas,"基础攻击 %d · 减伤 %d"%[st.attack,st.armor],Rect2(29,y+55,title_w-58,22),12 if side_layout else 14)
	if side_layout:
		var right = w-summary_width-34
		panel(canvas,Rect2(summary_width+12,91,right+12,139),Color(PAPER,0.93),Color("b6a98d"))
		button(canvas,"继续闯关" if engine.state.run != null else "开始闯关",Rect2(summary_width+18,101,right,48),goto.bind("map"),"red","",23,"Depart")
		button(canvas,"修炼",Rect2(summary_width+18,159,right/2-5,46),goto.bind("cultivation"))
		button(canvas,"整理术式",Rect2(summary_width+23+right/2,159,right/2-5,46),goto.bind("deck"))
		label(canvas,"三式备齐，再赴下一程。",Rect2(summary_width+18,205,right,22),12,MUTED,HORIZONTAL_ALIGNMENT_CENTER)
		return
	button(canvas,"继续闯关" if engine.state.run != null else "开始闯关",Rect2(20,y+97,w-40,49),goto.bind("map"),"red","",23,"Depart")
	button(canvas,"修炼",Rect2(20,y+157,(w-50)/2,44),goto.bind("cultivation"))
	button(canvas,"整理术式",Rect2(30+(w-50)/2,y+157,(w-50)/2,44),goto.bind("deck"))

func render_entry():
	render_stages()

func depart():
	var error = engine.deck_error()
	if error: goto("deck"); toast(error); return
	if perform({"type":"newRun"}): goto("battle")

func render_stages():
	var r = engine.state.run
	heading("关卡历练","四境连续五战 · 每关第五场迎战首领")
	if side_layout: label(canvas,"四只前哨
一场首领",Rect2(25,140,summary_width-50,55),19)
	var list = list_area(142,h-nav_height()-67)
	for i in range(4):
		var ch = engine.d.chapters[i]
		var active = r != null and i == r.chapter
		var status = "已通关" if engine.state.profile.records.highestChapter > i else "待挑战"
		if r != null: status = "本轮已过关" if i < r.chapter else ("挑战中 · %d/5"%r.wave if engine.state.battle != null else "准备出战") if active else "后续关卡"
		var card = list_button(list,"",stage_detail.bind(i),"","green" if active else "paper",114,"Stage"+str(i))
		var width = menu_width()
		image(card,tex(engine.d.enemyArt[i*2+1].file),Rect2(4,12,78,84))
		label(card,"第%d关"%[i+1],Rect2(88,8,width-99,17),11,MUTED)
		label(card,ch.name,Rect2(87,27,width-98,29),22 if width > 300 else 19)
		label(card,"四场前哨 · 首领压阵",Rect2(88,59,width-99,21),12,MUTED)
		menu_badge(card,status,Rect2(88,85,minf(width-99,156),22),active)
	list_button(list,"通关试炼 · 六道印章",trials_modal,"","paper",48,"Trials")
	var ar = action_rect()
	if r == null: button(canvas,"开始第1关 · 竹林道",ar,depart,"red","",19 if side_layout else 22,"Depart")
	else:
		var text = "继续第%d关"%[r.chapter+1] if engine.state.battle != null else "开始第%d关"%[r.chapter+1]
		var primary_width = ar.size.x*0.63
		button(canvas,text,Rect2(ar.position,Vector2(primary_width,46)),continue_stage,"red","",18 if side_layout else 22,"ContinueStage")
		button(canvas,"本轮详情",Rect2(ar.position+Vector2(primary_width+8,0),Vector2(ar.size.x-primary_width-8,46)),run_detail,"paper","",14 if side_layout else 15,"RunDetail")

func continue_stage():
	if engine.state.battle == null:
		if not perform({"type":"enterNode","id":engine.available_node()}): return
	goto("battle")

func stage_detail(index: int):
	var ch = engine.d.chapters[index]; var tuning = engine.d.combat.chapters[index]
	var body = show_modal("第%d关 · %s"%[index+1,ch.name],ch.theme+"\n连续击败五只怪，最后一只为最强首领。",[{"text":"关闭","cb":close_modal,"kind":"green"}],false,220)
	for n in engine.d.nodes:
		var title = "第%d战 · %s"%[n.level+1,"首领" if n.id == "boss" else "精英" if n.type == "elite" else "前哨"]
		list_text(body,title,18,RED if n.id == "boss" else INK)
		list_text(body,"气血 %d · 普攻 %d"%[roundi(tuning.hp*engine.d.combat.healthScale[n.id]),roundi(tuning.attack*engine.d.combat.waveAttackScale[n.id])],14,MUTED)

func trials_modal():
	if busy: return
	var description = "六项固定角色与种子的单章五战。通关且达到条件可获印章，重复完成记录最佳交换步数。"
	if normal_engine.state.profile.records.clears <= 0: description += "\n普通四境通关后全部开启。"
	if not trial_warning.is_empty(): description += "\n\n"+trial_warning
	var body = show_modal("通关试炼",description,[{"text":"返回历练","cb":close_modal,"kind":"green","name":"CloseTrials"}],false,260)
	if trial_session.has_session():
		var current = trial_session.engine.state.trial
		var saved = normal_engine.trial_definition(current.id)
		list_text(body,"上次试炼："+saved.name,16)
		var reason = trial_resume_reason()
		list_button(body,"继续试炼" if trial_session.engine.state.run != null else "查看上次结果",resume_trial,reason,"green",44,"ResumeTrial")
	for definition in normal_engine.trial_definitions():
		var stamp = normal_engine.state.profile.records.get("trialStamps",{}).get(definition.id,{})
		var status = "已获章 · 最佳%d步"%stamp.bestMoves if stamp.get("earned",false) else "尚未获章"
		list_button(body,definition.name+" · "+status,trial_detail.bind(definition.id),"","paper",56,"Trial_"+definition.id)

func trial_resume_reason() -> String:
	if not trial_session.has_session(): return "尚无试炼记录"
	if normal_engine.state.run != null: return "请先完成或结束普通历练，再继续试炼"
	if normal_engine.state.profile.records.clears <= 0: return "普通四境通关后开启"
	return ""

func trial_detail(id: String):
	var definition = normal_engine.trial_definition(id)
	var deck: Array[String] = []
	for card_id in definition.deck: deck.append(normal_engine.cards[card_id].name)
	var treasures: Array[String] = []
	for treasure in definition.treasures: treasures.append(normal_engine.treasures[treasure].name)
	var description = "获章条件："+definition.requirement+"\n\n"+normal_engine.d.chapters[definition.chapter].name+" · 第%d层境界\n固定三式："%[definition.realm+1]+"、".join(deck)+"\n固定法宝："+("、".join(treasures) if not treasures.is_empty() else "无")+"\n装备：桃木剑、粗布衣、古玉佩。满气血、无修炼倾向。\n固定种子：%d\n\n试炼中不可使用道具、购买、突破或换装。试炼只有印章和最佳交换记录，普通成长与收藏独立保存。"%definition.seed
	var stamp = normal_engine.state.profile.records.get("trialStamps",{}).get(id,{})
	if stamp.get("earned",false): description += "\n\n已获印章 · 最佳%d步"%stamp.bestMoves
	var actions = [{"text":"返回试炼","cb":trials_modal}]
	var reason = trial_session.start_reason(normal_engine)
	if trial_session.has_session() and trial_session.engine.state.trial.id == id:
		actions.append({"text":"继续" if trial_session.engine.state.run != null else "查看结果","cb":resume_trial,"reason":trial_resume_reason(),"kind":"green","name":"ResumeTrial"})
		actions.append({"text":"重新开始","cb":begin_trial.bind(id,false),"reason":reason,"name":"RetryTrial"})
	else: actions.append({"text":"开始试炼","cb":begin_trial.bind(id,false),"reason":reason,"kind":"green","name":"StartTrial"})
	var body = show_modal(definition.name,description,actions,false,90)
	if not reason.is_empty(): list_text(body,reason,13,RED)

func begin_trial(id: String, confirmed: bool = false):
	if busy: return
	trial_session.persistence = persistence
	if not confirmed and trial_session.has_session() and trial_session.engine.state.run != null:
		show_modal("重新开始试炼？","当前未完成的试炼将被替换。重新开始会恢复该试炼的固定角色、种子与棋盘，普通历练进度保留。",[{"text":"取消","cb":trial_detail.bind(id)},{"text":"重新开始","cb":begin_trial.bind(id,true),"kind":"red","name":"ReplaceTrial"}]); return
	if not trial_session.start(id,normal_engine):
		trial_warning = trial_session.last_error
		if modal != null: show_error(trial_warning)
		return
	activate_trial()

func activate_trial():
	close_modal(true); guide_queue.clear(); guide_open = false; guide_replay = false
	engine = trial_session.engine; trial_active = true; trial_warning = ""
	selected_card = -1; selected_tile = -1; presentation_state = {}; view = "battle" if engine.state.battle != null else "map"
	render(); check_forced()

func resume_trial():
	var reason = trial_resume_reason()
	if not reason.is_empty(): show_error(reason); return
	activate_trial()

func pause_trial():
	if busy or not trial_active: return
	var saved = save_progress()
	close_modal(true); engine = normal_engine; trial_active = false
	selected_card = -1; selected_tile = -1; presentation_state = {}; guide_queue.clear(); guide_open = false; guide_replay = false
	view = "map"; feedback = "试炼已暂存，可在通关试炼中继续。" if saved else "试炼暂存失败；当前会话仍可继续，请查看试炼页提示。"
	render(); check_forced()

func render_trial_lobby():
	var definition = engine.trial_definition(engine.state.trial.id)
	heading("通关试炼",definition.name)
	var list = list_area(142,h-64)
	var body = menu_card(list)
	list_text(body,definition.name,23)
	list_text(body,"获章条件："+definition.requirement,15)
	list_text(body,"固定角色 · 单章连续五战\n结果仅计印章与最佳交换记录。",13,MUTED)
	button(canvas,"返回普通历练",Rect2(14,h-56,w-28,46),pause_trial,"paper","",18,"TrialLobbyReturn")

func trial_result_modal():
	var result = engine.trial_result_info()
	var summary = engine.state.lastResult.get("summary",{}) if engine.state.lastResult != null else {}
	var description = ("五战完成，获章条件已达成。" if result.qualified else "五战完成，获章条件尚未达成。" if result.kind == "clear" else "本次试炼已结束，获章条件尚未达成。")
	description += "\n条件："+result.requirement+"\n本次指标 %d · 有效交换 %d步\n\n"%[result.metric,result.moves]+recap_compact(summary)
	if result.qualified: description += "\n\n印章已记录。" if trial_session.receipt_committed else "\n\n印章尚待记录，返回后可重试提交。"
	if not trial_warning.is_empty(): description += "\n\n"+trial_warning
	show_modal("试炼获章" if result.qualified else "试炼复盘",description,[{"text":"返回历练","cb":pause_trial,"kind":"green","name":"TrialReturn"},{"text":"重新开始","cb":begin_trial.bind(result.id,true),"reason":trial_session.start_reason(normal_engine),"name":"RetryTrial"},{"text":"完整复盘","cb":recap_detail.bind(summary,true),"name":"TrialRecap"}],true)

func open_trials_after_result():
	finish_result(); view = "map"; render(); trials_modal()

func render_deck():
	heading("藏经阁","三式同行 · 装备与收藏分区显示","ui-library-vignette.png")
	var y = 139.0; var sw = (summary_width-36)/3
	if side_layout: y = 110
	var slot_h = 44 if side_layout else 72
	for i in range(3):
		var id = engine.state.profile.deck[i]; var x = 12+i*(sw+6)
		var name = engine.cards[id].name if id != null else "待装备"
		var b = button(canvas,"",Rect2(x,y,sw,slot_h),select_slot.bind(i),"green" if selected_slot == i else "paper","",17,"Slot"+str(i))
		if not side_layout and id != null: image(b,skill_art(id),Rect2((sw-33)/2,3,33,33))
		label(b,"第%d式"%(i+1),Rect2(0,2 if side_layout else 35,sw,15),10,MUTED,HORIZONTAL_ALIGNMENT_CENTER)
		label(b,name,Rect2(0,19 if side_layout else 48,sw,23),13 if side_layout else 16,INK,HORIZONTAL_ALIGNMENT_CENTER)
		button(canvas,"卸下",Rect2(x,y+slot_h+6,sw,44),deck_remove.bind(i),"paper","本轮锁定" if engine.state.run != null else "未装备" if id == null else "",14,"Unload"+str(i))
	var list = list_area(272,h-nav_height()-65)
	if engine.state.run != null: list_text(list,"本轮术式锁定，整轮结束后可更换。",13,RED)
	list_button(list,"推荐组合 · 自由搭配",preset_modal,"","paper",44,"DeckPresets")
	menu_section(list,"术式卷藏","三式同行")
	var grid = GridContainer.new(); grid.columns = 3; list.add_child(grid)
	grid.add_theme_constant_override("h_separation",8); grid.add_theme_constant_override("v_separation",8)
	for c in engine.d.cards:
		var equipped = c.id in engine.state.profile.deck; var owned = engine.state.profile.collection[c.id] == 1
		var width = (scroll.size.x-28)/3
		var b = list_button(grid,"",skill_detail.bind(c.id),"","green" if equipped else "paper",108,"Skill_"+c.id)
		b.custom_minimum_size.x = width; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		image(b,skill_art(c.id),Rect2((width-43)/2,5,43,43)).modulate.a = 1.0 if owned else 0.4
		label(b,c.name,Rect2(2,51,width-4,25),15,INK if owned else MUTED,HORIZONTAL_ALIGNMENT_CENTER)
		label(b,"已装备" if equipped else "%d墨"%engine.card_cost(c.id) if owned else "未收藏",Rect2(2,79,width-4,19),11,RED if equipped else MUTED,HORIZONTAL_ALIGNMENT_CENTER)
	button(canvas,"返回历练" if engine.state.run != null else "携三式启程",action_rect(),goto.bind("map") if engine.state.run != null else depart,"red","",21,"DeckDepart")

func skill_art(id: String) -> Texture2D:
	for i in range(engine.d.cards.size()):
		if engine.d.cards[i].id == id: return atlas("assets/skill-ink-atlas.png",4,3,i)
	return null

func item_art(id: String) -> Texture2D:
	for i in range(engine.d.items.size()):
		if engine.d.items[i].id == id: return atlas("assets/inventory-ink-atlas.png",5,2,i)
	return null

func select_slot(i: int): selected_slot = i; render(true)
func deck_remove(i: int): perform({"type":"deckRemove","slot":i})

func render_bag():
	heading("行囊","装备、补给分区收纳","ui-bag-vignette.png")
	var sw = (summary_width-36)/3; var equipment = engine.state.profile.equipment
	var ey = 110.0 if side_layout else 139.0
	for i in range(3):
		var slot = ["weapon","armor","accessory"][i]; var id = equipment[slot]; var x = 12+i*(sw+6)
		panel(canvas,Rect2(x,ey,sw,98 if side_layout else 114),Color("f7efdd"),Color("b6aa90"))
		label(canvas,["武器","防具","饰品"][i],Rect2(x,ey+2,sw,20),11,MUTED,HORIZONTAL_ALIGNMENT_CENTER)
		label(canvas,engine.items[id].name if id != null else "未装备",Rect2(x+2,ey+23,sw-4,27),13 if side_layout else 17,INK,HORIZONTAL_ALIGNMENT_CENTER)
		button(canvas,"卸下" if id != null else "待置入",Rect2(x+3,ey+50 if side_layout else ey+62,sw-6,44),perform.bind({"type":"unequip","id":slot}),"paper","战斗中锁定" if engine.state.battle != null else "未装备" if id == null else "",13 if side_layout else 14)
	var list = list_area(265,h-nav_height()-65)
	menu_section(list,"随身物品","点选查看")
	var grid = GridContainer.new(); grid.columns = 3; list.add_child(grid)
	grid.add_theme_constant_override("h_separation",8); grid.add_theme_constant_override("v_separation",8)
	for item in engine.d.items:
		var count = engine.state.profile.inventory[item.id]; var equipped = item.id in equipment.values()
		var width = (scroll.size.x-28)/3
		var b = list_button(grid,"",item_detail.bind(item.id),"","green" if equipped else "paper",112,"Item_"+item.id)
		b.custom_minimum_size.x = width; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		image(b,item_art(item.id),Rect2((width-45)/2,5,45,45)).modulate.a = 1.0 if count else 0.4
		label(b,item.name,Rect2(2,53,width-4,24),15,INK,HORIZONTAL_ALIGNMENT_CENTER)
		label(b,"已装备 · ×%d"%count if equipped else "持有 ×%d"%count,Rect2(2,80,width-4,19),11,RED if equipped else MUTED,HORIZONTAL_ALIGNMENT_CENTER)
	var ar = action_rect()
	button(canvas,"继续对战" if engine.state.battle != null else "返回历练",Rect2(ar.position,Vector2((summary_width-38)/2,46)),goto.bind("battle" if engine.state.battle != null else "map"),"paper","",15 if side_layout else 18)
	button(canvas,"购置补给",Rect2(summary_width/2+5,ar.position.y,(summary_width-38)/2,46),goto.bind("shop"),"red","",15 if side_layout else 18)

func render_cultivation():
	var p = engine.state.profile; var realm = engine.d.realms[int(p.realm)]; var st = engine.stats()
	heading("修炼","境界与成长 · 积攒铜钱突破","ui-cultivation-vignette.png")
	var cy = 109.0 if side_layout else 139.0
	panel(canvas,Rect2(12,cy,summary_width-24,99 if side_layout else 105),Color("eaf0e1"),Color("91a183"))
	label(canvas,"当前境界 · %d/10"%[p.realm+1],Rect2(25,cy+4,summary_width-50,18),11,MUTED)
	label(canvas,realm.name,Rect2(25,cy+24,summary_width-50,30),21 if side_layout else 27)
	label(canvas,"气血 %d · 攻击 %d · 减伤 %d"%[st.maxHp,st.attack,st.armor],Rect2(25,cy+57,summary_width-50,21),11 if side_layout else 14)
	label(canvas,"下境 +%d气血 · +%d攻击"%[realm.hp,realm.attack] if realm.cost != null else "已至筑基，静待新境。",Rect2(25,cy+80,summary_width-50,19),11,MUTED)
	var list = list_area(257,h-nav_height()-65)
	var info = engine.cultivation_info()
	var path = menu_card(list)
	list_text(path,"修炼倾向 · "+info.selectedName,19)
	list_text(path,cultivation_selected_text(),13,MUTED)
	list_text(path,"第3／6／9层分别开启一／二／三级效果。",12,MUTED)
	if info.nextRealm >= 0:
		list_text(path,"下次提升：第%d层 · %s"%[info.nextRealm+1,engine.d.realms[info.nextRealm].name],12,RED)
	else: list_text(path,"倾向层级已全部开启。",12,RED)
	list_button(path,"选择与查看倾向",cultivation_paths_modal,"","paper",44,"PathChoices")
	menu_section(list,"十境修行","步步进益")
	for i in range(engine.d.realms.size()):
		var r = engine.d.realms[i]; var body = menu_card(list,i == p.realm)
		var row = HBoxContainer.new(); body.add_child(row)
		var number = list_text(row,"%02d"%[i+1],21,RED if i == p.realm else MUTED); number.custom_minimum_size.x = 34
		var name = list_text(row,r.name,20); name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var status = list_text(row,"当前" if i == p.realm else "已达" if i < p.realm else "待突破",11,RED if i == p.realm else MUTED)
		status.autowrap_mode = TextServer.AUTOWRAP_OFF
		list_text(body,"气血 +%d · 攻击 +%d · 减伤 +%d"%[r.hp,r.attack,r.armor],12,MUTED)
	var action = {"type":"cultivate"}
	button(canvas,"突破 · %s铜钱"%realm.cost if realm.cost != null else "已达最高境界",action_rect(),perform.bind(action),"red",engine.preflight(action),19 if side_layout else 21,"Cultivate")

func cultivation_selected_text() -> String:
	# Preview only: preferred path at current profile realm; no model mutation or RNG.
	var preview = engine.state.duplicate(true); preview.run = null; preview.battle = null
	var description = engine.cultivation_info(preview).text
	if engine.state.run != null:
		if engine.rules_version() < 4: description += "\n本轮沿用旧规则，倾向从下一轮开始生效。"
		else: description += "\n本轮倾向已锁定；关间突破后，新层级从下一关进场生效。"
	return description

func cultivation_paths_modal():
	var description = "选择与取消均免费。倾向在整轮历练中锁定，关间仍可突破境界；新关卡按进场境界取得效果。"
	if engine.state.profile.realm < 2: description += "\n达到第3层境界后可选择倾向。"
	var body = show_modal("修炼倾向",description,[{"text":"返回修炼","cb":close_modal,"kind":"green","name":"ClosePaths"}],false,260)
	for id in ["sword","guard","spirit","none"]:
		var preview = engine.state.duplicate(true); preview.run = null; preview.battle = null; preview.profile.cultivationPath = id
		var info = engine.cultivation_info(preview)
		var selected = engine.state.profile.get("cultivationPath","none") == id
		var card = menu_card(body,selected)
		list_text(card,info.name+(" · 当前" if selected else ""),20)
		list_text(card,cultivation_choice_text(id),13,MUTED)
		var action = {"type":"cultivationPath","id":id}; var reason = engine.preflight(action)
		if not reason.is_empty(): list_text(card,reason,12,RED)
		list_button(card,"取消倾向" if id == "none" else "选择"+info.name,choose_cultivation_path.bind(id),reason,"green" if selected else "paper",44,"Path_"+id)

func choose_cultivation_path(id: String):
	if perform({"type":"cultivationPath","id":id}): render(true)

func cultivation_choice_text(id: String) -> String:
	var preview = engine.state.duplicate(true); preview.run = null; preview.battle = null; preview.profile.cultivationPath = id
	if id == "none": return engine.cultivation_info(preview).text
	var realm = int(preview.profile.realm)
	if realm < 2: preview.profile.realm = 2
	var text = ("第3层开启后：" if realm < 2 else "当前境界：")+engine.cultivation_info(preview).text
	for next_realm in [5,8]:
		if realm < next_realm:
			preview.profile.realm = next_realm
			text += "\n第%d层：%s"%[next_realm+1,engine.cultivation_info(preview).text]
	return text

func render_shop():
	heading("云游行商","价钱、效果与持有数量清楚呈现","ui-shop-vignette.png")
	var list = list_area(142,h-nav_height()-66)
	menu_section(list,"随身补给","常备物品")
	for item in engine.d.items:
		if not item.has("price"): continue
		var body = menu_card(list); var row = HBoxContainer.new(); body.add_child(row)
		var art = TextureRect.new(); row.add_child(art); art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.texture = item_art(item.id); art.custom_minimum_size = Vector2(52,52); art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var copy = VBoxContainer.new(); row.add_child(copy); copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list_text(copy,item.name,20); list_text(copy,"%d铜钱 · 持有 ×%d"%[item.price,engine.state.profile.inventory[item.id]],12,MUTED)
		list_text(body,item.text,13,MUTED)
		var action = {"type":"buyItem","id":item.id}; var reason = engine.preflight(action)
		list_button(body,"购入 · %d铜钱"%item.price,perform.bind(action),reason,"green",44,"Buy_"+item.id)
		if reason: list_text(body,reason,11,RED)
	menu_section(list,"本轮法宝","仅本轮生效")
	for t in engine.d.treasures:
		var owned = engine.has(engine.state,t.id); var body = menu_card(list,owned)
		var row = HBoxContainer.new(); body.add_child(row)
		var art = TextureRect.new(); row.add_child(art); art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.texture = tex("assets/treasure-"+t.art+"-pdf.png"); art.custom_minimum_size = Vector2(52,52); art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var copy = VBoxContainer.new(); row.add_child(copy); copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list_text(copy,t.name,20); list_text(copy,"本轮已拥有" if owned else "%d铜钱"%t.price,12,RED if owned else MUTED)
		list_text(body,t.text,13,MUTED)
		var action = {"type":"buyTreasure","id":t.id}; var reason = engine.preflight(action)
		list_button(body,"本轮已拥有" if owned else "购入法宝 · %d铜钱"%t.price,perform.bind(action),reason,"green",44,"Buy_"+t.id)
		if reason and not owned: list_text(body,reason,11,RED)
	button(canvas,"返回历练",action_rect(),goto.bind("map"),"red")

func render_tasks():
	heading("云笺录事","任务进度与奖励分开呈现")
	var list = list_area(142,h-nav_height()-18)
	for t in engine.d.tasks:
		var state = int(engine.state.profile.tasks[t.id]); var body = menu_card(list,state == 1)
		var row = HBoxContainer.new(); body.add_child(row)
		var title = list_text(row,t.name,22); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var status = list_text(row,["进行中","可领取","已完成"][state],11,RED if state == 1 else MUTED)
		status.autowrap_mode = TextServer.AUTOWRAP_OFF
		list_text(body,t.text,14,MUTED)
		var reward = HBoxContainer.new(); body.add_child(reward)
		list_text(reward,"奖励 %d 铜钱"%t.reward,15,INK).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list_button(body,["尚未完成","领取奖励","已领取"][state],perform.bind({"type":"claimTask","id":t.id}),"" if state == 1 else "已领取" if state == 2 else "尚未完成","red" if state == 1 else "paper",44,"Claim_"+t.id)

func render_records():
	heading("历练记录","胜负与成长，收进一卷山水")
	var r = engine.state.profile.records; var list = list_area(142,h-nav_height()-18)
	var hero = menu_card(list,true)
	list_text(hero,"累计胜场",15,MUTED)
	list_text(hero,str(r.wins),46,INK).custom_minimum_size.y = 57
	list_text(hero,"每一次胜利，都是下一程的底气。",12,MUTED)
	var grid = GridContainer.new(); list.add_child(grid); grid.columns = 2
	grid.add_theme_constant_override("h_separation",8); grid.add_theme_constant_override("v_separation",8)
	var entries = [["通关次数",str(r.clears)],["最高连锁",str(r.maxCombo)],["最远境界","第%d境"%r.highestChapter],["最佳步数",str(r.bestMoves) if r.bestMoves != null else "待记录"]]
	for entry in entries:
		var body = menu_card(grid); body.get_parent().custom_minimum_size.x = (scroll.size.x-16)/2
		list_text(body,entry[0],13,MUTED); list_text(body,entry[1],27).custom_minimum_size.y = 37
	if r.wins == 0:
		var empty = menu_card(list); list_text(empty,"第一程，从竹林道开始。",19)
		list_text(empty,"尚无战绩，闯关后会自动留下记录。",13,MUTED)
	var recent = r.get("lastSummary",{})
	if not recent.is_empty():
		var recap = menu_card(list)
		list_text(recap,"最近一程",19)
		list_text(recap,recap_compact(recent),13,MUTED)
		list_button(recap,"查看历练复盘",recap_detail.bind(recent,false),"","paper",44,"RecentRecap")

func refine_battle_button(control: Button, fill: Color, accent: Color, selected: bool = false):
	var family = "selected" if selected else "cinnabar" if fill == RED else "jade" if control.name == "EndTurn" else "paper"
	apply_ink_button(control,family,4)

func battle_summary(rect: Rect2):
	var b = battle_state().battle
	panel(canvas,rect,Color("f4eddc"),Color("b7ad93"))
	var third = rect.size.x/3
	var point = 12 if rect.size.x < 300 else 15 if rect.size.y < 35 else 17
	label(canvas,"第 %d 回合"%b.round,Rect2(rect.position+Vector2(6,0),Vector2(third-10,rect.size.y)),point,INK,HORIZONTAL_ALIGNMENT_CENTER).name = "BattleRound"
	label(canvas,"剩余 %d 步"%b.steps,Rect2(rect.position+Vector2(third,0),Vector2(third,rect.size.y)),point+1,RED,HORIZONTAL_ALIGNMENT_CENTER).name = "BattleSteps"
	label(canvas,"灵墨 %d/7"%b.mana,Rect2(rect.position+Vector2(third*2,0),Vector2(third-5,rect.size.y)),point,Color("66566e"),HORIZONTAL_ALIGNMENT_CENTER).name = "BattleMana"
	for i in [1,2]: panel(canvas,Rect2(rect.position+Vector2(third*i,8),Vector2(1,rect.size.y-16)),Color("c8bea8"),Color("c8bea8"))

func battle_controls(rect: Rect2, compact: bool):
	panel(canvas,rect,Color("f5eedc"),Color("afa58e"))
	var inset = 7.0
	var hand_h = 62.0 if compact else 84.0
	render_hand(Rect2(rect.position+Vector2(inset,7),Vector2(rect.size.x-inset*2,hand_h)))
	var effect = battle_instruction()
	var action_h = 44.0 if compact else 48.0
	var action_y = rect.end.y-action_h-7
	var effect_y = rect.position.y+hand_h+10
	label(canvas,effect,Rect2(rect.position.x+10,effect_y,rect.size.x-20,maxf(18,action_y-effect_y-3)),12 if compact else 14,INK)
	var action_w = (rect.size.x-22)/2
	var cast = button(canvas,"确认施放",Rect2(rect.position.x+7,action_y,action_w,action_h),cast_selected,"red",cast_reason(),19 if compact else 21,"ConfirmCast")
	refine_battle_button(cast,RED,RED)
	var end = button(canvas,"结束回合",Rect2(rect.position.x+15+action_w,action_y,action_w,action_h),perform.bind({"type":"endTurn"}),"green","",19 if compact else 21,"EndTurn")
	refine_battle_button(end,Color("e6e9d9"),INK)

func battle_state() -> Dictionary:
	return presentation_state if busy and not presentation_state.is_empty() else engine.state

func render_battle(landscape: bool):
	if battle_state().battle == null:
		view = "map"; render(); return
	var b = battle_state().battle; var ch = engine.d.chapters[int(battle_state().run.chapter)]
	var compact = h < 650
	var header_h = 56.0 if compact else 62.0
	panel(canvas,Rect2(0,0,w,header_h),Color(PAPER,0.95),Color("b8ac91"))
	panel(canvas,Rect2(10,8,3,27),RED if b.enemy.type == "boss" else INK,RED if b.enemy.type == "boss" else INK)
	label(canvas,"试炼 · "+ch.name if trial_active else ch.name,Rect2(19,2,w-216,31),(13 if w < 350 else 18) if trial_active else 24 if w < 350 else 27)
	var progress_hit = button(canvas,"",Rect2(12,17,maxf(44,w-216),44),next_enemy_modal,"paper","",12,"NextEnemyPreview")
	for state_name in ["normal","hover","pressed","disabled"]: progress_hit.add_theme_stylebox_override(state_name,StyleBoxEmpty.new())
	progress_hit.tooltip_text = "查看下一战特征与接战规则"
	var progress = label(progress_hit,"第%d关 · %d/5%s"%[battle_state().run.chapter+1,battle_state().run.wave," Boss" if b.enemy.type == "boss" else ""],Rect2(7,14,w-212,23),12,RED if b.enemy.type == "boss" else MUTED)
	progress.name = "WaveProgress"
	for i in range(4):
		var cb = [battle_bag,hint,rules_modal,pause_battle][i]
		var control = button(canvas,["行囊","提示","规则","暂停"][i],Rect2(w-198+i*48,6,44,44),cb,"paper","试炼中不可使用物品" if trial_active and i == 0 else "",14,"PauseTrial" if trial_active and i == 3 else "BattleTool"+str(i))
		refine_battle_button(control,Color("eee7d5"),Color("9eaa94"))
	if landscape:
		var left = minf(w*0.42,350)
		var bs = minf(h-118,w-left-28)
		var summary_y = h-104
		player_rect = Rect2(13,header_h+5,(left-32)/2,maxf(53,summary_y-header_h-13))
		enemy_rect = Rect2(left/2+3,header_h+5,(left-32)/2,player_rect.size.y)
		board_rect = Rect2(left+(w-left-bs)/2,header_h+5,bs,bs)
		battle_portraits()
		battle_summary(Rect2(12,summary_y,left-24,30))
		render_board(b.board)
		render_hand(Rect2(12,h-67,left-24,59))
		var action_y = board_rect.end.y+6
		var action_w = (w-left-30)/2
		var cast = button(canvas,"确认施放",Rect2(left+10,action_y,action_w,44),cast_selected,"red",cast_reason(),18,"ConfirmCast")
		refine_battle_button(cast,RED,RED)
		var end = button(canvas,"结束回合",Rect2(left+20+action_w,action_y,action_w,44),perform.bind({"type":"endTurn"}),"green","",18,"EndTurn")
		refine_battle_button(end,Color("e6e9d9"),INK)
	else:
		var controls_h = 144.0 if compact else 178.0
		var summary_h = 32.0 if compact else 36.0
		var min_arena = 58.0 if compact else 90.0
		var bs = minf(w-24,h-header_h-controls_h-summary_h-26-min_arena)
		var arena_h = h-header_h-controls_h-summary_h-26-bs
		player_rect = Rect2(15,header_h+3,(w-42)/2,arena_h)
		enemy_rect = Rect2(w/2+6,header_h+3,(w-42)/2,arena_h)
		battle_portraits()
		var summary_y = header_h+arena_h+7
		battle_summary(Rect2(12,summary_y,w-24,summary_h))
		board_rect = Rect2((w-bs)/2,summary_y+summary_h+6,bs,bs)
		render_board(b.board)
		battle_controls(Rect2(10,h-controls_h-8,w-20,controls_h),compact)

func enemy_intent_text() -> String:
	var e = battle_state().battle.enemy
	return "蓄力 %d"%e.nextDamage if e.intentKind == "charge" else "守势 +%d"%e.intentShield if e.intentKind == "guard" else "重击 %d"%e.intent if e.intentKind == "heavy" else "普攻 %d"%e.intent

func battle_status_label(parent: Control, text: String, rect: Rect2, point: int, color: Color = INK, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var copy = label(parent,text,rect,point,color,align)
	copy.add_theme_color_override("font_outline_color",PAPER)
	copy.add_theme_constant_override("outline_size",3)
	return copy

func battle_metric_width(value: String, point: int, icon_size: float) -> float:
	return icon_size+4+ceilf(font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,point).x)+2

func battle_metric(parent: Control, kind: String, value: String, rect: Rect2, point: int, icon_size: float, node_name: String):
	image(parent,tex("assets/ui/status-"+kind+".svg"),Rect2(rect.position+Vector2(0,(rect.size.y-icon_size)/2),Vector2(icon_size,icon_size)))
	var copy = battle_status_label(parent,value,Rect2(rect.position+Vector2(icon_size+4,0),rect.size-Vector2(icon_size+4,0)),point,INK,HORIZONTAL_ALIGNMENT_LEFT)
	copy.name = node_name

func battle_health_plate(parent: Control, hp: int, max_hp: int, shield: int, enemy: bool):
	var width = parent.size.x
	var compact = parent.size.y < 104 or width < 140
	var point = 11 if compact else 13
	var icon_size = 15.0 if compact else 18.0
	var attack = battle_state().battle.enemy.damage if enemy else engine.stats(battle_state()).attack
	var prefix = "Enemy" if enemy else "Player"
	var status_h = 48.0 if compact else 55.0
	var y = maxf(0,parent.size.y-status_h)
	image(parent,tex("assets/ui/status-heart.svg"),Rect2(4,y+1,icon_size,icon_size))
	var bar = ProgressBar.new(); parent.add_child(bar)
	bar.name = prefix+"Health"; bar.position = Vector2(icon_size+9,y+5)
	bar.min_value = 0; bar.max_value = max_hp; bar.value = hp; bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for kind in ["background","fill"]:
		var skin = style(Color("e7dec9") if kind == "background" else Color("b44335"),Color(0,0,0,0),0)
		skin.content_margin_left = 0; skin.content_margin_right = 0
		skin.content_margin_top = 0; skin.content_margin_bottom = 0
		bar.add_theme_stylebox_override(kind,skin)
	# Set geometry after the native percentage/style minimum size has been removed.
	bar.size = Vector2(width-icon_size-14,9 if compact else 10)
	var attack_w = battle_metric_width(str(attack),point,icon_size)
	var shield_w = battle_metric_width(str(shield),point,icon_size)
	var gap = 16.0 if width >= 140 else 10.0
	var x = (width-attack_w-shield_w-gap)/2
	battle_metric(parent,"sword",str(attack),Rect2(x,y+19,attack_w,20),point,icon_size,prefix+"Attack")
	battle_metric(parent,"shield",str(shield),Rect2(x+attack_w+gap,y+19,shield_w,20),point,icon_size,prefix+"Shield")
	var hint = battle_status_label(parent,enemy_intent_text() if enemy else "点击查看详情",Rect2(2,y+39,width-4,12 if compact else 15),10 if compact else 11,RED if enemy else MUTED)
	if enemy: hint.name = "EnemyIntent"
	parent.tooltip_text = "%s状态 · 气血 %d/%d · 攻击 %d · 护盾 %d · 点击查看完整状态"%["敌方" if enemy else "我方",hp,max_hp,attack,shield]
	var focus_mark = Line2D.new(); parent.add_child(focus_mark)
	focus_mark.width = 1.5; focus_mark.default_color = RED
	focus_mark.add_point(Vector2(width/2-11,y+17)); focus_mark.add_point(Vector2(width/2+11,y+17))
	focus_mark.visible = parent.has_focus()
	parent.focus_entered.connect(focus_mark.show); parent.focus_exited.connect(focus_mark.hide)

func battle_portraits():
	var state = battle_state(); var e = state.battle.enemy
	var a = button(canvas,"",player_rect,battle_status.bind("player"),"paper","",17,"PlayerPortrait")
	a.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
	a.add_theme_stylebox_override("normal",StyleBoxEmpty.new()); a.tooltip_text = "我方 · 查看完整状态"
	a.add_theme_stylebox_override("hover",StyleBoxEmpty.new()); a.add_theme_stylebox_override("pressed",StyleBoxEmpty.new())
	image(a,tex("assets/player-portrait.png"),Rect2(Vector2.ZERO,player_rect.size)).name = "PlayerArt"
	battle_health_plate(a,state.profile.hp,engine.stats(battle_state()).maxHp,state.battle.shield,false)
	var b = button(canvas,"",enemy_rect,battle_status.bind("enemy"),"paper","",17,"EnemyPortrait")
	b.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
	b.add_theme_stylebox_override("normal",StyleBoxEmpty.new()); b.tooltip_text = "敌方 · 查看完整状态"
	b.add_theme_stylebox_override("hover",StyleBoxEmpty.new()); b.add_theme_stylebox_override("pressed",StyleBoxEmpty.new())
	image(b,tex(engine.enemy_art(battle_state())),Rect2(Vector2.ZERO,enemy_rect.size)).name = "EnemyArt"
	battle_health_plate(b,e.hp,e.maxHp,e.shield,true)

func render_board(models: Array):
	panel(canvas,Rect2(board_rect.position-Vector2(3,3),board_rect.size+Vector2(6,6)),Color("e5dcc3"),INK)
	var cell = board_rect.size.x/6
	for i in range(36):
		var rect = Rect2(board_rect.position+Vector2(i%6,i/6)*cell,Vector2(cell,cell))
		var b = button(canvas,"",rect,tile_click.bind(i),"paper","",12,"Tile"+str(i))
		b.add_theme_stylebox_override("normal",style(Color("fcf9ee"),RED if selected_tile == i else Color("c4b99e"),2 if selected_tile == i else 1))
		var data = engine.d.tiles[models[i].type]
		image(b,tex("assets/tile-"+data.asset+"-watercolor.jpg"),Rect2(Vector2(4,4),rect.size-Vector2(8,8)),true)
		b.tooltip_text = "第%d行第%d列 · %s"%[i/6+1,i%6+1,data.effect]
		b.gui_input.connect(tile_input.bind(i)); tile_buttons.append(b)
	if is_instance_valid(fx) and fx.get_parent() == canvas: canvas.move_child(fx,-1)

func card_summary(id: String) -> String:
	var c = engine.cards[id]; var stats = engine.stats(battle_state())
	if c.has("damage"): return "伤害 %d"%engine.card_value(id,battle_state())
	if c.has("shieldRatio"): return "护盾 %d"%roundi(stats.maxHp*c.shieldRatio)
	if c.has("shield"): return "护盾 %d"%c.shield
	if c.has("healRatio"): return "恢复 %d"%roundi(stats.maxHp*c.healRatio)
	if c.has("heal"): return "恢复 %d"%c.heal
	return "连击增益"

func render_hand(rect: Rect2):
	var b = battle_state().battle; var cw = (rect.size.x-12)/3
	var compact = rect.size.y < 75
	for i in range(3):
		var c = b.hand[i]; var data = engine.cards[c.cardId]; var reason = engine.card_reason(c.uid,battle_state())
		var selected = selected_card == c.uid
		var card = button(canvas,"",Rect2(rect.position+Vector2(i*(cw+6),0),Vector2(cw,rect.size.y)),select_card.bind(c.uid),"paper","",16,"Card"+str(i))
		refine_battle_button(card,Color("eee2cc") if selected else Color("faf3e2"),RED if selected else Color("ada38b"),selected)
		card.tooltip_text = data.name+" · "+engine.card_description(c.cardId,battle_state())+("\n"+reason if reason else "")
		if cw < 90:
			label(card,data.name,Rect2(4,2,cw-8,22),14,INK,HORIZONTAL_ALIGNMENT_CENTER)
			label(card,card_summary(c.cardId),Rect2(4,24,cw-8,16),11,INK,HORIZONTAL_ALIGNMENT_CENTER)
			label(card,reason if reason else "%d墨 · %s"%[engine.card_cost(c.cardId),"已选" if selected else "可用"],Rect2(4,42,cw-8,15),10,RED if reason or selected else Color("66566e"),HORIZONTAL_ALIGNMENT_CENTER)
			continue
		var title_point = 14 if cw < 90 else 16 if compact else 18
		label(card,data.name,Rect2(6,2,cw-36,24),title_point,INK)
		panel(card,Rect2(cw-28,4,22,21),Color("e8e1e9"),Color("aa96ac"))
		label(card,str(engine.card_cost(c.cardId)),Rect2(cw-28,4,22,21),14,Color("66566e"),HORIZONTAL_ALIGNMENT_CENTER)
		var art_size = 24.0 if compact else 39.0
		image(card,skill_art(c.cardId),Rect2(5,28,art_size,art_size))
		var text_x = art_size+9
		label(card,card_summary(c.cardId),Rect2(text_x,27,cw-text_x-4,20),11 if cw < 90 else 12 if compact else 13,INK)
		label(card,"结算中" if busy else reason if reason else "已选中" if selected else "可施放",Rect2(text_x,44 if compact else 49,cw-text_x-4,18),10 if compact else 11,RED if reason or selected else MUTED)
		panel(card,Rect2(5,rect.size.y-4,cw-10,2),RED if selected else Color("ccc0a7"),RED if selected else Color("ccc0a7"))
		card.tooltip_text = data.name+" · "+engine.card_description(c.cardId,battle_state())+("\n"+reason if reason else "")

func card_effect(id: String) -> String:
	var c = engine.cards[id]
	if c.has("damage"):
		return "造成%d点伤害%s%s。"%[engine.card_value(id,battle_state()),"，无视护盾并移除6点敌盾" if id == "armorBreak" else "","，恢复%d点气血"%c.heal if c.has("heal") else ""]
	return c.text

func battle_instruction() -> String:
	var s = battle_state()
	if s.battle == null: return "选择术式，查看效果后确认施放。"
	for c in s.battle.hand:
		if c.uid == selected_card:
			var suffix = ""
			var links = s.battle.get("links",{})
			if engine.rules_version(s) >= 3:
				if c.cardId == "sword" and links.get("swordReady",false): suffix = " · 蓄剑已就绪"
				elif c.cardId == "ironwall" and links.get("wardArmed",false): suffix = " · 盾破返墨待触发"
				elif c.cardId == "spiritArray" and links.get("purpleReady",false): suffix = " · 紫消增墨待触发"
			return engine.cards[c.cardId].name+" · "+card_summary(c.cardId)+suffix
	var preview = engine.next_enemy_preview(s)
	if preview.available: return "下战 · %s：%s %d（顶部查看）"%[preview.role,intent_name(preview.firstIntent),preview.firstValue]
	return "试炼首领 · 胜后直接判定" if trial_active else "首领战 · 胜后统一领奖与整备"

func intent_name(value: String) -> String:
	return {"attack":"普攻","charge":"蓄力","heavy":"重击","guard":"守势"}.get(value,value)

func next_enemy_modal():
	if busy or engine.state.battle == null: return
	var preview = engine.next_enemy_preview()
	var description = preview.text
	if preview.available:
		description = "第%d/5战 · %s\n%s\n入场首个行动：%s %d\n\n接战保留棋盘、灵墨、护盾和剩余步数。战胜恢复最大气血的10%%。"%[preview.wave,preview.role,preview.text,intent_name(preview.firstIntent),preview.firstValue]
	if trial_active:
		var definition = engine.trial_definition(engine.state.trial.id)
		if not preview.available: description = "试炼首领已登场。击败后直接判定获章条件，不进入普通奖励或关间整备。"
		description += "\n\n获章条件："+definition.requirement+"\n当前指标：%d"%engine.trial_metric(definition,engine.state.run.summary)
	if engine.rules_version() < 3: description += "\n\n本轮沿用更新前的战斗规则；新规则从下一轮开始。"
	show_modal("下一战预告" if preview.available else "本关首领",description,[{"text":"返回战斗","cb":close_modal,"kind":"green","name":"ClosePreview"}])

func preset_modal():
	var body = show_modal("推荐组合","三式可自由搭配。推荐仅提供打法参考，不附加职业或被动。",[{"text":"返回藏经阁","cb":close_modal}],false,240)
	for preset in engine.preset_list():
		var section = menu_card(body)
		list_text(section,preset.name,20)
		list_text(section,preset.description,13,MUTED)
		var missing: Array[String] = []
		for id in preset.deck:
			list_text(section,"%s · %d墨"%[engine.cards[id].name,engine.card_cost(id)],14)
			if engine.state.profile.collection.get(id,0) != 1: missing.append(engine.cards[id].name)
		if not missing.is_empty(): list_text(section,"尚需收藏："+"、".join(missing)+"。可在关卡首领奖励中获得。",13,RED)
		var reason = engine.preflight({"type":"deckPreset","id":preset.id})
		if engine.state.run != null: list_text(section,"本轮三式已锁定，结束历练后可装备。",13,RED)
		list_button(section,"一键装备",apply_preset.bind(preset.id),reason,"green",44,"Preset_"+preset.id)

func apply_preset(id: String):
	if perform({"type":"deckPreset","id":id}):
		selected_slot = 0; render(true)

func cast_reason() -> String:
	return "结算中" if busy else "请先选择术式" if selected_card < 0 else engine.card_reason(selected_card)

func select_card(uid: int):
	if busy or modal != null: return
	selected_card = uid; render()

func cast_selected():
	if selected_card >= 0: perform({"type":"card","uid":selected_card})

func tile_click(i: int):
	if suppress_click: suppress_click = false; return
	if busy or modal != null: return
	if selected_tile < 0: selected_tile = i; render(); return
	if i == selected_tile: selected_tile = -1; render(); return
	if not engine.adjacent(selected_tile,i): selected_tile = i; render(); return
	var previous = selected_tile; selected_tile = -1
	perform({"type":"swap","a":previous,"b":i})

func tile_input(event: InputEvent, i: int):
	if busy or modal != null: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: dragging = i; drag_start = event.global_position
		else: dragging = -1
	if event is InputEventMouseMotion and dragging == i and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		var delta = event.global_position-drag_start
		if delta.length() > board_rect.size.x/6*0.38:
			var other = i+(1 if delta.x > 0 else -1) if absf(delta.x) > absf(delta.y) else i+(6 if delta.y > 0 else -6)
			if engine.adjacent(i,other):
				dragging = -1; selected_tile = -1; suppress_click = true
				perform({"type":"swap","a":i,"b":other})
	if event is InputEventScreenTouch:
		if event.pressed: dragging = i; drag_start = event.position
		else: dragging = -1
	if event is InputEventScreenDrag and dragging == i:
		var delta = event.position-drag_start
		if delta.length() > board_rect.size.x/6*0.38:
			var other = i+(1 if delta.x > 0 else -1) if absf(delta.x) > absf(delta.y) else i+(6 if delta.y > 0 else -6)
			if engine.adjacent(i,other): dragging = -1; suppress_click = true; perform({"type":"swap","a":i,"b":other})

func hint():
	if busy or engine.state.battle == null: return
	var pair = engine.possible_move(engine.state.battle.board)
	for i in pair:
		if i < tile_buttons.size(): tile_buttons[i].add_theme_stylebox_override("normal",style(PAPER,RED,3)); tile_buttons[i].modulate = Color(1.0,0.78,0.55)

func pause_battle():
	if not busy:
		if trial_active: pause_trial()
		else: goto("map")

func perform(action: Dictionary) -> bool:
	if busy: return false
	if action.type in ["swap","card","endTurn"]:
		presentation_state = engine.state.duplicate(true)
	var result = engine.dispatch(action)
	if not result.ok:
		if modal != null: show_error(result.notice)
		else: toast(result.notice)
		return false
	collect_guide_events(action,result.events)
	save_progress()
	if action.type in ["swap","card","endTurn"]:
		busy = true; close_modal()
		for control in canvas.find_children("*","Button",true,false): control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for node_name in ["ConfirmCast","EndTurn"]:
			var control = canvas.find_child(node_name,true,false)
			if control != null: control.disabled = true
		play_events(result.events,result.notice); return true
	close_modal(true); feedback = result.notice; render(true); check_forced()
	if opener_name: call_deferred("restore_focus_by_name")
	call_deferred("maybe_show_guide")
	return true

func sync_combat_state(snapshot: Dictionary, animate: bool = true):
	presentation_state = snapshot.duplicate(true)
	var state = battle_state(); var b = state.battle
	if b == null: return
	for prefix in ["Player","Enemy"]:
		var health = canvas.find_child(prefix+"Health",true,false)
		var hp = state.profile.hp if prefix == "Player" else b.enemy.hp
		var maximum = engine.stats(state).maxHp if prefix == "Player" else b.enemy.maxHp
		if health != null:
			if health_tweens.has(prefix) and health_tweens[prefix].is_valid(): health_tweens[prefix].kill()
			health.max_value = maximum
			if animate and not state.settings.reducedMotion:
				var tween = create_tween(); health_tweens[prefix] = tween
				tween.tween_property(health,"value",hp,0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			else: health.value = hp
		var shield = canvas.find_child(prefix+"Shield",true,false)
		if shield != null: shield.text = str(b.shield if prefix == "Player" else b.enemy.shield)
		var attack = canvas.find_child(prefix+"Attack",true,false)
		if attack != null: attack.text = str(engine.stats(state).attack if prefix == "Player" else b.enemy.damage)
	var intent = canvas.find_child("EnemyIntent",true,false)
	if intent != null: intent.text = enemy_intent_text()
	for entry in [["BattleRound","第 %d 回合"%b.round],["BattleSteps","剩余 %d 步"%b.steps],["BattleMana","灵墨 %d/7"%b.mana],
		["WaveProgress","第%d关 · %d/5%s"%[state.run.chapter+1,state.run.wave," Boss" if b.enemy.type == "boss" else ""]]]:
		var copy = canvas.find_child(entry[0],true,false)
		if copy != null: copy.text = entry[1]

func play_events(sequence: Array, notice: String):
	var short = engine.state.settings.reducedMotion
	for event in sequence:
		match event.type:
			"swap", "board", "reshuffle":
				if not presentation_state.is_empty() and presentation_state.battle != null: presentation_state.battle.board = event.board
				for tile in tile_buttons:
					if is_instance_valid(tile): tile.queue_free()
				tile_buttons.clear(); render_board(event.board)
				await get_tree().create_timer(0.04 if short else 0.10).timeout
			"match", "card":
				if event.type == "match":
					for i in event.indices:
						if i < tile_buttons.size():
							var tw = create_tween(); tw.tween_property(tile_buttons[i],"modulate:a",0.18,0.06 if short else 0.16)
					if event.chain > 1: float_text("%d 连锁"%event.chain,board_rect.get_center(),RED)
					if event.get("bonusStep",0): float_text("四连 · 步数 +1",board_rect.get_center()+Vector2(0,27),INK)
				await combat_beat(event,false)
			"enemy":
				if event.kind in ["attack","heavy"]: await combat_beat(event,true)
				else:
					sync_combat_state(event.state)
					combat_pulse("shield" if event.kind == "guard" else "entry",enemy_rect,Color("397fa8") if event.kind == "guard" else RED)
					float_text("蓄力 · 下击%d"%event.nextDamage if event.kind == "charge" else "护盾 +%d"%event.guard,combat_center(enemy_rect),RED)
					play_sound("guard" if event.kind == "guard" else "entry")
					await get_tree().create_timer(0.30 if short else 0.52).timeout
			"enrage":
				sync_combat_state(event.state,false); battle_banner("首领震怒",RED)
				combat_pulse("entry",enemy_rect,RED,true); play_sound("entry")
				await get_tree().create_timer(0.32 if short else 0.46).timeout
			"link":
				sync_combat_state(event.state)
				var messages = {"sword":"蓄剑 · 额外伤害 +10","ward":"盾破返墨触发","purple":"紫消增墨触发"}
				float_text(messages.get(event.kind,"术式联动"),combat_center(player_rect),INK)
				await get_tree().create_timer(0.20 if short else 0.30).timeout
			"revive":
				sync_combat_state(event.state); combat_pulse("heal",player_rect,INK)
				float_text("还魂 · 重生",combat_center(player_rect),INK); play_sound("heal")
				await get_tree().create_timer(0.32 if short else 0.50).timeout
			"win":
				sync_combat_state(event.state)
				battle_banner("首领击破 · 5/5" if event.wave == 5 else "击破 · %d/5"%event.wave,RED)
				combat_pulse("defeat",enemy_rect,RED)
				if event.get("heal",0): float_text("战胜 · 气血 +%d"%event.heal,combat_center(player_rect),INK)
				var actor = canvas.find_child("EnemyArt",true,false)
				if actor != null:
					var tween = create_tween().set_parallel()
					tween.tween_property(actor,"modulate:a",0.0,0.16 if short else 0.28)
					if not short: tween.tween_property(actor,"position:x",actor.position.x+12,0.28)
				play_sound("defeat")
				await get_tree().create_timer(0.32 if short else 0.38).timeout
			"wave":
				sync_combat_state(event.state,false)
				var actor = canvas.find_child("EnemyArt",true,false)
				if actor != null:
					actor.texture = tex(engine.enemy_art(event.state)); actor.modulate = Color(1,1,1,0)
					actor.position = Vector2(0 if short else 18,0)
					var tween = create_tween().set_parallel()
					tween.tween_property(actor,"modulate:a",1.0,0.12 if short else 0.30)
					if not short: tween.tween_property(actor,"position:x",0.0,0.30).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				battle_banner("首领登场 · 5/5" if event.wave == 5 else "下一战 · %d/5"%event.wave,RED if event.wave == 5 else INK)
				combat_pulse("entry",enemy_rect,RED if event.wave == 5 else INK,event.wave == 5)
				play_sound("entry")
				await get_tree().create_timer(0.34 if short else 0.50).timeout
	busy = false; presentation_state = {}; health_tweens.clear()
	selected_tile = -1; suppress_click = false; feedback = notice
	if engine.state.battle == null: view = "map"; selected_card = -1
	elif not engine.state.battle.hand.any(func(c): return c.uid == selected_card): selected_card = -1
	render(); check_forced()
	call_deferred("maybe_show_guide")

func save_progress() -> bool:
	if trial_active:
		trial_session.persistence = persistence
		var saved = trial_session.save()
		if saved: saved = trial_session.reconcile(normal_engine)
		trial_warning = trial_session.last_error if not saved else ""
		return saved
	if not persistence: return true
	if save_blocked or Store.writes_blocked:
		save_blocked = true
		save_warning = Store.last_error if not Store.last_error.is_empty() else save_warning
		return false
	var err = Store.save_state(engine.state)
	if err != OK:
		save_warning = "进度保存失败，请检查目录权限与剩余空间。"
		feedback = save_warning
		return false
	return true

func storage_warning_modal():
	if busy: return
	var path = ProjectSettings.globalize_path(Store.SAVE)
	show_modal("进度需要恢复",save_warning+"\n\n本次可临时试玩，新的操作不会写入存档。现有文件会保留。\n\n存档目录：\n"+path.get_base_dir()+"\n\n请先备份该目录，再恢复可用的 progress-v2.json 或 progress-v2.backup.json，重启游戏后继续。",[{"text":"我已知晓","cb":close_modal,"kind":"green","name":"StorageWarningClose"}])

func guide_enabled() -> bool:
	return not trial_active and (guide_replay or engine.state.settings.get("guide",{}).get("enabled",false))

func guide_seen(checkpoint: String) -> bool:
	return checkpoint in guide_replay_seen if guide_replay else checkpoint in engine.state.settings.get("guide",{}).get("seen",[])

func queue_guide(checkpoint: String):
	if guide_enabled() and not guide_seen(checkpoint) and checkpoint not in guide_queue: guide_queue.append(checkpoint)

func collect_guide_events(action: Dictionary, sequence: Array):
	if not guide_enabled(): return
	for event in sequence:
		match event.type:
			"match":
				if action.type == "swap": queue_guide("swap")
				if event.get("bonusStep",0) > 0: queue_guide("fourMatch")
			"card": queue_guide("cast")
			"enemy": queue_guide("endTurn")
			"wave": queue_guide("wave")
			"link": queue_guide("links")

func guide_copy(checkpoint: String) -> String:
	match checkpoint:
		"swap": return "相邻同色灵玉连成三枚即可消除。无效交换不扣步；一次交换的下落连锁会继续结算。\n\n五色分别用于攻击、恢复、护盾、铜钱和灵墨。顶部的「提示」可标出一组能消除的交换。"
		"cast": return "选择术式后再确认施放。只要灵墨足够，三张常驻术式可以反复使用。\n\n三式在整轮历练中锁定；新收藏的术式要在下轮开始前装备。"
		"endTurn": return "结束回合会执行敌方已经预告的行动。点击敌方可查看完整状态与预计失血。\n\n我方护盾抵挡本次攻击后全部消散；蓄力当回合不攻击，下一次重击的伤害已经锁定。"
		"fourMatch": return "刚才的直线四枚及以上消除返还了1步。每个玩家回合最多返还2步，跨接战继续共用这份额度。\n\n返还只看实际到账，连锁每层另有15%的收益增加。"
		"wave": return "普通怪击败后直接迎战下一只，棋盘、三式、灵墨、护盾和剩余步数继续保留。战胜会恢复最大气血的10%。\n\n第五只是首领。顶部的战斗进度可以查看下一战特征，首领战胜后统一领奖。"
		"links": return "术式联动按实际行动触发：剑气诀四连蓄剑，金刚符护盾被击破后返墨，聚灵阵为下一次紫消增墨。\n\n联动刷新但不叠加；回合结束或新关卡会清除。点击我方可查看当前联动，术式详情可以重看完整条件。"
	return ""

func maybe_show_guide():
	if busy or modal != null or not guide_enabled() or view != "battle" or engine.state.battle == null: return
	if engine.state.run.pendingReward != null or engine.state.lastResult != null: return
	while not guide_queue.is_empty() and guide_seen(guide_queue[0]): guide_queue.pop_front()
	if guide_queue.is_empty(): return
	guide_checkpoint = guide_queue.pop_front(); guide_open = true
	var titles = {"swap":"灵玉消除","cast":"常驻术式","endTurn":"预判行动","fourMatch":"四连返步","wave":"连续接战","links":"术式联动"}
	show_modal("分步指引 · "+titles.get(guide_checkpoint,"初行"),guide_copy(guide_checkpoint),[{"text":"明白了","cb":complete_guide,"kind":"green","name":"GuideContinue"},{"text":"跳过指引","cb":skip_guide,"name":"GuideSkip"}])

func complete_guide():
	var checkpoint = guide_checkpoint
	guide_open = false; guide_checkpoint = ""
	if guide_replay:
		if checkpoint not in guide_replay_seen: guide_replay_seen.append(checkpoint)
	else:
		engine.dispatch({"type":"guideProgress","id":checkpoint}); save_progress()
	close_modal()
	call_deferred("maybe_show_guide")

func skip_guide():
	guide_open = false; guide_checkpoint = ""; guide_queue.clear()
	if guide_replay: guide_replay = false; guide_replay_seen.clear()
	else:
		engine.dispatch({"type":"guideSkip"}); save_progress()
	close_modal()

func disable_guides():
	guide_open = false; guide_checkpoint = ""; guide_queue.clear()
	guide_replay = false; guide_replay_seen.clear()
	engine.dispatch({"type":"guideSkip"}); save_progress()
	settings_modal()

func guide_replay_modal():
	var body = show_modal("分步指引","可先逐条重看，也可开启跟随操作的短提示。重看不会重开历练或消耗资源。",[{"text":"返回规则","cb":rules_modal},{"text":"跟随操作提示","cb":start_guide_replay,"kind":"green","name":"GuideReplayStart"}],false,230)
	for checkpoint in ["swap","cast","endTurn","fourMatch","wave","links"]:
		if checkpoint == "links" and engine.rules_version() < 3: continue
		list_text(body,guide_copy(checkpoint),14)

func start_guide_replay():
	guide_replay = true; guide_replay_seen.clear(); guide_queue.clear()
	close_modal(); feedback = "分步提示已开启，会在实际操作后出现。"; render(true)

func recap_compact(summary: Dictionary) -> String:
	if summary.is_empty(): return "本次没有详细记录。"
	var casts = 0
	for count in summary.get("casts",{}).values(): casts += int(count)
	var text = "最高%d连锁 · 返步%d · 施法%d次"%[summary.get("maxChain",0),summary.get("refundSteps",0),casts]
	if summary.get("coverage","") == "partial": text = "详细数据自第%d关第%d战起记录。\n"%[summary.get("startChapter",0)+1,summary.get("startWave",1)]+text
	return text

func recap_detail(summary: Dictionary, return_to_result: bool):
	var actions = [{"text":"返回结算" if return_to_result else "关闭","cb":check_forced if return_to_result else close_modal,"kind":"green","name":"CloseRecap"}]
	var description = engine.summary_text(summary)
	var advice = engine.recap_advice(summary) if not summary.is_empty() else ""
	if not advice.is_empty(): description += "\n\n此行提示：\n"+advice
	show_modal("历练复盘",description,actions,return_to_result,100)

func combat_center(rect: Rect2) -> Vector2:
	return Vector2(rect.get_center().x,rect.position.y+maxf(12,(rect.size.y-50)*0.48))

func combat_beat(event: Dictionary, enemy: bool):
	var short = engine.state.settings.reducedMotion
	var attack = event.kind in ["attack","heavy"] if enemy else event.get("attack",false)
	var target_rect = player_rect if enemy else enemy_rect
	var amount = event.damage if enemy else event.dealt
	var strong = (enemy and event.kind == "heavy") or (not enemy and event.get("chain",1) > 1)
	if attack:
		strike(enemy,strong); play_sound("swing")
		await get_tree().create_timer(0.03 if short else 0.12).timeout
		hit_actor(enemy,strong)
		if amount > 0:
			float_text("−%d"%amount,combat_center(target_rect)+Vector2(0,-13),RED,true)
			play_sound("impact")
		elif event.get("blocked",0) > 0: float_text("完全格挡",combat_center(target_rect)+Vector2(0,-13),Color("397fa8"),true)
		if event.get("blocked",0) > 0:
			combat_pulse("shield",target_rect,Color("397fa8"))
			float_text("格挡 %d"%event.blocked,combat_center(target_rect)+Vector2(0,23),Color("397fa8"))
			play_sound("guard")
	sync_combat_state(event.state)
	if not enemy:
		if event.heal > 0:
			combat_pulse("heal",player_rect,Color("547c4d")); play_sound("heal")
			float_text("气血 +%d"%event.heal,combat_center(player_rect)+Vector2(0,-12),Color("547c4d"))
		if event.shield > 0:
			combat_pulse("shield",player_rect,Color("397fa8")); play_sound("guard")
			float_text("护盾 +%d"%event.shield,combat_center(player_rect)+Vector2(0,20),Color("397fa8"))
		if event.type == "card" and not attack and event.heal == 0 and event.shield == 0:
			combat_pulse("entry",player_rect,INK); float_text("术式生效",combat_center(player_rect),INK)
	await get_tree().create_timer(0.30 if short else 0.43).timeout

func float_text(text: String, at: Vector2, color: Color, damage: bool = false):
	if not is_instance_valid(fx): return
	var width = minf(w-16,210)
	var copy = label(fx,text,Rect2(Vector2(clampf(at.x-width/2,8,w-width-8),at.y-23),Vector2(width,46)),32 if damage else 18,color,HORIZONTAL_ALIGNMENT_CENTER)
	copy.name = "DamagePopup" if damage else "CombatPopup"
	copy.add_theme_color_override("font_outline_color",PAPER); copy.add_theme_constant_override("outline_size",6 if damage else 4)
	copy.add_theme_color_override("font_shadow_color",Color("233f38",0.24)); copy.add_theme_constant_override("shadow_offset_y",2)
	var short = engine.state.settings.reducedMotion
	var tween = create_tween()
	if not short:
		copy.pivot_offset = copy.size/2; copy.scale = Vector2(0.88,0.88)
		tween.tween_property(copy,"scale",Vector2.ONE,0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(copy,"position:y",copy.position.y-13,0.35)
	else: tween.tween_interval(0.16)
	tween.tween_property(copy,"modulate:a",0.0,0.14 if short else 0.15); tween.tween_callback(copy.queue_free)

func battle_banner(text: String, accent: Color):
	for old in fx.get_children():
		if old.name == "BattleBanner":
			old.name = "RetiredBanner"; old.queue_free()
	var width = minf(w-20,290)
	var ribbon = panel(fx,Rect2((w-width)/2,maxf(63,enemy_rect.position.y+6),width,38),Color(PAPER,0.96),Color(accent,0.55))
	ribbon.name = "BattleBanner"
	label(ribbon,text,Rect2(0,0,width,38),20,accent,HORIZONTAL_ALIGNMENT_CENTER)
	var tween = create_tween(); tween.tween_interval(0.35 if engine.state.settings.reducedMotion else 0.42)
	tween.tween_property(ribbon,"modulate:a",0.0,0.08); tween.tween_callback(ribbon.queue_free)

func combat_pulse(kind: String, rect: Rect2, accent: Color, strong: bool = false):
	var stroke = CombatStroke.new(); fx.add_child(stroke); stroke.name = "CombatPulse"
	stroke.kind = kind; stroke.target = combat_center(rect); stroke.accent = accent; stroke.strong = strong
	stroke.still = engine.state.settings.reducedMotion
	var tween = create_tween(); tween.tween_property(stroke,"progress",1.0,0.28 if stroke.still else 0.48)
	tween.tween_callback(stroke.queue_free)

func strike(enemy: bool, strong: bool = false):
	var stroke = CombatStroke.new(); fx.add_child(stroke); stroke.name = "CombatStrike"
	stroke.origin = combat_center(enemy_rect if enemy else player_rect)
	stroke.target = combat_center(player_rect if enemy else enemy_rect)
	stroke.accent = RED if enemy else Color("577e86"); stroke.strong = strong
	stroke.still = engine.state.settings.reducedMotion
	var tween = create_tween(); tween.tween_property(stroke,"progress",1.0,0.28 if stroke.still else 0.47); tween.tween_callback(stroke.queue_free)
	if stroke.still: return
	var actor = canvas.find_child("EnemyArt" if enemy else "PlayerArt",true,false)
	if actor != null:
		var direction = -1 if enemy else 1
		var movement = create_tween()
		movement.tween_property(actor,"position:x",-4*direction,0.06)
		movement.tween_property(actor,"position:x",9*direction,0.07).set_trans(Tween.TRANS_CUBIC)
		movement.tween_property(actor,"position:x",0.0,0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func hit_actor(enemy_attack: bool, strong: bool):
	var actor = canvas.find_child("PlayerArt" if enemy_attack else "EnemyArt",true,false)
	if actor == null: return
	actor.self_modulate = Color("ffb3a3")
	var flash = create_tween(); flash.tween_property(actor,"self_modulate",Color.WHITE,0.26)
	if engine.state.settings.reducedMotion: return
	var direction = -1 if enemy_attack else 1
	var recoil = create_tween()
	recoil.tween_property(actor,"position:x",(10 if strong else 7)*direction,0.055)
	recoil.tween_property(actor,"position:x",-3*direction,0.06)
	recoil.tween_property(actor,"position:x",2*direction,0.06)
	recoil.tween_property(actor,"position:x",0.0,0.12)

func play_sound(cue: String):
	if not engine.state.settings.sound: return
	var stream = load("res://assets/audio/"+cue+".wav")
	if stream == null: return
	var player = AudioStreamPlayer.new(); add_child(player); player.name = "CombatAudio"
	player.stream = stream; player.volume_db = -8 if cue in ["impact","defeat"] else -12
	player.finished.connect(player.queue_free); player.play()

func toast(message: String): feedback = message; render(true)

func show_error(message: String):
	if modal != null:
		var l = modal.find_child("ModalError",true,false)
		if l != null:
			l.text = message
			if view != "battle": l.visible = not message.is_empty()

func show_modal(title: String, description: String = "", actions: Array = [], required: bool = false, extra_height: float = 0) -> VBoxContainer:
	if busy: return null
	var focused = get_viewport().gui_get_focus_owner()
	if modal == null:
		modal_opener = focused; opener_name = str(focused.name) if focused != null else ""
	close_modal(true,false)
	modal_required = required
	modal = Control.new(); modal.name = "Dialog"; add_child(modal); modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim = ColorRect.new(); modal.add_child(dim); dim.color = Color(0.06,0.12,0.10,0.65); dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and not modal_required: close_modal())
	var safe = screen_area(); var vp = safe.size; var mw = minf(vp.x-24,480)
	var lines = 0
	for line in description.split("\n"): lines += maxi(1,ceili(line.length()/maxf(10,(mw-28)/17)))
	var mh = minf(vp.y-32,minf(570,maxf(230,lines*24+122+extra_height)))
	var box = PanelContainer.new(); modal.add_child(box); box.position = safe.position+(vp-Vector2(mw,mh))/2; box.size = Vector2(mw,mh)
	box.add_theme_stylebox_override("panel",style(PAPER,INK,2) if view == "battle" else menu_skin(Color("f8f1e0"),INK,1))
	var outer = VBoxContainer.new(); box.add_child(outer); outer.add_theme_constant_override("separation",8)
	var header = HBoxContainer.new(); outer.add_child(header)
	var heading_label = list_text(header,title,27 if view == "battle" else 25); heading_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not required: list_button(header,"×",close_modal,"","paper",44,"CloseDialog").custom_minimum_size.x = 44
	var ms = ScrollContainer.new(); outer.add_child(ms); ms.size_flags_vertical = Control.SIZE_EXPAND_FILL; ms.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var body = VBoxContainer.new(); ms.add_child(body); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation",8)
	if description: list_text(body,description,17 if view == "battle" else 15).custom_minimum_size.y = 50 if view == "battle" else 25
	var error_label = list_text(outer,"",14,RED); error_label.name = "ModalError"; error_label.custom_minimum_size.y = 22
	if view != "battle": error_label.hide()
	var footer = HBoxContainer.new(); outer.add_child(footer); footer.add_theme_constant_override("separation",8)
	for a in actions:
		var b = list_button(footer,a.text,a.cb,a.get("reason",""),a.get("kind","paper"),46,a.get("name","")); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	call_deferred("focus_modal")
	return body

func focus_modal():
	if modal == null: return
	var buttons = modal.find_children("*","Button",true,false)
	var enabled = []
	for b in buttons:
		if not b.disabled: enabled.append(b)
	for i in range(enabled.size()):
		enabled[i].focus_next = enabled[(i+1)%enabled.size()].get_path()
		enabled[i].focus_previous = enabled[(i-1+enabled.size())%enabled.size()].get_path()
	if not enabled.is_empty(): enabled[0].grab_focus()

func close_modal(force: bool = false, restore: bool = true):
	if modal == null or (modal_required and not force): return
	if guide_open:
		var checkpoint = guide_checkpoint
		guide_open = false; guide_checkpoint = ""
		if guide_replay:
			if checkpoint not in guide_replay_seen: guide_replay_seen.append(checkpoint)
		else:
			engine.dispatch({"type":"guideProgress","id":checkpoint}); save_progress()
	remove_child(modal); modal.queue_free(); modal = null; modal_required = false
	if restore:
		if is_instance_valid(modal_opener) and modal_opener.is_inside_tree(): modal_opener.grab_focus()
		elif opener_name and is_instance_valid(canvas):
			var b = canvas.find_child(opener_name,true,false)
			if b != null: b.grab_focus()
	call_deferred("maybe_show_guide")

func restore_focus_by_name():
	if modal != null or not is_instance_valid(canvas): return
	var b = canvas.find_child(opener_name,true,false)
	if b != null and b is Button and not b.disabled: b.grab_focus()

func battle_status(side: String):
	if busy or engine.state.battle == null: return
	var s = engine.state; var b = s.battle; var e = b.enemy; var st = engine.stats(); var text = ""
	if side == "player": text = "气血  %d / %d\n攻击  %d\n护盾  %d\n减伤  %d\n\n攻击为每枚剑玉的基础攻击。\n护盾在敌方行动后清空。"%[s.profile.hp,st.maxHp,st.attack,b.shield,st.armor]
	else:
		text = "气血  %d / %d\n临时护盾  %d\n当前行动  %s\n"%[e.hp,e.maxHp,e.shield,{"attack":"普攻","charge":"蓄力","guard":"守势","heavy":"重击"}[e.intentKind]]
		if e.intentKind == "charge": text += "本次伤害  0\n下次重击（已锁定）  %d"%e.nextDamage
		elif e.intentKind == "guard": text += "本次伤害  0\n将获得护盾  %d"%e.intentShield
		else: text += "攻击伤害  %d\n预计失血  %d"%[e.intent,maxi(0,e.intent-st.armor-b.shield)]
		text += "\n状态  "+("已激怒" if e.phase == "enraged" else "正常")+"\n\n临时护盾在敌方下次行动前消散。\n蓄力预告后进入激怒，不改变已锁定伤害。"
	if side == "player" and engine.rules_version(s) >= 3:
		var links = engine.link_state_text(s)
		text += "\n\n术式联动\n"+(links if not links.is_empty() else "当前没有待触发联动。")
	if side == "player":
		var cultivation = engine.cultivation_info(s)
		text += "\n\n修炼倾向\n"+cultivation.text
		text += "\n\n战斗效果来源\n"+engine.combat_sources_text(s)
	show_modal("我方状态" if side == "player" else "敌方状态",text,[{"text":"返回战斗","cb":close_modal,"kind":"green"}])

func skill_detail(id: String):
	var c = engine.cards[id]; var p = engine.state.profile
	var slot = p.deck.find(id)
	var reason = "本轮锁定" if engine.state.run != null else "尚未解锁" if p.collection[id] == 0 else "已装备于第%d槽"%(slot+1) if slot >= 0 else ""
	var description = engine.card_description(id)
	if engine.state.run != null and engine.rules_version() < 3: description += "\n\n本轮沿用旧规则，新的联动下轮生效。"
	var body = show_modal(c.name,"基础灵墨消耗：%d\n\n%s\n\n%s"%[c.cost,description,reason if reason else "已解锁 · 可装备"],[{"text":"装备至第%d槽"%(selected_slot+1),"cb":perform.bind({"type":"deckEquip","id":id,"slot":selected_slot}),"reason":reason,"kind":"green","name":"EquipSkill"}],false,120)
	if body != null:
		var art = TextureRect.new(); body.add_child(art); body.move_child(art,0); art.texture = skill_art(id); art.custom_minimum_size.y = 120; art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

func item_detail(id: String):
	var i = engine.items[id]; var p = engine.state.profile; var acts = []
	if i.kind in ["equipment","consumable"]:
		var action = {"type":"equip" if i.kind == "equipment" else "use","id":id}
		var reason = "已装备" if id in p.equipment.values() else engine.preflight(action)
		acts.append({"text":"装备" if i.kind == "equipment" else "使用","cb":item_action.bind(action),"reason":reason,"kind":"green","name":"ItemPrimary"})
	var sell = {"type":"sell","id":id}
	acts.append({"text":"出售 +"+str(engine.d.sellPrices[i.quality]),"cb":item_action.bind(sell),"reason":engine.preflight(sell),"name":"SellItem"})
	var body = show_modal(i.name,"%s · 持有 ×%d\n\n%s"%[i.quality,p.inventory[id],i.text],acts,false,120)
	if body != null:
		var art = TextureRect.new(); body.add_child(art); body.move_child(art,0); art.texture = item_art(id); art.custom_minimum_size.y = 120; art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

func item_action(action: Dictionary):
	if perform(action): item_detail(action.id)

func battle_bag():
	if busy or trial_active: return
	var body = show_modal("战中行囊","",[{"text":"返回战斗","cb":close_modal}],false,260)
	for i in engine.d.items:
		if i.kind != "consumable": continue
		list_text(body,i.name+" ×"+str(engine.state.profile.inventory[i.id])+"\n"+i.text,17)
		var a = {"type":"use","id":i.id}; list_button(body,"使用",battle_use.bind(a),engine.preflight(a),"green",44,"Use_"+i.id)

func battle_use(action: Dictionary):
	if perform(action): battle_bag()

func more_modal():
	var body = show_modal("山中诸事","修行、补给与记录，皆在此处。",[],false,300)
	var grid = GridContainer.new(); body.add_child(grid); grid.columns = 2
	grid.add_theme_constant_override("h_separation",8); grid.add_theme_constant_override("v_separation",8)
	var cell = (minf(screen_area().size.x-24,480)-36)/2
	var entries = [["修炼","cultivation",5],["云游行商","shop",6],["云笺录事","tasks",3],["历练记录","records",1],["初行指引","help",3],["设置与进度","settings",4]]
	for entry in entries:
		var cb = rules_modal if entry[1] == "help" else settings_modal if entry[1] == "settings" else goto.bind(entry[1])
		var b = list_button(grid,"",cb,"","paper",95,"More_"+entry[1])
		b.custom_minimum_size.x = cell; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		image(b,atlas("assets/home-ink-icons.png",4,2,entry[2]),Rect2((cell-53)/2,3,53,53))
		label(b,entry[0],Rect2(0,60,cell,30),19,INK,HORIZONTAL_ALIGNMENT_CENTER)

func rules_modal():
	if trial_active:
		var definition = engine.trial_definition(engine.state.trial.id)
		show_modal("试炼规则",definition.name+"\n获章条件："+definition.requirement+"\n当前指标：%d"%engine.trial_metric(definition,engine.state.run.summary)+"\n\n单章连续五战，首领击败后直接判定。角色、三式、法宝和种子固定，不使用普通成长与修炼倾向。\n\n相邻三枚消除；直线四枚及以上返步，每回合最多两步。三式可反复施放，敌方按已预告行动执行。\n\n可暂存返回普通历练，再从试炼入口继续。",[{"text":"返回战斗","cb":close_modal,"kind":"green"}]); return
	show_modal("初行指引","每关五只怪依次登场，第五只为最强首领。普通怪击败后直接接战，不需选路；首领击败后统一领取关卡奖励。\n\n相邻灵玉同色连成三枚消除，无效交换不扣步。直线四枚及以上消除返还1步，每回合最多返还2步。连锁每层增加15%收益。\n\n赤刃攻击，青木恢复，玄水护盾，金铢铜钱，紫灵补充灵墨（上限7）。\n\n三张常驻术式整轮锁定，灵墨足够可反复使用。新怪登场保留棋盘、灵墨、护盾和剩余步数；战胜恢复10%最大气血。击败首领后可整备再进入下一关，新关卡重新布置棋盘，气血延续。\n\n结束回合执行敌方已预告行动，护盾随后清空。点击人物查看完整状态。\n\n快捷键：1–3选术式，Enter确认，E结束回合，H提示，Esc关闭详情或暂停。",[{"text":"我已知晓","cb":close_modal,"kind":"green"},{"text":"分步重看","cb":guide_replay_modal,"name":"GuideReplay"}])

func settings_modal():
	var description = "试炼单独保存，暂存后可从试炼入口继续。" if trial_active else "进度自动保存在本机，退出后可继续。" if not save_blocked else "现有存档需要恢复。本次为临时试玩，不会写入新进度。"
	var body = show_modal("设置与进度",description,[{"text":"关闭","cb":close_modal}],false,240)
	if trial_active and not trial_warning.is_empty(): list_text(body,trial_warning,13,RED)
	elif save_blocked and not trial_active: list_button(body,"查看存档恢复提示",storage_warning_modal,"","paper",44,"StorageRecovery")
	elif not trial_active and not save_warning.is_empty(): list_text(body,save_warning,13,RED)
	var check = CheckButton.new(); body.add_child(check); check.text = "减少动态效果"; check.custom_minimum_size.y = 48; check.button_pressed = engine.state.settings.reducedMotion
	check.name = "ReducedMotion"
	refine_ink_toggle(check)
	check.add_theme_color_override("font_color",INK); check.add_theme_color_override("font_hover_color",RED)
	check.add_theme_color_override("font_pressed_color",INK); check.add_theme_color_override("font_focus_color",INK)
	check.toggled.connect(func(value):
		engine.dispatch({"type":"settings","id":"reducedMotion","value":value})
		save_progress())
	var sound = CheckButton.new(); body.add_child(sound); sound.name = "SoundToggle"; sound.text = "战斗音效"
	refine_ink_toggle(sound)
	sound.custom_minimum_size.y = 48; sound.button_pressed = engine.state.settings.sound
	for state_color in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: sound.add_theme_color_override(state_color,INK)
	sound.toggled.connect(func(value):
		engine.dispatch({"type":"settings","id":"sound","value":value})
		save_progress())
	if trial_active:
		list_text(body,"试炼角色固定，声音与动态设置仅用于本次试炼。",13,MUTED)
		list_button(body,"暂存并返回历练",pause_trial,"","paper",44,"TrialSettingsReturn")
		return
	list_button(body,"分步指引 · 重看",guide_replay_modal,"","paper",44,"SettingsGuideReplay")
	if guide_enabled(): list_button(body,"关闭分步提示",disable_guides,"","paper",44,"SettingsGuideSkip")
	list_button(body,"重开本轮历练",confirm_abandon,"" if engine.state.run != null else "当前没有历练","paper",48)
	list_button(body,"重置普通进度",confirm_reset,"请先恢复现有存档" if save_blocked else "","paper",48,"ResetNative")
	list_text(body,"重开本轮会保留成长与收藏。\n重置普通进度不删除独立试炼会话。",13)

func confirm_abandon():
	show_modal("结束本轮？","回到洞府后可重新装备术式。本轮关卡和法宝将结束。",[{"text":"取消","cb":close_modal},{"text":"结束历练","cb":perform.bind({"type":"abandon"}),"kind":"red"}])

func confirm_reset():
	show_modal("重置普通进度？","将重置普通角色、收藏和历练记录；独立试炼会话保留。已完成试炼的印章可重新补记。",[{"text":"取消","cb":close_modal},{"text":"重置普通进度","cb":reset_native,"kind":"red"}])

func reset_native():
	if trial_active: return
	if save_blocked: storage_warning_modal(); return
	engine.state = engine.create(int(Time.get_unix_time_from_system()) & 0xffffffff)
	guide_queue.clear(); guide_checkpoint = ""; guide_open = false; guide_replay = false; guide_replay_seen.clear()
	save_progress()
	close_modal(); selected_card = -1; view = "home"; render()

func run_detail():
	var r = engine.state.run; var text = "第%d关 · 第%d/5只\n本关战利铜钱 %d · 已交换 %d 步\n本轮携带术式：\n"%[r.chapter+1,r.wave,r.chapterCoins,r.moves]
	for id in r.deck: text += engine.cards[id].name+"  "
	text += "\n\n修炼倾向：\n"+engine.cultivation_info().text
	text += "\n\n本轮法宝：\n"
	for id in r.treasures: text += engine.treasures[id].name+"\n"
	if r.treasures.is_empty(): text += "尚未获得法宝"
	show_modal("此行所获",text,[{"text":"关闭","cb":close_modal},{"text":"结束历练","cb":confirm_abandon}])

func check_forced():
	if busy: return
	if trial_active:
		if engine.state.lastResult != null: trial_result_modal()
		return
	if engine.state.run != null and engine.state.run.pendingReward != null:
		var q = engine.state.run.pendingReward
		var description = "首领已击败，五战全部完成。\n本关战利铜钱 %d（已到账）。"%q.get("chapterCoins",q.coins)
		if q.has("fixedCard"):
			description += "\n固定术式：%s%s。"%[engine.cards[q.fixedCard].name,"已解锁" if q.fixedNew else "已拥有，转为20铜钱"]
		if not q.choices.is_empty(): description += "\n可再择一卷术式收藏，下轮可装备。"
		else: description += "\n全部术式已收藏，额外20铜钱已到账。"
		if q.get("legacyReward", false): description = "旧版战斗奖励：%s · %d铜钱已到账。\n领取后继续新的五战关卡。"%[q.enemy,q.coins]
		if q.chapterComplete and engine.state.run.chapter < 3: description += "\n领取后可修炼、购置，再开始下一关。"
		var continue_text = "完成四关" if engine.state.run.chapter == 3 and q.chapterComplete else "领取并整备" if q.chapterComplete else "继续接战"
		var body = show_modal("关卡告捷" if q.chapterComplete else "一战告捷",description,[{"text":"不选牌 · "+continue_text if not q.choices.is_empty() else continue_text,"cb":claim_stage_reward.bind(""),"kind":"green","name":"SkipReward"}],true,220)
		for id in q.choices:
			list_text(body,engine.cards[id].text,15)
			list_button(body,engine.cards[id].name+" · "+str(engine.cards[id].cost)+"墨",claim_stage_reward.bind(id),"","paper",56,"Reward_"+id)
	elif engine.state.lastResult != null:
		var r = engine.state.lastResult
		var summary = r.get("summary",{})
		var description = "本程抵达第%d境，交换%d步。\n%s\n\n铜钱、收藏和修炼成长已保留，三式可以重新装备。"%[r.chapter+1,r.moves,recap_compact(summary)]
		var advice = engine.recap_advice(summary) if not summary.is_empty() else ""
		if not advice.is_empty(): description += "\n\n"+advice
		var actions = [{"text":"返回洞府","cb":finish_result,"kind":"green","name":"FinishResult"},{"text":"查看复盘","cb":recap_detail.bind(summary,true),"name":"ResultRecap"}]
		if r.kind == "clear": actions.append({"text":"通关试炼","cb":open_trials_after_result,"name":"OpenTrialsAfterClear"})
		show_modal({"clear":"四境通关","defeat":"胜败乃寻常","abandon":"归山整装"}[r.kind],description,actions,true)

func claim_stage_reward(id: String):
	if perform({"type":"reward","id":id}):
		selected_card = -1
		if engine.state.battle != null: view = "battle"; render()
		elif engine.state.run != null: view = "map"; render()

func finish_result():
	if trial_active: pause_trial(); return
	close_modal(true); engine.dispatch({"type":"clearResult"})
	save_progress()
	view = "home"; render()
	guide_queue.clear()

func _unhandled_key_input(event: InputEvent):
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE:
		if modal != null: close_modal()
		elif view == "battle": pause_battle()
		else: goto("home")
		get_viewport().set_input_as_handled(); return
	if busy or modal != null or view != "battle" or engine.state.battle == null: return
	if event.keycode in [KEY_1,KEY_2,KEY_3]: select_card(engine.state.battle.hand[event.keycode-KEY_1].uid)
	elif event.keycode == KEY_ENTER: cast_selected()
	elif event.keycode == KEY_E: perform({"type":"endTurn"})
	elif event.keycode == KEY_H: hint()
