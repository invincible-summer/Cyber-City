## 原生工具 UI：地图菜单、画质选择、机位提示、加载遮罩。F1 整体隐藏。
extends CanvasLayer

signal map_requested(map_id: String)
signal unload_requested()
signal quality_requested(id: String)

var root_control: Control
var info_panel: PanelContainer
var map_label: Label
var quality_buttons: Dictionary = {}   # id -> Button
var hint_label: Label
var menu_panel: PanelContainer
var menu_box: VBoxContainer
var menu_map_box: VBoxContainer
var busy_label: Label
var cjk_font: SystemFont


func _init() -> void:
	layer = 10
	cjk_font = SystemFont.new()
	cjk_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "sans-serif"])

	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)

	_build_info_panel()
	_build_hint()
	_build_menu()


func _new_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", cjk_font)
	l.add_theme_font_size_override("font_size", size)
	return l


func _new_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", cjk_font)
	b.add_theme_font_size_override("font_size", 15)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _build_info_panel() -> void:
	info_panel = PanelContainer.new()
	info_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	info_panel.position = Vector2(14, 12)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.10, 0.72)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	info_panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	map_label = _new_label("霓湾 · Neon Haven", 17)
	map_label.add_theme_color_override("font_color", Color(0.88, 0.94, 0.95, 0.95))
	box.add_child(map_label)
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 6)
	for id in ["eco", "balanced"]:
		var b := _new_button("经济档" if id == "eco" else "均衡档")
		b.toggle_mode = true
		b.pressed.connect(func() -> void: quality_requested.emit(id))
		quality_buttons[id] = b
		qrow.add_child(b)
	box.add_child(qrow)
	info_panel.add_child(box)
	root_control.add_child(info_panel)


func _build_hint() -> void:
	hint_label = _new_label("右键拖动观察 · WASD/QE 移动 · Shift 加速 · 滚轮调速 · 1/2/3 机位 · Home 默认机位\nF1 隐藏 UI · F2 诊断 · F12 截图 · Esc 菜单", 14)
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position = Vector2(-560, -84)
	hint_label.custom_minimum_size = Vector2(1120, 0)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_color_override("font_color", Color(0.85, 0.92, 0.93, 0.8))
	root_control.add_child(hint_label)


func _build_menu() -> void:
	menu_panel = PanelContainer.new()
	menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.10, 0.94)
	style.border_color = Color(0.35, 0.77, 0.76, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	menu_panel.add_theme_stylebox_override("panel", style)
	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 8)
	var title := _new_label("霓湾 · 地图与工具", 22)
	title.add_theme_color_override("font_color", Color(0.35, 0.83, 0.81, 1.0))
	menu_box.add_child(title)
	menu_map_box = VBoxContainer.new()
	menu_map_box.add_theme_constant_override("separation", 4)
	menu_box.add_child(menu_map_box)
	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(360, 8)
	menu_box.add_child(sep)
	var reload := _new_button("重新进入当前地图")
	reload.pressed.connect(func() -> void:
		if not str(map_label.get_meta("map_id", "")).is_empty():
			map_requested.emit(str(map_label.get_meta("map_id"))))
	menu_box.add_child(reload)
	var unload := _new_button("卸载地图（回到空场景）")
	unload.pressed.connect(func() -> void: unload_requested.emit())
	menu_box.add_child(unload)
	var close := _new_button("关闭菜单")
	close.pressed.connect(func() -> void: menu_panel.visible = false)
	menu_box.add_child(close)
	busy_label = _new_label("", 14)
	busy_label.add_theme_color_override("font_color", Color(0.96, 0.73, 0.43, 1.0))
	menu_box.add_child(busy_label)
	menu_panel.add_child(menu_box)
	menu_panel.visible = false
	root_control.add_child(menu_panel)


func set_map_info(map_id: String, display_name: String) -> void:
	map_label.text = "霓湾 · %s" % display_name
	map_label.set_meta("map_id", map_id)


func set_map_entries(entries: Array) -> void:
	## entries: [{id, display_name, available}]
	for child in menu_map_box.get_children():
		menu_map_box.remove_child(child)
		child.queue_free()
	for entry in entries:
		var b := _new_button("进入 %s (%s)" % [entry.get("display_name", entry.get("id", "?")), entry.get("id", "?")])
		var mid: String = entry.get("id", "")
		b.pressed.connect(func() -> void: map_requested.emit(mid))
		menu_map_box.add_child(b)


func set_quality(id: String, label_text: String) -> void:
	for k in quality_buttons:
		var b: Button = quality_buttons[k]
		b.button_pressed = (k == id)


func set_busy(busy: bool, text: String = "") -> void:
	busy_label.text = text if busy else ""
	if busy:
		menu_panel.visible = true


func set_loading_progress(progress: float) -> void:
	busy_label.text = "地图加载中… %d%%" % int(clampf(progress, 0.0, 1.0) * 100.0)


func toggle_menu() -> void:
	menu_panel.visible = not menu_panel.visible


func is_menu_open() -> bool:
	return menu_panel.visible


func set_visible_all(flag: bool) -> void:
	root_control.visible = flag


func is_ui_visible() -> bool:
	return root_control.visible
