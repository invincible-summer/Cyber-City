## 应用外壳（组合根）：MapSlot + 相机 Rig + 工具 UI + 加载遮罩 + 诊断 + 设置 + 书签 + 截图 + 基准。
## chapter1-1 §7：组合根初始化并注入 QualityController、ObserverCamera 与共享活动 guard。
## 自动化（user args 在 `--` 后）：
##   --shoot [--graybox] [--quality eco|balanced|both]
##   --perf [--route legacy_v1|expanded_v11] [--quality ...] [--runs N] [--mode capped|headroom] [--occlusion on|off]
extends Node3D

const AUTO_MAP_ID := "m01_afterglow"

var map_slot: Node3D
var camera_rig: Node3D            # camera_controller.gd
var camera_ctl                    # camera_controller 实例（弱类型便于测试替换）
var tool_ui: CanvasLayer          # tool_ui.gd
var loading_overlay: CanvasLayer
var loading_label: Label
var diagnostics                   # diagnostics.gd
var settings                      # settings_manager.gd（QualityController 合同）
var map_manager: Node             # map_manager.gd
var capture_service: Node         # capture_service.gd
var benchmark_runner: Node        # benchmark_runner.gd
var activity_guard: ActivityGuard
var bookmarks: BookmarkStore

var _ui_hidden := false
## 基准期间为 true：主循环不应用失焦/最小化节流与整树暂停（基准自行检测失焦并中止）。
var _automation_measure := false
var _perf_config: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_shell()

	activity_guard = ActivityGuard.new()
	bookmarks = BookmarkStore.new()

	settings = get_node("SettingsManager")
	map_manager = get_node("MapManager")
	map_manager.setup(map_slot, activity_guard, settings, camera_ctl)
	map_manager.load_registry_file("res://data/map_registry.json")
	capture_service.setup(activity_guard, map_manager, settings, camera_ctl)
	benchmark_runner.setup(activity_guard, map_manager, settings, camera_ctl, self)
	_wire_signals()

	_refresh_map_menu()
	# 手动同步一次画质 UI（SettingsManager 在 _ready 中发信号时本节点尚未接线）
	_on_quality_changed(&"eco", settings.get_effective_state())

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
	(tool_ui.root_control as CanvasItem).add_to_group("capture_ui")

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
	loading_overlay.add_to_group("capture_ui")

	var diag_layer := CanvasLayer.new()
	diag_layer.layer = 11
	add_child(diag_layer)
	var diag_script := load("res://scripts/app/diagnostics.gd")
	diagnostics = diag_script.new()
	diag_layer.add_child(diagnostics)
	diag_layer.add_to_group("capture_ui")

	var capture := Node.new()
	capture.name = "CaptureService"
	capture.set_script(load("res://scripts/app/capture_service.gd"))
	capture.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(capture)
	capture_service = capture

	var bench := Node.new()
	bench.name = "BenchmarkRunner"
	bench.set_script(load("res://scripts/diagnostics/benchmark_runner.gd"))
	bench.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(bench)
	benchmark_runner = bench


func _wire_signals() -> void:
	map_manager.map_loading.connect(_on_map_loading)
	map_manager.map_loaded.connect(_on_map_loaded)
	map_manager.map_unloaded.connect(_on_map_unloaded)
	map_manager.map_failed.connect(_on_map_failed)
	tool_ui.map_requested.connect(func(mid: String) -> void: map_manager.request_map(StringName(mid)))
	tool_ui.unload_requested.connect(func() -> void:
		map_manager.request_unload()
		tool_ui.toggle_menu())
	tool_ui.quality_requested.connect(func(id: String) -> void: settings.set_profile(StringName(id)))
	settings.quality_changed.connect(_on_quality_changed)
	# 书签
	tool_ui.bookmark_save_requested.connect(_on_bookmark_save)
	tool_ui.bookmark_load_requested.connect(_on_bookmark_load)
	tool_ui.bookmark_delete_requested.connect(_on_bookmark_delete)
	# 截图
	capture_service.capture_completed.connect(func(req_id: int, png: String, _json: String) -> void:
		print("截图已保存: ", png))
	capture_service.capture_failed.connect(func(req_id: int, err: Error, msg: String) -> void:
		printerr("截图失败: ", msg))


func _refresh_map_menu() -> void:
	var entries: Array = []
	for mid in map_manager.get_available_map_ids():
		var def = map_manager.get_definition(mid)
		if def != null:
			entries.append({"id": mid, "display_name": def.display_name, "available": def.available})
	tool_ui.set_map_entries(entries)


func _on_quality_changed(requested_id: StringName, effective_state: Dictionary) -> void:
	tool_ui.set_quality(String(requested_id), str(effective_state.get("profile_id", "")))
	# 地图侧应用由 MapManager 在激活期完成；这里处理空场景时也同步 UI 状态。
	var v: Viewport = get_viewport()
	v.use_occlusion_culling = true


func _on_map_loading(map_id: StringName, _tx: int, stage: StringName, progress: float) -> void:
	loading_overlay.visible = true
	var stage_text := "地图加载中…"
	match String(stage):
		"unloading":
			stage_text = "卸载旧地图…"
		"resource_loading":
			if progress >= 0.0:
				stage_text = "地图资源加载中… %d%%" % int(clampf(progress, 0.0, 1.0) * 100.0)
			else:
				stage_text = "地图资源加载中…"
		"activating":
			stage_text = "激活地图…"
	loading_label.text = stage_text
	camera_ctl.set_input_enabled(false)
	tool_ui.set_busy(true, stage_text)


func _on_map_loaded(map_id: StringName, _tx: int) -> void:
	loading_overlay.visible = false
	tool_ui.set_busy(false)
	camera_ctl.set_input_enabled(true)
	var def: MapDefinition = map_manager.get_definition(String(map_id))
	var roots := get_tree().get_nodes_in_group("active_map_root")
	if roots.is_empty() or def == null:
		return
	var map_root := roots[0] as MapRoot
	tool_ui.set_map_info(String(map_id), def.display_name)
	# 锚点位姿值（不持有锚点节点）；默认机位已由 MapManager 在激活期应用
	var poses := {}
	for anchor_id in map_root.get_anchor_ids():
		poses[anchor_id] = map_root.get_anchor_pose(anchor_id)
	var contract: Dictionary = map_manager.get_camera_contract()
	camera_ctl.set_anchor_poses(poses, contract.get("default_anchor", &""))
	tool_ui.set_anchor_hint(camera_ctl._anchor_order)
	_refresh_bookmark_menu()
	diagnostics.set_map_node_count(count_map_nodes(map_root))
	diagnostics.set_extra_info("地图 %s (r%s) | 资源加载 %.0f ms | 激活 %.0f ms" % [
		String(map_id), map_manager.get_current_content_revision(),
		map_manager.last_resource_load_ms, map_manager.last_activation_ms])


func _on_map_unloaded(_map_id: StringName, _tx: int) -> void:
	tool_ui.set_map_info("", "未加载地图")
	camera_ctl.unbind_map()
	tool_ui.set_anchor_hint(PackedStringArray())


func _on_map_failed(_map_id: StringName, _tx: int, _error: Error, message: String) -> void:
	loading_overlay.visible = false
	tool_ui.set_busy(false)
	camera_ctl.set_input_enabled(true)
	tool_ui.set_map_info("", "未加载地图")
	camera_ctl.unbind_map()
	tool_ui.set_busy(true, "加载失败：%s\n可从下方菜单重试或返回空场景。" % message)


func count_map_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count


func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count


# ---------------- 书签 ----------------

func _on_bookmark_save(label: String) -> void:
	var pose: CameraPose = camera_ctl.get_pose()
	if pose == null:
		tool_ui.set_busy(true, "书签保存失败：未绑定地图")
		tool_ui.set_busy(false)
		return
	var result := bookmarks.save_bookmark(label, pose, map_manager.get_current_content_revision())
	_refresh_bookmark_menu()
	if result.error != OK:
		tool_ui.show_transient_message(str(result.message))


func _on_bookmark_load(bookmark_id: String) -> void:
	var pose := bookmarks.load_bookmark(bookmark_id)
	if pose == null:
		tool_ui.show_transient_message("书签不存在或数据无效")
		return
	var err: Error = camera_ctl.apply_pose(pose, true)
	if err != OK:
		tool_ui.show_transient_message("书签位置在当前地图不可用，可删除后重新保存")


func _on_bookmark_delete(bookmark_id: String) -> void:
	bookmarks.delete_bookmark(bookmark_id)
	_refresh_bookmark_menu()


func _refresh_bookmark_menu() -> void:
	var map_id: StringName = map_manager.get_current_map_id()
	tool_ui.set_bookmarks(bookmarks.list_bookmarks(map_id))


# ---------------- 输入 ----------------

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
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
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
			var err: Error = capture_service.request_capture()
			if err == ERR_BUSY:
				print("截图忙/节流中")
		KEY_ESCAPE:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				tool_ui.toggle_menu()
		_:
			pass


# ---------------- 焦点与最小化 ----------------

func set_automation_measure(flag: bool) -> void:
	_automation_measure = flag


func _notification(what: int) -> void:
	if _automation_measure:
		return  # 基准运行期间：节流保持生效但暂停行为由基准中止逻辑负责
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		settings.set_window_state(false, _was_minimized())
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		settings.set_window_state(true, _was_minimized())


func _was_minimized() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED


func _process(_delta: float) -> void:
	if _automation_measure:
		return
	var minimized := _was_minimized()
	set_meta("_last_minimized", minimized)
	if minimized != bool(get_meta("_prev_minimized", false)):
		set_meta("_prev_minimized", minimized)
		get_tree().paused = minimized  # 最小化暂停环境动画
		settings.set_window_state(not minimized and DisplayServer.window_is_focused(), minimized)
	elif DisplayServer.window_is_focused() != bool(get_meta("_prev_focused", true)):
		set_meta("_prev_focused", DisplayServer.window_is_focused())
		settings.set_window_state(DisplayServer.window_is_focused(), minimized)


# ---------------- 自动化：截图 ----------------

func _run_automation_shoot(args: PackedStringArray) -> void:
	await _await_map_ready()
	var tiers: Array[String] = _tier_args(args, ["eco", "balanced"])
	var graybox := args.has("--graybox")
	var shot_root := get_node("CaptureService")

	if graybox:
		var gray := StandardMaterial3D.new()
		gray.albedo_color = Color(0.62, 0.63, 0.66)
		gray.roughness = 1.0
		var roots := get_tree().get_nodes_in_group("active_map_root")
		var map_root := roots[0] as MapRoot
		_apply_override(map_root, gray)
		await _shoot_anchors(shot_root, "graybox")
		_apply_override(map_root, null)

	for tier in tiers:
		settings.set_profile(StringName(tier), false)
		await get_tree().create_timer(0.6).timeout
		await _shoot_anchors(shot_root, tier)
	print("SHOOT_DONE")
	get_tree().quit()


func _shoot_anchors(shot_root: Node, tier: String) -> void:
	for anchor in camera_ctl._anchor_order:
		camera_ctl.go_to_anchor(anchor)
		await get_tree().create_timer(0.45).timeout
		var err: Error = shot_root.request_capture("%s_%s" % [tier, anchor])
		if err == OK:
			await shot_root.capture_completed
	print("自动截图完成: ", tier)
	# 一张带诊断的验证图
	if camera_ctl._anchor_order.size() > 0:
		camera_ctl.go_to_anchor(camera_ctl._anchor_order[0])
		await get_tree().create_timer(0.3).timeout
		diagnostics.visible = true
		var err: Error = shot_root.request_capture("%s_%s_diag" % [tier, camera_ctl._anchor_order[0]])
		if err == OK:
			await shot_root.capture_completed
		diagnostics.visible = false


func _apply_override(root: Node, mat: Material) -> void:
	for child in root.get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).material_override = mat
		if child is Node:
			_apply_override(child, mat)


# ---------------- 自动化：性能路线（BenchmarkRunner 合同） ----------------

func _run_automation_perf(args: PackedStringArray) -> void:
	await _await_map_ready()
	tool_ui.set_visible_all(false)
	(diagnostics.get_parent() as CanvasLayer).visible = false
	# 测量前重置用户配置，保证档位序列确定
	DirAccess.remove_absolute("user://settings.cfg")
	var tiers: Array[String] = _tier_args(args, ["eco", "balanced"])
	var runs := 3
	var route := "legacy_v1"
	var mode := "capped"
	var occlusion := "default"
	var warmup := 15.0
	for i in range(args.size()):
		match args[i]:
			"--runs":
				if i + 1 < args.size():
					runs = clampi(int(args[i + 1]), 1, 10)
			"--route":
				if i + 1 < args.size():
					route = args[i + 1]
			"--mode":
				if i + 1 < args.size():
					mode = args[i + 1]
			"--occlusion":
				if i + 1 < args.size():
					occlusion = args[i + 1]
			"--warmup":
				if i + 1 < args.size():
					warmup = float(args[i + 1])
	print("PERF warmup(内置于首轮) 15s …")
	await get_tree().create_timer(15.0).timeout
	for tier in tiers:
		for r in runs:
			var stamp := Time.get_datetime_string_from_system(false, true)
			stamp = stamp.replace(":", "").replace("-", "").replace("T", "_").replace(" ", "")
			var run_id := "v11_%s_%s_%s_r%d" % [route, tier, stamp, r]
			_perf_config = {
				"schema_version": 1,
				"run_id": run_id,
				"profile_id": tier,
				"route_id": route,
				"mode": mode,
				"warmup_seconds": warmup if r == 0 else 0.0,
				"duration_seconds": 60.0,
				"occlusion_override": occlusion,
				"output_directory": "user://benchmarks",
			}
			var err: Error = benchmark_runner.start_run(_perf_config)
			if err != OK:
				printerr("PERF_ABORT: start_run 失败 err=", err)
				get_tree().quit(1)
				return
			var result: Array = await _await_benchmark_end()
			if result[0] != "completed":
				printerr("PERF_ABORT: ", result[1])
				get_tree().quit(1)
				return
			print("PERF run done: ", run_id)
	print("PERF_DONE")
	get_tree().quit()


func _await_benchmark_end() -> Array:
	var outcome: Array = ["", ""]
	var done := [false]
	var on_complete := func(_run_id: String, _dir: String) -> void:
		outcome[0] = "completed"
		done[0] = true
	var on_abort := func(_run_id: String, reason: String) -> void:
		outcome[0] = "aborted"
		outcome[1] = reason
		done[0] = true
	benchmark_runner.benchmark_completed.connect(on_complete, CONNECT_ONE_SHOT)
	benchmark_runner.benchmark_aborted.connect(on_abort, CONNECT_ONE_SHOT)
	while not done[0]:
		await get_tree().process_frame
	benchmark_runner.benchmark_completed.disconnect(on_complete)
	benchmark_runner.benchmark_aborted.disconnect(on_abort)
	return outcome


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
