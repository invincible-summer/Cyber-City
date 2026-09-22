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
# ---- 门户运行时（chapter1-2 §4.4）----
var _portals: Array[Dictionary] = []
var _active_portal: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_shell()

	activity_guard = ActivityGuard.new()
	bookmarks = BookmarkStore.new()

	settings = get_node("SettingsManager")
	map_manager = get_node("MapManager")
	map_manager.setup(map_slot, activity_guard, settings, camera_ctl)
	# §16.1：注册表加载失败必须停止默认地图请求并给出明确错误，不得假装正常启动
	if not map_manager.load_registry_file("res://data/map_registry.json"):
		tool_ui.show_transient_message("地图注册表不可用：data/map_registry.json 解析/校验失败")
		printerr("MAIN: 地图注册表不可用，停止默认地图请求")
		camera_ctl.set_input_enabled(false)
		return
	capture_service.setup(activity_guard, map_manager, settings, camera_ctl,
		OS.get_environment("NEON_BUILD_ID"))  # §28.3：build_id 为空写 unknown，不伪造
	benchmark_runner.setup(activity_guard, map_manager, settings, camera_ctl, self)
	_wire_signals()
	camera_ctl.pose_changed.connect(_on_pose_changed)

	_refresh_map_menu()
	# §8.7（C13-22）：UI 首次同步用真实持久化档位，不再硬编码 eco；
	# 不为初始化 UI 再次 set_profile（避免多余持久化/quality_changed）。
	_on_quality_changed(settings.get_profile_id(), settings.get_effective_state())

	var args := OS.get_cmdline_user_args()
	var auto_map := AUTO_MAP_ID
	for i in range(args.size()):
		if args[i] == "--map" and i + 1 < args.size():
			auto_map = args[i + 1]
	if args.has("--perf"):
		if _request_initial_map(StringName(auto_map)) != OK:
			return
		_run_automation_perf(args)
	elif args.has("--shoot"):
		if _request_initial_map(StringName(auto_map)) != OK:
			return
		_run_automation_shoot(args)
	else:
		_request_initial_map(StringName(auto_map))


## §13.2：自动化入口的 request_map 同步 preflight 失败立即退出，不进入死等。
func _request_initial_map(map_id: StringName) -> Error:
	var err: Error = map_manager.request_map(map_id)
	if err != OK:
		printerr("MAIN: 初始地图请求失败 err=%d（%s）" % [err, map_manager.get_state_snapshot().get("last_error", "")])
		if OS.get_cmdline_user_args().size() > 0:
			get_tree().quit(1)
	return err


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
	## §8.5：只做 ToolUI 状态同步。occlusion 由 SettingsManager.apply_to_map /
	## apply_no_map_defaults 唯一控制，此处不再写 Viewport。
	tool_ui.set_quality(String(requested_id), str(effective_state.get("profile_id", "")))


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
	_portals = []
	_active_portal = {}
	tool_ui.hide_portal_hint()


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
	# §14.1：外部只走公开接口，不读相机私有字段
	tool_ui.set_anchor_hint(camera_ctl.get_anchor_order(), camera_ctl.is_walk_mode())
	_portals = []
	for p in contract.get("portals", []):
		if p is Dictionary:
			_portals.append(p)
	_active_portal = {}
	_refresh_bookmark_menu()
	diagnostics.set_map_node_count(count_map_nodes(map_root))
	diagnostics.set_extra_info("地图 %s (r%s) | 资源加载 %.0f ms | 激活 %.0f ms" % [
		String(map_id), map_manager.get_current_content_revision(),
		map_manager.last_resource_load_ms, map_manager.last_activation_ms])


func _on_map_unloaded(_map_id: StringName, _tx: int) -> void:
	tool_ui.set_map_info("", "未加载地图")
	camera_ctl.unbind_map()
	tool_ui.set_anchor_hint(PackedStringArray())
	_portals = []
	_active_portal = {}
	tool_ui.hide_portal_hint()


func _on_map_failed(_map_id: StringName, tx: int, _error: Error, message: String) -> void:
	## §12.2 信号语义：tx==0 = preflight 拒绝（未开始切图事务）——管理器仍 READY 时
	## 保留当前地图 UI/相机/锚点/门户，只弹错误提示；tx>0 = 事务失败回 EMPTY，完整清空。
	if tx == 0 and map_manager.state == map_manager.State.READY:
		loading_overlay.visible = false
		camera_ctl.set_input_enabled(true)
		tool_ui.show_transient_message("加载失败：%s" % message)
		return
	loading_overlay.visible = false
	tool_ui.set_busy(false)
	camera_ctl.set_input_enabled(true)
	tool_ui.set_map_info("", "未加载地图")
	camera_ctl.unbind_map()
	_portals = []
	_active_portal = {}
	tool_ui.hide_portal_hint()
	tool_ui.set_anchor_hint(PackedStringArray())
	_refresh_bookmark_menu()
	tool_ui.set_busy(true, "加载失败：%s\n可从下方菜单重试或返回空场景。" % message)


# ---------------- 门户（chapter1-2 §4.4） ----------------

func _on_pose_changed(pose: CameraPose) -> void:
	## ≤10 Hz 门户命中轮询（每图 ≤4 个门户）；命中显示 F 提示并开门，离开关门。
	if pose == null or _portals.is_empty() or map_manager.is_busy():
		return
	var hit: Dictionary = {}
	for p in _portals:
		var pp: Vector3 = p.get("pos", Vector3.INF)
		if pp.distance_to(pose.transform.origin) <= float(p.get("radius", 1.5)):
			hit = p
			break
	var hit_id := "%s:%s" % [str(hit.get("target_map_id", "")), str(hit.get("target_anchor", ""))]
	var active_id := "%s:%s" % [str(_active_portal.get("target_map_id", "")), str(_active_portal.get("target_anchor", ""))]
	if not hit.is_empty() and hit_id != active_id:
		_active_portal = hit
		tool_ui.show_portal_hint("按 F — %s" % str(hit.get("label", "进入")))
		_set_portal_doors(true)
	elif hit.is_empty() and not _active_portal.is_empty():
		_active_portal = {}
		tool_ui.hide_portal_hint()
		_set_portal_doors(false)


func _set_portal_doors(open: bool) -> void:
	var roots := get_tree().get_nodes_in_group("active_map_root")
	if roots.is_empty():
		return
	(roots[0] as MapRoot).set_portal_door_open(open)


func _try_enter_portal() -> void:
	if _active_portal.is_empty():
		return
	var target := str(_active_portal.get("target_map_id", ""))
	var anchor := str(_active_portal.get("target_anchor", ""))
	var err: Error = map_manager.request_map(StringName(target), false, StringName(anchor))
	if err == ERR_BUSY:
		tool_ui.show_transient_message("地图切换进行中，请稍候…")
	# 受理后 _on_map_loading 清提示；失败由 _on_map_failed 呈现


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
	# §15：以当前地图实际 revision 为基准标记旧书签
	tool_ui.set_bookmarks(bookmarks.list_bookmarks(map_id), map_manager.get_current_content_revision())


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
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			# §14.2：统一 1–9；超界索引由 go_to_anchor_index 安全 no-op
			if not tool_ui.is_menu_open():
				camera_ctl.go_to_anchor_index(key - KEY_1)
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
		KEY_F:
			if not tool_ui.is_menu_open():
				_try_enter_portal()
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
	# §13.2：等待 READY 必须有失败/超时出口，坏 --map 不得永久挂住进程
	if await _await_map_ready() != OK:
		printerr("SHOOT_ABORT: 地图未就绪（%s）" % str(map_manager.get_state_snapshot().get("last_error", "timeout")))
		get_tree().quit(1)
		return
	var tiers: Array[String] = _tier_args(args, ["eco", "balanced"])
	var graybox := args.has("--graybox")
	var shot_root := get_node("CaptureService")
	# §14.3：截图自动化使用 capture_anchor_ids（当前为空回落全部锚点）
	var contract: Dictionary = map_manager.get_camera_contract()
	var capture_ids: Array[StringName] = []
	for a in contract.get("capture_anchor_ids", []):
		capture_ids.append(a)

	if graybox:
		var gray := StandardMaterial3D.new()
		gray.albedo_color = Color(0.62, 0.63, 0.66)
		gray.roughness = 1.0
		var roots := get_tree().get_nodes_in_group("active_map_root")
		var map_root := roots[0] as MapRoot
		_apply_override(map_root, gray)
		var g_err: Error = await _shoot_anchors(shot_root, "graybox", capture_ids)
		_apply_override(map_root, null)
		if g_err != OK:
			get_tree().quit(1)
			return

	for tier in tiers:
		if settings.set_profile(StringName(tier), false) != OK:
			printerr("SHOOT_ABORT: 画质档不存在 %s" % tier)
			get_tree().quit(1)
			return
		await get_tree().create_timer(0.6).timeout
		if await _shoot_anchors(shot_root, tier, capture_ids) != OK:
			get_tree().quit(1)
			return
	print("SHOOT_DONE")
	get_tree().quit(0)


func _shoot_anchors(shot_root: Node, tier: String, anchors: Array[StringName]) -> Error:
	## §13.3：任何目标失败都让本轮自动化 exit 1；不允许静默跳图后仍 SHOOT_DONE。
	## §29：不再拍摄"diag"图（诊断层属于 capture_ui，截图时本就会被隐藏，
	## 该图只是重复截图且无独立证据价值；render_stats JSON 是截图时诊断权威）。
	var failed: Array[String] = []
	var capture_failed_flag := [false]
	var on_fail := func(_rid: int, _err: Error, msg: String) -> void:
		failed.append(msg)
		capture_failed_flag[0] = true
	for anchor in anchors:
		if not camera_ctl.go_to_anchor(String(anchor)):
			printerr("SHOOT_FAIL: 机位切换失败 %s_%s" % [tier, anchor])
			failed.append("go_to_anchor %s" % anchor)
			continue
		# 1.2 修复：拍摄前把鼠标移到右下角，避免视口内光标残留在画面中部
		Input.warp_mouse(get_viewport().get_visible_rect().end - Vector2(12.0, 12.0))
		# 等待须大于 CaptureService.THROTTLE_MSEC(500ms)，否则 request_capture 返回 ERR_BUSY
		await get_tree().create_timer(0.62).timeout
		var err: Error = shot_root.request_capture("%s_%s" % [tier, anchor])
		if err != OK:
			await get_tree().create_timer(0.35).timeout
			err = shot_root.request_capture("%s_%s" % [tier, anchor])
		if err != OK:
			printerr("SHOOT_FAIL: request_capture err=%d %s_%s" % [err, tier, anchor])
			failed.append("request_capture %s_%s" % [tier, anchor])
			continue
		shot_root.capture_failed.connect(on_fail, CONNECT_ONE_SHOT)
		await shot_root.capture_completed
		if capture_failed_flag[0]:
			shot_root.capture_failed.disconnect(on_fail)
			printerr("SHOOT_FAIL: 截图写盘失败 %s_%s" % [tier, anchor])
			break
		if shot_root.capture_failed.is_connected(on_fail):
			shot_root.capture_failed.disconnect(on_fail)
	print("自动截图完成: ", tier)
	if not failed.is_empty():
		printerr("SHOOT_FAIL: 本档 %d 项失败: %s" % [failed.size(), ", ".join(failed)])
		return ERR_CANT_CREATE
	return OK


func _apply_override(root: Node, mat: Material) -> void:
	for child in root.get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).material_override = mat
		if child is Node:
			_apply_override(child, mat)


# ---------------- 自动化：性能路线（BenchmarkRunner 合同） ----------------

func _run_automation_perf(args: PackedStringArray) -> void:
	# §9.2 错误 C：不再删除用户 settings.cfg；Benchmark persist=false + 快照恢复已足够。
	if await _await_map_ready() != OK:
		printerr("PERF_ABORT: 地图未就绪（%s）" % str(map_manager.get_state_snapshot().get("last_error", "timeout")))
		get_tree().quit(1)
		return
	tool_ui.set_visible_all(false)
	(diagnostics.get_parent() as CanvasLayer).visible = false
	var tiers: Array[String] = _tier_args(args, ["eco", "balanced"])
	var runs := 3
	var route := "legacy_v1"
	var mode := "capped"
	var occlusion := "default"
	var warmup := 15.0
	var duration := 60.0
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
			"--duration":
				# §34：headroom 冒烟可 1..60；capped 固定 60，不开放缩短正式采样
				if i + 1 < args.size() and mode == "headroom":
					duration = clampf(float(args[i + 1]), 1.0, 60.0)
	for tier in tiers:
		if settings.set_profile(StringName(tier), false) != OK:
			printerr("PERF_ABORT: 画质档不存在 %s" % tier)
			get_tree().quit(1)
			return
		for r in runs:
			var stamp := Time.get_datetime_string_from_system(false, true)
			stamp = stamp.replace(":", "").replace("-", "").replace("T", "_").replace(" ", "")
			var run_id := "v13_%s_%s_%s_r%d" % [route, tier, stamp, r]
			_perf_config = {
				"schema_version": 1,
				"run_id": run_id,
				"profile_id": tier,
				"route_id": route,
				"mode": mode,
				"warmup_seconds": warmup,  # §10.5：每轮 warmup 由 BenchmarkRunner 单一权威控制
				"duration_seconds": duration,
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
	get_tree().quit(0)


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


## §13.2：等待 READY 带超时/失败出口。READY→OK；ERROR/EMPTY 带 last_error→ERR_CANT_OPEN；
## 超时→ERR_TIMEOUT。不再无出口死等。
func _await_map_ready(timeout_sec: float = 35.0) -> Error:
	var start := Time.get_ticks_msec()
	while map_manager.state != 1:  # MapManager.State.READY
		if map_manager.state == 0 and not str(map_manager.get_state_snapshot().get("last_error", "")).is_empty():
			return ERR_CANT_OPEN
		if float(Time.get_ticks_msec() - start) / 1000.0 > timeout_sec:
			return ERR_TIMEOUT
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	return OK


func _tier_args(args: PackedStringArray, defaults: Array[String]) -> Array[String]:
	## §13.4：逐项验证 profile 存在；--quality nonsense 不得用旧档渲染却按 nonsense 命名。
	var tiers: Array[String] = []
	var wanted := ""
	for i in range(args.size()):
		if args[i] == "--quality" and i + 1 < args.size():
			wanted = args[i + 1]
	if wanted == "both":
		tiers = defaults.duplicate()
	elif not wanted.is_empty():
		tiers = [wanted]
	if tiers.is_empty():
		tiers = defaults.duplicate()
	var known: Array[String] = settings.get_quality_ids()
	for t in tiers:
		if not known.has(t):
			printerr("未知画质档: %s（可用: %s）" % [t, ", ".join(known)])
			return []
	return tiers
