## 应用外壳：MapSlot + 相机 Rig + 工具 UI + 加载遮罩 + 诊断 + 设置。
## 支持命令行自动化（项目运行）：`-- --shoot [--graybox] [--quality eco|balanced|both]`
## 与 `-- --perf [--quality ...] [--runs N] [--occlusion on|off]`。
extends Node3D

const AUTO_MAP_ID := "m01_afterglow"

var map_slot: Node3D
var camera_rig: Node3D            # camera_controller.gd
var camera_ctl                    # camera_controller 实例（弱类型以便测试替换）
var tool_ui: CanvasLayer          # tool_ui.gd
var loading_overlay: CanvasLayer
var loading_label: Label
var diagnostics                   # diagnostics.gd
var settings                      # settings_manager.gd
var map_manager: Node             # map_manager.gd

var _ui_hidden := false
var _focus_throttled := false
var _was_minimized := false
var _perf_rows: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_shell()

	settings = get_node("SettingsManager")
	map_manager = get_node("MapManager")
	map_manager.setup(map_slot)
	map_manager.load_registry_file("res://data/map_registry.json")
	_wire_signals()

	_refresh_map_menu()
	# 手动同步一次画质 UI（SettingsManager 在 _ready 中发信号时本节点尚未接线）
	_on_quality_changed(settings.get_profile())

	var args := OS.get_cmdline_user_args()
	if args.has("--perf"):
		map_manager.request_map(AUTO_MAP_ID)
		_run_automation_perf(args)
	elif args.has("--shoot"):
		map_manager.request_map(AUTO_MAP_ID)
		_run_automation_shoot(args)
	else:
		map_manager.request_map(AUTO_MAP_ID)


func _build_shell() -> void:
	map_slot = Node3D.new()
	map_slot.name = "MapSlot"
	add_child(map_slot)

	var rig := Node3D.new()
	rig.name = "CameraRig"
	add_child(rig)
	var ctl_script := load("res://scripts/app/camera_controller.gd")
	camera_ctl = ctl_script.new()
	rig.add_child(camera_ctl)

	var sm := Node.new()
	sm.name = "SettingsManager"
	sm.set_script(load("res://scripts/app/settings_manager.gd"))
	add_child(sm)

	var mm := Node.new()
	mm.name = "MapManager"
	mm.set_script(load("res://scripts/maps/map_manager.gd"))
	mm.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(mm)

	var ui_script := load("res://scripts/app/tool_ui.gd")
	tool_ui = ui_script.new()
	add_child(tool_ui)

	loading_overlay = CanvasLayer.new()
	loading_overlay.layer = 20
	loading_overlay.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading_overlay.add_child(dim)
	loading_label = Label.new()
	loading_label.text = "地图加载中…"
	loading_label.set_anchors_preset(Control.PRESET_CENTER)
	loading_label.position = Vector2(-140, -20)
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.custom_minimum_size = Vector2(280, 0)
	loading_label.add_theme_font_size_override("font_size", 20)
	loading_label.add_theme_color_override("font_color", Color(0.9, 0.94, 0.95, 1.0))
	loading_overlay.add_child(loading_label)
	add_child(loading_overlay)

	var diag_layer := CanvasLayer.new()
	diag_layer.layer = 11
	add_child(diag_layer)
	var diag_script := load("res://scripts/app/diagnostics.gd")
	diagnostics = diag_script.new()
	diag_layer.add_child(diagnostics)

	var shot := Node.new()
	shot.name = "ScreenshotTool"
	shot.set_script(load("res://scripts/app/screenshot_tool.gd"))
	add_child(shot)


func _wire_signals() -> void:
	map_manager.map_loading.connect(_on_map_loading)
	map_manager.map_loaded.connect(_on_map_loaded)
	map_manager.map_failed.connect(_on_map_failed)
	tool_ui.map_requested.connect(func(mid: String) -> void: map_manager.request_map(mid))
	tool_ui.unload_requested.connect(func() -> void:
		map_manager.unload_current_map()
		tool_ui.toggle_menu())
	tool_ui.quality_requested.connect(func(id: String) -> void: settings.set_quality(id))
	settings.quality_changed.connect(_on_quality_changed)


func _refresh_map_menu() -> void:
	var entries: Array = []
	for mid in map_manager.get_available_map_ids():
		var def = map_manager.get_definition(mid)
		if def != null:
			entries.append({"id": mid, "display_name": def.display_name, "available": def.available})
	tool_ui.set_map_entries(entries)


func _on_quality_changed(profile: Dictionary) -> void:
	tool_ui.set_quality(str(profile.get("id", "eco")), str(profile.get("label", "")))
	var roots := get_tree().get_nodes_in_group("active_map_root")
	for r in roots:
		if r is MapRoot:
			(r as MapRoot).apply_quality(profile)
	var v: Viewport = get_viewport()
	v.use_occlusion_culling = not _occlusion_forced_off


func _on_map_loading(map_id: String, progress: float) -> void:
	loading_overlay.visible = true
	loading_label.text = "地图加载中… %d%%" % int(clampf(progress, 0.0, 1.0) * 100.0)
	camera_ctl.enabled = false
	tool_ui.set_busy(true, "地图加载中…")


func _on_map_loaded(map_id: String) -> void:
	loading_overlay.visible = false
	tool_ui.set_busy(false)
	camera_ctl.enabled = true
	var def: MapDefinition = map_manager.get_definition(map_id)
	var roots := get_tree().get_nodes_in_group("active_map_root")
	if roots.is_empty() or def == null:
		return
	var map_root := roots[0] as MapRoot
	tool_ui.set_map_info(map_id, def.display_name)
	# 相机边界与机位：持有 Transform3D 值，不持有地图锚点节点
	var anchor_transforms := {}
	for anchor in def.anchor_names:
		anchor_transforms[anchor] = map_root.get_anchor_transform(anchor)
	camera_ctl.set_map_data(def.camera_bounds, def.camera_exclusion_bounds, def.anchor_names, def.default_anchor, anchor_transforms)
	camera_ctl.go_to_default_anchor()
	map_root.apply_quality(settings.get_profile())
	diagnostics.set_map_node_count(_count_nodes(map_root))
	diagnostics.set_extra_info("地图 %s | 资源加载 %.0f ms | 激活 %.0f ms" % [map_id, map_manager.last_resource_load_ms, map_manager.last_activation_ms])


func _on_map_failed(map_id: String, reason: String) -> void:
	loading_overlay.visible = false
	tool_ui.set_busy(false)
	camera_ctl.enabled = true
	tool_ui.set_map_info("", "未加载地图")
	camera_ctl.clear_map_data()
	tool_ui.set_busy(true, "加载失败：%s\n可从下方菜单重试或返回空场景。" % reason)


func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count


# ---------------- 输入 ----------------

var _occlusion_forced_off := false


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and not tool_ui.is_menu_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey:
		camera_ctl.handle_key(event)
		if event.pressed and not event.echo:
			_handle_key(event.keycode)


func _handle_key(key: Key) -> void:
	match key:
		KEY_1, KEY_2, KEY_3:
			if not tool_ui.is_menu_open():
				var idx := (key - KEY_1) as int
				var names: PackedStringArray = camera_ctl._anchor_order
				if idx >= 0 and idx < names.size():
					camera_ctl.go_to_anchor(names[idx])
		KEY_HOME:
			camera_ctl.go_to_default_anchor()
		KEY_F1:
			_ui_hidden = not _ui_hidden
			tool_ui.set_visible_all(not _ui_hidden)
			(diagnostics.get_parent() as CanvasLayer).visible = not _ui_hidden
		KEY_F2:
			diagnostics.visible = not diagnostics.visible
		KEY_F12:
			_take_screenshot(false)
		KEY_ESCAPE:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				tool_ui.toggle_menu()
		_:
			pass


func _take_screenshot(diag_variant: bool) -> void:
	var shot := get_node("ScreenshotTool")
	var layers: Array = []
	if not diag_variant:
		layers = [tool_ui, diagnostics.get_parent()]
	var view := "free_camera"
	var roots := get_tree().get_nodes_in_group("active_map_root")
	if roots.size() > 0:
		var map_root := roots[0] as MapRoot
		# 粗略判断当前是否处于某个锚点附近
		var ct: Transform3D = camera_ctl.get_camera_global_transform()
		for anchor in camera_ctl._anchor_order:
			var at: Transform3D = map_root.get_anchor_transform(anchor)
			if at.origin.distance_to(ct.origin) < 0.6:
				view = anchor
				break
	var path: String = await shot.take_screenshot(layers, map_manager.current_map_id, view if not diag_variant else view + "_diag", settings.current_quality)
	if not path.is_empty():
		print("截图已保存: ", path)


# ---------------- 焦点与最小化 ----------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focus_throttled = true
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		settings.apply_focus_throttle(true, _was_minimized)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focus_throttled = false
		settings.apply_focus_throttle(false, _was_minimized)


func _process(_delta: float) -> void:
	var minimized := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED
	if minimized != _was_minimized:
		_was_minimized = minimized
		get_tree().paused = minimized  # 最小化暂停环境动画
		settings.apply_focus_throttle(_focus_throttled, minimized)


# ---------------- 自动化：截图 ----------------

func _run_automation_shoot(args: PackedStringArray) -> void:
	await _await_map_ready()
	var tiers: Array[String] = _tier_args(args, ["eco", "balanced"])
	var graybox := args.has("--graybox")
	var out_dir := "res://artifacts/screenshots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var shot := get_node("ScreenshotTool")

	if graybox:
		var gray := StandardMaterial3D.new()
		gray.albedo_color = Color(0.62, 0.63, 0.66)
		gray.roughness = 1.0
		var roots := get_tree().get_nodes_in_group("active_map_root")
		var map_root := roots[0] as MapRoot
		_apply_override(map_root, gray)
		await _shoot_anchors(shot, "graybox", out_dir)
		_apply_override(map_root, null)

	for tier in tiers:
		settings.set_quality(tier)
		await get_tree().create_timer(0.6).timeout
		await _shoot_anchors(shot, tier, out_dir)
	print("SHOOT_DONE")
	get_tree().quit()


func _shoot_anchors(shot: Node, tier: String, out_dir: String) -> void:
	for anchor in camera_ctl._anchor_order:
		camera_ctl.go_to_anchor(anchor)
		await get_tree().create_timer(0.45).timeout
		var layers: Array = [tool_ui, diagnostics.get_parent()]
		var path: String = await shot.take_screenshot(layers, map_manager.current_map_id, anchor, tier)
		print("自动截图: ", path)
	# 一张带诊断的验证图（清晰区分用途）
	if camera_ctl._anchor_order.size() > 0:
		camera_ctl.go_to_anchor(camera_ctl._anchor_order[0])
		await get_tree().create_timer(0.3).timeout
		diagnostics.visible = true
		var path: String = await shot.take_screenshot([tool_ui], map_manager.current_map_id, camera_ctl._anchor_order[0] + "_diag", tier)
		diagnostics.visible = false
		print("诊断截图: ", path)


func _apply_override(root: Node, mat: Material) -> void:
	for child in root.get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).material_override = mat
		if child is Node:
			_apply_override(child, mat)


# ---------------- 自动化：性能路线 ----------------

func _run_automation_perf(args: PackedStringArray) -> void:
	await _await_map_ready()
	var tiers: Array[String] = _tier_args(args, ["eco", "balanced"])
	var runs := 3
	for i in range(args.size()):
		if args[i] == "--runs" and i + 1 < args.size():
			runs = clampi(int(args[i + 1]), 1, 10)
	for i in range(args.size()):
		if args[i] == "--occlusion" and i + 1 < args.size():
			_occlusion_forced_off = args[i + 1] == "off"
			get_viewport().use_occlusion_culling = not _occlusion_forced_off

	print("PERF warmup 15s …")
	await get_tree().create_timer(15.0).timeout
	for tier in tiers:
		settings.set_quality(tier)
		await get_tree().create_timer(2.0).timeout
		for r in runs:
			await _run_one_route(tier, r + 1)
	_write_perf_csv()
	print("PERF_DONE")
	get_tree().quit()


func _await_map_ready() -> void:
	while map_manager.state != 1:  # MapManager.State.READY
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout


func _tier_args(args: PackedStringArray, defaults: Array[String]) -> Array[String]:
	var tiers: Array[String] = []
	for i in range(args.size()):
		if args[i] == "--quality" and i + 1 < args.size():
			if args[i + 1] == "both":
				tiers = defaults.duplicate()
			else:
				tiers = [args[i + 1]]
	if tiers.is_empty():
		tiers = defaults.duplicate()
	return tiers


const ROUTE_SEGMENTS := [
	{"p0": Vector3(-3, 1.7, 52), "p1": Vector3(-3, 1.7, 20), "look": Vector3(1, 8, -45)},
	{"p0": Vector3(15, 1.8, 31), "p1": Vector3(19, 2.0, 29), "look": Vector3(33, 2.5, 25)},
	{"p0": Vector3(18, 12, -35), "p1": Vector3(14, 13, -38), "look": Vector3(0, 12, -62)},
]


func _route_transform(t: float) -> Transform3D:
	## 60 秒固定路线，三段明确切镜，时间驱动、与帧率无关。
	var seg := int(clampf(t, 0.0, 59.999) / 20.0)
	var local := clampf(t - seg * 20.0, 0.0, 20.0) / 20.0
	var s: Dictionary = ROUTE_SEGMENTS[seg]
	var pos: Vector3 = s["p0"].lerp(s["p1"], local)
	var xf := Transform3D(Basis(), pos)
	return xf.looking_at(s["look"], Vector3.UP)


func _run_one_route(tier: String, run_index: int) -> void:
	diagnostics.begin_sampling()
	var elapsed := 0.0
	while elapsed < 60.0:
		var delta: float = get_process_delta_time()
		elapsed += delta
		camera_ctl.set_route_transform(_route_transform(elapsed))
		await get_tree().process_frame
	var stats: Dictionary = diagnostics.end_sampling()
	var row := {
		"run_id": "%s_%s_r%d_%s" % [tier, "m01", run_index, Time.get_datetime_string_from_system(false, false).replace("-", "")],
		"map_id": "m01_afterglow", "quality": tier,
		"renderer": diagnostics.get_renderer_name(), "build_type": "project_run",
		"engine_version": str(Engine.get_version_info().get("string", "")),
		"window_width": int(get_window().size.x), "window_height": int(get_window().size.y),
		"render_scale": float(settings.get_profile().get("render_scale", 1.0)),
		"frame_cap": int(settings.get_profile().get("max_fps", 0)),
		"average_fps": stats.get("avg_fps", 0.0),
		"frame_interval_p50_ms": stats.get("p50_ms", 0.0),
		"frame_interval_p95_ms": stats.get("p95_ms", 0.0),
		"frame_interval_p99_ms": stats.get("p99_ms", 0.0),
		"stutter_over_100ms_count": int(stats.get("stutter_over_100ms", 0)),
		"draw_calls_peak": int(stats.get("draw_call_peak", 0)),
		"map_node_count": 0,
		"process_working_set_mib": "N/A",
		"gpu_memory_mib": roundf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)),
		"resource_load_ms": map_manager.last_resource_load_ms,
		"activation_ms": map_manager.last_activation_ms,
		"notes": "gpu_memory 为引擎估计;工作集需外部测量;遮挡剔除 %s" % ("关闭" if _occlusion_forced_off else "开启"),
	}
	var roots := get_tree().get_nodes_in_group("active_map_root")
	if roots.size() > 0:
		row["map_node_count"] = _count_nodes(roots[0])
	_perf_rows.append(row)
	print("路线完成: ", row["run_id"], " avg_fps=", row["average_fps"])


const CSV_HEADER := "run_id,map_id,quality,renderer,build_type,engine_version,window_width,window_height,render_scale,frame_cap,average_fps,frame_interval_p50_ms,frame_interval_p95_ms,frame_interval_p99_ms,stutter_over_100ms_count,draw_calls_peak,map_node_count,process_working_set_mib,gpu_memory_mib,resource_load_ms,activation_ms,notes"


func _write_perf_csv() -> void:
	var dir := "res://artifacts/performance"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + "/chapter1_metrics.csv"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_line(CSV_HEADER)
	for row in _perf_rows:
		var cols := [
			row["run_id"], row["map_id"], row["quality"], row["renderer"], row["build_type"],
			row["engine_version"], str(row["window_width"]), str(row["window_height"]),
			str(row["render_scale"]), str(row["frame_cap"]), "%.2f" % float(row["average_fps"]),
			"%.2f" % float(row["frame_interval_p50_ms"]), "%.2f" % float(row["frame_interval_p95_ms"]),
			"%.2f" % float(row["frame_interval_p99_ms"]), str(row["stutter_over_100ms_count"]),
			str(row["draw_calls_peak"]), str(row["map_node_count"]), str(row["process_working_set_mib"]),
			str(row["gpu_memory_mib"]), "%.1f" % float(row["resource_load_ms"]),
			"%.1f" % float(row["activation_ms"]), '"%s"' % str(row["notes"]),
		]
		f.store_line(",".join(cols))
	f.close()
	print("性能 CSV 已写入: ", path)
