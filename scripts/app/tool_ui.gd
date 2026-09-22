## 原生工具 UI：地图菜单、画质选择、机位提示、书签、加载遮罩。F1 整体隐藏。
extends CanvasLayer

signal map_requested(map_id: String)
signal unload_requested()
signal quality_requested(id: String)
signal bookmark_save_requested(label: String)
signal bookmark_load_requested(bookmark_id: String)
signal bookmark_delete_requested(bookmark_id: String)

var root_control: Control
var info_panel: PanelContainer
var map_label: Label
var quality_buttons: Dictionary = {}   # id -> Button
var hint_label: Label
var portal_label: Label
var menu_panel: PanelContainer
var menu_box: VBoxContainer
var menu_map_box: VBoxContainer
var bookmark_box: VBoxContainer
var bookmark_input: LineEdit
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
	hint_label = _new_label("右键拖动观察 · WASD/QE 移动 · Shift 加速 · 滚轮调速 · 1–6 机位 · Home 默认机位\nF1 隐藏 UI · F2 诊断 · F12 截图 · Esc 菜单/书签", 14)
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position = Vector2(-560, -84)
	hint_label.custom_minimum_size = Vector2(1120, 0)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_color_override("font_color", Color(0.85, 0.92, 0.93, 0.8))
	root_control.add_child(hint_label)
	# 门户提示（chapter1-2 §4.4）：进入门户半径时出现
	portal_label = _new_label("", 20)
	portal_label.set_anchors_preset(Control.PRESET_CENTER)
	portal_label.position = Vector2(-260, 96)
	portal_label.custom_minimum_size = Vector2(520, 0)
	portal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portal_label.add_theme_color_override("font_color", Color(0.45, 0.92, 0.89, 0.96))
	portal_label.visible = false
	root_control.add_child(portal_label)


func show_portal_hint(text: String) -> void:
	portal_label.text = text
	portal_label.visible = true


func hide_portal_hint() -> void:
	portal_label.visible = false
	portal_label.text = ""


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
	# 书签区
	var bm_title := _new_label("摄影书签（当前地图最多 12 个）", 15)
	menu_box.add_child(bm_title)
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 6)
	bookmark_input = LineEdit.new()
	bookmark_input.placeholder_text = "书签名称（1–40 字）"
	bookmark_input.custom_minimum_size = Vector2(220, 0)
	bookmark_input.add_theme_font_override("font", cjk_font)
	bookmark_input.add_theme_font_size_override("font_size", 14)
	save_row.add_child(bookmark_input)
	var save_btn := _new_button("保存当前视角")
	save_btn.pressed.connect(func() -> void:
		bookmark_save_requested.emit(bookmark_input.text)
		bookmark_input.text = "")
	save_row.add_child(save_btn)
	menu_box.add_child(save_row)
	bookmark_box = VBoxContainer.new()
	bookmark_box.add_theme_constant_override("separation", 3)
	menu_box.add_child(bookmark_box)
	var sep2 := HSeparator.new()
	sep2.custom_minimum_size = Vector2(360, 8)
	menu_box.add_child(sep2)
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
	busy_label.custom_minimum_size = Vector2(360, 0)
	busy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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


func set_bookmarks(entries: Array, current_revision: String = "") -> void:
	## entries: [{id, label, map_id, content_revision, created_utc}]
	## §15 修订标签：entry revision == 当前地图 revision → 无标签；
	## 非空且不同 → [旧 rX]；为空 → [旧 未知]（仍可加载，兼容风险提示交给 validate_pose）。
	for child in bookmark_box.get_children():
		bookmark_box.remove_child(child)
		child.queue_free()
	if entries.is_empty():
		var empty := _new_label("（暂无书签）", 13)
		empty.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 0.8))
		bookmark_box.add_child(empty)
		return
	for entry in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var bm_id: String = entry.get("id", "")
		var rev: String = entry.get("content_revision", "")
		var label_text: String = entry.get("label", "?")
		if rev.is_empty():
			label_text += " [旧 未知]"
		elif rev != current_revision:
			label_text += " [旧 r%s]" % rev
		var load_btn := _new_button("▶ %s" % label_text)
		load_btn.pressed.connect(func() -> void: bookmark_load_requested.emit(bm_id))
		row.add_child(load_btn)
		var del_btn := _new_button("×")
		del_btn.tooltip_text = "删除"
		del_btn.pressed.connect(func() -> void: bookmark_delete_requested.emit(bm_id))
		row.add_child(del_btn)
		bookmark_box.add_child(row)


func set_quality(id: String, _label_text: String) -> void:
	for k in quality_buttons:
		var b: Button = quality_buttons[k]
		b.button_pressed = (k == id)


func set_anchor_hint(anchor_names: PackedStringArray, walk_mode: bool = false) -> void:
	var move_hint := "右键拖动观察 · WASD 步行 · Shift 快走 · 滚轮调速 · 楼梯可直接走上/走下"
	if not walk_mode:
		move_hint = "右键拖动观察 · WASD/QE 移动 · Shift 加速 · 滚轮调速 · Home 默认"
	if anchor_names.is_empty():
		hint_label.text = "右键拖动观察 · WASD/QE 移动 · Shift 加速 · 滚轮调速\nF1 隐藏 UI · F2 诊断 · F12 截图 · Esc 菜单/书签"
		return
	# §14.2：数字快捷键只有 1–9；超过 9 个的锚点不伪造数字键提示
	var parts := PackedStringArray()
	for i in mini(anchor_names.size(), 9):
		parts.append("%d=%s" % [i + 1, anchor_names[i]])
	hint_label.text = "%s\n%s\nF1 隐藏 UI · F2 诊断 · F12 截图 · Esc 菜单/书签" % [move_hint, " · ".join(parts)]


func set_busy(busy: bool, text: String = "") -> void:
	busy_label.text = text if busy else ""
	menu_panel.visible = busy


func show_transient_message(text: String) -> void:
	## 菜单打开时显示在菜单内；否则短暂弹出提示后关闭。
	if menu_panel.visible:
		busy_label.text = text
	else:
		menu_panel.visible = true
		busy_label.text = text
		var timer := get_tree().create_timer(2.5)
		timer.timeout.connect(func() -> void:
			if busy_label.text == text:
				busy_label.text = ""
				menu_panel.visible = false)


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
