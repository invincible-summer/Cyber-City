## 中文招牌纹理生成（制作阶段工具，需窗口运行以使用 SubViewport 渲染）。
## 运行：godot --path . res://tools/run_gen_signs.tscn
## 字体：项目内固定可再分发字体（chapter1-1 FIX-10）：Noto Sans SC（OFL 1.1）。
## 同输入必产同输出；许可与哈希记录见 docs/asset_sources.md。
extends Node

const OUT := "res://assets/m01_afterglow/textures/signs"
const FONT_PATH := "res://assets/fonts/source/NotoSansSC-Regular.otf"

var _font: Font


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_font = load(FONT_PATH) as Font
	if _font == null:
		push_error("固定字体加载失败: %s（先 --headless --import）" % FONT_PATH)
		get_tree().quit(1)
		return

	await _sign_main()
	await _sign_small()
	print("SIGNS_DONE")
	get_tree().quit()


func _begin(w: int, h: int, bg: Color, border: Color, bw: int, radius: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	if radius > 0:
		sb.set_corner_radius_all(radius)
	panel.add_theme_stylebox_override("panel", sb)
	vp.add_child(panel)
	return vp


func _label(parent: Control, text: String, color: Color, size: int, top: int, bottom: int) -> Label:
	## 全矩形 Label，通过 top/bottom 内缩控制垂直位置（单位 px）。
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", maxf(2.0, size / 28.0))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	l.offset_top = top
	l.offset_bottom = -bottom
	parent.add_child(l)
	return l


func _finish(vp: SubViewport, name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, name])
	print("sign: ", name, " ", img.get_size())
	vp.queue_free()
	await get_tree().process_frame


func _sign_main() -> void:
	# 余晖维修（修理店主招牌）
	var vp := _begin(1024, 256, Color(0.07, 0.075, 0.1), Color(1.0, 0.62, 0.3), 8, 4)
	_label(vp.get_child(0), "余 晖 维 修", Color(1.0, 0.72, 0.42), 150, 0, 58)
	_label(vp.get_child(0), "AFTERGLOW REPAIR", Color(0.85, 0.66, 0.5), 30, 192, 8)
	await _finish(vp, "repair_main")

	# 霓湾站（高架站名牌）
	vp = _begin(1024, 256, Color(0.03, 0.09, 0.1), Color(0.5, 0.9, 0.88), 8, 4)
	_label(vp.get_child(0), "霓 湾 站", Color(0.62, 0.93, 0.9), 160, 0, 58)
	_label(vp.get_child(0), "NEON HAVEN STATION", Color(0.55, 0.78, 0.78), 26, 196, 8)
	await _finish(vp, "station_main")

	# 海风便利
	vp = _begin(1024, 256, Color(0.04, 0.1, 0.14), Color(0.45, 0.85, 0.82), 8, 4)
	_label(vp.get_child(0), "海 风 便 利", Color(0.93, 0.98, 0.96), 150, 0, 58)
	_label(vp.get_child(0), "SEABREEZE MART · 24H", Color(0.66, 0.85, 0.83), 28, 194, 8)
	await _finish(vp, "convenience")

	# 湾流洗衣（生活广场主招牌，chapter1-1 §3.3）
	vp = _begin(1024, 256, Color(0.05, 0.1, 0.11), Color(0.5, 0.9, 0.88), 8, 4)
	_label(vp.get_child(0), "湾 流 洗 衣", Color(0.78, 0.96, 0.94), 150, 0, 58)
	_label(vp.get_child(0), "BAYFLOW LAUNDRY · 自助/取送", Color(0.6, 0.84, 0.82), 26, 196, 8)
	await _finish(vp, "laundry")

	# 岬角咖啡
	vp = _begin(768, 256, Color(0.12, 0.08, 0.06), Color(0.95, 0.78, 0.55), 6, 4)
	_label(vp.get_child(0), "岬 角 咖 啡", Color(0.97, 0.86, 0.66), 120, 0, 58)
	_label(vp.get_child(0), "CAPE COFFEE", Color(0.8, 0.65, 0.5), 26, 196, 8)
	await _finish(vp, "cafe")


func _sign_small() -> void:
	# 老巷面馆
	var vp := _begin(768, 224, Color(0.1, 0.07, 0.05), Color(1.0, 0.68, 0.4), 6, 4)
	_label(vp.get_child(0), "老 巷 面 馆", Color(1.0, 0.8, 0.52), 110, 0, 0)
	await _finish(vp, "noodle")

	# 临港药房
	vp = _begin(768, 224, Color(0.05, 0.11, 0.08), Color(0.6, 0.95, 0.7), 6, 4)
	_label(vp.get_child(0), "临 港 药 房 ＋", Color(0.8, 0.98, 0.86), 110, 0, 0)
	await _finish(vp, "pharmacy")

	# 蓝鸟电器
	vp = _begin(768, 224, Color(0.04, 0.07, 0.13), Color(0.55, 0.72, 1.0), 6, 4)
	_label(vp.get_child(0), "蓝 鸟 电 器", Color(0.75, 0.86, 1.0), 110, 0, 0)
	await _finish(vp, "electronics")

	# 汽水铺
	vp = _begin(768, 224, Color(0.12, 0.06, 0.04), Color(1.0, 0.55, 0.35), 6, 4)
	_label(vp.get_child(0), "汽 水 铺", Color(1.0, 0.75, 0.5), 110, 0, 0)
	await _finish(vp, "soda")

	# 湾区旅社（竖排）
	vp = _begin(256, 1024, Color(0.09, 0.05, 0.1), Color(0.95, 0.68, 0.85), 6, 4)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	vp.get_child(0).add_child(box)
	for ch in "湾区旅社":
		var l := Label.new()
		l.text = ch
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", _font)
		l.add_theme_font_size_override("font_size", 120)
		l.add_theme_color_override("font_color", Color(0.98, 0.78, 0.92))
		box.add_child(l)
	await _finish(vp, "hotel_v")

	# 酒（竖排小霓虹）
	vp = _begin(192, 768, Color(0.06, 0.02, 0.02), Color(1.0, 0.25, 0.2), 6, 3)
	var l2 := Label.new()
	l2.set_anchors_preset(Control.PRESET_FULL_RECT)
	l2.text = "酒"
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l2.add_theme_font_override("font", _font)
	l2.add_theme_font_size_override("font_size", 150)
	l2.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	vp.get_child(0).add_child(l2)
	await _finish(vp, "bar_v")

	# ---- chapter1-2 §5.2：街面丰富 A 牌字图（非发光白板/黑板风） ----
	# 今日特惠（便利店外摆 A 字立牌，G3）
	vp = _begin(384, 512, Color(0.92, 0.90, 0.86), Color(0.35, 0.28, 0.22), 10, 6)
	_label(vp.get_child(0), "今日特惠", Color(0.22, 0.16, 0.10), 86, 56, 0)
	_label(vp.get_child(0), "全场九折", Color(0.55, 0.18, 0.12), 64, 190, 0)
	_label(vp.get_child(0), "海风便利", Color(0.35, 0.30, 0.26), 44, 330, 0)
	await _finish(vp, "special")

	# 营业中（维修铺广场 A 板，G4）
	vp = _begin(384, 512, Color(0.10, 0.07, 0.06), Color(1.0, 0.62, 0.32), 10, 6)
	_label(vp.get_child(0), "营业中", Color(1.0, 0.80, 0.52), 96, 96, 0)
	_label(vp.get_child(0), "余晖维修", Color(0.88, 0.76, 0.64), 54, 268, 0)
	_label(vp.get_child(0), "WALK-IN", Color(0.55, 0.48, 0.42), 30, 356, 0)
	await _finish(vp, "open_board")
